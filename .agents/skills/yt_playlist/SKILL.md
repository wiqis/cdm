---
name: yt_playlist
description: ChemicalDM YouTube downloads — the async single-video pipeline (AsyncDlState, start/poll/cancel, format+quality resolution, ffmpeg merge) AND the playlist subsystem (fan-out into per-item video+audio downloads, retry/link-refresh, the poll `videos` array, UI playlist card). Load when working on YouTube downloads, per-video progress, retry, or hiding child items from the main queue list.
---

# ChemicalDM YouTube Download Subsystem

Two layers share one engine (`src/core/YtAsync.ch`): **single video** downloads and
**playlist** jobs. Both shell out to yt-dlp for URL extraction and merge with ffmpeg.
Tool availability/exec rules live in the `cdm_yt_tools` skill; metadata parsing in
`src/core/YtInfo.ch`.

## Data model (`src/core/YtAsync.ch`)

- **`AsyncDlState`** — the core per-download struct, used by BOTH single and playlist
  flows. Holds `dm_task_id`, `audio_task_id`, `needs_merge`, `merge_status`
  (`idle|waiting|merging|merged|failed`), `merge_error`, `retry_count`, `max_retries`,
  `output_dir`, `dm`, and a `mutex mu`.
- **Single-download globals**: `g_async_dl` (one `AsyncDlState` + status/progress/done/
  error fields) for the current video; `g_async_info` for background info extraction
  (`start_async_info` → `poll_async_info`, spawned via `process::execute`-safe thread).
- **`g_async_pl`** — `@never_destructed` global holding the whole playlist job:
  - `items : *mut vector<*mut YtPlItem>` (heap, `new vector<...>()`; per item is `new YtPlItem()`)
  - `dm : *mut DownloadManager` (the live manager)
  - `items_total`, `items_done`, `progress`, `max_retries`, `running`, `done`, `error`,
    `current_title`, `status_line`, `mu`.
- **`YtPlItem`** — one playlist entry. Embeds `dl : AsyncDlState`, plus `index`,
  `entry_url` (original watch URL, used for link refresh), `title`, `retry_count`,
  `max_retries`.

## Format & quality resolution (single + playlist share it)

- `quality_to_format(height)` maps a pixel height → yt-dlp format selector.
- `resolve_yt_format(ui_format, min_q, max_q)` turns the dialog's quality chips
  (`min_quality`/`max_quality` ints, `format` string, `mode` video/audio,
  `audio_format`) into the concrete `-f` selector passed to yt-dlp. HLS streams are
  filtered out of extraction results (`no_hls_filter` returns the yt-dlp filter arg)
  because HLS segments can't be resumed/segmented by our engine.

## Single-video flow

1. **UI → `yt_download`** (`Bridge.ch`): parses `{url,format,mode,audio_format,
   min_quality,max_quality,max_retries,auto_merge,delete_separate}`, calls
   `start_async_download(...)` (background thread; the UI wraps the bridge call in
   `setTimeout(...,50)` so the dialog paints first).
2. The thread runs `do_item_download(&raw mut g_async_dl)`: `extract_urls`
   (yt-dlp --get-url, HLS filtered), `add_task_ex` for video (and audio if 2 URLs),
   records the link, `maybe_start_merge_monitor`.
3. **UI polls `yt_download_poll`** → `poll_async_download()`: progress + state +
   per-task ids (the dialog matches them against DM `state` items for segmented bars).
4. **`yt_cancel`** → `cancel_async_download()`: cancels the DM tasks and flags done.

## Playlist flow

1. **UI → `yt_download_playlist`** (`Bridge.ch`): same body shape + playlist options,
   calls `start_async_playlist_download(...)`.
2. **`playlist_thread_entry`** (background thread):
   - `yt-dlp --flat-playlist --print "%(url)s|||%(title)s|||%(duration)s"` → one line per
     entry (cap with `yt_max_playlist_items`).
   - For each line: `new YtPlItem()`, fill fields, `item.dl.dm = dm`, `pl_push_item(item)`,
     then `do_item_download(&raw mut item.dl)`.
   - After queuing all, loop until every item's `merge_status` is `merged` or `failed`
     (key off `merge_status`, NOT `g_async_pl.running`).
3. **`merge_monitor_entry`** (one thread per item) — `snapshot(dm)`-polls video+audio task
   ids; when both `STATE_DONE`, runs `ffmpeg_merge_files`. On link/merge failure:
   `requeue_item(dl)` (which `change_url` re-queues the DM tasks with refreshed URLs) and
   restarts the monitor, up to `dl.max_retries`.

## Bridge handlers (`src/api/Bridge.ch`)

- `yt_info`, `yt_info_get`, `yt_info_poll` — metadata (background thread + poll).
- `yt_download`, `yt_download_poll`, `yt_cancel` — single video.
- `yt_download_playlist`, `yt_download_playlist_poll`, `yt_download_playlist_retry`
  (`retry_playlist_item(index)` — refresh + re-queue one item),
  `yt_download_playlist_open` (`playlist_item_output_path(index)` then
  `process::execute("xdg-open", path, ...)` — there is NO `open_file` symbol in this
  module for yt paths; use `process::execute` directly, it's fork-safe).
- `debug_log` — forwards JS console messages to stderr for diagnosing the webview side.

## Poll shapes

- `yt_download_poll` → single object: `{running, done, error, progress, speed, status,
  title, video_task_id, audio_task_id, merge_status, merge_error, needs_merge,
  container_id}` — `container_id` is the YT_SINGLE card id (see the `cdm_containers`
  skill).
- `poll_async_playlist_download` returns a flat `videos` array, one object per item:
  `{index,title,state,progress,video_task_id,audio_task_id,merge_status,merge_error,
  status,retry_count,output_path}`. The UI renders the playlist card from this and
  matches the per-video/audio segmented bars by `video_task_id`/`audio_task_id` against
  DM `state` (`items`).

## UI (`src/ui/CdmApp.ch`)

- Single: `openYtDownload` → `fetchYtInfo` (setTimeout-wrapped `yt_info`, then
  `pollYtInfo` interval) → format list + quality chips → `startYtDownload` →
  `pollYtDownload` interval → progress card with video/audio segmented bars. The single
  job ALSO gets a `ITEM_TYPE_YT_SINGLE` container card (`renderYtVideoCard`) whose
  header progress is driven from the async poll via `set_item_state_progress`.
- Playlist card: collapsed by default; overall combined progress + `items_done/items_total`;
  per-video rows with a combined progress bar; expand → video+audio segmented bars
  (`items.find(it.id === v.video_task_id)`), merge status/error, Retry (failed) / Open
  (done) / Cancel (active child) buttons.
- **Hide the child DM items**: the playlist's video/audio `DownloadItem`s are real tasks
  but must NOT appear as separate cards. Children are tagged `card_type = ITEM_TYPE_YT_CHILD`
  (+ `parent_id`), and the UI renders top-level cards from
  `mainItems = items.filter((u) => u.card_type !== CARD_YT_CHILD)`. The playlist card itself
  is the `ITEM_TYPE_PLAYLIST` container item created by `create_container_item`; the poll's
  `container_id` is kept in `ytPlContainerId`, and the card renders as "active" while
  `item.id === ytPlContainerId` (expanded-card state + progress sync).
- **Keep `ytDownloading = true` for the whole job** — set it on start, clear it only in
  the poll callback when `d.done`. (Clearing it in the start callback makes the empty
  state reappear during the download.)
- Reset `ytPlVideos = []`, `ytPlContainerId = ""`, `ytPlExpanded = {}` when starting a new
  playlist.

## Cross-session link refresh (`src/core/YtAsync.ch` + `Main.ch`)

- `g_yt_links : *mut vector<YtLinkRecord>` (heap, `new`, NOT a constructor call)
  persists `video_id/audio_id/youtube_url/format/mode/audio_format/min_q/max_q` to
  `~/.chemicaldm/yt_links.txt` via `save_yt_links`/`load_yt_links`/`record_yt_link`.
- `refresh_stale_yt_links(&raw mut dm)` is called in `Main.ch` after `restore_queue` at
  launch and re-queues any stale links. Keep this call.

## Gotchas (cost real debugging time — honor them)

1. **`new YtPlItem()`, never `malloc(sizeof(T)) as *mut T; *p = T()`.** The temporary's
   destructor destroys the embedded `mutex`; a later `mu.lock()` corrupts the heap
   (`free(): invalid pointer`).
2. **`get_async_info` must dispatch on `is_playlist`** to `parse_playlist_json`
   (NDJSON-first). `parse_video_json` only sees the first NDJSON line → "0 videos" + a
   single video's title. `YtPlaylistInfo.is_playlist` is set `true` inside the parser and
   emitted in `to_json()` so the UI branches correctly.
3. **`change_url(dm, id, new_url)` takes `id : &string`** (the DownloadItem id), and
   `snapshot(dm : &mut DownloadManager)`. Call with `&raw mut dl`-style pointers; `&mut *dm`
   dereferences a raw pointer (warning in `--build`, may error in `--test`).
4. `requeue_item`/`retry_playlist_item` re-queue via `change_url`; `maybe_start_merge_monitor`
   spawns a fresh monitor thread (the original loop may have exited after a failure).
5. **Orphaned "Queued" tasks**: if a task is re-queued late (after the scheduler has
   drained, e.g. via `requeue_item`/`retry_playlist_item`/link-refresh) and `start_pending`
   is NOT called again, it stays `Queued` forever even though nothing else is running. Any
   re-queue path must re-trigger the scheduler (call `start_pending` or ensure
   `enqueue_task`/`change_url` does). This is the usual cause of "one audio file stuck on
   Queued while everything else finished".
6. **Do not cancel the playlist driver loop on `running=false`** — the loop keys off each
   item's `merge_status`; cancelling early strands items mid-merge.

## Tests

- `tests/yt_tests.ch` (48) — offline logic: `CDM_yt_playlist_ndjson_entries` (NDJSON → 2
  entries, correct playlist title, `is_playlist:true`) guards the parse fix; arg building,
  URL detection, progress-line parsing, quality/format resolution.
- `tests/bridge_tests.ch` — bridge-level download flows against local servers.
  Add playlist regression tests to `yt_tests.ch`; remember the test module can only call
  `public` functions and `TestEnv.error(msg:*char)` (no `error_int`), and compare strings
  with `.equals_view()` not `==`/`!=`.
