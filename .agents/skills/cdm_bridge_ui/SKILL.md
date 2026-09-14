---
name: cdm_bridge_ui
description: End-to-end feature development in the ChemicalDM app — adding a bridge method (JS→native), the JSON wire format, CdmApp universal component patterns (state, polling, dialogs), the theme system, and GUI lifecycle. Load when working on src/api/Bridge.ch, src/ui/, or Main.ch.
---

# ChemicalDM app — bridge + UI

The desktop GUI is a WebKitGTK webview showing SSR HTML from a single `#universal`
component (`src/ui/CdmApp.ch`, ~1960 lines). There is NO local HTTP server: JS talks to
native through `webview::webview_bind` → `cdm::bridge_call` (`src/api/Bridge.ch`, ~940 lines).

## GUI startup sequence (`src/Main.ch run_gui`)

```
DownloadManager() → load_settings + apply_settings_to_dm
  → fs::create_dir_all(download_dir) → restore_queue(dm)
  → build_ui_html(): HtmlPage + defaultPrepare + defaultUniversalSetup
      + injectDefaultComponentsTheme + viewport/title + CdmTheme(&mut page)
      + #html { <CdmApp /> }   → page.toString("", "dark", "chx-default")
  → webview::create(CDM_NAME, 1080, 720) → webview_bind(handler)
  → webview_load_html → webview_show → webview_run (blocks on GTK loop)
  → webview_destroy → shutdown(&mut dm) → save_queue(&dm)
```

The bridge handler captures `&raw mut dm` in a capturing lambda:
```chemical
webview::webview_bind(&raw mut wv, (|dmp|(method, args) => {
    return cdm::bridge_call(dmp, method, args)
}))
```

## Bridge protocol

JS side:
```js
window.webview_bridge.call(method, argsJson).then(function(result) { ... })
```

**The framework resolves the promise with an ALREADY-PARSED JS object** (not a JSON
string) — every consumer reads `d.items` / `d.x` directly. Do NOT `JSON.parse()` the
result (parsing an object throws `SyntaxError`, and a silent `catch` leaves the UI on a
stale fallback). If you must be defensive:
`var r = (typeof result === "string") ? JSON.parse(result) : result;`

Native side `bridge_call(dm : *mut DownloadManager, method : string_view, args : string_view) : string`
(the native handler returns a JSON *string*; the framework parses it before resolving).

**Args-wrapping gotcha**: the injected bridge JS wraps bodies as `{id, method, params:[body]}`,
so `args` may arrive as `"[{\"url\":...}]"`. ALWAYS extract fields through the helpers
`json_field / json_int_field / json_bool_field` — they call `resolve_bridge_args()` first,
which unwraps element 0 when it's a stringified object.

Response envelope (build with `ok_json()/err_json(&msg)`):
```json
{"ok":true}
{"ok":false,"error":"..."}
{"ok":true,"id":"<uuid>"}          // add
{ ... state document ... }         // state / settings_get / yt_status / yt_info / polls
```

Method dispatch declares `var m_<name> = string_view::make_no_len("<name>")` then chains
`method.equals(&m_<name>)`. Current method set (grouped):

- **Queue**: `state, add, pause, resume, cancel, remove, remove_file, retry, restart,
  edit, change_url`
- **Settings**: `settings_get, settings_set, settings_export, settings_import`
  (export/import write/read a JSON settings file at an explicit `path`)
- **Desktop**: `open_file, show_in_folder, clipboard_monitor` (toggle clipboard watching)
- **Tools**: `yt_status, yt_install` (+ per-tool status JSON)
- **yt-dlp info/download**: `yt_info, yt_info_get, yt_info_poll, yt_download,
  yt_download_poll, yt_cancel, debug_log`
- **Playlist**: `yt_download_playlist, yt_download_playlist_poll,
  yt_download_playlist_retry, yt_download_playlist_open` (see the `yt_playlist` skill)
- **~35 `yt_*` option setters** (persisted via CdmSettings): `yt_proxy, yt_quality,
  yt_format, yt_audio_only, yt_audio_format, yt_audio_quality, yt_max_playlist_items,
  yt_output_template, yt_merge_output_format, yt_recode_video, yt_write_subs,
  yt_write_auto_subs, yt_sub_langs, yt_embed_subs, yt_convert_subs, yt_embed_metadata,
  yt_embed_thumbnail, yt_write_description, yt_write_info_json, yt_write_comments,
  yt_restrict_filenames, yt_trim_filenames, yt_no_overwrites, yt_playlist_start,
  yt_playlist_end, yt_playlist_items, yt_geo_bypass, yt_geo_bypass_country,
  yt_no_check_certificates, yt_legacy_server_connect, yt_socket_timeout,
  yt_source_address, yt_ffmpeg_location, yt_exec_cmd, yt_extractor_retries,
  yt_sponsorblock_mark, yt_remove_sponsorblock`
- Also handled in `settings_set`: generic `proxy_host/proxy_port, user_agent, cookie_file,
  verify_ssl, connect_timeout, auth_header, referer_header, force_ipv4/force_ipv6,
  checksum, max_download_size, min_disk_space_mb, post_download_cmd, move_completed_to,
  filename_template, notifications_enabled, language, theme, max_history, auto_start,
  quiet, use_categories, auto_rename_duplicates, bandwidth_limit_per, temporary_folder,
  debug_log, category*, duplicate_action, auto_resume_failed, enable_resume,
  allow_segments, max_concurrent, max_segments, max_retries, retry_delay_ms,
  download_dir, speed_limit_kbps`

### Checklist: adding a new bridge method

1. Native handler in `Bridge.ch::bridge_call` — declare `var m_<name> = ...` next to the
   others, parse fields via `json_*` helpers, validate with `src/core/Validation.ch`,
   call the DownloadManager/library API or app core, return `ok_json()`/`err_json()`/payload.
2. If it exposes new data, extend the payload builder (`state_json`, `settings_json`,
   `item_to_json` in `src/core/JsonBuild.ch`) — manual string building with `json_string()`
   escaping; raw pre-serialized values go through `json_kv`/`json_kv_raw`.
3. JS wrapper in `CdmApp.ch`: use `post(method, id, extra)` (adds id + refreshes) or
   `call(method, body, onDone)` or raw `asyncBridge(method, body, onResult)`.
4. App-level test if the logic is testable headlessly (`tests/json_tests.ch` pattern for
   wire-format round-trips, `tests/bridge_tests.ch` for bridge_call itself).
5. Blocking methods (spawn processes): the caller must wrap the bridge call in
   `setTimeout(..., 50)` so the GTK UI paints its "loading" state first — see
   `fetchYtInfo()`/`startYtDownload()` in CdmApp.ch. Longer-running work belongs behind a
   background thread + poll pair (the `yt_info`/`yt_info_poll` pattern, `src/core/YtAsync.ch`).

### State JSON item shape (contract with the UI)

From `item_to_json` (`JsonBuild.ch`) + `snapshot_segments_json` (Engine.ch):
`id, url, filename, display_name, dir, state` (HUMAN name: Queued/Downloading/Paused/Done/
Failed/Cancelled — NOT the int), `error, total_bytes, downloaded_bytes,
speed_bytes_per_sec, priority, max_segments, speed_limit_kbps, duplicate_suffix,
category` (human name), `percent` (string), `eta` (string), `retry_count,
was_interrupted` (raw bool literal), and optional `segments` array of
`{index,start,end,total,copied,done}`.
Top-level `state` doc: `download_dir, max_concurrent, version, items[]`.
Settings doc (`settings_json`): mirrors `CdmSettings` (`download_dir, max_concurrent,
max_segments, speed_limit_kbps, enable_resume, allow_segments, duplicate_action,
auto_resume_failed, max_retries, retry_delay_ms, proxy_host, proxy_port, user_agent, …`
— see the `cdm_app_core` skill for the full field list).

## CdmApp component patterns (`src/ui/CdmApp.ch`)

One `#universal CdmApp(props)`. Conventions to follow:

- **State**: plain `state name = initial` per concern (items, dialog open flags, form
  fields, toast, ctx menu, tabs). Reassign whole values; don't mutate arrays in place for
  reactivity (`ytPlaylistSelected = ytPlaylistSelected.filter(...)` not push).
- **Polling**: `useEffect(..., [])` sets `setInterval(refresh, 1000)` calling bridge
  `state`; cleanup returns `() => clearInterval(t)` plus removes the global mousedown
  listener that closes the context menu.
- **Derived lists** are computed inline each render: `visibleItems = items.filter(...)`
  then `.sort(...)` — filter chips (`filter`, `catFilter`), search box, sort dropdown all
  feed this. Match states by HUMAN strings ("Downloading"), categories by name too.
- **Playlist child-item hiding**: children are filtered by `card_type` in the item JSON —
  `mainItems = items.filter((u) => u.card_type !== CARD_YT_CHILD)`; top-level cards dispatch
  on type (`renderPlaylistCard` / `renderYtVideoCard` / `renderNormalCard`). Keep
  `ytDownloading = true` until `d.done` (clears empty-state flicker). See the `cdm_containers` skill.
- **Dialogs**: pattern `{open && item ? (<div class="cdm-dialog-overlay" onClick={close}>
  <div class="cdm-dialog" onClick={(e)=>{e.stopPropagation()}}>...) : null}`.
- **Context menu**: `openContextMenu(e,item)` records clientX/Y into state; actions map to
  bridge methods; special-cases open_file/show_in_folder which take a path not an id.
- **Per-segment progress**: item.segments array → flex row of `cdm-seg` bars, width
  `100/n%`, fill `% = copied*100/total`, class done/active/pending.
- **Resume button logic**: Failed items show Resume only when error ===
  "interrupted by shutdown" (matches Engine shutdown marker); otherwise Retry.
- **Toasts**: `showToast(msg,type)` + auto-hide `setTimeout(4000)`; types info/success/error.
- **Error surface**: `<ErrorOverlay />` (shared components lib) is mounted at the root;
  `window.__reportError(msg, stack?)` is the way bridge consumers that swallow errors
  (`.catch`) surface failures. `refreshTools()` seeds a safe fallback BEFORE awaiting the
  bridge so a slow/failed call can't leave `ytTools` null.

## Theme (`src/ui/CdmTheme.ch`)

All CSS lives here appended via `page.append_css_view(""" ... """)`.
Class prefix convention: `cdm-*` for everything new. Colors use shadcn-style tokens
injected by `page.injectDefaultComponentsTheme()`: `hsl(var(--primary))`,
`hsl(var(--muted-foreground))`, `hsl(var(--border))`, `hsl(var(--destructive))`, etc.
Never hardcode palette colors except YouTube brand red (#ff0000 accents are fine).

## Desktop integrations

- `open_file` / `show_in_folder`: spawn `xdg-open <path>` via
  `process::execute` (fork-safe; raw `popen()`/`fork()` deadlocks the multithreaded
  WebKitGTK GUI). Pass args as a `vector<string>` — no shell quoting needed.
- Clipboard paste: JS `navigator.clipboard.readText()` → validates http(s) → opens Add
  dialog prefilled. `clipboard_monitor` toggles background watching.

## Blocking-call hazards (GTK thread)

`process::execute` is fork-safe BY DESIGN (the child only does async-signal-safe ops:
close/dup2/chdir/execve — no malloc/getenv/execvp). Use it, never raw `popen()`.
Availability checks (`find_binary`) stat fixed paths + `$PATH` dirs instead of spawning
`which`, and `check_tools_status_json` deliberately skips version queries. Any new bridge
code that must spawn a long-lived process should be moved behind a background thread +
poll pair (the `g_async_*` pattern in `src/core/YtAsync.ch`) and polled from the UI.
