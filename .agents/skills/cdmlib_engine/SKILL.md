---
name: cdmlib_engine
description: Deep dive into the cdmlib download library — DownloadManager queue API, Engine worker threads, segmented downloads with .part files, resume, probe, retry policy, and the strict library-vs-app boundary. Load before changing anything under cdmlib/.
---

# cdmlib — the reusable download engine

`cdmlib/` is a standalone Chemical module (`module cdmlib`) meant to be imported by ANY
app that needs segmented, resumable HTTP downloads. It is NOT aware of the cdm app: no
JSON, no UI, no settings files, no categories routing, no process spawning.

## Dependency budget (hard rule)

`cdmlib/chemical.mod` imports exactly: `cstd`, `std`, `core`, `net`, `http`, `fs`, `uuid`
(plus `test`/`test_env` only when the `test` def is set). Never add more. If a feature
needs json/page/webview/process/environment, it belongs in the app (`src/`).

Namespace is `cdm` — shared with the app's code, but symbols are NOT shared across
modules unless declared `public` and the import direction allows it (the app imports
cdmlib; cdmlib can never see app types).

## File responsibilities

| File | Contents |
|------|----------|
| `src/Constants.ch` | `CDM_VERSION`, state ints (`STATE_QUEUED=0 … STATE_CANCELLED=5`), `RetryPolicy` struct, defaults (`DEFAULT_MAX_CONCURRENT=3`, `DEFAULT_MAX_SEGMENTS=4`, `DEFAULT_MIN_SEGMENT_SIZE=256KiB`, socket timeout 30s), `expand_home()` |
| `src/Model.ch` | `DownloadItem` — pure data POD (id/url/dir/filename, byte counters, state, priority, duplicate_suffix, category tag, segments_json, was_interrupted). No pointers/sockets by design. Has `local_path()`, `display_filename()`, manual `copy()` |
| `src/UrlUtil.ch` | `UrlInfo`, `parse_url` (wraps `http::URL::parse`), `sanitize_filename` (strips path separators + unsafe chars, falls back to "download"), `suggested_filename` (last URL path segment) |
| `src/CdHttp.ch` | `request(method, url, range_start, range_end=-1)` — redirect-following GET/HEAD-ish client (`MAX_REDIRECTS=10`, `Accept-Encoding: identity`, UA `ChemicalDM/0.1`). `probe(url, hint)` → `CdProbe{ok,status,total_bytes,supports_resume,filename,error}` using `Range: bytes=0-0`. `open_download(url, resume_from)`, `open_download_range(url,start,end)`. Header parsers: `parse_content_length`, `parse_content_range_total`, `parse_content_disposition_name` |
| `src/Engine.ch` | `TaskRuntime`, `TaskProgress`, `SegmentState`, job structs, thread entries, `stream_body`, `run_download_task`, segment split/assemble, all locked_* helpers |
| `src/DownloadManager.ch` | The public queue facade: add/edit/retry/restart/pause/resume/cancel/remove/change_url/clear_finished/snapshot/poll_auto_resume/shutdown + scheduler `start_pending` |

## Download lifecycle

```
add_task_ex(dm, url, dir_hint, filename_hint, priority, category)
  # category: int (0=Other, 1=Documents, 2=Programs, 3=Video, 4=Music, 5=Compressed)
  # add_task_ex_id(dm, id, url, dir_hint, filename_hint, priority, category) = same but
  #   preserves a caller-supplied id (used by queue.txt restore).
  ├─ uuid id, suggested_filename / sanitize, resolve dir (hint > manager default)
  ├─ fs::create_dir_all(resolved_dir)
  ├─ resolve_duplicate_filename  (duplicate_action: 0=rename " (N)", 1=overwrite, 2=skip→returns "")
  ├─ items.push_back(item)
  └─ start_pending(dm)

start_pending(dm)
  ├─ count_active() = items whose runtime reports STATE_DOWNLOADING
  └─ while active < max_concurrent: pick QUEUED item w/o runtime, lowest priority first
       (queue order tiebreak); copy overrides onto new TaskRuntime; start_task();
       on success mark item DOWNLOADING; on failure erase runtime + delete rt and STOP.

worker thread: start_task → spawn(download_entry → run_download_task)
  1. state=DOWNLOADING, clear error
  2. if total<=0 && downloaded<=0 → probe()
       ok     → store total_bytes (+ supports_resume)
       failed → STATE_FAILED immediately (non-retryable)
  3. decide segmentation:
       use_segments iff supports_resume && allow_segments &&
         compute_segment_count(total, max_segments, min_size) > 1
       resumed segmented session (segments non-empty) → reuse + load_segment_state()
  4. SEGMENTED: build_segments splits [0,total) into N contiguous ranges (extra byte to
     first rem segments). Each unfinished segment gets its own thread:
       SegmentJob → segment_entry → raw_download_segment
         open_download_range(url, start+copied, end)   // bounded Range request
         stream into <dir>/<filename>.<index>.part     (fopen r+b at copied, or wb)
         publish s.copied/s.done back under info_mutex
     join all → if all done → assemble_segments (concat parts in order, 1MiB buffer,
     remove .part files) → STATE_DONE. Else count as failed attempt, reload copied from
     disk, sleep delay_ms, loop.
  5. NON-SEGMENTED: open_download(url, resume_from) → status handling:
       200 while resuming → server ignored Range: reset downloaded to 0, truncate file
       200/206 → read Content-Length / Content-Range for totals → stream_body to file
       416 → if downloaded >= total → DONE else fail attempt
       other 4xx except 429 → STATE_FAILED immediately; everything else retries
  6. Retry loop guarded by RetryPolicy.should_retry(attempt) (-1 = infinite).
     Pause inside stream_body: close socket, flush, return 2 → outer loop waits in
     wait_resume_or_cancel then reconnects (no retry cost). Cancel wins over pause.
```

Resume truth lives on DISK:
- Segmented: each `.part` file size == copied bytes (`segment_copied_from_disk`)
- Single-stream: output file opened `r+b`, seek to resume_from
- Across restarts: `DownloadItem.downloaded_bytes/total_bytes` are preserved by the
  manager (poll_auto_resume deliberately does NOT zero them).

## Threading & locking model

- One OS thread per active task (`std::concurrent::spawn(download_entry, *mut DownloadJob)`).
  Segmented tasks spawn N additional short-lived segment threads per attempt.
- `TaskRuntime` is heap-allocated (`new`), owned by the manager's
  `runtimes : ordered_map<string, *mut TaskRuntime>` keyed by item id.
- EVERY access to runtime fields goes through `rt.info_mutex`: use the helpers
  `locked_set_state/error/total/downloaded/speed`, `locked_get_downloaded/total`,
  `locked_add_downloaded`, `should_cancel`, `should_pause`, `snapshot_progress`,
  `snapshot_segments_json`. Don't invent new lock-free paths.
- Worker threads NEVER touch `dm.items`. `snapshot(dm)` merges live progress into deep
  copies of items — that vector is the only thing handed outward.
- Jobs (`DownloadJob`/`SegmentJob`) are `new`'d by the spawner and `delete`'d at the end
  of the thread entry — strings are COPIED into them (constructor takes string_view,
  stores owned string) so nothing aliases across threads.
- `shutdown(dm)`: cancel+join every runtime, mark still-downloading items
  `STATE_FAILED` + `was_interrupted=true` + error "interrupted by shutdown", replace the
  runtimes map. The UI keys special resume behavior off that exact error string.

## Speed limiting

Per-task `speed_limit_kbps` (0=off). Enforced coarsely inside `stream_body` via
`throttle(rt, n)`: budget_ms = bytes / kbps after each read. Sampling window for speed
display is `SPEED_SAMPLE_MS = 500`.

## Public API contract (what apps call)

States: `STATE_QUEUED/DOWNLOADING/PAUSED/DONE/FAILED/CANCELLED` (plain ints).

```chemical
var dm = cdm::DownloadManager()
var id  = cdm::add_task(&mut dm, url_view)                       // defaults
var id2 = cdm::add_task_ex(&mut dm, url, dir, fname, prio, cat)  // full control
cdm::pause_task/resume_task/cancel_task/retry_task/restart_task(&mut dm, &id)
cdm::edit_item(&mut dm, &id, dir_v, fname_v, prio, segs, kbps, cat)   // non-running only
cdm::change_url(&mut dm, &id, url_v)                                  // resets progress
cdm::remove_task(&mut dm, &id) / remove_task_file(..., true)          // +delete file
cdm::clear_finished(&mut dm) -> removed_count
cdm::snapshot(&mut dm) -> vector<DownloadItem>   // merge of record + live progress
cdm::poll_auto_resume(&mut dm) -> requeued_count // was_interrupted items (and FAILED if auto_resume_failed)
cdm::shutdown(&mut dm)                           // app exit
cdm::find_item_index(&dm, &id) -> usize (== items.size() means missing)
```

Pure helpers also public (tested directly): `compute_segment_count`, `build_segments`,
`parse_content_length`, `parse_content_range_total`, `suggested_filename`,
`sanitize_filename`, `resolve_duplicate_filename`, `expand_home`.

## Boundary rules when editing

1. New capability that reads env vars, spawns processes, parses JSON for humans, or
   knows about folders like "Documents" → belongs in the APP. cdmlib accepts fully
   resolved dir/filename strings, period.
2. `category` on `DownloadItem` is an OPAQUE int tag (0 = none). The library never
   interprets it.
3. Keep `fprintf(stderr, "[CDM] ...")` trace style for new engine logs — they're the
   primary debugging tool (see `[CDM]`, `[CDM-POLL]` prefixes).
4. Any new cross-thread data must go behind `info_mutex`; snapshot-style getters must
   return copies (strings included) — never references into runtime state.
5. Bounded range requests (`open_download_range`) exist because some servers stream the
   whole file regardless of Range; never replace a segment request with an open-ended one.

## Known quirks / dead code (don't blindly "fix")

- `pick_next_queued()` is an unused stub kept "for symmetry".
- `save_interval_millis` / `last_save_millis` fields on the manager are unused
  (persistence moved to the app).
- `count_active` treats "has runtime && progress says DOWNLOADING" as active — a task
  that just finished but wasn't reaped still occupies a slot until cleanup.
- `restart_task`/`remove_task_file` scan part files only for indices 0..63 — fine for
  max_segments ≤ 32 but worth knowing.
- The "category param" refactor is DONE: `DownloadItem.category` is a plain `int` tag and
   both `add_task_ex` and `add_task_ex_id` take it. cdmlib never interprets the tag (the app
   routes categories before calling). See repo AGENTS.md "Current state".
