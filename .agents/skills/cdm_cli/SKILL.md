---
name: cdm_cli
description: ChemicalDM headless CLI — CliOptions parsing, batch downloads from files/URLs, headless progress rendering, CLI↔settings interaction, error codes, and how the same binary doubles as GUI, CLI, and test runner. Load when adding CLI flags, fixing headless mode, or changing main() dispatch.
---

# ChemicalDM CLI & headless mode

`src/core/Cli.ch` (~660 lines) handles everything when the app runs without the GUI.
The binary dispatches on argv shape (see `src/Main.ch` main()):

```
./bin/cdm --test ...     → test_runner (BEFORE anything else)
./bin/cdm                → GUI (no args)
./bin/cdm <url>...       → headless download of the URLs
./bin/cdm anything-non-url / flags → headless mode
```

## CLI surface

```
cdm <url>...                     # download URLs
  --file batch.txt               # one URL per line
  -d, --dir DIR                  # destination directory
  -o, --out NAME                 # output filename
  -p, --segments N               # max segments per download
  -j, --jobs N                   # max concurrent downloads
  --speed-limit KB               # per-task speed limit
  --priority N                   # queue priority (lower = sooner)
  --category NAME                # route to a category folder
  --max-size BYTES               # max_download_size (parsed, not enforced)
  --min-disk MB                  # min_disk_space_mb (parsed, not enforced)
  --post-cmd CMD                 # post-download command, {} = output path (ENFORCED)
  --gui / -g                     # force GUI
  -q                             # quiet
  -v / -h                        # version / help
```

`parse_cli` fills `CliOptions`; unrecognized args → headless with an error message and a
non-zero exit. String dispatch uses the `comptime_fnv1_hash("flag")` + `fnv1_hash(arg)`
switch pattern. argv buffers are `unsafe var argv : [N]*char` (see cli_tests).

## run_headless flow

1. `load_settings` → overlay CLI flags (CLI wins over config.txt).
2. Apply onto the DownloadManager (`apply_settings_to_dm` equivalent fields: jobs,
   segments, speed limit, post_download_cmd…).
3. Route categories: `--category`/`--categories` → `cli_route` resolves the destination
   dir exactly like the Bridge `add` path (see `cdm_app_core` skill) — one truth for
   category → folder mapping.
4. `add_task_ex` per URL (validating first), then poll `snapshot()` and print progress
   lines (formatted by Formatters.ch) until all items reach a terminal state.
5. Exit code reflects failures (validation errors and failed downloads).

## Batch file semantics

`--file` reads one URL per line; empty lines and `#` comments are skipped. Each line
gets its own task with the shared dir/name/priority options.

## Adding a CLI flag (checklist)

1. `CliOptions` field + default in the constructor.
2. Parse case in the fnv-hash switch inside `parse_cli` (long and short forms).
3. Wire into `run_headless` (manager field or per-task override) — prefer routing through
   `apply_settings`-style merging so GUI and CLI share semantics.
4. Update `-h` text.
5. Test in `tests/cli_tests.ch` (parse-level tests only; headless e2e needs network or
   the loopback server pattern from `tests/http_tests.ch`).
6. If the flag mirrors a GUI setting, mirror it in `settings_json`/`settings_set` too
   (see the "adding a setting" checklist in the `cdm_app_core` skill).

## Conventions & gotchas

- CLI and Bridge must BOTH call `Validation.ch` validators — no separate CLI-only
  validation rules (single truth, see `cdm_app_core` skill).
- Headless prints to stdout with `\r` progress updates; the GUI bridge never writes to
  stdout (the webview owns the process stdio). Don't add prints inside bridge paths.
- `--test` dispatch in main() must stay FIRST — the test runner spawns this same binary
  with `--test-id/--comm-id` and any other handling would break it.
- Exit codes: 0 = all downloads ok, non-zero = validation failure or any failed task
  (used by scripts/CI).
- CLI-only flags that don't exist as settings (e.g. `--file`) live only in CliOptions;
  do not force every flag into CdmSettings.
