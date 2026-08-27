// ChemicalDM — Async YouTube operations.
//
// All yt-dlp operations run in background threads via popen() to keep the
// webview UI responsive. The download flow extracts direct URLs with
// yt-dlp --get-url, feeds them to the segmented downloader, and auto-merges
// separate video+audio streams with ffmpeg.

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
        var url : string
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

    // ---- Async download state ----

    public struct AsyncDlState {
        var running : bool
        var done : bool
        var error : string
        var progress : double
        var speed : string
        var eta : string
        var status_line : string
        var title : string
        var output_path : string
        var url : string
        var format : string
        var output_dir : string
        var dm : *mut DownloadManager  // pointer to the app's download manager
        var mu : mutex

        @constructor func constructor() {
            return AsyncDlState {
                running = false, done = false,
                error = string(), progress = 0.0,
                speed = string(), eta = string(),
                status_line = string(), title = string(),
                output_path = string(),
                url = string(), format = string(), output_dir = string(),
                dm = null,
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
        var url : string
        var format : string
        var output_dir : string
        var min_quality : int
        var max_quality : int
        var dm : *mut DownloadManager
        var mu : mutex

        @constructor func constructor() {
            return AsyncPlState {
                running = false, done = false,
                error = string(), progress = 0.0,
                speed = string(), eta = string(),
                status_line = string(), items_done = 0,
                items_total = 0, current_title = string(),
                url = string(), format = string(), output_dir = string(),
                min_quality = 0, max_quality = 0, dm = null,
                mu = mutex()
            }
        }
    }

    @never_destructed public unsafe var g_async_pl = zeroed<AsyncPlState>()

    // ---- Quality/format helpers ----

    // Map a quality height (e.g. 720) to a yt-dlp format string.
    public func quality_to_format(height : int) : string {
        if(height <= 0) {
            return string::make_no_len("bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best")
        }
        var fmt = string::make_no_len("bestvideo[height<=")
        var hs = string()
        hs.append_integer(height as bigint)
        fmt.append_string(&hs)
        fmt.append_view(string_view::make_no_len("][ext=mp4]+bestaudio[ext=m4a]/best[height<="))
        fmt.append_string(&hs)
        fmt.append_view(string_view::make_no_len("][ext=mp4]/best"))
        return fmt
    }

    // Build the effective format string from UI selection + min/max quality.
    public func resolve_yt_format(ui_format : string_view, min_q : int, max_q : int) : string {
        // "best" = auto-select; otherwise use the specific format_id.
        var best_marker = string_view::make_no_len("best")
        var is_best = (ui_format.size() == 0u)
        if(!is_best && ui_format.size() == 4u) {
            is_best = (ui_format.get(0) == 'b' && ui_format.get(1) == 'e' && ui_format.get(2) == 's' && ui_format.get(3) == 't')
        }
        if(is_best) {
            if(max_q > 0) {
                return quality_to_format(max_q)
            }
            if(min_q > 0) {
                return quality_to_format(min_q)
            }
            return quality_to_format(0)
        }
        // User picked a specific format_id — use it directly.
        return string(ui_format.data(), ui_format.size())
    }

    // ---- Shell escaping ----

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

    func parse_yt_progress_line(line : string_view, progress : &mut double,
                                speed : &mut string, eta : &mut string,
                                status : &mut string, title : &mut string) {
        *status = string(line.data(), line.size())

        var dl_marker = string_view::make_no_len("[download]")
        var dl_idx = line.find(&dl_marker)
        if(dl_idx != std::NPOS) {
            var pct_marker = string_view::make_no_len("%")
            var pct_idx = line.find(&pct_marker)
            if(pct_idx != std::NPOS) {
                var pct_end = pct_idx
                var pct_start = pct_end
                while(pct_start > 0 && line.get(pct_start - 1u) != ' ') {
                    pct_start = pct_start - 1u
                }
                *progress = parse_double_view(line.subview(pct_start, pct_end))
            }
            var si : usize = 0
            while(si + 3u < line.size()) {
                if(line.get(si) == ' ' && line.get(si + 1u) == 'a' &&
                   line.get(si + 2u) == 't' && line.get(si + 3u) == ' ') {
                    var ss = si + 4u
                    var se = ss
                    while(se < line.size() && line.get(se) != ' ') { se = se + 1u }
                    *speed = string(line.data() + ss, se - ss)
                    break
                }
                si = si + 1u
            }
            var ei : usize = 0
            while(ei + 3u < line.size()) {
                if(line.get(ei) == 'E' && line.get(ei + 1u) == 'T' &&
                   line.get(ei + 2u) == 'A' && line.get(ei + 3u) == ' ') {
                    var es = ei + 4u
                    var ee = es
                    while(ee < line.size() && line.get(ee) != ' ' &&
                          line.get(ee) != '\n' && line.get(ee) != '\r') { ee = ee + 1u }
                    *eta = string(line.data() + es, ee - es)
                    break
                }
                ei = ei + 1u
            }
            return
        }
        var merge_marker = string_view::make_no_len("[Merger]")
        if(line.find(&merge_marker) != std::NPOS) {
            *status = string(line.data(), line.size())
        }
    }

    // ---- Info fetch ----

    func info_thread_entry(arg : *void) : *void {
        std::concurrent.sleep_ms(10u)

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
        var fp = popen(cmd.data(), "r")
        if(fp == null) {
            g_async_info.mu.lock()
            g_async_info.error = string::make_no_len("failed to start yt-dlp")
            g_async_info.done = true
            g_async_info.running = false
            g_async_info.mu.unlock()
            return null
        }

        var json_out = string()
        while(true) {
            var ch = fgetc(fp)
            if(ch == -1) { break }
            json_out.append(ch as char)
        }
        var exit_code = pclose(fp)

        g_async_info.mu.lock()
        if(exit_code != 0 && json_out.size() == 0u) {
            g_async_info.error = string::make_no_len("yt-dlp failed (exit ")
            var ecs = string()
            ecs.append_integer(exit_code as bigint)
            g_async_info.error.append_string(&ecs)
            g_async_info.error.append(')')
            g_async_info.done = true
            g_async_info.running = false
            g_async_info.mu.unlock()
            return null
        }
        if(json_out.size() > 0u && json_out.get(0) != '{') {
            g_async_info.error = json_out.copy()
            g_async_info.done = true
            g_async_info.running = false
            g_async_info.mu.unlock()
            return null
        }
        g_async_info.result_json = json_out.copy()
        g_async_info.done = true
        g_async_info.running = false
        g_async_info.mu.unlock()
        return null
    }

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
        std::concurrent.spawn(info_thread_entry, null)
        return string()
    }

    public func poll_async_info() : string {
        g_async_info.mu.lock()
        var running = g_async_info.running
        var done = g_async_info.done
        var error = g_async_info.error.copy()
        var result = g_async_info.result_json.copy()
        var is_pl = g_async_info.is_playlist
        g_async_info.mu.unlock()

        var out = string::make_no_len("{\"running\":")
        if(running) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"done\":"))
        if(done) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"error\":"))
        out.append_string(&json_string(string_view::make_view(&error)))
        out.append_string(&string::make_no_len(",\"is_playlist\":"))
        if(is_pl) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        if(done && error.size() == 0u && result.size() > 0u) {
            out.append_string(&string::make_no_len(",\"info\":"))
            out.append_string(&result)
        }
        out.append('}')
        return out
    }

    public func cancel_async_info() {
        g_async_info.mu.lock()
        g_async_info.running = false
        g_async_info.done = true
        g_async_info.error = string::make_no_len("cancelled")
        g_async_info.mu.unlock()
    }

    // ---- URL extraction + download via segmented downloader ----

    // Extract direct download URL(s) from a YouTube video using yt-dlp --get-url.
    // Returns the URL(s) separated by newlines (video+audio = 2 lines, combined = 1).
    func extract_urls(url : string_view, format : string_view) : string {
        var args = vector<string>()
        args.push_back(ytdlp_resolved_path())
        args.push_back(string::make_no_len("--get-url"))
        args.push_back(string::make_no_len("--no-warnings"))
        args.push_back(string::make_no_len("--no-playlist"))
        args.push_back(string::make_no_len("-f"))
        args.push_back(string(format.data(), format.size()))
        args.push_back(string(url.data(), url.size()))

        var cmd = build_cmd(&args)
        var fp = popen(cmd.data(), "r")
        if(fp == null) { return string() }

        var urls = string()
        while(true) {
            var ch = fgetc(fp)
            if(ch == -1) { break }
            urls.append(ch as char)
        }
        pclose(fp)
        return urls
    }

    // Trim whitespace from a string_view.
    func trim_view(s : string_view) : string_view {
        var start : usize = 0
        while(start < s.size() && (s.get(start) == ' ' || s.get(start) == '\n' || s.get(start) == '\r' || s.get(start) == '\t')) {
            start = start + 1u
        }
        var end = s.size()
        while(end > start && (s.get(end - 1u) == ' ' || s.get(end - 1u) == '\n' || s.get(end - 1u) == '\r' || s.get(end - 1u) == '\t')) {
            end = end - 1u
        }
        if(end <= start) { return string_view::make_no_len("") }
        return s.subview(start, end)
    }

    // Split extracted URLs into individual lines and return them as a vector.
    func split_urls(raw : string_view) : vector<string> {
        var urls = vector<string>()
        var line_start : usize = 0
        var i : usize = 0
        while(i < raw.size()) {
            var c = raw.get(i)
            if(c == '\n' || c == '\r') {
                var trimmed = trim_view(raw.subview(line_start, i))
                if(trimmed.size() > 0u) {
                    urls.push_back(string(trimmed.data(), trimmed.size()))
                }
                line_start = i + 1u
                // Skip \r\n
                if(c == '\r' && i + 1u < raw.size() && raw.get(i + 1u) == '\n') {
                    i = i + 1u
                    line_start = line_start + 1u
                }
            }
            i = i + 1u
        }
        // Last line
        if(line_start < raw.size()) {
            var trimmed = trim_view(raw.subview(line_start, raw.size()))
            if(trimmed.size() > 0u) {
                urls.push_back(string(trimmed.data(), trimmed.size()))
            }
        }
        return urls
    }

    // Suggest a filename from the YouTube URL/title.
    func suggest_yt_filename(title : string_view, ext : string_view) : string {
        if(title.size() > 0u) {
            var fname = string(title.data(), title.size())
            // Sanitize: replace problematic chars with underscore.
            for(var i = 0u; i < fname.size(); i++) {
                var c = fname.get(i)
                if(c == '/' || c == '\\' || c == ':' || c == '*' || c == '?' ||
                   c == '"' || c == '<' || c == '>' || c == '|') {
                    fname.set(i, '_' as char)
                }
            }
            fname.append('.')
            fname.append_view(&ext)
            return fname
        }
        return string::make_no_len("video.mp4")
    }

    // ---- Download thread ----

    func download_thread_entry(arg : *void) : *void {
        std::concurrent.sleep_ms(10u)

        var dm = g_async_dl.dm
        var fmt = resolve_yt_format(
            string_view::make_view(&g_async_dl.format),
            0, 0
        )

        // Step 1: Extract direct URLs via yt-dlp --get-url
        g_async_dl.mu.lock()
        g_async_dl.status_line = string::make_no_len("Extracting download URLs...")
        g_async_dl.mu.unlock()

        var raw_urls = extract_urls(string_view::make_view(&g_async_dl.url), string_view::make_view(&fmt))
        var urls = split_urls(string_view::make_view(&raw_urls))

        if(urls.size() == 0u) {
            g_async_dl.mu.lock()
            g_async_dl.error = string::make_no_len("Failed to extract download URLs from yt-dlp")
            g_async_dl.done = true
            g_async_dl.running = false
            g_async_dl.mu.unlock()
            return null
        }

        // Step 2: Get the video title for filename.
        var title_args = vector<string>()
        title_args.push_back(ytdlp_resolved_path())
        title_args.push_back(string::make_no_len("--get-title"))
        title_args.push_back(string::make_no_len("--no-warnings"))
        title_args.push_back(string::make_no_len("--no-playlist"))
        title_args.push_back(g_async_dl.url.copy())
        var title_cmd = build_cmd(&title_args)
        var title_fp = popen(title_cmd.data(), "r")
        var video_title = string()
        if(title_fp != null) {
            while(true) {
                var ch = fgetc(title_fp)
                if(ch == -1 || ch == '\n' as int || ch == '\r' as int) { break }
                video_title.append(ch as char)
            }
            pclose(title_fp)
        }

        g_async_dl.mu.lock()
        g_async_dl.title = video_title.copy()
        g_async_dl.mu.unlock()

        // Step 3: Add URLs to the download manager.
        if(urls.size() == 1u) {
            // Single URL (combined video+audio) — add directly.
            var fname = suggest_yt_filename(string_view::make_view(&video_title), string_view::make_no_len("mp4"))
            g_async_dl.mu.lock()
            g_async_dl.status_line = string::make_no_len("Adding to download queue...")
            g_async_dl.mu.unlock()

            if(dm != null) {
                    var url0s = urls.get_ptr(0).size()
                    var url0d = urls.get_ptr(0).data()
                    var id = add_task_ex(&mut *dm, string_view(url0d, url0s),
                                     string_view::make_view(&g_async_dl.output_dir),
                                     string_view::make_view(&fname), 0, 0)
                if(id.size() > 0u) {
                    g_async_dl.mu.lock()
                    g_async_dl.output_path = id.copy()
                    g_async_dl.mu.unlock()
                }
            }

            // Wait for the download to complete by polling the DM.
            // (The download runs in the DM's worker thread.)
            var poll_interval_ms = 500
            while(dm != null) {
                std::concurrent.sleep_ms(poll_interval_ms as u32)
                if(dm == null) { break }
                var snap = snapshot(&mut *dm)
                var found = false
                var dl_done = false
                var dl_failed = false
                var dl_downloaded : i64 = 0
                var dl_total : i64 = 0
                var dl_speed : i64 = 0
                for(var i = 0u; i < snap.size(); i++) {
                    var it = snap.get_ptr(i)
                    if(it.id.equals(&g_async_dl.output_path)) {
                        found = true
                        dl_downloaded = it.downloaded_bytes
                        dl_total = it.total_bytes
                        dl_speed = it.speed_bytes_per_sec
                        if(it.state == STATE_DONE) { dl_done = true }
                        if(it.state == STATE_FAILED || it.state == STATE_CANCELLED) { dl_failed = true }
                        break
                    }
                }
                if(!found && g_async_dl.output_path.size() > 0u) {
                    // Item was removed or not found — assume done.
                    dl_done = true
                }
                // Update progress.
                g_async_dl.mu.lock()
                if(dl_total > 0) {
                    g_async_dl.progress = (dl_downloaded as double) * 100.0 / (dl_total as double)
                }
                g_async_dl.speed = format_bytes(dl_speed)
                g_async_dl.mu.unlock()

                if(dl_done) {
                    g_async_dl.mu.lock()
                    g_async_dl.progress = 100.0
                    g_async_dl.done = true
                    g_async_dl.running = false
                    g_async_dl.mu.unlock()
                    return null
                }
                if(dl_failed) {
                    g_async_dl.mu.lock()
                    var it_err = string()
                    // Get error from snapshot.
                    for(var i = 0u; i < snap.size(); i++) {
                        var it = snap.get_ptr(i)
                        if(it.id.equals(&g_async_dl.output_path)) {
                            it_err = it.error.copy()
                            break
                        }
                    }
                    if(it_err.size() == 0u) { it_err = string::make_no_len("download failed") }
                    g_async_dl.error = it_err.copy()
                    g_async_dl.done = true
                    g_async_dl.running = false
                    g_async_dl.mu.unlock()
                    return null
                }
            }
        } else if(urls.size() >= 2u) {
            // Two URLs: video + audio — add both, then merge when both complete.
            var video_url_d = urls.get_ptr(0).data()
            var video_url_s = urls.get_ptr(0).size()
            var audio_url_d = urls.get_ptr(1).data()
            var audio_url_s = urls.get_ptr(1).size()
            var base_name = suggest_yt_filename(string_view::make_view(&video_title), string_view::make_no_len("mp4"))

            // Strip extension for base name.
            var dot_pos = base_name.size()
            var j = base_name.size()
            while(j > 0u) {
                j = j - 1u
                if(base_name.get(j) == '.') {
                    dot_pos = j
                    break
                }
            }
            var base = string(base_name.data(), dot_pos)
            var video_name = base.copy()
            video_name.append_view(string_view::make_no_len(".video.mp4"))
            var audio_name = base.copy()
            audio_name.append_view(string_view::make_no_len(".audio.m4a"))

            g_async_dl.mu.lock()
            g_async_dl.status_line = string::make_no_len("Adding video+audio to download queue...")
            g_async_dl.mu.unlock()

            var video_id = string()
            var audio_id = string()
            if(dm != null) {
                video_id = add_task_ex(&mut *dm, string_view(video_url_d, video_url_s),
                                       string_view::make_view(&g_async_dl.output_dir),
                                       string_view::make_view(&video_name), 0, 0)
                audio_id = add_task_ex(&mut *dm, string_view(audio_url_d, audio_url_s),
                                       string_view::make_view(&g_async_dl.output_dir),
                                       string_view::make_view(&audio_name), 0, 0)
            }

            // Wait for both to complete.
            var poll_ms = 500
            while(dm != null) {
                std::concurrent.sleep_ms(poll_ms as u32)
                if(dm == null) { break }
                var snap = snapshot(&mut *dm)
                var v_done = false
                var a_done = false
                var v_failed = false
                var a_failed = false
                var v_downloaded : i64 = 0
                var v_total : i64 = 0
                var a_downloaded : i64 = 0
                var a_total : i64 = 0
                var v_speed : i64 = 0

                for(var i = 0u; i < snap.size(); i++) {
                    var it = snap.get_ptr(i)
                    if(video_id.size() > 0u && it.id.equals(&video_id)) {
                        v_downloaded = it.downloaded_bytes
                        v_total = it.total_bytes
                        v_speed = it.speed_bytes_per_sec
                        if(it.state == STATE_DONE) { v_done = true }
                        if(it.state == STATE_FAILED || it.state == STATE_CANCELLED) { v_failed = true }
                    }
                    if(audio_id.size() > 0u && it.id.equals(&audio_id)) {
                        a_downloaded = it.downloaded_bytes
                        a_total = it.total_bytes
                        if(it.state == STATE_DONE) { a_done = true }
                        if(it.state == STATE_FAILED || it.state == STATE_CANCELLED) { a_failed = true }
                    }
                }

                // Update progress (average of both).
                var total_all = v_total + a_total
                var downloaded_all = v_downloaded + a_downloaded
                g_async_dl.mu.lock()
                if(total_all > 0) {
                    g_async_dl.progress = (downloaded_all as double) * 100.0 / (total_all as double)
                }
                g_async_dl.speed = format_bytes(v_speed)
                g_async_dl.mu.unlock()

                if(v_failed || a_failed) {
                    g_async_dl.mu.lock()
                    g_async_dl.error = string::make_no_len("download failed")
                    g_async_dl.done = true
                    g_async_dl.running = false
                    g_async_dl.mu.unlock()
                    return null
                }

                if(v_done && a_done) {
                    // Step 4: Merge with ffmpeg.
                    g_async_dl.mu.lock()
                    g_async_dl.status_line = string::make_no_len("Merging video + audio with ffmpeg...")
                    g_async_dl.progress = 99.0
                    g_async_dl.mu.unlock()

                    var video_path = g_async_dl.output_dir.copy()
                    video_path.append('/')
                    video_path.append_string(&video_name)
                    var audio_path = g_async_dl.output_dir.copy()
                    audio_path.append('/')
                    audio_path.append_string(&audio_name)
                    var merged_path = g_async_dl.output_dir.copy()
                    merged_path.append('/')
                    merged_path.append_string(&base_name)

                    var merge_result = ffmpeg_merge(
                        string_view::make_view(&video_path),
                        string_view::make_view(&audio_path),
                        string_view::make_view(&merged_path)
                    )

                    if(merge_result.size() > 0u) {
                        // Remove the temporary video+audio files.
                        remove(video_path.data())
                        remove(audio_path.data())
                        // Remove the download items from the queue.
                        if(dm != null) {
                            remove_task(&mut *dm, &video_id)
                            remove_task(&mut *dm, &audio_id)
                        }
                        g_async_dl.mu.lock()
                        g_async_dl.progress = 100.0
                        g_async_dl.output_path = merged_path.copy()
                        g_async_dl.done = true
                        g_async_dl.running = false
                        g_async_dl.mu.unlock()
                    } else {
                        // Merge failed — retry once.
                        g_async_dl.mu.lock()
                        g_async_dl.status_line = string::make_no_len("Merge failed, retrying...")
                        g_async_dl.mu.unlock()
                        std::concurrent.sleep_ms(1000u)
                        merge_result = ffmpeg_merge(
                            string_view::make_view(&video_path),
                            string_view::make_view(&audio_path),
                            string_view::make_view(&merged_path)
                        )
                        if(merge_result.size() > 0u) {
                            remove(video_path.data())
                            remove(audio_path.data())
                            if(dm != null) {
                                remove_task(&mut *dm, &video_id)
                                remove_task(&mut *dm, &audio_id)
                            }
                            g_async_dl.mu.lock()
                            g_async_dl.progress = 100.0
                            g_async_dl.output_path = merged_path.copy()
                            g_async_dl.done = true
                            g_async_dl.running = false
                            g_async_dl.mu.unlock()
                        } else {
                            g_async_dl.mu.lock()
                            g_async_dl.error = string::make_no_len("ffmpeg merge failed after retry")
                            g_async_dl.done = true
                            g_async_dl.running = false
                            g_async_dl.mu.unlock()
                        }
                    }
                    return null
                }
            }
        }

        g_async_dl.mu.lock()
        g_async_dl.done = true
        g_async_dl.running = false
        g_async_dl.mu.unlock()
        return null
    }

    public func start_async_download(url : string_view, format : string_view,
                                     dir : string_view, dm : *mut DownloadManager) : string {
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
        g_async_dl.dm = dm
        g_async_dl.mu.unlock()
        std::concurrent.spawn(download_thread_entry, null)
        return string()
    }

    public func poll_async_download() : string {
        g_async_dl.mu.lock()
        var running = g_async_dl.running
        var done = g_async_dl.done
        var error = g_async_dl.error.copy()
        var progress = g_async_dl.progress
        var speed = g_async_dl.speed.copy()
        var status = g_async_dl.status_line.copy()
        var title = g_async_dl.title.copy()
        g_async_dl.mu.unlock()

        var out = string::make_no_len("{\"running\":")
        if(running) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"done\":"))
        if(done) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"error\":"))
        out.append_string(&json_string(string_view::make_view(&error)))
        out.append_string(&string::make_no_len(",\"progress\":"))
        var ps = string()
        ps.append_double(progress, 1)
        out.append_string(&ps)
        out.append_string(&string::make_no_len(",\"speed\":"))
        out.append_string(&json_string(string_view::make_view(&speed)))
        out.append_string(&string::make_no_len(",\"status\":"))
        out.append_string(&json_string(string_view::make_view(&status)))
        out.append_string(&string::make_no_len(",\"title\":"))
        out.append_string(&json_string(string_view::make_view(&title)))
        out.append('}')
        return out
    }

    public func cancel_async_download() {
        g_async_dl.mu.lock()
        g_async_dl.running = false
        g_async_dl.done = true
        g_async_dl.error = string::make_no_len("cancelled")
        g_async_dl.mu.unlock()
    }

    // ---- Playlist download ----

    func playlist_thread_entry(arg : *void) : *void {
        std::concurrent.sleep_ms(10u)

        var dm = g_async_pl.dm
        var fmt = resolve_yt_format(
            string_view::make_view(&g_async_pl.format),
            g_async_pl.min_quality, g_async_pl.max_quality
        )

        // First, extract the playlist entries using --flat-playlist --print url.
        var args = vector<string>()
        args.push_back(ytdlp_resolved_path())
        args.push_back(string::make_no_len("--flat-playlist"))
        args.push_back(string::make_no_len("--print"))
        args.push_back(string::make_no_len("%(url)s|||%(title)s|||%(duration)s"))
        args.push_back(string::make_no_len("--no-warnings"))
        args.push_back(g_async_pl.url.copy())

        var cmd = build_cmd(&args)
        var fp = popen(cmd.data(), "r")
        if(fp == null) {
            g_async_pl.mu.lock()
            g_async_pl.error = string::make_no_len("failed to start yt-dlp")
            g_async_pl.done = true
            g_async_pl.running = false
            g_async_pl.mu.unlock()
            return null
        }

        // Read all output lines.
        var entries_raw = string()
        while(true) {
            var ch = fgetc(fp)
            if(ch == -1) { break }
            entries_raw.append(ch as char)
        }
        pclose(fp)

        // Parse entries (each line: url|||title|||duration).
        var entries = vector<string>()
        var line_start : usize = 0
        var k : usize = 0
        while(k < entries_raw.size()) {
            if(entries_raw.get(k) == '\n') {
                var line = trim_view(string_view::make_view(&entries_raw).subview(line_start, k))
                if(line.size() > 0u) {
                    entries.push_back(string(line.data(), line.size()))
                }
                line_start = k + 1u
            }
            k = k + 1u
        }
        if(line_start < entries_raw.size()) {
            var line = trim_view(string_view::make_view(&entries_raw).subview(line_start, entries_raw.size()))
            if(line.size() > 0u) {
                entries.push_back(string(line.data(), line.size()))
            }
        }

        if(entries.size() == 0u) {
            g_async_pl.mu.lock()
            g_async_pl.error = string::make_no_len("no playlist entries found")
            g_async_pl.done = true
            g_async_pl.running = false
            g_async_pl.mu.unlock()
            return null
        }

        g_async_pl.mu.lock()
        g_async_pl.items_total = entries.size() as int
        g_async_pl.items_done = 0
        g_async_pl.mu.unlock()

        // Download each entry.
        var total_entries = entries.size() as int
        for(var idx = 0u; idx < entries.size(); idx++) {
            // Check for cancellation.
            g_async_pl.mu.lock()
            var cancelled = !g_async_pl.running
            g_async_pl.mu.unlock()
            if(cancelled) { break }

            // Parse entry: url|||title|||duration
            var entry_d = entries.get_ptr(idx).data()
            var entry_s = entries.get_ptr(idx).size()
            var entry_v = string_view(entry_d, entry_s)
            var sep = string_view::make_no_len("|||")
            var sep_idx = entry_v.find(&sep)
            unsafe var entry_url : string_view
            unsafe var entry_title : string_view
            if(sep_idx != std::NPOS) {
                entry_url = entry_v.subview(0, sep_idx)
                var rest = entry_v.subview(sep_idx + 3u, entry_s)
                var sep2_idx = rest.find(&sep)
                if(sep2_idx != std::NPOS) {
                    entry_title = rest.subview(0, sep2_idx)
                } else {
                    entry_title = rest
                }
            } else {
                entry_url = entry_v
                entry_title = string_view::make_no_len("")
            }

            g_async_pl.mu.lock()
            g_async_pl.current_title = string(entry_title.data(), entry_title.size())
            g_async_pl.status_line = string::make_no_len("Downloading: ")
            g_async_pl.status_line.append_view(&entry_title)
            g_async_pl.mu.unlock()

            // Extract URL for this entry and add to DM.
            var raw_urls = extract_urls(entry_url, string_view::make_view(&fmt))
            var urls = split_urls(string_view::make_view(&raw_urls))

            if(urls.size() == 0u) {
                g_async_pl.mu.lock()
                g_async_pl.items_done = g_async_pl.items_done + 1
                g_async_pl.mu.unlock()
                continue
            }

            // Add first URL to the DM.
            var fname = suggest_yt_filename(entry_title, string_view::make_no_len("mp4"))
            if(dm != null) {
                var eu_d = urls.get_ptr(0).data()
                var eu_s = urls.get_ptr(0).size()
                add_task_ex(&mut *dm, string_view(eu_d, eu_s),
                            string_view::make_view(&g_async_pl.output_dir),
                            string_view::make_view(&fname), 0, 0)
            }

            // Wait for this entry to finish.
            while(dm != null) {
                std::concurrent.sleep_ms(500u)
                if(dm == null) { break }
                var snap = snapshot(&mut *dm)
                var all_terminal = true
                var any_failed = false
                for(var i = 0u; i < snap.size(); i++) {
                    var it = snap.get_ptr(i)
                    if(it.state == STATE_QUEUED || it.state == STATE_DOWNLOADING || it.state == STATE_PAUSED) {
                        all_terminal = false
                    }
                    if(it.state == STATE_FAILED || it.state == STATE_CANCELLED) {
                        any_failed = true
                    }
                }
                if(all_terminal) { break }
            }

            g_async_pl.mu.lock()
            g_async_pl.items_done = g_async_pl.items_done + 1
            g_async_pl.progress = (g_async_pl.items_done as double) * 100.0 / (total_entries as double)
            g_async_pl.mu.unlock()
        }

        g_async_pl.mu.lock()
        g_async_pl.done = true
        g_async_pl.running = false
        g_async_pl.progress = 100.0
        g_async_pl.mu.unlock()
        return null
    }

    public func start_async_playlist_download(url : string_view, format : string_view,
                                              dir : string_view, min_quality : int,
                                              max_quality : int, dm : *mut DownloadManager) : string {
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
        g_async_pl.dm = dm
        g_async_pl.mu.unlock()
        std::concurrent.spawn(playlist_thread_entry, null)
        return string()
    }

    public func poll_async_playlist_download() : string {
        g_async_pl.mu.lock()
        var running = g_async_pl.running
        var done = g_async_pl.done
        var error = g_async_pl.error.copy()
        var progress = g_async_pl.progress
        var items_done = g_async_pl.items_done
        var items_total = g_async_pl.items_total
        var current_title = g_async_pl.current_title.copy()
        var status = g_async_pl.status_line.copy()
        g_async_pl.mu.unlock()

        var out = string::make_no_len("{\"running\":")
        if(running) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"done\":"))
        if(done) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"error\":"))
        out.append_string(&json_string(string_view::make_view(&error)))
        out.append_string(&string::make_no_len(",\"progress\":"))
        var ps = string()
        ps.append_double(progress, 1)
        out.append_string(&ps)
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
        out.append_string(&string::make_no_len(",\"status\":"))
        out.append_string(&json_string(string_view::make_view(&status)))
        out.append('}')
        return out
    }

    public func cancel_async_playlist_download() {
        g_async_pl.mu.lock()
        g_async_pl.running = false
        g_async_pl.done = true
        g_async_pl.error = string::make_no_len("cancelled")
        g_async_pl.mu.unlock()
    }

} // end namespace cdm
