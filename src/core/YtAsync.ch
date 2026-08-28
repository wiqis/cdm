// ChemicalDM — Async YouTube operations.
//
// All yt-dlp operations run in background threads via process::execute (fork-safe)
// to keep the webview UI responsive. The download flow extracts direct URLs with
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
        var result_json : string
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
        var dm_task_id : string       // video task ID in the DM
        var audio_task_id : string    // audio task ID (when 2 URLs)
        var needs_merge : bool
        var auto_merge : bool
        var delete_separate : bool
        var merge_status : string     // "idle" | "waiting" | "merging" | "merged" | "failed"
        var merge_error : string
        var url : string
        var format : string
        var mode : string
        var audio_format : string
        var min_quality : int
        var max_quality : int
        var output_dir : string
        var dm : *mut DownloadManager
        var mu : mutex

        @constructor func constructor() {
            return AsyncDlState {
                running = false, done = false,
                error = string(), progress = 0.0,
                speed = string(), eta = string(),
                status_line = string(), title = string(),
                dm_task_id = string(), audio_task_id = string(),
                needs_merge = false, auto_merge = true, delete_separate = true,
                merge_status = string(), merge_error = string(),
                url = string(), format = string(),
                mode = string(), audio_format = string(),
                min_quality = 0, max_quality = 0,
                output_dir = string(),
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

    // yt-dlp protocol filter that EXCLUDES HLS manifests (m3u8). The app's own
    // segmented HTTP engine cannot download HLS playlists (it would save the
    // playlist text as the "video file", which ffmpeg then fails to read). We
    // force progressive / DASH streams that the engine can fetch directly, and
    // that ffmpeg can mux with -c copy.
    public func no_hls_filter() : string {
        return string::make_no_len("[protocol!=m3u8][protocol!=m3u8_native][protocol!=http_hls][protocol!=https_hls]")
    }

    public func quality_to_format(height : int) : string {
        var proto = no_hls_filter()
        if(height <= 0) {
            var fmt = string::make_no_len("bestvideo[ext=mp4]")
            fmt.append_string(&proto)
            fmt.append_view(string_view::make_no_len("+bestaudio[ext=m4a]"))
            fmt.append_string(&proto)
            fmt.append_view(string_view::make_no_len("/best[ext=mp4]"))
            fmt.append_string(&proto)
            fmt.append_view(string_view::make_no_len("/best"))
            fmt.append_string(&proto)
            return fmt
        }
        var hs = string()
        hs.append_integer(height as bigint)
        var fmt = string::make_no_len("bestvideo[height<=")
        fmt.append_string(&hs)
        fmt.append_view(string_view::make_no_len("][ext=mp4]"))
        fmt.append_string(&proto)
        fmt.append_view(string_view::make_no_len("+bestaudio[ext=m4a]"))
        fmt.append_string(&proto)
        fmt.append_view(string_view::make_no_len("/best[height<="))
        fmt.append_string(&hs)
        fmt.append_view(string_view::make_no_len("][ext=mp4]"))
        fmt.append_string(&proto)
        fmt.append_view(string_view::make_no_len("/best"))
        fmt.append_string(&proto)
        return fmt
    }

    public func resolve_yt_format(ui_format : string_view, min_q : int, max_q : int) : string {
        var is_best = (ui_format.size() == 0u)
        if(!is_best && ui_format.size() == 4u) {
            is_best = (ui_format.get(0) == 'b' && ui_format.get(1) == 'e' && ui_format.get(2) == 's' && ui_format.get(3) == 't')
        }
        if(is_best) {
            if(max_q > 0) { return quality_to_format(max_q) }
            if(min_q > 0) { return quality_to_format(min_q) }
            return quality_to_format(0)
        }
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
                while(pct_start > 0 && line.get(pct_start - 1u) != ' ') { pct_start = pct_start - 1u }
                *progress = parse_double_view(line.subview(pct_start, pct_end))
            }
            var si : usize = 0
            while(si + 3u < line.size()) {
                if(line.get(si) == ' ' && line.get(si + 1u) == 'a' && line.get(si + 2u) == 't' && line.get(si + 3u) == ' ') {
                    var ss = si + 4u; var se = ss
                    while(se < line.size() && line.get(se) != ' ') { se = se + 1u }
                    *speed = string(line.data() + ss, se - ss); break
                }
                si = si + 1u
            }
            var ei : usize = 0
            while(ei + 3u < line.size()) {
                if(line.get(ei) == 'E' && line.get(ei + 1u) == 'T' && line.get(ei + 2u) == 'A' && line.get(ei + 3u) == ' ') {
                    var es = ei + 4u; var ee = es
                    while(ee < line.size() && line.get(ee) != ' ' && line.get(ee) != '\n' && line.get(ee) != '\r') { ee = ee + 1u }
                    *eta = string(line.data() + es, ee - es); break
                }
                ei = ei + 1u
            }
            return
        }
        var merge_marker = string_view::make_no_len("[Merger]")
        if(line.find(&merge_marker) != std::NPOS) { *status = string(line.data(), line.size()) }
    }

    // Run a yt-dlp/ffmpeg command and capture its output.
    //
    // Uses the `process` library (fork-safe execve in the child: no malloc/getenv
    // after fork) so it is safe to call from a background thread inside the
    // multithreaded WebKitGTK GUI. Raw popen()/fork() here would deadlock the
    // child whenever another thread holds a lock at fork time, leaving the info
    // fetch (or download) stuck forever.
    func run_yt_command(args : vector<string>, want_stderr : bool,
                        out_stdout : *mut string, out_stderr : *mut string, out_exit : *mut int) : bool {
        var cfg = process::ProcessConfig.default()
        cfg.args = args
        cfg.capture_stdout = true
        cfg.capture_stderr = want_stderr
        var res = process::execute(cfg)
        if(res is Result.Err) { return false }
        var Ok(pr) = res else unreachable
        *out_stdout = string(pr.output.stdout_data.data() as *char, pr.output.stdout_data.size())
        *out_stderr = string(pr.output.stderr_data.data() as *char, pr.output.stderr_data.size())
        *out_exit = pr.status.code
        return true
    }

    // ---- Info fetch ----

    func info_thread_entry(arg : *void) : *void {
        fprintf(stderr, "[CDM-INFO] thread started, url=%s\n", g_async_info.url.data())
        std::concurrent.sleep_ms(10u)
    var args = vector<string>()
    args.push_back(ytdlp_resolved_path())
    args.push_back(string::make_no_len("--dump-json"))
    args.push_back(string::make_no_len("--no-warnings"))
    if(g_async_info.is_playlist) { args.push_back(string::make_no_len("--flat-playlist")) }
    else { args.push_back(string::make_no_len("--no-playlist")) }
    args.push_back(g_async_info.url.copy())
    fprintf(stderr, "[CDM-INFO] spawning yt-dlp via process::execute\n")
    var json_out = string()
    var err_out = string()
    var exit_code = 0
    var spawned = run_yt_command(args, true, &raw mut json_out, &raw mut err_out, &raw mut exit_code)
    if(!spawned) {
        fprintf(stderr, "[CDM-INFO] process::execute failed to start\n")
        g_async_info.mu.lock()
        g_async_info.error = string::make_no_len("failed to start yt-dlp")
        g_async_info.done = true; g_async_info.running = false
        g_async_info.mu.unlock(); return null
    }
    fprintf(stderr, "[CDM-INFO] done, exit=%d, size=%d\n", exit_code, json_out.size() as int)
    g_async_info.mu.lock()
    if(exit_code != 0 && json_out.size() == 0u) {
        g_async_info.error = string::make_no_len("yt-dlp failed (exit ")
        var ecs = string(); ecs.append_integer(exit_code as bigint)
        g_async_info.error.append_string(&ecs); g_async_info.error.append(')')
        if(err_out.size() > 0u) { g_async_info.error.append(' '); g_async_info.error.append_string(&err_out) }
        g_async_info.done = true; g_async_info.running = false
        g_async_info.mu.unlock(); return null
    }
    if(json_out.size() > 0u && json_out.get(0) != '{') {
        g_async_info.error = json_out.copy()
        g_async_info.done = true; g_async_info.running = false
        g_async_info.mu.unlock(); return null
    }
    g_async_info.result_json = json_out.copy()
    g_async_info.done = true; g_async_info.running = false
    g_async_info.mu.unlock(); return null
}

    public func start_async_info(url : string_view) : string {
        g_async_info.mu.lock()
        if(g_async_info.running) { g_async_info.mu.unlock(); return string::make_no_len("info fetch already in progress") }
        g_async_info.running = true; g_async_info.done = false
        g_async_info.error = string(); g_async_info.result_json = string()
        g_async_info.is_playlist = is_youtube_playlist_url(url)
        g_async_info.url = string(url.data(), url.size())
        g_async_info.mu.unlock()
        std::concurrent.spawn(info_thread_entry, null)
        return string()
    }

    public func poll_async_info() : string {
        g_async_info.mu.lock()
        var running = g_async_info.running; var done = g_async_info.done
        var error = g_async_info.error.copy()
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
        out.append_string(&string::make_no_len(",\"has_info\":"))
        if(done && error.size() == 0u) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append('}')
        fprintf(stderr, "[CDM-INFO] poll_async_info -> running=%d done=%d has_info=%d json=%s\n",
                running as int, done as int, (done && error.size() == 0u) as int, out.data())
        return out
    }

    // Retrieve info by parsing the raw yt-dlp JSON into YtVideoInfo,
    // then serializing only the compact fields the UI needs.
    public func get_async_info() : string {
        g_async_info.mu.lock()
        var raw = g_async_info.result_json.copy()
        g_async_info.mu.unlock()
        if(raw.size() == 0u) { return string::make_no_len("{}") }
        // Parse with the existing JSON parser from YtInfo.ch
        var info = parse_video_json(std::string_view(raw.data(), raw.size()))
        var result = info.to_json()
        var vparser = JsonParser(256, 1048576)
        var vph = ASTJsonHandler.make()
        var vres = vparser.parse(result.data(), result.size(), &mut vph)
        fprintf(stderr, "[CDM-INFO] get_async_info: compact=%d bytes (from %d raw) JSON_VALID=%d msg=%s\n",
                result.size() as int, raw.size() as int, vres.ok as int, vres.msg)
        return result
    }

    public func cancel_async_info() {
        g_async_info.mu.lock()
        g_async_info.running = false; g_async_info.done = true
        g_async_info.error = string::make_no_len("cancelled")
        g_async_info.mu.unlock()
        fprintf(stderr, "[CDM-INFO] cancelled\n")
    }

    // ---- URL extraction ----

    func extract_urls(url : string_view, format : string_view) : string {
        var args = vector<string>()
        args.push_back(ytdlp_resolved_path())
        args.push_back(string::make_no_len("--get-url"))
        args.push_back(string::make_no_len("--no-warnings"))
        args.push_back(string::make_no_len("--no-playlist"))
        args.push_back(string::make_no_len("-f"))
        args.push_back(string(format.data(), format.size()))
    args.push_back(string(url.data(), url.size()))
    var urls = string()
    var err_out = string()
    var exit_code = 0
    if(!run_yt_command(args, false, &raw mut urls, &raw mut err_out, &raw mut exit_code)) { return string() }
    return urls
}

    func trim_view(s : string_view) : string_view {
        var start : usize = 0
        while(start < s.size() && (s.get(start) == ' ' || s.get(start) == '\n' || s.get(start) == '\r' || s.get(start) == '\t')) { start = start + 1u }
        var end = s.size()
        while(end > start && (s.get(end - 1u) == ' ' || s.get(end - 1u) == '\n' || s.get(end - 1u) == '\r' || s.get(end - 1u) == '\t')) { end = end - 1u }
        if(end <= start) { return string_view::make_no_len("") }
        return s.subview(start, end)
    }

    func split_urls(raw : string_view) : vector<string> {
        var urls = vector<string>()
        var line_start : usize = 0; var i : usize = 0
        while(i < raw.size()) {
            var c = raw.get(i)
            if(c == '\n' || c == '\r') {
                var trimmed = trim_view(raw.subview(line_start, i))
                if(trimmed.size() > 0u) { urls.push_back(string(trimmed.data(), trimmed.size())) }
                line_start = i + 1u
                if(c == '\r' && i + 1u < raw.size() && raw.get(i + 1u) == '\n') { i = i + 1u; line_start = line_start + 1u }
            }
            i = i + 1u
        }
        if(line_start < raw.size()) {
            var trimmed = trim_view(raw.subview(line_start, raw.size()))
            if(trimmed.size() > 0u) { urls.push_back(string(trimmed.data(), trimmed.size())) }
        }
        return urls
    }

    func suggest_yt_filename(title : string_view, ext : string_view) : string {
        if(title.size() > 0u) {
            var fname = string(title.data(), title.size())
            for(var i = 0u; i < fname.size(); i++) {
                var c = fname.get(i)
                if(c == '/' || c == '\\' || c == ':' || c == '*' || c == '?' || c == '"' || c == '<' || c == '>' || c == '|') { fname.set(i, '_' as char) }
            }
            fname.append('.'); fname.append_view(&ext)
            return fname
        }
        return string::make_no_len("video.mp4")
    }

    public func start_async_download(url : string_view, format : string_view,
                                        mode : string_view, audio_fmt : string_view,
                                        min_q : int, max_q : int,
                                        dir : string_view, dm : *mut DownloadManager) : string {
        g_async_dl.mu.lock()
        if(g_async_dl.running) { g_async_dl.mu.unlock(); return string::make_no_len("download already in progress") }
        g_async_dl.running = true; g_async_dl.done = false; g_async_dl.error = string()
        g_async_dl.progress = 0.0; g_async_dl.speed = string(); g_async_dl.eta = string()
        g_async_dl.status_line = string(); g_async_dl.title = string()
        g_async_dl.dm_task_id = string(); g_async_dl.audio_task_id = string()
        g_async_dl.needs_merge = false; g_async_dl.merge_status = string::make_no_len("idle")
        g_async_dl.merge_error = string()
        g_async_dl.url = string(url.data(), url.size())
        g_async_dl.format = string(format.data(), format.size())
        g_async_dl.mode = string(mode.data(), mode.size())
        g_async_dl.audio_format = string(audio_fmt.data(), audio_fmt.size())
        g_async_dl.min_quality = min_q; g_async_dl.max_quality = max_q
        g_async_dl.output_dir = string(dir.data(), dir.size())
        g_async_dl.dm = dm
        g_async_dl.mu.unlock()
        std::concurrent.spawn(download_thread_entry, null)
        return string()
    }


    // Merge separate video+audio files using ffmpeg via process::execute (fork-safe).
    // Writes to a temp file first, then renames to avoid overwriting the input.
    // On failure, `err` is filled with the ffmpeg stderr / a diagnostic message so
    // the UI can surface the real reason (e.g. missing ffmpeg or a codec mismatch).
    func ffmpeg_merge_files(video_path : string_view, audio_path : string_view,
                            output_path : string_view, err : &mut string) : bool {
        var ffmpeg = ffmpeg_resolved_path()
        if(ffmpeg.size() == 0u || !fs::exists(ffmpeg.data())) {
            err.append_string(&string::make_no_len("ffmpeg not found ("))
            err.append_string(&ffmpeg)
            err.append_string(&string::make_no_len(") - install ffmpeg to merge"))
            fprintf(stderr, "[CDM-MERGE] %s\n", err.data())
            return false
        }
        // Temp output path: output_path + ".merge_tmp.mp4"
        var tmp_path = string(output_path.data(), output_path.size())
        tmp_path.append_view(string_view::make_no_len(".merge_tmp.mp4"))
        var args = vector<string>()
        args.push_back(ffmpeg)
        args.push_back(string::make_no_len("-i"))
        args.push_back(string(video_path.data(), video_path.size()))
        args.push_back(string::make_no_len("-i"))
        args.push_back(string(audio_path.data(), audio_path.size()))
        // `-strict experimental` lets ffmpeg mux codecs like VP9/Opus into an MP4
        // container (older ffmpeg rejects them without it). Comes before -c copy.
        args.push_back(string::make_no_len("-strict"))
        args.push_back(string::make_no_len("experimental"))
        args.push_back(string::make_no_len("-c"))
        args.push_back(string::make_no_len("copy"))
        args.push_back(string::make_no_len("-y"))
        args.push_back(string(tmp_path.data(), tmp_path.size()))
        fprintf(stderr, "[CDM-MERGE] ffmpeg -i %s -i %s -strict experimental -c copy -y %s\n", video_path.data(), audio_path.data(), tmp_path.data())
        var cfg = process::ProcessConfig.default()
        cfg.args = args
        cfg.capture_stdout = false
        cfg.capture_stderr = true
        var res = process::execute(cfg)
        if(res is Result.Err) {
            err.append_string(&string::make_no_len("ffmpeg could not be started"))
            remove(tmp_path.data())
            return false
        }
        var Ok(pr) = res else unreachable
        var exit_code = pr.status.code
        if(exit_code != 0) {
            // Capture ffmpeg's own diagnostics so the failure is explainable.
            var sv = pr.stderr_str()
            err.append_view(&sv)
            fprintf(stderr, "[CDM-MERGE] ffmpeg exited %d: %s\n", exit_code, sv.data())
            // Clean up temp file on failure.
            remove(tmp_path.data())
            return false
        }
        // Rename temp to final output.
        var rename_res = rename(tmp_path.data(), output_path.data())
        if(rename_res != 0) {
            remove(tmp_path.data())
            err.append_string(&string::make_no_len("rename of merged file failed"))
            return false
        }
        return fs::exists(output_path.data())
    }

    // ---- Download thread (NON-BLOCKING) ----
    // Extracts URLs, adds to DM, returns immediately.

    func download_thread_entry(arg : *void) : *void {
        std::concurrent.sleep_ms(10u)
        var dm = g_async_dl.dm
        var user_fmt = string_view::make_view(&g_async_dl.format)
        var dl_mode = string_view::make_view(&g_async_dl.mode)
        var min_q = g_async_dl.min_quality
        var max_q = g_async_dl.max_quality
        var is_best = (user_fmt.size() == 0u)
        if(!is_best && user_fmt.size() == 4u) {
            is_best = (user_fmt.get(0) == 'b' && user_fmt.get(1) == 'e' && user_fmt.get(2) == 's' && user_fmt.get(3) == 't')
        }
        var is_audio_only = false
        if(dl_mode.size() == 10u) {
            is_audio_only = (dl_mode.get(0) == 'a' && dl_mode.get(1) == 'u' && dl_mode.get(2) == 'd' && dl_mode.get(3) == 'i' && dl_mode.get(4) == 'o' && dl_mode.get(5) == '_' && dl_mode.get(6) == 'o' && dl_mode.get(7) == 'n' && dl_mode.get(8) == 'l' && dl_mode.get(9) == 'y')
        }
        var fmt = string()
        if(is_audio_only) {
            fmt = string::make_no_len("bestaudio")
            fmt.append_string(&no_hls_filter())
        } else if(is_best) {
            fmt = resolve_yt_format(user_fmt, min_q, max_q)
        } else {
            fmt = string(user_fmt.data(), user_fmt.size())
            fmt.append_string(&no_hls_filter())
            fmt.append_view(string_view::make_no_len("+bestaudio"))
            fmt.append_string(&no_hls_filter())
            fmt.append_view(string_view::make_no_len("/best"))
            fmt.append_string(&no_hls_filter())
        }

        // Step 1: Extract direct URLs via yt-dlp --get-url
        g_async_dl.mu.lock()
        g_async_dl.status_line = string::make_no_len("Extracting download URLs...")
        g_async_dl.mu.unlock()

        var raw_urls = extract_urls(string_view::make_view(&g_async_dl.url), string_view::make_view(&fmt))
        var urls = split_urls(string_view::make_view(&raw_urls))

        if(urls.size() == 0u) {
            g_async_dl.mu.lock()
            g_async_dl.error = string::make_no_len("Failed to extract download URLs from yt-dlp")
            g_async_dl.done = true; g_async_dl.running = false
            g_async_dl.mu.unlock(); return null
        }

        // Step 2: Get the video title for filename.
    var title_args = vector<string>()
    title_args.push_back(ytdlp_resolved_path())
    title_args.push_back(string::make_no_len("--get-title"))
    title_args.push_back(string::make_no_len("--no-warnings"))
    title_args.push_back(string::make_no_len("--no-playlist"))
    title_args.push_back(g_async_dl.url.copy())
    var title_out = string()
    var title_err = string()
    var title_exit = 0
    var video_title = string()
    if(run_yt_command(title_args, false, &raw mut title_out, &raw mut title_err, &raw mut title_exit)) {
        var ti = 0u
        while(ti < title_out.size() && title_out.get(ti) != '\n' && title_out.get(ti) != '\r') { video_title.append(title_out.get(ti)); ti = ti + 1u }
    }
    g_async_dl.mu.lock()
        g_async_dl.title = video_title.copy()
        g_async_dl.mu.unlock()

        // Step 3: Add URL(s) to the download manager and return.
        if(dm != null) {
            var fname = suggest_yt_filename(string_view::make_view(&video_title), string_view::make_no_len("mp4"))
            g_async_dl.mu.lock()
            g_async_dl.status_line = string::make_no_len("Queued in download manager")
            g_async_dl.mu.unlock()

            var url0s = urls.get_ptr(0).size()
            var url0d = urls.get_ptr(0).data()
            var id = add_task_ex(&mut *dm, string_view(url0d, url0s),
                                 string_view::make_view(&g_async_dl.output_dir),
                                 string_view::make_view(&fname), 0, 0)

            if(id.size() > 0u) {
                g_async_dl.mu.lock()
                g_async_dl.dm_task_id = id.copy()
                g_async_dl.mu.unlock()
            }

            // If we have 2 URLs (separate video+audio), add the audio too.
            if(urls.size() >= 2u) {
                var audio_name = string::make_no_len("audio_")
                audio_name.append_string(&video_title)
                audio_name.append_view(string_view::make_no_len(".m4a"))
                var a_url_d = urls.get_ptr(1).data()
                var a_url_s = urls.get_ptr(1).size()
                var audio_id = add_task_ex(&mut *dm, string_view(a_url_d, a_url_s),
                            string_view::make_view(&g_async_dl.output_dir),
                            string_view::make_view(&audio_name), 0, 0)
                g_async_dl.mu.lock()
                g_async_dl.audio_task_id = audio_id.copy()
                g_async_dl.needs_merge = true
                g_async_dl.merge_status = string::make_no_len("waiting")
                g_async_dl.mu.unlock()
            }
        }

        // Mark as done — the URL extraction and DM add are complete.
        g_async_dl.mu.lock()
        g_async_dl.status_line = string::make_no_len("Download started")
        g_async_dl.done = true
        g_async_dl.running = false
        g_async_dl.mu.unlock()

        // Start merge monitor if this was a 2-URL download.
        maybe_start_merge_monitor(dm)
        return null
    }


    // ---- Merge monitor thread ----
    // Waits for both video and audio tasks to complete, then merges with ffmpeg.
    // Retries merge once on failure.

    func merge_monitor_entry(arg : *void) : *void {
        var dm = g_async_dl.dm
        var vid_id = string()
        var aud_id = string()
        var vid_dir = string()
        var vid_fname = string()
        var aud_fname = string()
        var title = string()
        var del_separate = false

        g_async_dl.mu.lock()
        vid_id = g_async_dl.dm_task_id.copy()
        aud_id = g_async_dl.audio_task_id.copy()
        vid_dir = g_async_dl.output_dir.copy()
        title = g_async_dl.title.copy()
        del_separate = g_async_dl.delete_separate
        g_async_dl.mu.unlock()

        // Build expected filenames.
        vid_fname = suggest_yt_filename(string_view::make_view(&title), string_view::make_no_len("mp4"))
        aud_fname = string::make_no_len("audio_")
        aud_fname.append_string(&title)
        aud_fname.append_view(string_view::make_no_len(".m4a"))

        // Poll until both tasks are done or failed.
        var vid_done = false
        var aud_done = false
        var merge_error = string()
        var poll_count = 0

        fprintf(stderr, "[CDM-MERGE] monitor started: vid=%s aud=%s\n", vid_id.data(), aud_id.data())

        while(!vid_done || !aud_done) {
            std::concurrent.sleep_ms(2000u)
            poll_count = poll_count + 1

            // Timeout after 2 hours.
            if(poll_count > 3600) {
                merge_error = string::make_no_len("merge timeout")
                break
            }

            var snap = snapshot(&mut *dm)
            vid_done = false
            aud_done = false
            var vid_failed = false
            var aud_failed = false

            for(var i = 0u; i < snap.size(); i++) {
                var it = snap.get_ptr(i)
                if(it.id.equals(&vid_id)) {
                    if(it.state == STATE_DONE) { vid_done = true }
                    if(it.state == STATE_FAILED || it.state == STATE_CANCELLED) { vid_failed = true }
                }
                if(it.id.equals(&aud_id)) {
                    if(it.state == STATE_DONE) { aud_done = true }
                    if(it.state == STATE_FAILED || it.state == STATE_CANCELLED) { aud_failed = true }
                }
            }

            if(vid_failed) {
                merge_error = string::make_no_len("video download failed")
                break
            }
            if(aud_failed) {
                merge_error = string::make_no_len("audio download failed")
                break
            }

            // Update status so UI shows waiting progress.
            if(vid_done && !aud_done) {
                g_async_dl.mu.lock()
                g_async_dl.status_line = string::make_no_len("Waiting for audio download...")
                g_async_dl.mu.unlock()
            } else if(!vid_done && aud_done) {
                g_async_dl.mu.lock()
                g_async_dl.status_line = string::make_no_len("Waiting for video download...")
                g_async_dl.mu.unlock()
            }
        }

        var both_int = 0
        if(vid_done && aud_done) { both_int = 1 }
        fprintf(stderr, "[CDM-MERGE] both done=%d, error=%s\n", both_int, merge_error.data())

        // Update status.
        g_async_dl.mu.lock()
        if(merge_error.size() > 0u) {
            g_async_dl.status_line = string::make_no_len("Merge failed: ")
            g_async_dl.status_line.append_string(&merge_error)
            g_async_dl.error = merge_error.copy()
            g_async_dl.merge_status = string::make_no_len("failed")
            g_async_dl.merge_error = merge_error.copy()
            g_async_dl.mu.unlock()
            return null
        }
        g_async_dl.status_line = string::make_no_len("Merging video + audio...")
        g_async_dl.merge_status = string::make_no_len("merging")
        g_async_dl.mu.unlock()

        // Perform the merge (with one retry).
        var video_path = string()
        video_path.append_string(&vid_dir)
        video_path.append('/')
        video_path.append_string(&vid_fname)

        var audio_path = string()
        audio_path.append_string(&vid_dir)
        audio_path.append('/')
        audio_path.append_string(&aud_fname)

        var output_path = string()
        output_path.append_string(&vid_dir)
        output_path.append('/')
        output_path.append_string(&vid_fname)

        var merge_err_s = string()
        var merged = ffmpeg_merge_files(
            string_view::make_view(&video_path),
            string_view::make_view(&audio_path),
            string_view::make_view(&output_path),
            &mut merge_err_s)

        // Retry once on failure.
        if(!merged) {
            fprintf(stderr, "[CDM-MERGE] first merge attempt failed, retrying...\n")
            std::concurrent.sleep_ms(1000u)
            merge_err_s = string()
            merged = ffmpeg_merge_files(
                string_view::make_view(&video_path),
                string_view::make_view(&audio_path),
                string_view::make_view(&output_path),
                &mut merge_err_s)
        }

        if(merged) {
            g_async_dl.mu.lock()
            g_async_dl.status_line = string::make_no_len("Merged successfully")
            g_async_dl.merge_status = string::make_no_len("merged")
            g_async_dl.mu.unlock()
            fprintf(stderr, "[CDM-MERGE] merge succeeded\n")

            // Delete the *separate audio* file if requested. The merged result is
            // written to output_path, which equals the video task's file, so the
            // "video" path must NOT be deleted here (it IS the final output).
            if(del_separate) {
                remove(audio_path.data())
                fprintf(stderr, "[CDM-MERGE] deleted separate audio file\n")
            }
        } else {
            g_async_dl.mu.lock()
            g_async_dl.status_line = string::make_no_len("ffmpeg merge failed")
            g_async_dl.error = string::make_no_len("ffmpeg merge failed - files kept separately")
            g_async_dl.merge_status = string::make_no_len("failed")
            // Surface the real ffmpeg error (or diagnostic) so the UI can show it.
            if(merge_err_s.size() > 0u) {
                g_async_dl.merge_error = merge_err_s.copy()
            } else {
                g_async_dl.merge_error = string::make_no_len("ffmpeg merge failed")
            }
            g_async_dl.mu.unlock()
            fprintf(stderr, "[CDM-MERGE] merge failed after retry: %s\n", g_async_dl.merge_error.data())
        }

        return null
    }

    // Start merge monitor after adding both video+audio to DM.
    func maybe_start_merge_monitor(dm : *mut DownloadManager) {
        g_async_dl.mu.lock()
        var needs = g_async_dl.needs_merge
        var auto = g_async_dl.auto_merge
        g_async_dl.mu.unlock()
        var needs_int = 0; if(needs) { needs_int = 1 }
        var auto_int = 0; if(auto) { auto_int = 1 }
        fprintf(stderr, "[CDM-MERGE] maybe_start: needs=%d auto=%d\n", needs_int, auto_int)
        if(needs && auto) {
            std::concurrent.spawn(merge_monitor_entry, null)
        }
    }

    // Poll async download status. Includes merge info so the UI can group items.
    public func poll_async_download() : string {
        g_async_dl.mu.lock()
        var running = g_async_dl.running
        var done = g_async_dl.done
        var error = g_async_dl.error.copy()
        var progress = g_async_dl.progress
        var speed = g_async_dl.speed.copy()
        var status = g_async_dl.status_line.copy()
        var title = g_async_dl.title.copy()
        var vid_id = g_async_dl.dm_task_id.copy()
        var aud_id = g_async_dl.audio_task_id.copy()
        var merge_st = g_async_dl.merge_status.copy()
        var merge_err = g_async_dl.merge_error.copy()
        var needs_merge = g_async_dl.needs_merge
        g_async_dl.mu.unlock()

        var out = string::make_no_len("{\"running\":")
        if(running) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"done\":"))
        if(done) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"error\":"))
        out.append_string(&json_string(string_view::make_view(&error)))
        out.append_string(&string::make_no_len(",\"progress\":"))
        var ps = string(); ps.append_double(progress, 1); out.append_string(&ps)
        out.append_string(&string::make_no_len(",\"speed\":"))
        out.append_string(&json_string(string_view::make_view(&speed)))
        out.append_string(&string::make_no_len(",\"status\":"))
        out.append_string(&json_string(string_view::make_view(&status)))
        out.append_string(&string::make_no_len(",\"title\":"))
        out.append_string(&json_string(string_view::make_view(&title)))
        out.append_string(&string::make_no_len(",\"video_task_id\":"))
        out.append_string(&json_string(string_view::make_view(&vid_id)))
        out.append_string(&string::make_no_len(",\"audio_task_id\":"))
        out.append_string(&json_string(string_view::make_view(&aud_id)))
        out.append_string(&string::make_no_len(",\"merge_status\":"))
        out.append_string(&json_string(string_view::make_view(&merge_st)))
        out.append_string(&string::make_no_len(",\"merge_error\":"))
        out.append_string(&json_string(string_view::make_view(&merge_err)))
        out.append_string(&string::make_no_len(",\"needs_merge\":"))
        if(needs_merge) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append('}')
        return out
    }

    public func cancel_async_download() {
        g_async_dl.mu.lock()
        g_async_dl.running = false; g_async_dl.done = true
        g_async_dl.error = string::make_no_len("cancelled")
        g_async_dl.mu.unlock()
    }

    // ---- Playlist download ----

    func playlist_thread_entry(arg : *void) : *void {
        std::concurrent.sleep_ms(10u)
        var dm = g_async_pl.dm
        var fmt = resolve_yt_format(string_view::make_view(&g_async_pl.format), g_async_pl.min_quality, g_async_pl.max_quality)

        // Extract playlist entries.
        var args = vector<string>()
        args.push_back(ytdlp_resolved_path())
        args.push_back(string::make_no_len("--flat-playlist"))
        args.push_back(string::make_no_len("--print"))
        args.push_back(string::make_no_len("%(url)s|||%(title)s|||%(duration)s"))
        args.push_back(string::make_no_len("--no-warnings"))
        args.push_back(g_async_pl.url.copy())
        var entries_raw = string()
        var pl_err = string()
        var pl_exit = 0
        var spawned = run_yt_command(args, false, &raw mut entries_raw, &raw mut pl_err, &raw mut pl_exit)
        if(!spawned) {
            g_async_pl.mu.lock()
            g_async_pl.error = string::make_no_len("failed to start yt-dlp")
            g_async_pl.done = true; g_async_pl.running = false
            g_async_pl.mu.unlock(); return null
        }

        var entries = vector<string>()
        var line_start : usize = 0; var k : usize = 0
        while(k < entries_raw.size()) {
            if(entries_raw.get(k) == '\n') {
                var trimmed = trim_view(string_view::make_view(&entries_raw).subview(line_start, k))
                if(trimmed.size() > 0u) { entries.push_back(string(trimmed.data(), trimmed.size())) }
                line_start = k + 1u
            }
            k = k + 1u
        }
        if(line_start < entries_raw.size()) {
            var trimmed = trim_view(string_view::make_view(&entries_raw).subview(line_start, entries_raw.size()))
            if(trimmed.size() > 0u) { entries.push_back(string(trimmed.data(), trimmed.size())) }
        }

        if(entries.size() == 0u) {
            g_async_pl.mu.lock()
            g_async_pl.error = string::make_no_len("no playlist entries found")
            g_async_pl.done = true; g_async_pl.running = false
            g_async_pl.mu.unlock(); return null
        }

        g_async_pl.mu.lock()
        g_async_pl.items_total = entries.size() as int
        g_async_pl.items_done = 0
        g_async_pl.mu.unlock()

        var total_entries = entries.size() as int
        for(var idx = 0u; idx < entries.size(); idx++) {
            g_async_pl.mu.lock()
            var cancelled = !g_async_pl.running
            g_async_pl.mu.unlock()
            if(cancelled) { break }

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
                if(sep2_idx != std::NPOS) { entry_title = rest.subview(0, sep2_idx) } else { entry_title = rest }
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
                g_async_pl.mu.lock(); g_async_pl.items_done = g_async_pl.items_done + 1; g_async_pl.mu.unlock()
                continue
            }

            var fname = suggest_yt_filename(entry_title, string_view::make_no_len("mp4"))
            if(dm != null) {
                var eu_d = urls.get_ptr(0).data()
                var eu_s = urls.get_ptr(0).size()
                add_task_ex(&mut *dm, string_view(eu_d, eu_s),
                            string_view::make_view(&g_async_pl.output_dir),
                            string_view::make_view(&fname), 0, 0)
            }

            g_async_pl.mu.lock()
            g_async_pl.items_done = g_async_pl.items_done + 1
            g_async_pl.progress = (g_async_pl.items_done as double) * 100.0 / (total_entries as double)
            g_async_pl.mu.unlock()
        }

        g_async_pl.mu.lock()
        g_async_pl.done = true; g_async_pl.running = false; g_async_pl.progress = 100.0
        g_async_pl.mu.unlock()
        return null
    }

    public func start_async_playlist_download(url : string_view, format : string_view,
                                              mode : string_view, audio_fmt : string_view,
                                              dir : string_view, min_quality : int,
                                              max_quality : int, dm : *mut DownloadManager) : string {
        g_async_pl.mu.lock()
        if(g_async_pl.running) { g_async_pl.mu.unlock(); return string::make_no_len("playlist download already in progress") }
        g_async_pl.running = true; g_async_pl.done = false; g_async_pl.error = string()
        g_async_pl.progress = 0.0; g_async_pl.speed = string(); g_async_pl.eta = string()
        g_async_pl.status_line = string(); g_async_pl.items_done = 0; g_async_pl.items_total = 0
        g_async_pl.current_title = string()
        g_async_pl.url = string(url.data(), url.size())
        g_async_pl.format = string(format.data(), format.size())
        g_async_pl.output_dir = string(dir.data(), dir.size())
        g_async_pl.min_quality = min_quality; g_async_pl.max_quality = max_quality
        g_async_pl.dm = dm
        g_async_pl.mu.unlock()
        std::concurrent.spawn(playlist_thread_entry, null)
        return string()
    }

    public func poll_async_playlist_download() : string {
        g_async_pl.mu.lock()
        var running = g_async_pl.running; var done = g_async_pl.done
        var error = g_async_pl.error.copy(); var progress = g_async_pl.progress
        var items_done = g_async_pl.items_done; var items_total = g_async_pl.items_total
        var current_title = g_async_pl.current_title.copy(); var status = g_async_pl.status_line.copy()
        g_async_pl.mu.unlock()
        var out = string::make_no_len("{\"running\":")
        if(running) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"done\":"))
        if(done) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"error\":"))
        out.append_string(&json_string(string_view::make_view(&error)))
        out.append_string(&string::make_no_len(",\"progress\":"))
        var ps = string(); ps.append_double(progress, 1); out.append_string(&ps)
        out.append_string(&string::make_no_len(",\"items_done\":"))
        var ds = string(); ds.append_integer(items_done as bigint); out.append_string(&ds)
        out.append_string(&string::make_no_len(",\"items_total\":"))
        var ts = string(); ts.append_integer(items_total as bigint); out.append_string(&ts)
        out.append_string(&string::make_no_len(",\"current_title\":"))
        out.append_string(&json_string(string_view::make_view(&current_title)))
        out.append_string(&string::make_no_len(",\"status\":"))
        out.append_string(&json_string(string_view::make_view(&status)))
        out.append('}'); return out
    }

    public func cancel_async_playlist_download() {
        g_async_pl.mu.lock()
        g_async_pl.running = false; g_async_pl.done = true
        g_async_pl.error = string::make_no_len("cancelled")
        g_async_pl.mu.unlock()
    }

} // end namespace cdm
