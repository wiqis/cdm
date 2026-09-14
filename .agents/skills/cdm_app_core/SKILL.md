---
name: cdm_app_core
description: ChemicalDM app-support layer (non-UI, non-library) — CLI parsing, CdmSettings config.txt, category routing, Validation single-truth, ErrorCodes, manual JSON building (JsonBuild), and human-readable Formatters. Load when adding a setting, CLI flag, category, or user-visible string.
---

# ChemicalDM app core (src/core, minus yt*)

Everything here is app-side glue between the UI/CLI and cdmlib. It resolves everything
user-visible BEFORE calling the library (dirs, names, categories) — the library only ever
sees URL → dir → filename → bytes on disk.

## Files

| File | Contents |
|------|----------|
| `src/core/Cli.ch` | `CliOptions`, `parse_cli` (fnv-hash switch on flags), `run_headless` (batch URLs / `--file batch.txt`, prints progress to stdout). CLI surface: `cdm <url>...`, `--file batch.txt`, `-d dir -o name`, `-p segments -j concurrent --speed-limit kb --priority n`, `--gui/-g`, `-q`, `-v`, `-h`; no args → GUI; anything non-URL → headless |
| `src/core/Categories.ch` | `Category` enum (Other=0, Documents, Programs, Video, Music, Compressed), extension → category map, `category_dir` (subfolder name), `categorize_path` |
| `src/core/Settings.ch` | `CdmSettings` (~60 fields), `config.txt` read/write, `settings_json`/`settings_set` payload side, `apply_settings_to_dm` (app→lib bridge), `save_settings_to_string`/`parse_settings_string` (in-memory roundtrip used by tests), `settings_import`/`settings_export` support, queue.txt save/restore (see `cdm_persistence` skill) |
| `src/core/Validation.ch` | `ValidationError` + `validate_url/max_concurrent/...` — the SINGLE source of validation truth; Bridge and CLI both call it |
| `src/core/ErrorCodes.ch` | `CdmErrorCode` enum + `CdmError {code,message}` |
| `src/core/JsonBuild.ch` | `json_escape`, `json_string` (adds surrounding quotes — wrap EXACTLY ONCE), `json_kv`/`json_kv_raw` helpers, `item_to_json` (the UI wire contract) |
| `src/core/Formatters.ch` | `format_bytes`, `format_speed`, `format_eta`, `format_state` (int → human name: Queued/Downloading/Paused/Done/Failed/Cancelled), `format_category` |
| `src/core/Storage.ch` | LEGACY json state file — superseded by Settings.ch queue.txt. DEAD code, don't extend; candidate for deletion |

## Settings model

`CdmSettings` highlights (full struct in Settings.ch):

- Download behavior: `download_dir, max_concurrent, max_segments, min_segment_size,
  speed_limit_kbps, enable_resume, allow_segments, duplicate_action (0=rename,1=overwrite,
  2=skip), auto_start, temporary_folder, move_completed_to, post_download_cmd,
  use_categories, auto_rename_duplicates, categories, category_dirs, min_disk_space_mb,
  max_download_size`
- Network: `proxy_host, proxy_port, user_agent, cookie_file, verify_ssl, connect_timeout,
  network_timeout, auth_header, referer_header, force_ipv4, force_ipv6, checksum,
  bandwidth_limit_per`
- Housekeeping/UI: `auto_resume_failed, max_retries, retry_delay_ms, notifications_enabled,
  language, theme, max_history, quiet`
- ~30 `yt_*` fields mirroring yt-dlp options (quality, subs, metadata, SponsorBlock,
  geo-bypass, playlist ranges, output template…) — see `cdm_yt_tools` skill.

### config.txt format

Line-based `key:value`, parsed and written MANUALLY (no json module). Keys are matched
with the `comptime_fnv1_hash("literal")` + `fnv1_hash(arg)` switch — the idiomatic
string-dispatch pattern in this codebase (~192 hash sites in Settings.ch). Booleans are
`true`/`false` literals (`parse_bool`).

### Adding a new setting (full path)

1. Field on `CdmSettings` + default in the constructor.
2. Writer: append `key:value` in `save_settings_to_string` (keep ordering stable).
3. Loader: `fnv1_hash(key)` case in `parse_settings_string` (and config.txt loader).
4. `apply_settings_to_dm` if the library needs it (manager fields only — cdmlib knows
   nothing about settings files).
5. `settings_json` payload + `settings_set` handler in Bridge.ch so the UI can read/write it.
6. UI control in `src/ui/CdmApp.ch` Settings dialog (`applySettings` reads form →
   `settings_set`).
7. Roundtrip test in `tests/settings_tests.ch` (`save_settings_to_string` →
   `parse_settings_string`, plus the disk roundtrip under `CDM_CONFIG_DIR`).

## Category routing (the layering contract in practice)

The APP resolves category → directory before calling the library:

```
Bridge add:   category name string → Category enum → category_dir(cat)
              → resolved_dir = download_dir + "/" + sub   (skip '/' if root ends in '/')
              → add_task_ex(..., resolved_dir, cat_tag)   // tag stored OPAQUELY
CLI:          cli_route does the same for --category/--categories
edit:         read the item's CURRENT category under lock first, then merge incoming args
              (cat >= 0 ? cat : current) — hardcoding 0 silently reset categories on edit
```

cdmlib never interprets the int tag. `validate_category_name` (Validation.ch) is the
single truth for accepted names.

## Validation & errors

- `ValidationError {ok, message}` + `is_ok()`; validators: `validate_url` (scheme must be
  http/https, non-empty host), `validate_max_concurrent`, `validate_max_segments`,
  `validate_speed_limit`, `validate_priority`, `validate_max_retries`,
  `validate_retry_delay`, `validate_task_speed_limit`, `validate_duplicate_action`,
  `validate_not_empty`, `validate_directory`, `validate_category_name`,
  `validate_segments` — the single truth for limits.
- Bridge `add` validates the URL BEFORE queueing so users get immediate feedback instead
  of a later failure. The CLI currently does NOT call these validators (see the
  `cdm_cli` skill note) — funnel new CLI checks through Validation.ch.
- `CdmErrorCode` enum + `CdmError{code,message}` for structured errors.
- Headless mode reports parse failures and exits non-zero (`return 1` sites in Cli.ch).

## JSON building rules (JsonBuild)

1. **`json_string()` wraps EXACTLY ONCE** — it already emits the surrounding quotes, so
   the field prefix is `"\"key\":"` with NO trailing `\"`. Double-wrapping produced
   `""yt-dlp""` → invalid JSON → bridge promise rejected (the "tools show Not Installed"
   bug). Prefer `json_kv`/`json_kv_raw`.
2. Manual `string.append_*` chains; don't introduce the json emitter into hot paths.
3. Parsing (settings import, yt-dlp output) uses `JsonParser + ASTJsonHandler` with
   `JsonValue` variants (`Null/Boolean/Integer/Double/String/Array/Object`); access maps
   via `get_ptr(string("key"))` and pattern-match `var String(s) = *vp`.

## Conventions

- Human-readable text lives in Formatters.ch — never build display strings ad hoc in
  Bridge/UI (state/category names especially: the UI matches on the human names).
- No `==`/`!=` on strings — use `.equals_view()`/`.equals()`/`.find()`.
- `~` expansion via `expand_home` (cdmlib), env roots via `CDM_CONFIG_DIR` (settings) and
  `CDM_TOOLS_DIR` (tools) — tests depend on both.
- No `+` on strings: `append_view`/`append_string(&s)`/`append(char)`; copy with
  `.copy()` when both sides stay alive; never append a moved string.
- `if` requires `else`; no ternary `?:`; switches on variants need all cases or `default`.
