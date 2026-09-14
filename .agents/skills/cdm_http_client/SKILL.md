---
name: cdm_http_client
description: ChemicalDM's own HTTP stack — cdmlib CdHttp (redirect-following requests, probe with Range bytes=0-0, header parsers, HttpOptions), how TaskRuntime network settings (proxy, cookies, SSL, IPv4/v6, Referer, auth) are plumbed into every request, and where settings are persisted but NOT yet enforced. Load when touching downloads' network behaviour, CdHttp.ch, or network settings.
---

# ChemicalDM HTTP client (cdmlib/src/CdHttp.ch + Engine plumbing)

cdmlib ships its own minimal HTTP client on top of the `net` module — no external
runtime deps beyond the dependency budget. All download traffic (probe, full download,
per-segment range requests) flows through it, so network behaviour is uniform and
configurable per task.

## HttpOptions (`cdmlib/src/CdHttp.ch`)

```chemical
public struct HttpOptions {
    var user_agent : string      // default UA: "ChemicalDM/0.1"
    var timeout_secs : int       // default 30
    var referer : string         // extra Referer header
    var auth : string            // Authorization header (raw value)
    var force_ipv4 : bool
    var force_ipv6 : bool
    var cookie_file : string     // Netscape-style cookie jar (yt-dlp compat)
    var verify_ssl : bool        // default true
    var proxy_host : string
    var proxy_port : int         // used only when host is non-empty AND port > 0
}
```

Applied per request via `cl.set_proxy(...)` when `proxy_host.size() > 0 && proxy_port > 0`,
`header("Referer", ...)` when set, `opts.auth` → Authorization header, and IPv4/v6 forced
resolution when requested.

## Plumbing chain: settings → UI/CLI → engine → socket

```
CdmSettings.proxy_host/proxy_port/user_agent/cookie_file/verify_ssl/connect_timeout/
  referer_header/auth_header/force_ipv4/force_ipv6
  → apply_settings_to_dm (Settings.ch)      // copies onto the manager
  → DownloadManager fields
  → start_pending copies them onto the new TaskRuntime (per-task snapshot)
  → build_http_opts(rt) (Engine.ch)          // TaskRuntime → HttpOptions
  → open_download / open_download_range / probe(..., opts)
```

**Per-task snapshot semantics**: changes to manager-level network settings apply to NEW
tasks; a running task keeps the options captured into its `TaskRuntime` at start. That's
intentional (mid-download proxy changes shouldn't corrupt a resume chain) — don't "fix"
by re-reading manager state from worker threads.

`max_retries`/`retry_delay_ms` follow the same path into `rt.retry_policy`
(`RetryPolicy{max_retries, delay_ms}`, -1 retries = infinite; 429 is retryable, other 4xx
fail immediately).

## Request types (what calls what)

| Function | Used for |
|----------|----------|
| `probe(url, hint, opts)` | GET with `Range: bytes=0-0`; 206 → resume + total from Content-Range; 200 → no resume, total from Content-Length; 416 → total from Content-Range. Fills `CdProbe{ok,status,total_bytes,supports_resume,filename,error}` |
| `open_download(url, resume_from, opts)` | Single-stream GET, `Range: bytes=N-` when resuming |
| `open_download_range(url, start, end, opts)` | BOUNDED `Range: bytes=start-end` — segments depend on the server honoring the end bound (some hosts ignore it and stream everything) |
| `request(method, url, range_start, range_end, opts)` | The core redirect-following client (`MAX_REDIRECTS=10`, sends `Accept-Encoding: identity` so byte counts match Content-Length) |

Header parsers (pure, unit-tested): `parse_content_length`,
`parse_content_range_total`, `parse_content_disposition_name` (Content-Disposition
filename override → suggested name).

## Redirect + resume interaction

Redirects are followed before the Range request is finally issued, so a 302 to a CDN
keeps the original `Range` header — resume works across redirect hops. If you touch the
redirect loop, preserve: (a) the Range header, (b) `Accept-Encoding: identity`, (c) the
per-request timeout, and (d) the invariant that `open_download_range` never degrades to
an open-ended request.

## Enforcement gaps (settings persisted but NOT yet wired)

These exist in `CdmSettings` + config.txt + UI, but the engine does not read them yet —
known deltas, don't assume they work, and don't silently "implement" them without tests:

- `checksum` ("md5:abc123" / "sha256:...") — stored on TaskRuntime, never verified after
  download.
- `move_completed_to` — persisted, never applied (no post-completion move in Engine).
- `max_download_size` / `min_disk_space_mb` — parsed from CLI/config, never checked
  mid-download.
- `post_download_cmd` — the ONE hook that IS wired: Engine runs it on completion via
  `system()` after replacing `{}` with the output path (note: `system()`, not
  `process::execute` — safe today only because it runs on the worker thread, not the GTK
  thread; migrating it to `process::execute` would be consistent with the fork-safety rule).
- `notifications_enabled`, `clipboard_monitor` — UI/settings exist; clipboard polling and
  desktop notifications are not implemented.

If you wire one of these up, follow the `post_download_cmd` pattern: capture onto
`TaskRuntime` in `start_pending`, act on the worker thread after `STATE_DONE`, add a
test, and document the setting here as enforced.
