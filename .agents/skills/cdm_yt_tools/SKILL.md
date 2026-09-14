---
name: cdm_yt_tools
description: yt-dlp/ffmpeg tool management in ChemicalDM — auto-install through the app's own downloader, fork-safety rules (process::execute, never popen), find_binary PATH scanning, availability/status reporting that must never lie, and the YtTools/YtDownloader/YtInfo file layout. Load when working on src/core/Yt*.ch, tool install, or anything that shells out.
---

# ChemicalDM YouTube tooling (yt-dlp / ffmpeg)

App-side subsystem (`src/core/YtTools.ch` install/status, `src/core/YtDownloader.ch`
lifecycle/progress, `src/core/YtInfo.ch` metadata parsing, `src/core/YtAsync.ch` async
execution). Optional: the rest of the app works without the tools.

## File responsibilities

| File | Contents |
|------|----------|
| `src/core/YtTools.ch` | Tool paths (`CDM_TOOLS_DIR` → `$HOME/.chemicaldm/tools`), `find_binary`/`find_binary_path` (PATH scanning), `ytdlp_is_available`/`ffmpeg_is_available`, `ytdlp_resolved_path`/`ffmpeg_resolved_path`, `check_tools_status_json` (status JSON for the Tools tab), `ensure_tool_executable`, `clear_stale_tool_duplicates`, install tracking globals `g_tool_dl_status/g_tool_dl_task_id` |
| `src/core/YtDownloader.ch` | `YtDownload` lifecycle tracker, yt-dlp stdout progress-line parsing (`[download] xx.x%` etc.), `build_ytdlp_playlist_args`, `ffmpeg_merge`, URL detection (`is_youtube_url` etc.) |
| `src/core/YtInfo.ch` | `YtVideoInfo`/`YtPlaylistInfo`/`YtFormat`, `parse_video_json`, `parse_playlist_json` (NDJSON-first — see `yt_playlist` skill) |
| `src/core/YtAsync.ch` | Async glue: background info extraction (`start_async_info`/`poll_async_info`), single download (`start_async_download`/`poll_async_download`), playlist fan-out (`g_async_pl`), link persistence/refresh (`g_yt_links`, `refresh_stale_yt_links`) |

## Fork-safety (THE critical rule)

**All yt-dlp/ffmpeg/xdg-open execution MUST use `process::execute`, never raw `popen()`
or bare `fork()`.** `process::execute` is fork-safe: the child performs only
async-signal-safe operations (close/dup2/chdir/`execve` — no `malloc`, no `getenv`, no
`execvp`), so it cannot deadlock the multithreaded WebKitGTK process.

The original bug this rule encodes: the info thread forked while another thread held a
lock; the child blocked forever; `done` never became true; the UI spinner never cleared
("stuck at fetching the info"). `open_file`/`show_in_folder` in Bridge.ch were migrated
for the same reason. If you write new code that shells out: `process::execute` with a
`vector<string>` argv (no shell quoting needed).

## Availability checks must not spawn

Availability/version detection deliberately avoids spawning a process (fork in the
multithreaded GUI can deadlock — see above):

- `find_binary(name)` stats a short hardcoded list (`/usr/bin`, `/usr/local/bin`,
  `/usr/bin/local`, `~/.local/bin`, `/opt/homebrew/bin` on macOS, `/snap/bin`,
  `$CDM_TOOLS_DIR`) **AND scans every directory in `$PATH`** (split on `:` POSIX /
  `;` Windows). A tool installed in any `$PATH` dir the hardcoded list misses (conda
  envs, custom `~/bin`) must still be detected — this was the "I downloaded yt-dlp but
  the app says not installed" bug.
- `find_binary_path(name)` returns the concrete discovered path (or the bare command name
  as fallback) and backs `ytdlp_resolved_path()`/`ffmpeg_resolved_path()`, so the Tools
  tab shows the real location and execution doesn't depend on `$PATH` at exec time.
- Version queries are skipped in status polling for the same no-spawn reason.

## yt-dlp is a Python script — not an ELF binary

`file`/`head` showing `#!/usr/bin/env python3` + a Zip payload is NORMAL for yt-dlp.
Availability only checks that the canonical file exists at the discovered path; it does
NOT require a binary magic header. Never "fix" this by requiring ELF magic — that breaks
the legit yt-dlp download.

## Install flow

1. UI "Install" → `yt_install` (Bridge.ch) queues the tool as a REGULAR download task
   (priority 100, target `$CDM_TOOLS_DIR`) through the app's own DownloadManager —
   the downloader downloads its own tools.
2. Status tracked via globals `g_tool_dl_status` / `g_tool_dl_task_id` (YtTools.ch);
   `yt_status` polls the manager snapshot for that task id, reports
   `status:"downloading"` + progress while running.
3. On completion: `ensure_tool_executable(path)` runs `fs::set_permissions(path, 0o755)`
   on Unix (a downloaded tool is always runnable — the status poll re-applies this for
   bundled paths that exist), then the task is removed from the queue.
4. `clear_stale_tool_duplicates(base_name)` removes leftover `name (N)` /
   `name (N).part` artifacts from older installs (a stray `yt-dlp (1)` next to the real
   `yt-dlp` is harmless but confusing). The install targets the CANONICAL name even when
   a stale file occupied that path.
5. Bridge URL redirect for tests: `CDM_TOOL_URL_OVERRIDE` lets `bridge_tests.ch` point
   the installer at a local python server (`CDM_BR_tool_download_progress`).

## Status JSON contract (Tools tab)

`check_tools_status_json` emits (build manually — see TCC gotcha below):
```
{ "yt_dlp": {name,status,version,path}, "ffmpeg": {...}, "both_ready": bool }
```
- `name` is the machine id (`yt-dlp`/`ffmpeg`), `status` is `"installed"`,
  `"not_installed"`, or `"downloading"`.
- **Every string value wrapped with `json_string()` EXACTLY ONCE** — it already adds the
  surrounding quotes. Use the `json_kv`/`json_kv_raw` helpers instead of hand-concatenating
  quotes; double-wrapping produced `""yt-dlp""` → invalid JSON → `JSON.parse` rejected the
  bridge result → the Tools tab stayed on a stale "Not Installed" fallback. Regression
  test: `CDM_tools_status_json_parseable`.
- It returns JSON built directly instead of a `ToolInfo` struct because returning
  struct-by-value with string members can trigger a TCC compound-expression double-free
  (documented inline in YtTools.ch).

## UI contract (`src/ui/CdmApp.ch`)

- The "checking..." status (`ytTools` state) must never stay stuck: `refreshTools()`
  (a) seeds a safe fallback immediately so a thrown/slow bridge call can't leave
  `ytTools` null, and (b) runs on mount (alongside `refresh`/`refreshSettings`).
- `asyncBridge`'s `.catch` swallows bridge errors — any caller that must surface data
  sets its own fallback (as `refreshTools` does) and reports via
  `window.__reportError(msg, stack)`.
- Install button → `installTool(name)` → `yt_install` then a `setInterval` poll of
  `yt_status` until installed/failed (see `pollToolProgress`).

## Tests

- `tests/tools_tests.ch` (14): availability ↔ status agreement, `CDM_TOOLS_DIR`
  redirection, status structure, `CDM_tools_detect_after_install`,
  `CDM_tools_install_uses_canonical_name`, `CDM_tools_detect_via_path` (binary ONLY in a
  `$PATH` dir outside the hardcoded list must be found), `CDM_tools_resolved_path_uses_discovered`.
- `tests/bridge_tests.ch`: `CDM_BR_tool_download_progress` drives a real redirected
  install end-to-end and asserts `"status":"downloading"` + progress > 0.
- `tests/yt_tests.ch` (48): offline logic — arg building, URL detection, progress-line
  parsing, JSON field extraction, NDJSON playlist parsing.
