// ChemicalDM — Async YouTube operations.
//
// Runs yt-dlp in background threads so the webview UI stays responsive.
// Progress is parsed from yt-dlp stderr lines and stored in globals
// that the UI polls via bridge methods.
//
// Thread safety: each async operation type has its own global state
// protected by a mutex. The UI thread polls; the worker thread writes.
// The global state holds BOTH config (url, format, dir) and result
// (progress, error, etc.) so the thread never captures stack variables.
//
// IMPORTANT: We use popen() + fgetc() instead of process::execute() to
// avoid fork() deadlocks in the multi-threaded WebKitGTK process.

public namespace cdm {

using std::string;
using std::string_view;
using std::vector;
using std::Result;
using std::mutex;

    // ---- Async info fetch state ----

    public struct AsyncInfoState {
        var running : bool
        var done : bool
        var error : string
        var result_json : string   // raw JSON from yt-dlp --dump-json
        var is_playlist : bool
        var url : string           // input URL (copied before spawn)
        var mu : mutex

        @constructor func constructor() {
            return AsyncInfoState {
                running = false, done = false,
                error = string(), result_json = string(),
                is_playlist = false, url = string(),
                mu = mutex()
            }
        }
    }

    @never_destructed public unsafe var g_async_info = zeroed<AsyncInfoState>()

    // ---- Async single download state ----

    public struct AsyncDlState {
        var running : bool
        var done : bool
        var error : string
        var progress : double      // 0.0 - 100.0
        var speed : string
        var eta : string
        var status_line : string
        var title : string
        var output_path : string
        // Config (set before spawn, read by thread).
        var url : string
        var format : string
        var output_dir : string
        var mu : mutex

        @constructor func constructor() {
            return AsyncDlState {
                running = false, done = false,
                error = string(), progress = 0.0,
                speed = string(), eta = string(),
                status_line = string(), title = string(),
                output_path = string(),
                url = string(), format = string(), output_dir = string(),
                mu = mutex()
            }
        }
    }

    @never_destructed public unsafe var g_async_dl = zeroed<AsyncDlState>()

    // ---- Async playlist download state ----

    public struct AsyncPlState {
        var running : bool
        var done : bool
        var error : string
        var progress : double
        var speed : string
        var eta : string
        var status_line : string
        var items_done : int
        var items_total : int
        var current_title : string
        // Config.
        var url : string
        var format : string
        var output_dir : string
        var min_quality : int
        var max_quality : int
        var mu : mutex

        @constructor func constructor() {
            return AsyncPlState {
                running = false, done = false,
                error = string(), progress = 0.0,
                speed = string(), eta = string(),
                status_line = string(), items_done = 0,
                items_total = 0, current_title = string(),
                url = string(), format = string(), output_dir = string(),
                min_quality = 0, max_quality = 0,
                mu = mutex()
            }
        }
    }

    @never_destructed public unsafe var g_async_pl = zeroed<AsyncPlState>()

    // ---- Shell escaping for popen ----

    func sh_escape(s : string_view) : string {
        var out = string()
        out.append('\'')
        for(var i = 0u; i < s.size(); i++) {
            var c = s.get(i)
            if(c == '\'') {
                out.append_string(&string::make_no_len("'\\''"))
            } else {
                out.append(c)
            }
        }
        out.append('\'')
        return out
    }

    // Build a shell command string from args. Each arg is shell-escaped.
    func build_cmd(args : &vector<string>) : string {
        var cmd = string()
        for(var i = 0u; i < args.size(); i++) {
            if(i > 0u) { cmd.append(' ') }
            var escaped = sh_escape(string_view::make_view(args.get_ref(i)))
            cmd.append_string(&escaped)
        }
        return cmd
    }

    // ---- Progress line parsing ----

    // Parse a yt-dlp stderr line for progress info.
    func parse_yt_progress_line(line : string_view, progress : &mut double,
                                speed : &mut string, eta : &mut string,
                                status : &mut string, title : &mut string) {
        *status = string(line.data(), line.size())

        // [download]  45.2% of  156.72MiB at  2.34MiB/s ETA 00:27
        var dl_marker = string_view::make_no_len("[download]")
        var dl_idx = line.find(&dl_marker)
        if(dl_idx != std::NPOS) {
            // Parse percentage
            var pct_marker = string_view::make_no_len("%")
            var pct_idx = line.find(&pct_marker)
            if(pct_idx != std::NPOS) {
                var pct_end = pct_idx
                var pct_start = pct_end
                while(pct_start > 0 && line.get(pct_start - 1u) != ' ') {
                    pct_start = pct_start - 1u
                }
                var pct_str = line.subview(pct_start, pct_end)
                *progress = parse_double_view(pct_str)
            }

            // Parse speed: " at X.XXMiB/s"
            var si : usize = 0
            while(si + 3u < line.size()) {
                if(line.get(si) == ' ' && line.get(si + 1u) == 'a' &&
                   line.get(si + 2u) == 't' && line.get(si + 3u) == ' ') {
                    var speed_start = si + 4u
                    var speed_end = speed_start
                    while(speed_end < line.size() && line.get(speed_end) != ' ') {
                        speed_end = speed_end + 1u
                    }
                    *speed = string(line.data() + speed_start, speed_end - speed_start)
                    break
                }
                si = si + 1u
            }

            // Parse ETA: "ETA HH:MM"
            var ei : usize = 0
            while(ei + 3u < line.size()) {
                if(line.get(ei) == 'E' && line.get(ei + 1u) == 'T' &&
                   line.get(ei + 2u) == 'A' && line.get(ei + 3u) == ' ') {
                    var eta_start = ei + 4u
                    var eta_end = eta_start
                    while(eta_end < line.size() && line.get(eta_end) != ' ' &&
                          line.get(eta_end) != '\n' && line.get(eta_end) != '\r') {
                        eta_end = eta_end + 1u
                    }
                    *eta = string(line.data() + eta_start, eta_end - eta_start)
                    break
                }
                ei = ei + 1u
            }
            return
        }

        // [youtube] — extract title
        var yt_marker = string_view::make_no_len("[youtube]")
        if(line.find(&yt_marker) != std::NPOS) {
            *title = string(line.data(), line.size())
            return
        }

        // [Merger] or [ffmpeg] — merge step
        var merge_marker1 = string_view::make_no_len("[Merger]")
        var merge_marker2 = string_view::make_no_len("[ffmpeg]")
        if(line.find(&merge_marker1) != std::NPOS || line.find(&merge_marker2) != std::NPOS) {
            *status = string(line.data(), line.size())
            return
        }
    }

    // ---- Info fetch (thread entry — non-capturing, uses globals) ----

    func info_thread_entry(arg : *void) : *void {
        std::concurrent.sleep_ms(10u)
        fprintf(stderr, "[CDM-ASYNC] info thread started\n")

        // Use popen() to run yt-dlp --dump-json instead of process::execute()
        // to avoid fork() deadlocks in the multi-threaded WebKitGTK process.
        var args = vector<string>()
        args.push_back(ytdlp_resolved_path())
        args.push_back(string::make_no_len("--dump-json"))
        args.push_back(string::make_no_len("--no-warnings"))
        if(g_async_info.is_playlist) {
            args.push_back(string::make_no_len("--flat-playlist"))
        } else {
            args.push_back(string::make_no_len("--no-playlist"))
        }
        args.push_back(g_async_info.url.copy())

        var cmd = build_cmd(&args)
        fprintf(stderr, "[CDM-ASYNC] info cmd: %s\n", cmd.data())

        var fp = popen(cmd.data(), "r")
        if(fp == null) {
            fprintf(stderr, "[CDM-ASYNC] info popen FAILED\n")
            g_async_info.mu.lock()
            g_async_info.error = string::make_no_len("failed to start yt-dlp process")
            g_async_info.done = true
            g_async_info.running = false
            g_async_info.mu.unlock()
            return null
        }

        // Read all stdout (the JSON output).
        var json_out = string()
        while(true) {
            var ch = fgetc(fp)
            if(ch == -1) { break }
            json_out.append(ch as char)
        }
        var exit_code = pclose(fp)

        fprintf(stderr, "[CDM-ASYNC] info done, exit=%d, json_len=%zu\n", exit_code, json_out.size())

        g_async_info.mu.lock()
        if(exit_code != 0 && json_out.size() == 0u) {
            g_async_info.error = string::make_no_len("yt-dlp failed with exit code ")
            var ecs = string()
            ecs.append_integer(exit_code as bigint)
            g_async_info.error.append_string(&ecs)
            g_async_info.done = true
            g_async_info.running = false
            g_async_info.mu.unlock()
            return null
        }

        // yt-dlp errors on stdout start with "ERROR:" prefix.
        if(json_out.size() > 0u && json_out.get(0) != '{') {
            g_async_info.error = json_out.copy()
            g_async_info.done = true
            g_async_info.running = false
            g_async_info.mu.unlock()
            return null
        }

        // Store the raw JSON — the JS UI will parse it.
        g_async_info.result_json = json_out.copy()
        g_async_info.done = true
        g_async_info.running = false
        g_async_info.mu.unlock()
        fprintf(stderr, "[CDM-ASYNC] info result stored, len=%zu\n", json_out.size())
        return null
    }

    // Start async info fetch. Copies url into the global state and spawns a thread.
    public func start_async_info(url : string_view) : string {
        g_async_info.mu.lock()
        if(g_async_info.running) {
            g_async_info.mu.unlock()
            return string::make_no_len("info fetch already in progress")
        }
        g_async_info.running = true
        g_async_info.done = false
        g_async_info.error = string()
        g_async_info.result_json = string()
        g_async_info.is_playlist = is_youtube_playlist_url(url)
        g_async_info.url = string(url.data(), url.size())
        g_async_info.mu.unlock()

        fprintf(stderr, "[CDM-ASYNC] start_async_info: url=%s is_pl=%d\n",
                g_async_info.url.data(), g_async_info.is_playlist as int)

        // Use a non-capturing function pointer — data flows through globals.
        std::concurrent.spawn(info_thread_entry, null)
        return string()
    }

    // Poll async info status. Returns JSON for the bridge.
    public func poll_async_info() : string {
        g_async_info.mu.lock()
        var running = g_async_info.running
        var done = g_async_info.done
        var error = g_async_info.error.copy()
        var result = g_async_info.result_json.copy()
        var is_pl = g_async_info.is_playlist
        g_async_info.mu.unlock()

        var out = string::make_no_len("{\"running\":")
        if(running) { out.append_string(&string::make_no_len("true")) }
        else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"done\":"))
        if(done) { out.append_string(&string::make_no_len("true")) }
        else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"error\":"))
        out.append_string(&json_string(string_view::make_view(&error)))
        out.append_string(&string::make_no_len(",\"is_playlist\":"))
        if(is_pl) { out.append_string(&string::make_no_len("true")) }
        else { out.append_string(&string::make_no_len("false")) }
        if(done && error.size() == 0u && result.size() > 0u) {
            out.append_string(&string::make_no_len(",\"info\":"))
            out.append_string(&result)
        }
        out.append('}')
        return out
    }

    // Cancel async info fetch.
    public func cancel_async_info() {
        g_async_info.mu.lock()
        g_async_info.running = false
        g_async_info.done = true
        g_async_info.error = string::make_no_len("cancelled")
        g_async_info.mu.unlock()
    }

    // ---- Download (thread entry) ----

    func download_thread_entry(arg : *void) : *void {
        std::concurrent.sleep_ms(10u)

        // Build output template.
        var out_template = g_async_dl.output_dir.copy()
        out_template.append_view(string_view::make_no_len("/%(title)s.%(ext)s"))

        // Build command args.
        var args = vector<string>()
        args.push_back(ytdlp_resolved_path())
        args.push_back(string::make_no_len("--no-warnings"))
        args.push_back(string::make_no_len("--newline"))
        args.push_back(string::make_no_len("--no-playlist"))
        args.push_back(string::make_no_len("--progress"))
        args.push_back(string::make_no_len("-o"))
        args.push_back(out_template.copy())

        if(g_async_dl.format.size() > 0) {
            args.push_back(string::make_no_len("-f"))
            args.push_back(g_async_dl.format.copy())
        } else {
            args.push_back(string::make_no_len("-f"))
            args.push_back(string::make_no_len("bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"))
        }

        if(ffmpeg_is_available()) {
            args.push_back(string::make_no_len("--merge-output-format"))
            args.push_back(string::make_no_len("mp4"))
        }

        args.push_back(g_async_dl.url.copy())

        // Build shell command with stderr merged to stdout.
        var cmd = build_cmd(&args)
        cmd.append_string(&string::make_no_len(" 2>&1"))

        var fp = popen(cmd.data(), "r")
        if(fp == null) {
            g_async_dl.mu.lock()
            g_async_dl.error = string::make_no_len("failed to start yt-dlp process")
            g_async_dl.done = true
            g_async_dl.running = false
            g_async_dl.mu.unlock()
            return null
        }

        var line = string()
        while(true) {
            var ch = fgetc(fp)
            if(ch == -1) { break }
            if(ch == '\n' as int || ch == '\r' as int) {
                if(line.size() > 0u) {
                    g_async_dl.mu.lock()
                    parse_yt_progress_line(
                        string_view::make_view(&line),
                        &mut g_async_dl.progress,
                        &mut g_async_dl.speed,
                        &mut g_async_dl.eta,
                        &mut g_async_dl.status_line,
                        &mut g_async_dl.title
                    )
                    g_async_dl.mu.unlock()
                    line = string()
                }
                continue
            }
            line.append(ch as char)
        }
        if(line.size() > 0u) {
            g_async_dl.mu.lock()
            parse_yt_progress_line(
                string_view::make_view(&line),
                &mut g_async_dl.progress,
                &mut g_async_dl.speed,
                &mut g_async_dl.eta,
                &mut g_async_dl.status_line,
                &mut g_async_dl.title
            )
            g_async_dl.mu.unlock()
        }

        var exit_code = pclose(fp)
        var success = (exit_code == 0)

        g_async_dl.mu.lock()
        if(!success && g_async_dl.error.size() == 0u) {
            g_async_dl.error = string::make_no_len("yt-dlp exited with error (code ")
            var ecs = string()
            ecs.append_integer(exit_code as bigint)
            g_async_dl.error.append_string(&ecs)
            g_async_dl.error.append(')')
        }
        if(success) {
            g_async_dl.progress = 100.0
        }
        g_async_dl.done = true
        g_async_dl.running = false
        g_async_dl.mu.unlock()
        return null
    }

    // Start async single-video download.
    public func start_async_download(url : string_view, format : string_view,
                                     dir : string_view) : string {
        g_async_dl.mu.lock()
        if(g_async_dl.running) {
            g_async_dl.mu.unlock()
            return string::make_no_len("download already in progress")
        }
        g_async_dl.running = true
        g_async_dl.done = false
        g_async_dl.error = string()
        g_async_dl.progress = 0.0
        g_async_dl.speed = string()
        g_async_dl.eta = string()
        g_async_dl.status_line = string()
        g_async_dl.title = string()
        g_async_dl.output_path = string()
        g_async_dl.url = string(url.data(), url.size())
        g_async_dl.format = string(format.data(), format.size())
        g_async_dl.output_dir = string(dir.data(), dir.size())
        g_async_dl.mu.unlock()

        std::concurrent.spawn(download_thread_entry, null)
        return string()
    }

    // Poll async download status.
    public func poll_async_download() : string {
        g_async_dl.mu.lock()
        var running = g_async_dl.running
        var done = g_async_dl.done
        var error = g_async_dl.error.copy()
        var progress = g_async_dl.progress
        var speed = g_async_dl.speed.copy()
        var eta = g_async_dl.eta.copy()
        var status = g_async_dl.status_line.copy()
        var title = g_async_dl.title.copy()
        g_async_dl.mu.unlock()

        var out = string::make_no_len("{\"running\":")
        if(running) { out.append_string(&string::make_no_len("true")) }
        else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"done\":"))
        if(done) { out.append_string(&string::make_no_len("true")) }
        else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"error\":"))
        out.append_string(&json_string(string_view::make_view(&error)))
        out.append_string(&string::make_no_len(",\"progress\":"))
        var ps = string()
        ps.append_double(progress, 1)
        out.append_string(&ps)
        out.append_string(&string::make_no_len(",\"speed\":"))
        out.append_string(&json_string(string_view::make_view(&speed)))
        out.append_string(&string::make_no_len(",\"eta\":"))
        out.append_string(&json_string(string_view::make_view(&eta)))
        out.append_string(&string::make_no_len(",\"status\":"))
        out.append_string(&json_string(string_view::make_view(&status)))
        out.append_string(&string::make_no_len(",\"title\":"))
        out.append_string(&json_string(string_view::make_view(&title)))
        out.append('}')
        return out
    }

    // Cancel async download.
    public func cancel_async_download() {
        g_async_dl.mu.lock()
        g_async_dl.running = false
        g_async_dl.done = true
        g_async_dl.error = string::make_no_len("cancelled")
        g_async_dl.mu.unlock()
    }

    // ---- Playlist download (thread entry) ----

    func playlist_thread_entry(arg : *void) : *void {
        std::concurrent.sleep_ms(10u)

        // Build playlist args.
        var args = build_ytdlp_playlist_args(
            string_view::make_view(&g_async_pl.url),
            string_view::make_view(&g_async_pl.output_dir),
            string_view::make_view(&g_async_pl.format),
            g_async_pl.min_quality, g_async_pl.max_quality
        )

        // Build shell command with stderr merged to stdout.
        var cmd = build_cmd(&args)
        cmd.append_string(&string::make_no_len(" 2>&1"))

        var fp = popen(cmd.data(), "r")
        if(fp == null) {
            g_async_pl.mu.lock()
            g_async_pl.error = string::make_no_len("failed to start yt-dlp process")
            g_async_pl.done = true
            g_async_pl.running = false
            g_async_pl.mu.unlock()
            return null
        }

        var line = string()
        while(true) {
            var ch = fgetc(fp)
            if(ch == -1) { break }
            if(ch == '\n' as int || ch == '\r' as int) {
                if(line.size() > 0u) {
                    g_async_pl.mu.lock()
                    var dummy_progress = 0.0
                    var dummy_speed = string()
                    var dummy_eta = string()
                    var dummy_status = string()
                    var dummy_title = string()
                    parse_yt_progress_line(
                        string_view::make_view(&line),
                        &mut dummy_progress,
                        &mut dummy_speed,
                        &mut dummy_eta,
                        &mut dummy_status,
                        &mut dummy_title
                    )
                    g_async_pl.status_line = dummy_status.copy()
                    if(dummy_speed.size() > 0u) {
                        g_async_pl.speed = dummy_speed.copy()
                    }
                    if(dummy_eta.size() > 0u) {
                        g_async_pl.eta = dummy_eta.copy()
                    }
                    if(dummy_title.size() > 0u) {
                        g_async_pl.current_title = dummy_title.copy()
                    }
                    var dl_100 = string_view::make_no_len("[download] 100%")
                    if(line.find(&dl_100) != std::NPOS) {
                        g_async_pl.items_done = g_async_pl.items_done + 1
                    }
                    g_async_pl.mu.unlock()
                    line = string()
                }
                continue
            }
            line.append(ch as char)
        }
        if(line.size() > 0u) {
            g_async_pl.mu.lock()
            var dummy_progress = 0.0
            var dummy_speed = string()
            var dummy_eta = string()
            var dummy_status = string()
            var dummy_title = string()
            parse_yt_progress_line(
                string_view::make_view(&line),
                &mut dummy_progress,
                &mut dummy_speed,
                &mut dummy_eta,
                &mut dummy_status,
                &mut dummy_title
            )
            g_async_pl.status_line = dummy_status.copy()
            g_async_pl.mu.unlock()
        }

        var exit_code = pclose(fp)
        var success = (exit_code == 0)

        g_async_pl.mu.lock()
        if(!success && g_async_pl.error.size() == 0u) {
            g_async_pl.error = string::make_no_len("yt-dlp playlist download failed (code ")
            var ecs = string()
            ecs.append_integer(exit_code as bigint)
            g_async_pl.error.append_string(&ecs)
            g_async_pl.error.append(')')
        }
        g_async_pl.progress = 100.0
        g_async_pl.done = true
        g_async_pl.running = false
        g_async_pl.mu.unlock()
        return null
    }

    // Start async playlist download.
    public func start_async_playlist_download(url : string_view, format : string_view,
                                              dir : string_view, min_quality : int,
                                              max_quality : int) : string {
        g_async_pl.mu.lock()
        if(g_async_pl.running) {
            g_async_pl.mu.unlock()
            return string::make_no_len("playlist download already in progress")
        }
        g_async_pl.running = true
        g_async_pl.done = false
        g_async_pl.error = string()
        g_async_pl.progress = 0.0
        g_async_pl.speed = string()
        g_async_pl.eta = string()
        g_async_pl.status_line = string()
        g_async_pl.items_done = 0
        g_async_pl.items_total = 0
        g_async_pl.current_title = string()
        g_async_pl.url = string(url.data(), url.size())
        g_async_pl.format = string(format.data(), format.size())
        g_async_pl.output_dir = string(dir.data(), dir.size())
        g_async_pl.min_quality = min_quality
        g_async_pl.max_quality = max_quality
        g_async_pl.mu.unlock()

        std::concurrent.spawn(playlist_thread_entry, null)
        return string()
    }

    // Poll async playlist download status.
    public func poll_async_playlist_download() : string {
        g_async_pl.mu.lock()
        var running = g_async_pl.running
        var done = g_async_pl.done
        var error = g_async_pl.error.copy()
        var progress = g_async_pl.progress
        var speed = g_async_pl.speed.copy()
        var eta = g_async_pl.eta.copy()
        var status = g_async_pl.status_line.copy()
        var items_done = g_async_pl.items_done
        var items_total = g_async_pl.items_total
        var current_title = g_async_pl.current_title.copy()
        g_async_pl.mu.unlock()

        var out = string::make_no_len("{\"running\":")
        if(running) { out.append_string(&string::make_no_len("true")) }
        else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"done\":"))
        if(done) { out.append_string(&string::make_no_len("true")) }
        else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"error\":"))
        out.append_string(&json_string(string_view::make_view(&error)))
        out.append_string(&string::make_no_len(",\"progress\":"))
        var ps = string()
        ps.append_double(progress, 1)
        out.append_string(&ps)
        out.append_string(&string::make_no_len(",\"speed\":"))
        out.append_string(&json_string(string_view::make_view(&speed)))
        out.append_string(&string::make_no_len(",\"eta\":"))
        out.append_string(&json_string(string_view::make_view(&eta)))
        out.append_string(&string::make_no_len(",\"status\":"))
        out.append_string(&json_string(string_view::make_view(&status)))
        out.append_string(&string::make_no_len(",\"items_done\":"))
        var ds = string()
        ds.append_integer(items_done as bigint)
        out.append_string(&ds)
        out.append_string(&string::make_no_len(",\"items_total\":"))
        var ts = string()
        ts.append_integer(items_total as bigint)
        out.append_string(&ts)
        out.append_string(&string::make_no_len(",\"current_title\":"))
        out.append_string(&json_string(string_view::make_view(&current_title)))
        out.append('}')
        return out
    }

    // Cancel async playlist download.
    public func cancel_async_playlist_download() {
        g_async_pl.mu.lock()
        g_async_pl.running = false
        g_async_pl.done = true
        g_async_pl.error = string::make_no_len("cancelled")
        g_async_pl.mu.unlock()
    }

} // end namespace cdm
