---
name: cdm_bridge_ui
description: End-to-end feature development in the ChemicalDM app — adding a bridge method (JS→native), the JSON wire format, CdmApp universal component patterns (state, polling, dialogs), the theme system, and GUI lifecycle. Load when working on src/api/Bridge.ch, src/ui/, or Main.ch.
---

# ChemicalDM app — bridge + UI

The desktop GUI is a WebKitGTK webview showing SSR HTML from a single `#universal`
component. There is NO local HTTP server: JS talks to native through
`webview::webview_bind` → `cdm::bridge_call` (`src/api/Bridge.ch`).

## GUI startup sequence (`Main.ch run_gui`)

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
window.webview_bridge.call(method, argsJson).then(function(jsonResultString) { ... })
```

Native side `bridge_call(dm : *mut DownloadManager, method : string_view, args : string_view) : string`.

**Args-wrapping gotcha**: the injected bridge JS wraps bodies as `{id, method, params:[body]}`,
so `args` may be `"[{\"url\":...}]"`. ALWAYS extract fields through the helpers
`json_field / json_int_field / json_bool_field` — they call `resolve_bridge_args()` first,
which unwraps element 0 when it's a stringified object.

Response envelope (build with `ok_json()/err_json(&msg)`):
```json
{"ok":true}
{"ok":false,"error":"..."}
{"ok":true,"id":"<uuid>"}          // add
{ ... state document ... }         // state / settings_get / yt_status / yt_info
```

Method dispatch uses `string_view::make_no_len("name")` + `.equals()` chains. Existing
methods: `state, add, pause, resume, cancel, remove, remove_file, retry, restart, edit,
change_url, settings_get, settings_set, open_file, show_in_folder, yt_status, yt_install,
yt_info, yt_download, yt_download_playlist`.

### Checklist: adding a new bridge method

1. Native handler in `Bridge.ch::bridge_call` — parse fields via json_* helpers,
   validate with `src/core/Validation.ch`, call DownloadManager/library API or app core,
   return `ok_json()`/`err_json()`/payload.
2. If it exposes new data, extend the payload builder (`state_json`, `settings_json`,
   `item_to_json` in `JsonBuild.ch`) — manual string building with `json_string()`
   escaping; raw pre-serialized values go through `json_kv_raw`.
3. JS wrapper in `CdmApp.ch`: use `post(method, id, extra)` (adds id + refreshes) or
   `call(method, body)` or raw `asyncBridge(method, body, onResult)`.
4. App-level test if the logic is testable headlessly (`tests/json_tests.ch` pattern for
   wire-format round-trips).
5. Blocking methods (spawn processes): the caller must wrap the bridge call in
   `setTimeout(..., 50)` so the GTK UI paints its "loading" state first — see
   `fetchYtInfo()`/`startYtDownload()`.

### State JSON item shape (contract with the UI)

From `item_to_json` (`JsonBuild.ch`) + `snapshot_segments_json` (Engine.ch):
id, url, filename, display_name, dir, state (HUMAN name: Queued/Downloading/Paused/Done/
Failed/Cancelled — NOT the int), error, total_bytes, downloaded_bytes,
speed_bytes_per_sec, priority, max_segments, speed_limit_kbps, duplicate_suffix,
category (human name), percent (string), eta (string), retry_count, was_interrupted
(raw bool literal), and optional `segments` array of {index,start,end,total,copied,done}.
Top-level `state` doc: download_dir, max_concurrent, version, items[].
Settings doc: download_dir, max_concurrent, max_segments, speed_limit_kbps,
enable_resume, allow_segments, duplicate_action, auto_resume_failed, max_retries,
retry_delay_ms.

## CdmApp component patterns (`src/ui/CdmApp.ch`)

One ~960-line `#universal CdmApp(props)`. Conventions to follow:

- **State**: plain `state name = initial` per concern (items, dialog open flags, form
  fields, toast, ctx menu). Reassign whole values; don't mutate arrays in place for
  reactivity (`ytPlaylistSelected = ytPlaylistSelected.filter(...)` not push).
- **Polling**: `useEffect(..., [])` sets `setInterval(refresh, 1000)` calling bridge
  `state`; cleanup returns `() => clearInterval(t)` plus removes the global mousedown
  listener that closes the context menu.
- **Derived lists** are computed inline each render: `visibleItems = items.filter(...)`
  then `.sort(...)` — filter chips (`filter`, `catFilter`), search box, sort dropdown all
  feed this. Match states by HUMAN strings ("Downloading"), categories by name too.
- **Dialogs**: pattern `{open && item ? (<div class="cdm-dialog-overlay" onClick={close}>
  <div class="cdm-dialog" onClick={(e)=>{e.stopPropagation()}}>...) : null}`.
- **Context menu**: `openContextMenu(e,item)` records clientX/Y into state; actions map to
  bridge methods; special-cases open_file/show_in_folder which take a path not an id.
- **Per-segment progress**: item.segments array → flex row of `cdm-seg` bars, width
  `100/n%`, fill `% = copied*100/total`, class done/active/pending.
- **Resume button logic**: Failed items show Resume only when error ===
  "interrupted by shutdown" (matches Engine shutdown marker); otherwise Retry.
- **Toasts**: `showToast(msg,type)` + auto-hide setTimeout(4000); types info/success/error.

## Theme (`src/ui/CdmTheme.ch`)

All CSS lives here (~750 lines) appended via `page.append_css_view(""" ... """)`.
Class prefix convention: `cdm-*` for everything new. Colors use shadcn-style tokens
injected by `page.injectDefaultComponentsTheme()`: `hsl(var(--primary))`,
`hsl(var(--muted-foreground))`, `hsl(var(--border))`, `hsl(var(--destructive))`, etc.
Never hardcode palette colors except YouTube brand red (#ff0000 accents are fine).

## Desktop integrations

- `open_file` / `show_in_folder`: build `xdg-open "<path>"` and `popen(...,"r")` (Linux).
  Keep quoting; paths come from the UI but originate from our own dir/filename resolution.
- Clipboard paste: JS `navigator.clipboard.readText()` → validates http(s) → opens Add
  dialog prefilled.

## Blocking-call hazards (GTK thread)

`process::execute` forks. Inside the running webview process fork can deadlock — that's
why availability checks (`find_binary`) stat fixed paths instead of spawning `which`, and
why `check_tools_status_json` deliberately skips version queries. Any new bridge code
that must spawn should either be short-lived+captured (like current yt-dlp runs) or moved
behind a tool-download-style async task tracked via globals (`g_tool_dl_status` pattern
in YtTools.ch) and polled from the UI.
