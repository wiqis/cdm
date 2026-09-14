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
    var user_agent : string      // default UA: "ChemicalDM/0.1" when empty
    var timeout_secs : int       // default 30
    var referer : string         // extra Referer header
    var auth : string            // Authorization header (raw value)
    var force_ipv4 : bool        // NOT consumed by request() yet (dead field)
    var force_ipv6 : bool        // NOT consumed by request() yet (dead field)
    var cookie_file : string     // NOT consumed anywhere (dead field)
    var verify_ssl : bool        // default true → build_client(): insecure_skip_verify
    var proxy_host : string
    var proxy_port : int         // used only when host is non-empty AND port > 0
}
```

Fields actually consumed by `request()`/`build_client()`: `timeout_secs`, `user_agent`,
`referer`, `auth`, `verify_ssl`, `proxy_host`/`proxy_port`. The other three are
struct-but-unwired (see gaps below).

## Plumbing chain: settings → UI/CLI → engine → socket

```
CdmSettings.proxy_host/proxy_port/user_agent/connect_timeout/referer_header/
  auth_header/force_ipv4/force_ipv6
  → apply_settings_to_dm (Settings.ch)      // copies onto the manager
  → DownloadManager fields
  → start_pending copies them onto the new TaskRuntime (per-task snapshot)
  → build_http_opts(rt) (Engine.ch)          // TaskRuntime → HttpOptions
  → open_download / open_download_range / probe(..., opts)
```

**Not in the chain**: `verify_ssl` and `cookie_file` have NO TaskRuntime field, so
`build_http_opts` cannot copy them — engine requests always use the default
(`verify_ssl = true`) regardless of settings. The proxy/auth/referer/UA/timeout fields
are the fully-wired set.

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

- `checksum` ("md5:abc123" / "sha256:...") — parsed (`--checksum`), stored on TaskRuntime,
  never verified after download.
- `move_completed_to` — persisted, never applied (no post-completion move in Engine).
- `max_download_size` / `min_disk_space_mb` — parsed from CLI/config, never checked
  mid-download.
- `verify_ssl` — IMPLEMENTED in CdHttp (`insecure_skip_verify`) but never plumbed:
  `TaskRuntime` lacks the field, so `--no-ssl-verify`/settings never reach the client.
  Wiring it = add `verify_ssl` to TaskRuntime + copy in `build_http_opts`.
- `force_ipv4`/`force_ipv6` — plumbed all the way into HttpOptions, then never read by
  `request()`.
- `cookie_file` — dead everywhere (no reader in CdHttp or Engine).
- `notifications_enabled`, `clipboard_monitor` — UI/settings exist; clipboard polling and
  desktop notifications are not implemented.
- `post_download_cmd` — the ONE post-download hook that IS wired: Engine runs it on
  completion via `system()` after replacing `{}` with the output path (note: `system()`,
  not `process::execute` — safe today only because it runs on the worker thread, not the
  GTK thread; migrating to `process::execute` would match the fork-safety rule).

If you wire one of these up, follow the `post_download_cmd` pattern: capture onto
`TaskRuntime` in `start_pending`, act on the worker thread after `STATE_DONE`, add a
test, and document the setting here as enforced.
