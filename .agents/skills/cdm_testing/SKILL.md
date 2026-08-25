---
name: cdm_testing
description: How the ChemicalDM test suites work — @test/TestEnv harness, run.sh --test flow, cdmlib unit/feature/integration suites including the in-process loopback HTTP Range server, app-level suites, and patterns for writing new tests. Load before writing or running cdm tests.
---

# ChemicalDM testing guide

## Harness

- Tests are `@test`-annotated functions taking `&mut TestEnv` (from the `test_env`
  module): `@test public func CDM_whatever(env : &mut TestEnv)`.
- Fail with `env.error("message"); return` — no exceptions, early-return after error.
- The runner forks ONE PROCESS PER TEST, so tests can bind ports, spawn threads, and
  mutate globals without cross-contamination.
- Entry point: `main()` in `src/Main.ch` scans argv for `--test/--test-id/--comm-id/
  --test-ids/--test-names` and dispatches to `test_runner(argc, argv)` BEFORE any other
  CLI handling. That's why the built binary doubles as the test runner child.

## Running

```bash
./run.sh --test          # builds with --test and runs ./bin/cdm --test
# equivalent manual flow:
../../../cmake-build-debug/TCCCompiler chemical.mod -o bin/cdm --mode debug_quick --no-cache --test
./bin/cdm --test
```

`--test` on the compiler defines the `test` def, which activates in BOTH modules:
- `cdmlib/chemical.mod`: `import test if test`, `import test_env if test`,
  `source "tests" if test`
- root `chemical.mod`: same for the app's `tests/`

Suite layout today (app `./run.sh --test`): bridge 22, cli 5, format 6, json 6, proc 1,
 queue 15, segment 11, settings 8, yt 45 (≈119 app tests; the `--test` run also collects
 any cdmlib `@test` fns compiled in and currently reports **144 passing**). cdmlib tests
 build separately via `cdmlib/chemical.mod --test` (unit 7 + feature 8 + integration 14 +
 behavior 13).

## Suite layout & what goes where

| Suite | File | Covers | Network? |
|-------|------|--------|----------|
| unit | `cdmlib/tests/unit_tests.ch` | parse_content_length/range_total/disposition, suggested_filename, sanitize_filename, UrlInfo, formatters | no |
| feature | `cdmlib/tests/feature_tests.ch` | DownloadManager ops: add/find, priority ordering, edit_item dir change, retry/restart semantics | no |
| integration | `cdmlib/tests/integration_tests.ch` | REAL downloads against a local server: single-stream, segmented, resume after pause/interrupt, throttled/chunked servers, 416 handling, duplicate naming | loopback only |
| cli | `tests/cli_tests.ch` | parse_cli flags, priority parsing | no |
| format/json | `tests/format_tests.ch`, `tests/json_tests.ch` | Formatters; JsonBuild wire format incl. escaping | no |
| proc | `tests/proc_test.ch` | process execution plumbing | no |
| queue | `tests/queue_tests.ch` | add_task_ex/priority/change_url/pause/resume/cancel/remove via public API (uses `find_item_for_tests` to poke state) | no |
| segment | `tests/segment_tests.ch` | compute_segment_count boundaries, build_segments math, category helpers | no |
| settings | `tests/settings_tests.ch` | config round-trip via `save_settings_to_string`/`parse_settings_string` (in-memory) AND a real disk round-trip via `save_settings`/`load_settings` isolated with `CDM_CONFIG_DIR` | no |
| http | `tests/http_tests.ch` | REAL downloads against `tests/http_server.py` (python `ThreadingHTTPServer` with Range/206) on loopback — 1 MiB segmented, 50 KiB single-stream, 5 MiB large; byte-verified against the served payload; tears down server (`fuser -k`) + temp dirs | loopback only (needs `python3`, `fuser`) |
| yt | `tests/yt_tests.ch` | yt-dlp arg building, playlist URL detection, progress-line parsing, JSON field extraction — all offline | no |
| tools | `tests/tools_tests.ch` | yt-dlp/ffmpeg availability + `check_tools_status_json` reporting: `CDM_TOOLS_DIR` redirection, `installed`/`not_installed` status matches reality, status-object structure (`name`/`status`/`version`/`path` + `both_ready`), status agrees with `ytdlp_is_available()`/`ffmpeg_is_available()` | no |
| bridge (tools) | `tests/bridge_tests.ch` | `CDM_BR_tool_download_progress` drives a REAL redirected install via `CDM_TOOL_URL_OVERRIDE` and polls `yt_status` to assert `"status":"downloading"` + progress > 0 (covers the live install-reporting path the `tools` suite can't) | loopback only (needs `python3`) |

Rule of thumb: library logic → cdmlib tests; wire format/UI-facing serialization →
json_tests; anything needing real sockets → integration suite only.

## Isolation tricks

- **Config isolation**: Settings code honors `CDM_CONFIG_DIR`; when unset it uses
  `$HOME/.chemicaldm`. Tests that touch persistence set this env var first.
- **Tool isolation**: tool paths honor `CDM_TOOLS_DIR` (else `$HOME/.chemicaldm/tools`).
- **Temp dirs**: integration tests download into fresh temp directories.
- Integration server base port is `TEST_PORT : uint = 0x0000BBDu` (= 3005; the inline
  comment claiming 3009 is stale). Tests allocate ports via a helper that returns
  `GLOBAL_TEST_PORT + offset` (see `get_port` around line 285), so parallel servers use
  distinct ports automatically — reuse that helper instead of hardcoding.

## The integration TestServer pattern

`cdmlib/tests/integration_tests.ch` embeds a minimal threaded HTTP file server:

```chemical
struct TestServer {
    var listen_sock : net::Socket
    var root : string        // serves files from here
    var port : uint
    var running : bool
    var thread : std::concurrent.Thread
    var chunk_bytes : int      // throttle: bytes per write
    var chunk_delay_ms : int   // throttle: sleep between writes
}
```

Implements exactly what the engine needs: GET, Content-Length, `Range:` → 206 partial
responses, 416 for unsatisfiable ranges. One GET per connection. Tests:
1. create a payload file in a temp dir,
2. start the server,
3. build a DownloadManager pointed at the allocated port on 127.0.0.1,
4. poll `snapshot()` until terminal state (or drive pause/resume mid-flight),
5. assert output file bytes match the payload,
6. stop server, clean up.

Copy this pattern for any new end-to-end behavior (e.g. testing speed limits — use the
chunk throttle fields).

## Writing tests — conventions

```chemical
using std::string;
using std::string_view;

@test
public func CDM_my_feature(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 10                    // avoid scheduler interference
    var id = cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/a.bin"))
    if(id.empty()) { env.error("add_task returned empty id"); return }
    var idx = cdm::find_item_index(&dm, &id)
    if(idx == dm.items.size()) { env.error("not found"); return }
}
```

- Helper style: local expect helpers like `cdm_expect_eq(env,label,&got,&want)` /
  `cdm_expect_true(...)` (see top of unit_tests.ch).
- Multi-condition asserts: separate `if(!cond) { env.error("..."); return }` blocks —
  do NOT chain `&&` across lines inside lambdas (Chemical parser rejects multi-line
  expressions in lambda bodies).
- Queue tests may see QUEUED *or* DOWNLOADING depending on whether start_pending already
  spawned a worker — accept both where legitimate (see CDM_queue_add_and_find).
- To simulate states directly use `cdm::find_item_for_tests(&mut dm, &id)` →
  `*mut DownloadItem` into the queue.
- Uninitialized buffers need `unsafe var argv : [4]*char` (cli_tests pattern).
- **String-temporary dangling-pointer gotcha**: passing `func_returning_string().data()`
  straight into a callee dangles — the temporary string is destroyed before the callee
  reads the pointer (saw this as `fopen` getting garbage in `http_tests.ch`). Always store
  first: `var p = it.local_path(); use(p.data())`. When the dir is deterministic, build the
  path into a named var instead of relying on snapshot string fields.
- Names prefix `CDM_` everywhere; keep them descriptive — the runner prints test names.

## Debugging a failing suite

1. Engine logs go to stderr with `[CDM]` prefixes (probe values, segment picks, retries);
   bridge/tool logs use `[CDM-BRIDGE]` / `[CDM-POLL]`. Run the binary directly to see them.
2. Per-test process isolation means a crash kills only that test — check the runner
   summary for missing/failed counts rather than assuming later tests ran.
 3. The app builds clean and the suite passes (see repo AGENTS.md "Current state"). If a
    build fails, compile cdmlib alone first to isolate the side:
    `../../../cmake-build-debug/TCCCompiler cdmlib/chemical.mod -o /tmp/x`.
