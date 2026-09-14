---
name: cdm_persistence
description: ChemicalDM crash recovery + queue persistence — queue.txt (app, Settings.ch) and progress.txt (cdmlib, DownloadManager.ch), atomic writes, save/restore ordering, startup sequence in Main.ch, and the CDM_CONFIG_DIR/CDM_TOOLS_DIR env overrides. Load when touching persistence, restore/save, or crash recovery.
---

# ChemicalDM persistence & crash recovery

Two files, both written atomically (tmp + rename) so a crash mid-write can't corrupt them:

| File | Owner | Module | Written |
|------|-------|--------|---------|
| `queue.txt` | app (`src/core/Settings.ch`) | chemicaldm | **clean shutdown only** (`save_queue` in run_gui cleanup) |
| `progress.txt` | library (`cdmlib/src/DownloadManager.ch`) | cdmlib | **periodically** (`periodic_save_progress` every `save_interval_millis`, default 30 s) + on shutdown |
| `yt_links.txt` | app (`src/core/YtAsync.ch`) | chemicaldm | after link refresh / when links recorded (YouTube URL cache, see `yt_playlist` skill) |

Root dir: `$HOME/.chemicaldm/` unless `CDM_CONFIG_DIR` is set (tests use it heavily).
`~` prefixes expand via `expand_home()` (cdmlib Constants.ch).

## queue.txt (app-side)

- Header `#cdm-queue-v2`; v1 rows (without progress fields) still parse.
- Tab-separated per row:
  `url \t id \t dir \t category \t downloaded \t total \t interrupted \t state`
- DONE items are skipped (nothing to resume).
- Written by `save_queue(dm)` (Settings.ch ~line 1308): builds the content, then
  `queue.txt.tmp` → `fwrite` → `fflush` → `fclose` → `rename()` → `queue.txt`.
- `restore_queue(dm)` (Settings.ch ~line 1164) parses it back. It inserts items DIRECTLY
  (bypasses `add_task_ex_id`) to preserve saved state and avoid firing `start_pending`
  per item. Restored items keep their saved state; interrupted ones become
  `STATE_FAILED` + `was_interrupted = true`.

## progress.txt (cdmlib-side)

- Header `#cdm-progress-v1`.
- Tab-separated: `id \t downloaded \t total \t interrupted` (interrupted = `1`/`0`).
- Rows written for `ITEM_TYPE_NORMAL` items only, and never for `STATE_DONE`.
  The interrupted flag is set when `was_interrupted || state == DOWNLOADING || state == PAUSED`
  (i.e. "not finished, assume it was cut off").
- **`dm.progress_file_path` must be set BEFORE the first `start_pending`** — otherwise
  `periodic_save_progress` silently no-ops (it early-returns on empty path). Main.ch sets
  it via `cdm::progress_file()`.
- `periodic_save_progress` snapshots items + merges live runtime progress under
  `items_mutex`, then writes OUTSIDE the lock via tmp+rename. Triggered from
  `start_pending` (which runs after every add/resume/completion), so the file stays fresh
  without a dedicated timer thread.
- `restore_progress(dm, path)` (DownloadManager.ch ~line 993) reads the file and overlays:
  takes the HIGHER of saved vs current `downloaded_bytes` (stale queue.txt data must not
  lower real progress), re-applies interrupted flags, sets `was_interrupted = true` +
  `STATE_FAILED` for interrupted rows.

## Startup sequence (`src/Main.ch`) — order is load-bearing

```
dm.progress_file_path = cdm::progress_file()   // 1. MUST be before start_pending
restore_queue(&mut dm)                          // 2. load items (no scheduling)
restore_progress(&mut dm, progress_file())      // 3. overlay crash-recovery data
start_pending(&mut dm)                          // 4. kick off QUEUED items once
```

**Key design rule:** `restore_queue` does NOT call `start_pending` per item. Workers must
not start until ALL progress is applied — otherwise a download could restart from byte 0
while saved progress says 50%. Also note `poll_auto_resume(dm)` is NOT called in the GUI
path (restore already handles interrupted items).

## Tests

`tests/persist_tests.ch` (23 tests) owns this area: state roundtrips (queued/paused/
interrupted), `CDM_persist_progress_file_roundtrip`, `CDM_persist_progress_overlay`
(progress.txt beats stale queue.txt), `CDM_persist_done_items_skipped`,
`CDM_persist_v1_backward_compat`, `CDM_persist_progress_does_not_corrupt_queue`,
`CDM_persist_retry_preserves_progress`, `CDM_persist_save_queue_atomic` (no `.tmp`
leftover), `CDM_parse_i64_leading_minus_only`. cdmlib's `behavior_tests.ch` covers the
library-side fields. All persistence tests set `CDM_CONFIG_DIR` to a temp dir.

## Gotchas (each cost real time)

1. **Atomic writes are mandatory.** `fopen(tmp,"wb") → fwrite → fflush → fclose →
   rename()`. A crash during a non-atomic write corrupts the file, and next launch
   `restore_queue` silently parses garbage, losing all items. The `.tmp` must be gone
   after rename (`CDM_persist_save_queue_atomic` guards this).
2. **`parse_i64_from_view` only treats a LEADING `-` as sign** — `"12-34"` parses as `12`.
   Parsing breaks at the first non-digit after digits start. Keep substring views in named
   locals (not temporaries) so they outlive the call.
3. **`save_queue` and `save_progress` snapshot under the mutex, write outside it.**
   Don't hold `items_mutex` through `fopen/fwrite` — worker threads block on snapshot
   reads and the UI stalls.
4. **Don't move persistence into cdmlib.** queue.txt knows about categories/states as the
   app encodes them; the library only tracks raw progress bytes.
5. **Progress overlay takes max(saved, current)** — never assign unconditionally, or a
   stale queue.txt row would rewind an item that made progress after the last queue save.
6. `save_interval_millis` / `last_save_millis` on the manager exist solely for
   `periodic_save_progress`; they are NOT the queue save mechanism.
