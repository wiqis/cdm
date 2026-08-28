# AGENTS.md — ChemicalDM (`cdm`) and `cdmlib`

Guidance for AI agents working on ChemicalDM, a download-manager desktop app written in
the Chemical programming language, living at `lang/compiled/cdm/` inside the chemical
compiler repo. This directory is its own git repo (nested, not a submodule).

---

## The one rule that governs everything: library vs app boundary

`cdmlib/` is a **reusable download library**. Any app should be able to import it to get
segmented, resumable HTTP downloads — without inheriting a whole application.

| Belongs in `cdmlib/` | Belongs in the app (`src/`) |
|---|---|
| Queue management, task lifecycle states | GUI / webview / HTML / CSS |
| Segmented + single-stream engine, threads | JSON wire format for the UI bridge |
| HTTP probe / range requests / redirects | Settings persistence (`config.txt`, `queue.txt`) |
| Resume via Range + `.part` files | Category routing (extension → subfolder) |
| Filename sanitize/suggest from URL | yt-dlp / ffmpeg tooling & process execution |
| Retry policy, speed limiting, pause/cancel | CLI parsing, validation, error codes for users |
| Duplicate-name resolution (`name (N).ext`) | Clipboard/open-file/show-folder desktop actions |

**cdmlib dependency budget:** `cstd`, `std`, `core`, `net`, `http`, `fs`, `uuid` only.
Never add `json`, `page`, `webview`, `process`, `environment`, or any CBI/UI module to
`cdmlib/chemical.mod`. If a feature needs those, it belongs in the app.

The layering contract: **the app resolves everything user-visible (dirs, names, categories)
before calling the library; the library only sees URL → dir → filename → bytes on disk.**
See the comment in `src/api/Bridge.ch` ("Category routing … resolve here in the app").

---

## Directory map

```
cdm/
├── chemical.mod            # application chemicaldm; imports ./cdmlib + full app dep set
├── run.sh                  # build/run/test helper (see below)
├── cdmlib/                 # THE LIBRARY — keep small
│   ├── chemical.mod        #   module cdmlib; minimal imports; "tests" only if test def
│   ├── src/
│   │   ├── Constants.ch    #   CDM_VERSION, STATE_* ints, RetryPolicy, defaults, expand_home
│   │   ├── Model.ch        #   DownloadItem POD (pure data, no sockets/threads)
│   │   ├── UrlUtil.ch      #   UrlInfo, parse_url, sanitize_filename, suggested_filename
│   │   ├── CdHttp.ch       #   request() w/ redirects+Range, probe(), open_download(_range),
│   │   │                   #   parse_content_length/_range_total/_disposition_name
│   │   ├── Engine.ch       #   TaskRuntime/SegmentState, worker threads, stream_body,
│   │   │                   #   segment .part files, assemble_segments, run_download_task
│   │   └── DownloadManager.ch # public queue API: add/retry/pause/resume/cancel/edit/remove,
│   │                       #   snapshot(), start_pending scheduler, shutdown
│   └── tests/              #   unit (pure fns), feature (queue ops), integration (loopback server)
├── src/
│   ├── Main.ch             # main(): --test dispatch → test_runner; GUI vs headless; run_gui()
│   ├── api/Bridge.ch       # bridge_call(): every JS→native method lives here (state/add/pause/…)
│   ├── core/
│   │   ├── Cli.ch          # CliOptions, parse_cli, run_headless (batch URLs, prints progress)
│   │   ├── Categories.ch   # Category enum, extension→category, categorize_path
│   │   ├── Settings.ch     # CdmSettings, config.txt read/write, queue.txt save/restore,
│   │   │                   # apply_settings_to_dm (app→lib bridge for settings)
│   │   ├── Validation.ch   # ValidationError + validate_url/max_concurrent/… (single truth)
│   │   ├── ErrorCodes.ch   # CdmErrorCode enum + CdmError {code,message}
│   │   ├── JsonBuild.ch    # json_escape/json_string/item_to_json (manual string building)
│   │   ├── Formatters.ch   # format_bytes/speed/eta/state/category
│   │   ├── Storage.ch      # LEGACY json state file — superseded by Settings.ch queue.txt (dead)
│   │   ├── YtTools.ch      # yt-dlp/ffmpeg install/status/paths; tool downloads via own engine
│   │   ├── YtInfo.ch       # YtVideoInfo/YtPlaylistInfo/YtFormat; yt-dlp --dump-json parsing
│   │   └── YtDownloader.ch # YtDownload lifecycle tracker, yt-dlp progress parsing,
│   │                       #   build_ytdlp_playlist_args, ffmpeg_merge, URL detection
│   └── ui/
│       ├── CdmApp.ch       # ONE big #universal component: all dialogs, filters, list rendering
│       └── CdmTheme.ch     # ~750 lines of CSS appended via page.append_css_view
└── tests/                  # app-level @test suite (cli/format/json/proc/queue/segments/settings/yt)
```

Build outputs land in `build/` and `bin/` (gitignored).

---

## Build, run, test

```bash
./run.sh                # build (TCC backend, debug_quick) then launch GUI
./run.sh --build        # build only → bin/cdm
./run.sh --test         # build with tests enabled and run the @test suite
./run.sh --llvm         # use LLVM backend (Compiler binary) instead of TCCCompiler
./run.sh --debug        # debug_complete mode
./run.sh --clean
```

Direct compile (what run.sh does):

```bash
../../../cmake-build-debug/TCCCompiler chemical.mod -o bin/cdm --mode debug_quick --no-cache
# add --test to enable the test build (defines `test`, pulls tests/ into both modules)
./bin/cdm --test        # run the suite as the runner's child processes expect
```

Compiler discovery: `../../..​/cmake-build-debug/TCCCompiler` (falls back to `out/build`).
Rebuild the compiler first if you changed C++ sources (`./scripts/build.sh --tcc`).

CLI surface of the built app: `cdm <url>...`, `--file batch.txt`, `-d dir -o name`,
`-p segments -j concurrent --speed-limit kb --priority n`, `--gui/-g`, `-q`, `-v`, `-h`.
No args → GUI. Anything non-URL → headless mode.

---

## cdmlib architecture

### Download lifecycle (single item)

1. **Queue**: `add_task_ex(dm, url, dir_hint, filename_hint, priority[, category])` creates a
   `DownloadItem` (uuid id), resolves dir/filename, applies duplicate policy
   (`duplicate_action`: 0=rename `(N)`, 1=overwrite, 2=skip), pushes, calls `start_pending`.
2. **Scheduling**: `start_pending` picks QUEUED items by lowest priority value first
   (queue order as tiebreak), up to `max_concurrent`. Per-item overrides fall back to
   manager defaults (segments, speed limit).
3. **Worker thread**: `start_task` spawns `download_entry` → `run_download_task`
   (`Engine.ch`). One OS thread per active task.
4. **Probe** (only when no known size): GET with `Range: bytes=0-0`.
   206 → resume supported + total from Content-Range; 200 → no resume, total from
   Content-Length; 416 → total from Content-Range.
5. **Segment decision**: segmented iff resume supported AND `allow_segments` AND
   `compute_segment_count(total, max_segments, min_segment_size) > 1`
   (min segment size default 256 KiB; too-small/unknown files are never split).
6. **Segmented path**: `[0,total)` split into N contiguous ranges; each segment gets its
   own thread (`segment_entry`) doing a **bounded** range request
   (`open_download_range(url, start+copied, end)`) streamed into `<dir>/<filename>.<i>.part`.
   When all segments report done, `assemble_segments` concatenates parts into the final
   file (1 MiB buffer) and removes the `.part` files.
7. **Non-segmented path**: `open_download(url, resume_from)` streams to the output file;
   `fopen("r+b") + fseek` when resuming, truncate-and-reset if the server ignores Range
   (200 while resuming).
8. **Retry loop**: `RetryPolicy{max_retries (-1 = infinite), delay_ms}`. Connection loss /
   failed segments retry with backoff; permanent 4xx (except 429) fail immediately.
9. **Pause/cancel**: flags polled inside `stream_body` every read; cancel wins over pause.
   Pause closes the socket, flushes, returns code 2; the loop reconnects after resume.

### Threading & state model

- `TaskRuntime` (heap, owned by manager, in `runtimes` ordered_map keyed by item id):
  holds `progress : TaskProgress`, pause/cancel flags, thread handle, `segments` vector,
  per-task limits. All reads/writes under `rt.info_mutex`.
- The manager's `items : vector<DownloadItem>` is the persistent record; worker threads
  NEVER touch it. `snapshot(dm)` merges live progress (deep copies) out of the runtimes —
  that copy is what crosses into JSON/UI territory.
- Cross-thread API: `request_pause/request_cancel/resume_runtime/snapshot_progress/
  snapshot_segments_json` (Engine.ch). Segment completion publishes back under the mutex.
- Shutdown: `shutdown(dm)` cancels + joins all workers, marks DOWNLOADING items
  `STATE_FAILED` + `was_interrupted = true`; next launch `poll_auto_resume` re-queues them
  (failed downloads are NOT auto-resumed unless `auto_resume_failed` is set).
- Resume data source is the filesystem: part-file sizes (`segment_copied_from_disk`) and
  downloaded_bytes preserved across restarts.

### Library public API (stable contract)

States: `STATE_QUEUED/DOWNLOADING/PAUSED/DONE/FAILED/CANCELLED` (plain ints, mirror XDM).
Key functions (namespace `cdm`): `DownloadManager()`, `add_task`, `add_task_ex`,
`edit_item`, `retry_task`, `restart_task`, `pause_task`, `resume_task`, `cancel_task`,
`remove_task(_file)`, `change_url`, `clear_finished`, `snapshot`, `poll_auto_resume`,
`shutdown`, `find_item_index`, `resolve_duplicate_filename`, plus Engine helpers
`compute_segment_count`, `build_segments`.

---

## App architecture

### JS ⇄ native bridge (no HTTP server!)

GUI = WebKitGTK webview (`webview::create/load_html/webview_run`) showing SSR'd HTML.
JS calls `window.webview_bridge.call(method, argsJson)` → Promise<string JSON>, wired via
`webview::webview_bind` to `bridge_call(dmp, method, args)` in `src/api/Bridge.ch`.

Methods: `state`, `add`, `pause`, `resume`, `cancel`, `remove`, `remove_file`, `retry`,
`restart`, `edit`, `change_url`, `settings_get`, `settings_set`, `open_file`,
`show_in_folder`, `yt_status`, `yt_install`, `yt_info`, `yt_download`,
`yt_download_playlist`.

Response shape: `{"ok":true,...}` / `{"ok":false,"error":"..."}`; `state` returns
`{"download_dir","max_concurrent","version","items":[item_to_json...]}`.
Gotcha: the bridge JS wraps bodies as `{id, method, params:[body]}` so `args` may arrive
array-wrapped — always funnel field extraction through `json_field/json_int_field/
json_bool_field`, which call `resolve_bridge_args` first.

Item JSON fields (JsonBuild.item_to_json): id,url,filename,display_name,dir,state(name),
error,total_bytes,downloaded_bytes,speed_bytes_per_sec,priority,max_segments,
speed_limit_kbps,duplicate_suffix,category(name),percent,eta,retry_count,was_interrupted
and optional raw `segments` array (pre-serialized by `snapshot_segments_json`).

Blocking bridge methods (`yt_info`, `yt_download`) run yt-dlp in **background threads**
(`src/core/YtAsync.ch`) via `process::execute` (fork-safe), so the GTK thread stays
responsive; the UI pre-wraps calls in `setTimeout(...,50)` so the dialog paints first and
polls `yt_info_poll` until the background thread sets `done`.

### GUI flow (`Main.ch run_gui`)

HtmlPage SSR (`defaultPrepare/defaultUniversalSetup/injectDefaultComponentsTheme` +
`CdmTheme(&mut page)` + `#html { <CdmApp /> }`) → create webview 1080x720 → bind bridge →
load_html → show/run/destroy → `shutdown` then `save_queue`.
Before opening the window: load settings → apply to manager → restore queue.

### Persistence (all app-side, `$HOME/.chemicaldm/`)

- `config.txt` — line-based `key:value` (`downloadFolder:`, `parallelDownloads:`,
  `maxSegments:`, `speedLimit:`, `enableResume:`, `allowSegments:`, `duplicateAction:`,
  `autoResumeFailed:`, `maxRetries:`, `retryDelayMs:`, `category*:` overrides, …).
  Parsed/written manually in Settings.ch; keys matched via fnv1 hash switch.
- `queue.txt` — header `#cdm-queue-v1`, one `url\tid\tdir\tcategory` per line (legacy
  `url\tid` rows are still accepted). `restore_queue` replays the saved id + dir +
  category via `add_task_ex_id` so a relaunch reproduces the exact queue.
- Env overrides: `CDM_CONFIG_DIR` (settings root — used by tests), `CDM_TOOLS_DIR`
  (yt-dlp/ffmpeg install root), `HOME`.
- `~` prefix expanded via `expand_home`.

### YouTube support (app-side, optional tools)

- Tools auto-install through the app's own downloader: `yt_install` queues yt-dlp/ffmpeg
  as regular tasks (priority 100, target `$CDM_TOOLS_DIR`), tracked via globals
  `g_tool_dl_status/g_tool_dl_task_id` in YtTools.ch; `yt_status` polls the manager
  snapshot, chmod +x on completion, removes the task from the queue afterwards.
- Availability checks deliberately avoid spawning a process (`fork()`/`exec` in the
  multi-threaded WebKitGTK process can deadlock) — `find_binary` stats fixed paths
  instead. Version queries also skipped in status polling for this reason.
- **Actual yt-dlp/ffmpeg execution (`src/core/YtAsync.ch`) MUST use `process::execute`,
  never raw `popen()`.** `process::execute` is fork-safe (the child does only
  async-signal-safe ops — close/dup2/chdir/`execve` — no `malloc`/`getenv`/`execvp`),
  so it cannot deadlock the multithreaded GUI. Raw `popen()`/`fork()` here was the root
  cause of the "stuck at fetching the info" bug: the info thread forked while another
  thread held a lock, the child blocked forever, `done` never became true, and the
  spinner never cleared. `open_file`/`show_in_folder` in `Bridge.ch` were also migrated to
  `process::execute` for the same reason.
- **`find_binary` scans `$PATH`** (split on `:` POSIX / `;` Windows) *in addition to* a
  short hardcoded list (`/usr/bin`, `/usr/local/bin`, `/usr/bin/local`, `~/.local/bin`,
  `/opt/homebrew/bin` on macOS, `/snap/bin`, `$CDM_TOOLS_DIR`). A tool installed in any
  `$PATH` directory the hardcoded list misses (conda envs, custom `~/bin`, etc.) must
  still be detected — this was the "I downloaded yt-dlp but the app says not installed"
  bug. `find_binary_path(name)` returns the concrete discovered path (or the bare command
   name as a fallback) and backs `ytdlp_resolved_path()`/`ffmpeg_resolved_path()`, so the
   Tools tab shows the real location and execution does not depend on `$PATH` at exec time.
- **`yt-dlp` is a Python script, not an ELF binary** — `file`/`head` showing `#!/usr/bin/env
   python3` + a Zip payload is normal. Availability only checks that the canonical file exists
   in `$CDM_TOOLS_DIR` (or `$PATH`); it does NOT require the file to be an ELF/binary. Never
   "fix" this by requiring a binary magic header — that would break the legit yt-dlp download.
- **Install hardening** (`src/core/YtTools.ch`): `clear_stale_tool_duplicates(base_name)`
   removes leftover `name (N)` / `name (N).part` artifacts (older installs left a stray
   `yt-dlp (1)` directly next to the real `yt-dlp`, which is harmless but confusing). After
   clearing the existing canonical file, `ensure_tool_executable(path)` runs
   `fs::set_permissions(path, 0o755)` on Unix so a downloaded tool is always runnable, and the
   status poll does the same for bundled paths that exist.
- Info extraction shells out to `yt-dlp --dump-json [--flat-playlist]`; results parsed
  with the json module into YtVideoInfo/YtPlaylistInfo; NDJSON playlists handled too.
- Downloads shell out to `yt-dlp -f <fmt> -o "<dir>/%(title)s.%(ext)s"`; ffmpeg presence
  adds `--merge-output-format mp4`.

### UI (`src/ui/CdmApp.ch`)

Single `#universal` component (~960 lines): toolbar, filter/search/sort bar, queue list
with per-segment progress bars fed from `segments` JSON, context menu, Add/Edit dialogs,
Settings dialog, Change-URL dialog, YouTube dialog (formats + playlist entry selection +
quality chips), tool installer with progress polling, toasts.
Polls `state` every 1000 ms via `setInterval`. State strings are the human names
("Downloading" etc.) produced by `format_state` — match on those, not ints.
Theme classes all prefixed `cdm-*`; base tokens come from shadcn-style variables
(`hsl(var(--primary))` etc.) injected by `page.injectDefaultComponentsTheme()`.

Global JS error capture: `<ErrorOverlay />` (from the shared `components` library,
`lang/libs/components/src/ErrorOverlay.ch`) is mounted at the root. It installs
`window.onerror` / `error` / `unhandledrejection` handlers on client mount and shows a
modal with the full message + stack trace and a "Copy report" button, so runtime JS
errors are visible instead of silently swallowed. It also exposes `window.__reportError(msg,
stack?)`; bridge consumers that swallow errors (e.g. `refreshTools`/`installTool`) call it so
a parse/transport failure surfaces in the overlay rather than leaving the UI on a stale state.

---

## Testing

Framework: `@test`-annotated functions taking `&mut TestEnv` (from `test_env`); each runs
in its own forked process; failures via `env.error("msg")`. Entry: `main()` detects
`--test/--test-id/--comm-id/...` argv and dispatches to `test_runner(argc, argv)`
BEFORE any other handling (Main.ch). Build with `--test` (activates `import test if test`
and `source "tests" if test` in both modules).

```bash
./run.sh --test                                  # build + run everything
```

Suites:
- `cdmlib/tests/unit_tests.ch` (15) — pure parsers/formatters, no network.
- `cdmlib/tests/feature_tests.ch` (8) — queue ops against a real DownloadManager.
- `cdmlib/tests/integration_tests.ch` (14) — spins a local threaded HTTP server with
  Range support (port 3009) in-process; exercises real downloads, segmentation, resume,
  throttling. Downloads go to temp dirs.
 - `tests/*.ch` (app-level) — bridge(22), cli(5), format(6), json(6), proc(1), queue(15),
   segment(11), settings(8), yt(45; mostly offline logic around yt-dlp args/parsing),
   http(3; real downloads against a python Range server — see below),
    tools(11; yt-dlp/ffmpeg availability + status-JSON reporting, PATH scanning, stale-duplicate
    cleanup — see below).
     Plus `cdmlib/tests/*` (unit/feature/integration/behavior). `./run.sh --test` runs the
     app suite; it currently passes end-to-end (~158 tests).

 Tool-status reporting tests (`tests/tools_tests.ch`, 10): these verify that the
 "checking whether yt-dlp/ffmpeg is installed" logic reports correctly and never lies:
 - `CDM_tools_dir_respects_env` — `CDM_TOOLS_DIR` (or `HOME`) redirects where the binary is
   looked up; availability flips when a fake binary is placed/removed at that path.
 - `CDM_tools_available_reported` / `CDM_tools_not_installed_reported` — `check_tools_status_json`
   emits `status:"installed"` vs `status:"not_installed"` matching reality. The negative test
   asserts the flip back to a captured *baseline* (not an absolute `false`), so it stays valid
   on a host that already has a system yt-dlp/ffmpeg installed.
 - `CDM_tools_status_structure` — every tool object has `name` (machine id `yt-dlp`/`ffmpeg`),
   `status`, `version`, `path` and the top-level object has `yt_dlp`+`ffmpeg`+`both_ready`.
 - `CDM_tools_status_matches_availability` — `yt_dlp.status`/`ffmpeg.status` agree with
   `ytdlp_is_available()`/`ffmpeg_is_available()`.
 - `CDM_tools_both_ready` — `both_ready` is true only when BOTH tools are available.
 - `CDM_tools_detect_after_install` — a binary already on disk at the canonical path is
   reported `installed` (regression for "downloaded but app says not installed").
 - `CDM_tools_install_uses_canonical_name` — installing (queueing) the tool targets the
   canonical name `yt-dlp` even when a stale binary occupied that path (regression for the
   duplicate-name rename to `yt-dlp (1)`).
 - `CDM_tools_detect_via_path` — a binary placed ONLY in a `$PATH` directory that is NOT in the
   hardcoded list must still be detected (regression for the `$PATH`-scanning fix). Isolates by
   pointing `CDM_TOOLS_DIR` at an empty temp dir and `PATH` at a temp dir holding the fake binary.
 - `CDM_tools_resolved_path_uses_discovered` — `ytdlp_resolved_path()` returns the discovered
   `$PATH` location (not just the bare `"yt-dlp"`), and falls back to the bare name when absent.
 The live "downloading"/"error" progress-reporting path is covered separately by
 `CDM_BR_tool_download_progress` in `bridge_tests.ch` (drives a real redirected install).


Settings tests isolate themselves with `CDM_CONFIG_DIR`.

Real-world download verification: `tests/http_tests.ch` spawns `tests/http_server.py`
(a small `ThreadingHTTPServer` with full `Range`/206 + `Accept-Ranges` support, like a
real host) on `127.0.0.1`, drives the actual `cdm::DownloadManager` engine against it
(1 MiB segmented, 50 KiB single-stream, 5 MiB large), and byte-compares the downloaded
file against the served payload. Each test forks its own server + temp dirs and cleans
them up (`fuser -k PORT/tcp`, `remove_dir_all_recursive`). Needs `python3` + `fuser` on
the host. These are the closest thing to an end-to-end "does the app really download?"
check.

When adding features: unit-testable logic goes in cdmlib with tests there; UI-facing
serialization in JsonBuild tests; keep integration tests hermetic (loopback only).

---

## Current state: builds clean, tests pass

The "opaque category tag" refactor is **done** (Option A). `DownloadItem.category` is a plain
`int` (0=Other, 1=Documents, 2=Programs, 3=Video, 4=Music, 5=Compressed). `add_task_ex` and
`add_task_ex_id` take an `int category`; the app routes categories (Bridge → `categorize_path`
/`category_dir`; CLI `--category`/`--categories` → `cli_route`), and `Settings.save_queue` /
`restore_queue` persist + restore `id`, `dir`, and `category` on disk. `cdmlib` stays minimal
(no `Category` enum, no `resolve_destination_dir`).

Build & verify:

```bash
./run.sh --build   # whole app (TCC backend)
./run.sh --test    # builds + runs the app test suite (currently all pass)
```

Also note these intentional-but-dead leftovers (candidates for cleanup, don't "fix"
blindly): `pick_next_queued` (stub), `save_interval_millis/last_save_millis` (unused),
`Storage.ch` `save_state/load_state` (superseded by Settings.ch queue persistence).

---

## Conventions & gotchas specific to this codebase

Chemical language rules live in the repo-root `AGENTS.md` + `.agents/skills/chemical_source`.
Project-specific ones:

- Everything is in `namespace cdm` on both sides; the app and lib share the namespace but
  NOT symbols — cross-module visibility needs `public` and follows import direction only.
- Manual JSON building everywhere (`string.append_*` chains + `json_escape`). Don't
  introduce the json emitter into hot paths; parsing uses `JsonParser + ASTJsonHandler`
  with top-level `JsonValue` variants (`Null/Boolean/Integer/Double/String/Array/Object`).
  Access maps via `get_ptr(string("key"))` and pattern-match `var String(s) = *vp`.
- `vector<T>`: use `.get_ptr(i)` (never `.get(i)` for destructible T — bitwise-copy temps
  double-free under TCC; see warnings in YtTools.ch). No `operator[]`. `.size()` not
  `.length()`.
- Returning struct-by-value with string members can trigger TCC compound-expression
  double-free — hence `check_tools_status_json` builds JSON directly instead of returning
  `ToolInfo` (documented inline in YtTools.ch).
- The Tools tab's "checking..." status (`ytTools` signal in `CdmApp.ch`) must never stay
  stuck: `refreshTools()` now (a) seeds a safe fallback immediately so a thrown/slow bridge
  call can't leave `ytTools` null, and (b) is invoked on mount (alongside `refresh`/
  `refreshSettings`). `asyncBridge`'s `.catch` swallows bridge errors, so any caller that
  must surface data should set its own fallback (as `refreshTools` does).
- **Manual JSON building: wrap every string value with `json_string()` EXACTLY ONCE.**
  `json_string()` (in `JsonBuild.ch`) already adds the surrounding quotes, so the field
  prefix must be `"\"key\":"` (NO trailing `\"`) and you append `json_string(value)`
  directly. Adding a manual leading/trailing `"` too produced `""yt-dlp""` — **invalid
  JSON** — which the webview framework's `JSON.parse(result)` then rejected with
  "Failed to parse binding result as JSON". That rejection was the real
  "yt-dlp/ffmpeg show Not Installed even though they ARE installed" bug: `check_tools_status_json`
  returned unparseable JSON, so the bridge promise rejected and the Tools tab stayed on the
  stale fallback. Use the `json_kv`/`json_kv_raw` helpers (which wrap with `json_string`)
  instead of hand-concatenating quotes. Regression test: `CDM_tools_status_json_parseable`.
- **Bridge results are ALREADY parsed objects, not strings.** The webview framework
  resolves `window.webview_bridge.call(...)` with a JS object (every `asyncBridge` consumer
  reads `d.items`/`d.x` directly). Do NOT `JSON.parse()` a bridge result — parsing an
  already-parsed object throws `SyntaxError`, and a silent `catch` leaves the UI stuck on a
  stale fallback. Guard with `typeof res === "string" ? JSON.parse(res) : res` if unsure.
  (The `cdm_bridge_ui` skill's `jsonResultString` naming is misleading — treat it as an object.)
- Uninitialized locals need `unsafe var x : T` (e.g. stream buffers, argv arrays).
- Strings: no `+`; use `append_view/append_string(&s)/append(char)`. Never append a moved
  string; copy explicitly with `.copy()` when both sides stay alive.
- Debug tracing is deliberate: `fprintf(stderr, "[CDM] ...")` throughout Engine/
  DownloadManager/YtTools. Keep prefixes consistent (`[CDM]`, `[CDM-BRIDGE]`,
  `[CDM-POLL]`, `[CDM-JS]` in browser console) when adding logs.
- `comptime_fnv1_hash("literal")` + `fnv1_hash(arg)` switch is the idiomatic
  string-dispatch pattern here (CLI flags, settings keys, bridge methods).
- Windows/macOS paths exist as `comptime if(def.windows/macos)` branches (tool URLs,
  binary names); Linux is the primary dev/test platform (GTK webview, xdg-open).
- `if` requires `else`; no bare ifs. No `defer`. Every `switch` on variants must cover all
  cases or provide `default`.

### YouTube playlist architecture (design decisions)

A playlist download is one logical job, but it fans out into N independent video+audio
downloads + ffmpeg merges. Decisions that are easy to break:

- **Per-item `AsyncDlState`**: each playlist entry gets its own `YtPlItem` (heap) embedding
  an `AsyncDlState` (`src/core/YtAsync.ch`). The video+audio+merge run exactly like a
  single YouTube download, so retry/link-refresh/merge logic is shared with `do_item_download`
  / `merge_monitor_entry`. Do NOT try to drive the whole playlist through one global
  `AsyncDlState` — that loses per-video retry and per-video merge error reporting.
- **`g_async_pl` global** (`@never_destructed`) holds `items : *mut vector<*mut YtPlItem>`,
  `dm : *mut DownloadManager`, `items_total/items_done`, `max_retries`, etc. The background
  thread `playlist_thread_entry` extracts entries with `yt-dlp --flat-playlist --print
  "%(url)s|||%(title)s|||%(duration)s"`, pushes a `YtPlItem` per line, and calls
  `do_item_download(&raw mut item.dl)` for each. After queuing, it loops until every item's
  `merge_status` is `merged` or `failed` (do NOT cancel mid-loop on `running=false`; the loop
  keys off `merge_status`, not `g_async_pl.running`).
- **One monitor thread per item**: `maybe_start_merge_monitor(dl)` spawns `merge_monitor_entry`
  which `snapshot(dm)`-polls the video+audio task ids, runs `ffmpeg_merge_files`, and on
  link/merge failure calls `requeue_item(dl)` (which `change_url` re-queues the DM tasks with
  refreshed URLs) and restarts the monitor, up to `dl.max_retries`. `retry_playlist_item(index)`
  does the same on demand from the UI.
- **Poll shape**: `yt_download_playlist_poll` returns a flat `videos` array — one object per
  item with `index,title,state,progress,video_task_id,audio_task_id,merge_status,merge_error,
  status,retry_count,output_path`. The UI renders the collapsible playlist card from this array
  and matches the per-video/audio segmented bars by `video_task_id`/`audio_task_id` against the
  DM `state` (`items`).
- **Cross-session link refresh**: resolved direct URLs expire. `g_yt_links : *mut vector<YtLinkRecord>`
  (heap, allocated with `new`, NOT a constructor call) persists `video_id/audio_id/youtube_url/format/...`
  to `~/.chemicaldm/yt_links.txt`. `refresh_stale_yt_links(&raw mut dm)` is called at launch
  (in `src/core/Main.ch` after `restore_queue`) and re-queues any stale links. Keep this call.
- **UI hides the child items**: the playlist's individual video/audio `DownloadItem`s are real
  DM tasks, but the main queue list must NOT show them as separate cards (the playlist card is
  enough). Track their task ids in `ytPlTaskIds` (rebuilt every `pollYtPlaylist` from
  `v.video_task_id`/`v.audio_task_id`) and filter `items` → `mainItems` before rendering. Keep
  `ytDownloading = true` for the whole playlist (clear it only in `pollYtPlaylist` when `d.done`)
  so the "No downloads yet" empty state stays suppressed while the playlist downloads.
- **Open file**: `yt_download_playlist_open` resolves `playlist_item_output_path(index)` then
  launches the merged file with `process::execute("xdg-open", path, ...)`. There is NO
  `open_file` symbol in this module — use `process::execute` (fork-safe; see the yt-dlp rule).

### Lessons learned (Chemical / cdm gotchas)

These bit us and cost real debugging time — honor them:

1. **`malloc` + assignment is a heap-corruption bug for structs with a `mutex`/destructor.**
   `var p = malloc(sizeof(T)) as *mut T; *p = T()` constructs a temporary, move/copies it into
   the malloc'd region, then the **temporary's destructor runs** and destroys the embedded
   `mutex` (or runs the dtor) — leaving the heap struct's mutex invalid. A later `mu.lock()`
   in a worker thread then corrupts the heap → `free(): invalid pointer` / `abort()`.
   **Always use `new T()` to construct in place.** (Fixed in `playlist_thread_entry`.)
2. **The test module can only call `public` functions.** A `tests/*.ch` test calling an internal
   `func foo(...)` fails symbol resolution and the build aborts with
   `[lab] error: failure during symbol resolution in the module chemicaldm` — the actual cause
   is an unresolved symbol, NOT the pointer-deref *warnings* (those are tolerated). Make the
   function `public` (as with `parse_playlist_json`).
3. **`TestEnv` error API**: `env.error(msg : *char)` only. There is **no** `error_int`. Build the
   message into a `string` (e.g. `env.error("expected 2 entries")`).
4. **No `==`/`!=` overload for `string`.** Comparing strings with `!=`/`==` fails with
   "expected the value to have primitive type or have operator overloaded". Use
   `s.equals_view(&other)` / `s.equals(&other)` / `s.find(...)`.
5. **Playlist info MUST be parsed with `parse_playlist_json`, not `parse_video_json`.**
   `yt-dlp --dump-json --flat-playlist` emits **NDJSON** (one JSON object per line). The old
   `get_async_info` used `parse_video_json`, which only sees the first line → dialog showed a
   single video's title and "0 videos". `parse_playlist_json` tries NDJSON line-splitting FIRST,
   then falls back to a single object with an `entries` array. `YtPlaylistInfo` carries
   `is_playlist` (set `true` inside the parser) and emits it in `to_json()` so the UI branches
   correctly.
6. **Pointer deref in safe context** (`&mut *dm`, `*(vec.get_ptr(i))`) is only a *warning* in
   `--build` but trips the stricter `--test` symres path in some configs. Prefer keeping such
   expressions valid in both; if unavoidable, wrap in `unsafe { }`.
7. **`if` requires `else`; no bare `if`; no `defer`; every `switch` on a variant needs all cases
   or `default`.** Ternary `? :` is NOT supported — use `if/else`.

### Where to change what (cheat sheet)

| Task | File(s) |
|---|---|
| New bridge method | `src/api/Bridge.ch` (`bridge_call`) + handler in `src/ui/CdmApp.ch` |
| New queue operation | `cdmlib/src/DownloadManager.ch` (+ test in `cdmlib/tests/feature_tests.ch`) |
| Engine/download behavior | `cdmlib/src/Engine.ch` (+ integration test) |
| Setting persisted to disk | `src/core/Settings.ch` (struct + writer + loader) → expose in `apply_settings_to_dm`, `settings_json`/`settings_set` in Bridge, UI control in CdmApp |
| New category/folder mapping | `src/core/Categories.ch` (+ `validate_category_name` in Validation.ch) |
| Human-readable text | `src/core/Formatters.ch` |
| yt-dlp invocation / progress parsing / ffmpeg merge | `src/core/YtDownloader.ch` (+ `YtInfo.ch` for metadata, `YtTools.ch` for install/status) |
| YouTube playlist (async fan-out, per-item `AsyncDlState`, poll `videos` array, retry/link-refresh, hide child cards) | `src/core/YtAsync.ch` (`g_async_pl`, `playlist_thread_entry`, `do_item_download`, `merge_monitor_entry`, `requeue_item`, `retry_playlist_item`, `playlist_item_output_path`, `poll_async_playlist_download`) + `yt_download_playlist*` handlers in `src/api/Bridge.ch` + playlist card / `ytPlTaskIds` filter in `src/ui/CdmApp.ch` |
| YouTube info parsing (playlist NDJSON vs single video) | `src/core/YtInfo.ch` (`parse_playlist_json` NDJSON-first, `YtPlaylistInfo.is_playlist`) + `get_async_info` playlist dispatch in `src/core/YtAsync.ch` |
