// ChemicalDM — download-oriented HTTP client.
//
// Thin layer over the http library configured for streaming. Requests have no
// body-size cap (Client.max_body_len = 0), follow redirects, and expose the
// metadata a download engine needs (total size, resume support, filename).

public namespace cdm {

using std::string;
using std::string_view;
using std::Option;
using std::Result;
using std::vector;

    // Configurable HTTP options for all request types.
    // Use defaults() to get production defaults; callers override specific fields.
    public struct HttpOptions {
        var user_agent : string
        var timeout_secs : int
        var referer : string
        var auth : string
        var force_ipv4 : bool
        var force_ipv6 : bool
        var cookie_file : string
        var verify_ssl : bool

        @constructor func constructor() {
            return HttpOptions {
                user_agent = string(),
                timeout_secs = 30,
                referer = string(),
                auth = string(),
                force_ipv4 = false,
                force_ipv6 = false,
                cookie_file = string(),
                verify_ssl = true
            }
        }

        public func defaults() : HttpOptions {
            return HttpOptions()
        }
    }

    // Metadata captured during a probe request.
    public struct CdProbe {
        var ok : bool
        var status : uint
        var total_bytes : i64           // -1 when unknown
        var supports_resume : bool
        var filename : string           // suggested file name
        var error : string

        @constructor func constructor() {
            return CdProbe {
                ok = false,
                status = 0u,
                total_bytes = -1,
                supports_resume = false,
                filename = string(),
                error = string()
            }
        }
    }

    public func parse_content_length(svc : &string) : i64 {
        if(svc.size() == 0) { return -1 }
        var val : i64 = 0
        var started = false
        var i : usize = 0
        // Content-Length must be non-negative. Leading '-' makes the whole value invalid.
        if(svc.get(0) == '-') { return -1 }
        while(i < svc.size()) {
            var c = svc.get(i)
            if(c >= '0' && c <= '9') {
                val = val * 10 + (c as i64 - '0' as i64)
                started = true
            } else if(started) {
                break
            }
            i = i + 1u
        }
        if(!started) { return -1 }
        return val
    }

    // Parse "bytes 0-0/total" (or trailing part after '/') into a total.
    // total may be "*" (unknown).
    public func parse_content_range_total(svc : &string) : i64 {
        // find last '/'
        var idx = svc.size()
        var found = false
        for(var i = 0u; i < svc.size(); i++) {
            if(svc.get(i) == '/') { idx = i; found = true }
        }
        var total : i64 = -1
        var any_digit = false
        if(found) {
            var j = idx + 1u
            while(j < svc.size()) {
                var c = svc.get(j)
                if(c >= '0' && c <= '9') {
                    if(total < 0) { total = 0 }
                    total = total * 10 + (c as i64 - '0' as i64)
                    any_digit = true
                }
                j = j + 1u
            }
        }
        if(!found || !any_digit) { return -1 }
        return total
    }

    // Extract a file name from a Content-Disposition header value.
    public func parse_content_disposition_name(cdv : &string) : Option<string> {
        // Look for filename= or filename*= at the end of the header.
        var i : usize = 0
        var best = string()
        var found = false
        while(i + 8 < cdv.size()) {
            // case-insensitive "filename="
            var c0 = cdv.get(i)
            var c1 = cdv.get(i + 1u)
            var c2 = cdv.get(i + 2u)
            var c3 = cdv.get(i + 3u)
            var c4 = cdv.get(i + 4u)
            var c5 = cdv.get(i + 5u)
            var c6 = cdv.get(i + 6u)
            var c7 = cdv.get(i + 7u)
            var c8 = cdv.get(i + 8u)
            var lower0 = c0
            var lower1 = c1
            var lower2 = c2
            var lower3 = c3
            var lower4 = c4
            var lower5 = c5
            var lower6 = c6
            var lower7 = c7
            if(lower0 >= 'A' && lower0 <= 'Z') { lower0 = (lower0 + 32) as char }
            if(lower1 >= 'A' && lower1 <= 'Z') { lower1 = (lower1 + 32) as char }
            if(lower2 >= 'A' && lower2 <= 'Z') { lower2 = (lower2 + 32) as char }
            if(lower3 >= 'A' && lower3 <= 'Z') { lower3 = (lower3 + 32) as char }
            if(lower4 >= 'A' && lower4 <= 'Z') { lower4 = (lower4 + 32) as char }
            if(lower5 >= 'A' && lower5 <= 'Z') { lower5 = (lower5 + 32) as char }
            if(lower6 >= 'A' && lower6 <= 'Z') { lower6 = (lower6 + 32) as char }
            if(lower7 >= 'A' && lower7 <= 'Z') { lower7 = (lower7 + 32) as char }
            if(lower0 == 'f' && lower1 == 'i' && lower2 == 'l' && lower3 == 'e' &&
               lower4 == 'n' && lower5 == 'a' && lower6 == 'm' && lower7 == 'e') {
                // note: index i+8 is '=' when plain filename=; for filename*= it
                // is '*' then '='. Accept either.
                if(c8 == '=' || c8 == '*') {
                    var vstart = i + 9u
                    if(c8 == '*') { vstart = i + 10u }
                    // skip spaces / possible quotes
                    while(vstart < cdv.size() && (cdv.get(vstart) == ' ' || cdv.get(vstart) == '"')) {
                        vstart = vstart + 1u
                    }
                    var val = string()
                    var ended = false
                    while(vstart < cdv.size()) {
                        var cc = cdv.get(vstart)
                        if(cc == '"' || cc == ';' || cc == '\r' || cc == '\n') { ended = true; break }
                        val.append(cc)
                        vstart = vstart + 1u
                    }
                    if(!ended && val.size() > 0) {
                        // no terminator; keep whatever we collected (already appended all)
                    }
                    if(val.size() > 0) {
                        best = val
                        found = true
                        i = vstart
                        continue
                    }
                }
            }
            i = i + 1u
        }
        if(found) { return Option.Some<string>(best) }
        return Option.None<string>()
    }

    func build_client() : http::Client {
        var cl = http::Client()
        cl.max_body_len = 0u
        return cl
    }

    // Perform a request with redirect following. Returns the final response
    // (status, headers, streaming body). max_redirects guards against loops.
    // range_start < 0 means no Range header. range_end < 0 means an open-ended
    // range from range_start to EOF (`bytes=N-`). When range_end >= 0 an exact
    // bounded range is requested (`bytes=N-M`) — used by the segmented engine.
    public func request(method : string_view, url_str : string_view, range_start : i64, range_end : i64, opts : HttpOptions) : Result<http::Response, string> {
        var cl = build_client()
        var current = string(url_str.data(), url_str.size())
        var redirects = 0
        while(redirects <= MAX_REDIRECTS) {
            var current_view = string_view::make_view(&current)
            var url_opt = http::URL::parse(&current_view)
            if(url_opt is Option.None) {
                var msg = string::make_no_len("invalid URL: ")
                msg.append_view(&current_view)
                return Result.Err<http::Response, string>(msg)
            }
            var Some(u) = url_opt else unreachable

            // std::replace moves the URL out of `u` (leaving an empty URL) so the
            // Option<URL> and the RequestBuilder never alias the same heap
            // strings — both would otherwise free() them at scope exit.
            var rb = http::RequestBuilder(method.data(), std::replace(&mut u, http::URL()))
            rb.timeout(opts.timeout_secs as long)
            var ua_val = string_view::make_no_len("ChemicalDM/0.1")
            if(opts.user_agent.size() > 0) { ua_val = string_view::make_view(&opts.user_agent) }
            rb.header("User-Agent", ua_val.data())
            rb.header("Accept", "*/*")
            rb.header("Accept-Encoding", "identity")
            if(opts.referer.size() > 0) { rb.header("Referer", opts.referer.data()) }
            if(opts.auth.size() > 0) { rb.header("Authorization", opts.auth.data()) }
            if(range_start >= 0) {
                var rh = string::make_no_len("bytes=")
                rh.append_integer(range_start as bigint)
                rh.append('-')
                if(range_end >= 0) {
                    rh.append_integer(range_end as bigint)
                }
                rb.header("Range", rh.data())
            }

            var res = cl.request(&rb)
            if(res is Result.Err) {
                var Err(e) = res else unreachable
                // Wrap the library error with the URL for context.
                var msg = string::make_no_len("network error: ")
                msg.append_string(&e)
                msg.append_string(&string::make_no_len(" ("))
                msg.append_view(&current_view)
                msg.append(')')
                return Result.Err<http::Response, string>(msg)
            }
            var Ok(rep) = res else unreachable

            var st = rep.status
            if(st == 301u || st == 302u || st == 303u || st == 307u || st == 308u) {
                var loc_opt = rep.headers.get("Location")
                if(loc_opt is Option.Some) {
                    var Some(loc) = loc_opt else unreachable
                    redirects = redirects + 1
                    if(redirects > MAX_REDIRECTS) {
                        rep.body.close_socket()
                        var msg = string::make_no_len("too many redirects (>")
                        var r = string()
                        r.append_integer(MAX_REDIRECTS as bigint)
                        msg.append_string(&r)
                        msg.append_string(&string::make_no_len(")"))
                        return Result.Err<http::Response, string>(msg)
                    }
                    current = loc.copy()
                    continue
                }
                // Redirect without Location: treat as the final response.
            }
            return Result.Ok<http::Response, string>(std::replace(&mut rep, http::Response()))
        }
        var msg = string::make_no_len("too many redirects (>")
        var r = string()
        r.append_integer(MAX_REDIRECTS as bigint)
        msg.append_string(&r)
        msg.append_string(&string::make_no_len(")"))
        return Result.Err<http::Response, string>(msg)
    }

    // Probe a URL for downloadability without downloading the body:
    // issue GET with Range: bytes=0-0. 206 -> resume + total; 200 -> no
    // resume, total from Content-Length; 416 -> total from Content-Range.
    public func probe(url_str : string_view, filename_hint : string_view, opts : HttpOptions) : CdProbe {
        var probe = CdProbe()
        if(filename_hint.size() > 0) {
            probe.filename = sanitize_filename(filename_hint)
        }

        // Retry probe up to 3 times on network errors (transient failures).
        var last_err = string()
        var attempt = 0
        while(attempt < 3) {
            var res = request("GET", url_str, 0, 0, opts)
            if(res is Result.Ok) {
                last_err = string()
                var Ok(rep) = res else unreachable
                probe.status = rep.status

                if(rep.status == 206u) {
                    probe.ok = true
                    probe.supports_resume = true
                    // Content-Range: bytes <start>-<end>/<total>
                    var cr_opt = rep.headers.get("Content-Range")
                    if(cr_opt is Option.Some) {
                        var Some(cr) = cr_opt else unreachable
                        probe.total_bytes = parse_content_range_total(&cr)
                    }
                    fprintf(stderr, "[CDM] probe: 206 resume supported, total=%lld\n", probe.total_bytes)
                } else if(rep.status == 200u) {
                    probe.ok = true
                    probe.supports_resume = false
                    var cl_opt = rep.headers.get("Content-Length")
                    if(cl_opt is Option.Some) {
                        var Some(cl) = cl_opt else unreachable
                        probe.total_bytes = parse_content_length(&cl)
                    }
                    fprintf(stderr, "[CDM] probe: 200 no resume, total=%lld\n", probe.total_bytes)
                } else if(rep.status == 416u) {
                    // Range not satisfiable — server usually gives total via Content-Range.
                    probe.ok = true
                    probe.supports_resume = false
                    var cr_opt = rep.headers.get("Content-Range")
                    if(cr_opt is Option.Some) {
                        var Some(cr) = cr_opt else unreachable
                        probe.total_bytes = parse_content_range_total(&cr)
                    }
                    fprintf(stderr, "[CDM] probe: 416 Range not satisfiable, total=%lld\n", probe.total_bytes)
                } else {
                    probe.error = string::make_no_len("server returned HTTP ")
                    probe.error.append_uinteger(rep.status as ubigint)
                    if(rep.status == 403u) {
                        probe.error.append_string(&string::make_no_len(" (access denied)") )
                    } else if(rep.status == 404u) {
                        probe.error.append_string(&string::make_no_len(" (not found)"))
                    } else if(rep.status == 429u) {
                        probe.error.append_string(&string::make_no_len(" (rate limited — try again later)"))
                    } else if(rep.status >= 500u) {
                        probe.error.append_string(&string::make_no_len(" (server error)"))
                    }
                    fprintf(stderr, "[CDM] probe: HTTP %u\n", rep.status)
                }

                // Filename from Content-Disposition, falling back to the URL path.
                var cd_opt = rep.headers.get("Content-Disposition")
                if(cd_opt is Option.Some) {
                    var Some(cd) = cd_opt else unreachable
                    var nm_opt = parse_content_disposition_name(&cd)
                    if(nm_opt is Option.Some) {
                        var Some(nm) = nm_opt else unreachable
                        probe.filename = sanitize_filename(string_view::make_view(&nm))
                    }
                }
                if(probe.filename.empty()) {
                    probe.filename = suggested_filename(url_str)
                }

                // Abandon the connection — only headers were needed.
                rep.body.close_socket()
                return probe
            } else {
                var Err(e) = res else unreachable
                last_err = e.copy()
                fprintf(stderr, "[CDM] probe attempt %d failed for %s: %s\n", attempt + 1, string(url_str.data(), url_str.size()).data(), e.data())
            }
            attempt = attempt + 1
            if(attempt < 3) {
                std::concurrent.sleep_ms(200u)
            }
        }
        probe.error = last_err.copy()
        return probe
    }

    // Open a resumable download stream starting at `resume_from` bytes
    // (0 = beginning). The caller pulls from response.body.read().
    public func open_download(url_str : string_view, resume_from : i64, opts : HttpOptions) : Result<http::Response, string> {
        return request("GET", url_str, resume_from, -1, opts)
    }

    // Open a bounded download stream covering exactly [start, end] (inclusive).
    // Used by the segmented engine so each segment only pulls its own bytes and
    // a server that streams the whole file cannot wedge the connection.
    public func open_download_range(url_str : string_view, start : i64, end : i64, opts : HttpOptions) : Result<http::Response, string> {
        return request("GET", url_str, start, end, opts)
    }

} // end namespace cdm