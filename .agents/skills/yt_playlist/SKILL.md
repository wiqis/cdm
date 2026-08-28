---
name: yt_playlist
description: ChemicalDM YouTube playlist subsystem — async fan-out into per-item video+audio downloads with ffmpeg merge, retry/link-refresh, the poll `videos` array, and the UI playlist card. Load when working on playlist downloads, per-video progress, retry, or hiding child items from the main queue list.
---

# ChemicalDM YouTube Playlist Subsystem

This skill documents how ChemicalDM downloads a YouTube playlist: one logical job that
fans out into N independent video+audio downloads + ffmpeg merges, each tracked by its own
`AsyncDlState`, with retry and cross-session link refresh.

## Data model (`src/core/YtAsync.ch`)

- **`g_async_pl`** — `@never_destructed` global holding the whole playlist job:
  - `items : *mut vector<*mut YtPlItem>` (heap, `new vector<...>()`; per item is `new YtPlItem()`)
  - `dm : *mut DownloadManager` (the live manager)
  - `items_total`, `items_done`, `progress`, `max_retries`, `running`, `done`, `error`,
    `current_title`, `status_line`, `mu`.
- **`YtPlItem`** — one playlist entry. Embeds `dl : AsyncDlState`, plus `index`, `entry_url`
  (original watch URL, used for link refresh), `title`, `retry_count`, `max_retries`.
- **`AsyncDlState`** — the SAME struct used by single YouTube downloads. Holds `dm_task_id`,
  `audio_task_id`, `needs_merge`, `merge_status` (`idle|waiting|merging|merged|failed`),
  `merge_error`, `retry_count`, `max_retries`, `output_dir`, `dm`, and a `mutex mu`.

## Flow

1. **UI → `yt_download_playlist`** (`Bridge.ch`): parses body `{url,format,mode,audio_format,
   min_quality,max_quality,max_retries,auto_merge,delete_separate}`, calls
   `start_async_playlist_download(...)`.
2. **`playlist_thread_entry`** (background thread):
   - `yt-dlp --flat-playlist --print "%(url)s|||%(title)s|||%(duration)s"` → one line per entry.
   - For each line: `new YtPlItem()`, fill fields, `item.dl.dm = dm`, `pl_push_item(item)`,
     then `do_item_download(&raw mut item.dl)`.
   - After queuing all, loop until every item's `merge_status` is `merged` or `failed`
     (key off `merge_status`, NOT `g_async_pl.running`).
3. **`do_item_download(dl)`** — `extract_urls` (yt-dlp --get-url, HLS filtered), `add_task_ex`
   for video (and audio if 2 URLs), records the link, then `maybe_start_merge_monitor(dl)`.
4. **`merge_monitor_entry`** (one thread per item) — `snapshot(dm)`-polls video+audio task ids;
   when both `STATE_DONE`, runs `ffmpeg_merge_files`. On link/merge failure: `requeue_item(dl)`
   (which `change_url` re-queues the DM tasks with refreshed URLs) and restarts the monitor,
   up to `dl.max_retries`.
5. **`poll_async_playlist_download`** — returns a flat `videos` array, one object per item:
   `index,title,state,progress,video_task_id,audio_task_id,merge_status,merge_error,status,
   retry_count,output_path`. The UI renders the playlist card from this and matches the
   per-video/audio segmented bars by `video_task_id`/`audio_task_id` against `state` (`items`).

## Bridge handlers (`src/api/Bridge.ch`)

- `yt_download_playlist` — start.
- `yt_download_playlist_poll` — poll (returns `videos` array).
- `yt_download_playlist_retry` — `retry_playlist_item(index)` (refresh + re-queue one item).
- `yt_download_playlist_open` — `playlist_item_output_path(index)` then
  `process::execute("xdg-open", path, ...)` (NO `open_file` symbol in this module).
- `cancel_async_playlist_download` — sets `running=false`/`done=true`.

## UI (`src/ui/CdmApp.ch`)

- Playlist card: collapsed by default; overall combined progress + `items_done/items_total`;
  per-video rows with a combined progress bar; expand → video+audio segmented bars
  (`items.find(it.id === v.video_task_id)`), merge status/error, Retry (failed) / Open (done)
  / Cancel (active child) buttons.
- **Hide the child DM items**: the playlist's video/audio `DownloadItem`s are real tasks but
  must NOT appear as separate cards. `pollYtPlaylist` rebuilds `ytPlTaskIds` (object of
  `v.video_task_id`/`v.audio_task_id` → true) every poll; the main list filters
  `items` → `mainItems = items.filter((u) => !ytPlTaskIds[u.id])` before rendering, and the
  Active/Done/Total stats and the "No downloads yet" empty state use `mainItems`.
- **Keep `ytDownloading = true` for the whole playlist** — set it on start, clear it only in
  `pollYtPlaylist` when `d.done`. (Clearing it in the start callback makes the empty state
  reappear during the download.)
- Reset `ytPlVideos = []`, `ytPlTaskIds = {}`, `ytPlExpanded = {}` when starting a new playlist.

## Cross-session link refresh (`src/core/YtAsync.ch` + `Main.ch`)

- `g_yt_links : *mut vector<YtLinkRecord>` (heap, `new`, NOT a constructor call) persists
  `video_id/audio_id/youtube_url/format/mode/audio_format/min_q/max_q` to
  `~/.chemicaldm/yt_links.txt` via `save_yt_links`/`load_yt_links`/`record_yt_link`.
- `refresh_stale_yt_links(&raw mut dm)` is called in `Main.ch` after `restore_queue` at launch
  and re-queues any stale links. Keep this call.

## Gotchas (cost real debugging time — honor them)

1. **`new YtPlItem()`, never `malloc(sizeof(T)) as *mut T; *p = T()`.** The temporary's
   destructor destroys the embedded `mutex`; a later `mu.lock()` corrupts the heap
   (`free(): invalid pointer`).
2. **`get_async_info` must dispatch on `is_playlist`** to `parse_playlist_json`
   (NDJSON-first). `parse_video_json` only sees the first NDJSON line → "0 videos" + a single
   video's title. `YtPlaylistInfo.is_playlist` is set `true` inside the parser and emitted in
   `to_json()` so the UI branches correctly.
3. **`change_url(dm, id, new_url)` takes `id : &string`** (the DownloadItem id), and
   `snapshot(dm : &mut DownloadManager)`. Call with `&raw mut dl`-style pointers; `&mut *dm`
   dereferences a raw pointer (warning in `--build`, may error in `--test`).
4. `requeue_item`/`retry_playlist_item` re-queue via `change_url`; `maybe_start_merge_monitor`
   spawns a fresh monitor thread (the original loop may have exited after a failure).
5. **Orphaned "Queued" tasks**: if a task is re-queued late (after the scheduler has drained,
   e.g. via `requeue_item`/`retry_playlist_item`/link-refresh) and `start_pending` is NOT called
   again, it stays `Queued` forever even though nothing else is running. Any re-queue path must
   re-trigger the scheduler (call `start_pending` or ensure `enqueue_task`/`change_url` does).
   This is the usual cause of "one audio file stuck on Queued while everything else finished".

## Tests

- `tests/yt_tests.ch` — `CDM_yt_playlist_ndjson_entries` (offline NDJSON → 2 entries, correct
  playlist title, `is_playlist:true`) guards the parse fix. Add playlist regression tests
  there; remember the test module can only call `public` functions and `TestEnv.error(msg:*char)`
  (no `error_int`), and compare strings with `.equals_view()` not `==`/`!=`.
