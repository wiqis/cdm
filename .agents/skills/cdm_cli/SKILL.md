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
  --file/-f batch.txt            # one URL per line, blank lines + # comments skipped
  -d,  --dir DIR                 # destination directory
  -o,  --output NAME             # output filename (--name alias too)
  -p,  --segments N              # max segments per download
  -j,  --concurrent N            # max concurrent downloads
  --speed-limit / --limit KB     # per-task speed limit
  --priority / --prio N          # queue priority (lower = sooner)
  --category/--categories NAME   # route to a category folder (--no-categories to disable)
  --user-agent / --ua S          # custom UA
  --cookies FILE                 # cookie jar (parsed; not yet consumed by the engine)
  --no-ssl-verify                # parsed; NOT yet plumbed to the engine (see cdm_http_client)
  --connect-timeout / --cto S    # socket timeout
  --referer / --ref / --auth     # extra headers
  --proxy host:port              # proxy for engine requests
  --template S / --name S        # filename template / name
  --checksum algo:hex            # e.g. md5:abc123 (parsed; not verified yet)
  --max-size BYTES               # max_download_size (parsed, not enforced)
  --min-disk MB                  # min_disk_space_mb (parsed, not enforced)
  --post-cmd CMD                 # post-download command, {} = output path (ENFORCED)
  --yt-quality / --yt-format / --yt-audio-only / --yt-max-playlist   # yt-dlp overrides
  --export-settings FILE         # write current settings as JSON and exit
  --import-settings FILE         # load settings JSON and exit
  --gui / -g                     # force GUI
  -q                             # quiet
  -v / -h                        # version / help
```

`parse_cli` fills `CliOptions`; unrecognized args → headless with an error message and a
non-zero exit. String dispatch uses the `comptime_fnv1_hash("flag")` + `fnv1_hash(arg)`
switch pattern. argv buffers are `unsafe var argv : [N]*char` (see cli_tests).

## run_headless flow

1. `load_settings` → `apply_settings_to_dm`, then overlay CLI flags onto the manager
   (CLI wins over config.txt; explicit `if(opts.X > 0)` guards per field).
2. Route categories: `--category`/`--categories` → `cli_route` resolves the destination
   dir exactly like the Bridge `add` path (see `cdm_app_core` skill) — one truth for
   category → folder mapping.
3. `add_task_ex` per URL, then poll `snapshot()` and print progress lines (formatted by
   Formatters.ch) until all items reach a terminal state.
4. Exit codes: 0 = success, 1 = validation/parse failure or failed downloads (see the
   `return 1` sites in Cli.ch).

NOTE: the CLI currently does NOT call `Validation.ch` validators on flags (the Bridge
`add` path does `validate_url` before queueing). Flag values are range-checked only where
`parse_cli` builds them — if you touch CLI input handling, prefer funneling through
Validation.ch so GUI and CLI share one truth.

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

- Headless prints to stdout with `\r` progress updates; the GUI bridge never writes to
  stdout (the webview owns the process stdio). Don't add prints inside bridge paths.
- `--test` dispatch in main() must stay FIRST — the test runner spawns this same binary
  with `--test-id/--comm-id` and any other handling would break it.
- CLI-only flags that don't exist as settings (e.g. `--file`) live only in CliOptions;
  do not force every flag into CdmSettings.
