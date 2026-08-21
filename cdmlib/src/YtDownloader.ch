// ChemicalDM — YouTube download management.
//
// Manages active YouTube downloads: spawns yt-dlp processes, parses
// progress output, handles ffmpeg merging of separate video+audio streams,
// and tracks download lifecycle.

public namespace cdm {

using std::string;
using std::string_view;
using std::vector;
using std::Result;
using std::Option;
using std::mutex;

    // ---- Download state ----

    public enum YtDownloadState {
        Queued = 0,
        FetchingInfo = 1,
        Downloading = 2,
        Merging = 3,
        Done = 4,
        Failed = 5,
        Cancelled = 6
    }

    // ---- Active download tracking ----

    public struct YtDownload {
        var id : string
        var url : string
        var title : string
        var state : YtDownloadState
        var progress : double          // 0.0 - 1.0
        var speed : string             // "1.2MiB/s"
        var eta : string               // "00:15"
        var status_line : string       // raw yt-dlp output line
        var error : string
        var output_path : string       // final file path
        var temp_dir : string          // temp dir for parts
        var selected_format : string   // yt-dlp -f argument
        var merge_output : string      // ffmpeg output
        var video_ext : string         // for merge: video file extension
        var audio_ext : string         // for merge: audio file extension
        var is_playlist : bool
        var playlist_title : string
        var item_index : int
        var item_total : int

        @constructor func constructor(id_ : string, url_ : string) {
            return YtDownload {
                id = id_,
                url = url_,
                title = string(),
                state = YtDownloadState.Queued,
                progress = 0.0,
                speed = string(),
                eta = string(),
                status_line = string(),
                error = string(),
                output_path = string(),
                temp_dir = string(),
                selected_format = string(),
                merge_output = string(),
                video_ext = string(),
                audio_ext = string(),
                is_playlist = false,
                playlist_title = string(),
                item_index = 0,
                item_total = 0
            }
        }

        public func copy(&self) : YtDownload {
            var c = YtDownload(self.id.copy(), self.url.copy())
            c.title = self.title.copy()
            c.state = self.state
            c.progress = self.progress
            c.speed = self.speed.copy()
            c.eta = self.eta.copy()
            c.status_line = self.status_line.copy()
            c.error = self.error.copy()
            c.output_path = self.output_path.copy()
            c.temp_dir = self.temp_dir.copy()
            c.selected_format = self.selected_format.copy()
            c.merge_output = self.merge_output.copy()
            c.video_ext = self.video_ext.copy()
            c.audio_ext = self.audio_ext.copy()
            c.is_playlist = self.is_playlist
            c.playlist_title = self.playlist_title.copy()
            c.item_index = self.item_index
            c.item_total = self.item_total
            return c
        }

        public func to_json(&self) : string {
            var out = string::make_no_len("{\"id\":")
            out.append_string(&json_string(string_view::make_view(&self.id)))
            out.append_string(&string::make_no_len(",\"url\":"))
            out.append_string(&json_string(string_view::make_view(&self.url)))
            out.append_string(&string::make_no_len(",\"title\":"))
            out.append_string(&json_string(string_view::make_view(&self.title)))
            out.append_string(&string::make_no_len(",\"state\":\""))
            var state_name = yt_state_name(self.state)
            out.append_string(&state_name)
            out.append_string(&string::make_no_len("\",\"progress\":"))
            var ps = string()
            ps.append_double(self.progress * 100.0, 1)
            out.append_string(&ps)
            out.append_string(&string::make_no_len(",\"speed\":"))
            out.append_string(&json_string(string_view::make_view(&self.speed)))
            out.append_string(&string::make_no_len(",\"eta\":"))
            out.append_string(&json_string(string_view::make_view(&self.eta)))
            out.append_string(&string::make_no_len(",\"error\":"))
            out.append_string(&json_string(string_view::make_view(&self.error)))
            out.append_string(&string::make_no_len(",\"output_path\":"))
            out.append_string(&json_string(string_view::make_view(&self.output_path)))
            out.append_string(&string::make_no_len(",\"is_playlist\":"))
            if(self.is_playlist) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
            out.append_string(&string::make_no_len(",\"playlist_title\":"))
            out.append_string(&json_string(string_view::make_view(&self.playlist_title)))
            out.append_string(&string::make_no_len(",\"item_index\":"))
            var is = string()
            is.append_integer(self.item_index as bigint)
            out.append_string(&is)
            out.append_string(&string::make_no_len(",\"item_total\":"))
            var ts = string()
            ts.append_integer(self.item_total as bigint)
            out.append_string(&ts)
            out.append('}')
            return out
        }
    }

    public func yt_state_name(s : YtDownloadState) : string {
        if(s == YtDownloadState.Queued) { return string::make_no_len("queued") }
        if(s == YtDownloadState.FetchingInfo) { return string::make_no_len("fetching_info") }
        if(s == YtDownloadState.Downloading) { return string::make_no_len("downloading") }
        if(s == YtDownloadState.Merging) { return string::make_no_len("merging") }
        if(s == YtDownloadState.Done) { return string::make_no_len("done") }
        if(s == YtDownloadState.Failed) { return string::make_no_len("failed") }
        if(s == YtDownloadState.Cancelled) { return string::make_no_len("cancelled") }
        return string::make_no_len("unknown")
    }

    // ---- Download manager ----

    public struct YtDownloadManager {
        var dl_mutex : mutex
        var downloads : vector<YtDownload>
        var output_dir : string       // where to save downloaded files

        @constructor func constructor() {
            var dir = expand_home(string_view::make_no_len(DEFAULT_DOWNLOAD_DIR))
            return YtDownloadManager {
                dl_mutex = mutex(),
                downloads = vector<YtDownload>(),
                output_dir = dir
            }
        }

        public func set_output_dir(&mut self, dir : string_view) {
            self.output_dir = string(dir.data(), dir.size())
        }

        // Add a download and return its id.
        public func add_download(&mut self, url : string_view, format : string_view) : string {
            var id = uuid::v4().to_string()
            var dl = YtDownload(id.copy(), string(url.data(), url.size()))
            dl.selected_format = string(format.data(), format.size())
            dl.state = YtDownloadState.Queued
            self.dl_mutex.lock()
            self.downloads.push_back(dl)
            self.dl_mutex.unlock()
            return id
        }

        // Get a snapshot of all downloads for the UI.
        public func snapshot(&self) : vector<YtDownload> {
            var out = vector<YtDownload>()
            for(var i = 0u; i < self.downloads.size(); i++) {
                var d = self.downloads.get_ptr(i)
                out.push_back(d.copy())
            }
            return out
        }

        // Get a single download by id.
        public func find_download(&self, id : &string) : Option<YtDownload> {
            for(var i = 0u; i < self.downloads.size(); i++) {
                var d = self.downloads.get_ptr(i)
                if(d.id.equals(id)) {
                    return Option.Some<YtDownload>(d.copy())
                }
            }
            return Option.None<YtDownload>()
        }

        // Find index of a download by id.
        func find_index(&self, id : &string) : usize {
            for(var i = 0u; i < self.downloads.size(); i++) {
                var d = self.downloads.get_ptr(i)
                if(d.id.equals(id)) { return i }
            }
            return self.downloads.size()
        }

        // Update a download's state (called from worker thread or tests).
        public func update_state(&mut self, id : &string, state : YtDownloadState) {
            var idx = self.find_index(id)
            if(idx < self.downloads.size()) {
                self.downloads.get_ptr(idx).state = state
            }
        }

        // Update a download's progress from yt-dlp output.
        func update_progress(&mut self, id : &string, progress : double, speed : string_view, eta : string_view, status : string_view) {
            var idx = self.find_index(id)
            if(idx < self.downloads.size()) {
                var d = self.downloads.get_ptr(idx)
                d.progress = progress
                d.speed = string(speed.data(), speed.size())
                d.eta = string(eta.data(), eta.size())
                d.status_line = string(status.data(), status.size())
            }
        }

        // Set download error.
        func set_error(&mut self, id : &string, err : string_view) {
            var idx = self.find_index(id)
            if(idx < self.downloads.size()) {
                var d = self.downloads.get_ptr(idx)
                d.error = string(err.data(), err.size())
                d.state = YtDownloadState.Failed
            }
        }

        // Set download title (after fetching info).
        func set_title(&mut self, id : &string, title : string_view) {
            var idx = self.find_index(id)
            if(idx < self.downloads.size()) {
                self.downloads.get_ptr(idx).title = string(title.data(), title.size())
            }
        }

        // Set output path.
        func set_output_path(&mut self, id : &string, path : string_view) {
            var idx = self.find_index(id)
            if(idx < self.downloads.size()) {
                self.downloads.get_ptr(idx).output_path = string(path.data(), path.size())
            }
        }

        // Cancel a download by killing its process.
        public func cancel_download(&mut self, id : &string) {
            var idx = self.find_index(id)
            if(idx < self.downloads.size()) {
                var d = self.downloads.get_ptr(idx)
                if(d.state == YtDownloadState.Downloading || d.state == YtDownloadState.FetchingInfo || d.state == YtDownloadState.Queued) {
                    d.state = YtDownloadState.Cancelled
                }
            }
        }

        // Remove a download from the list.
        public func remove_download(&mut self, id : &string) {
            var idx = self.find_index(id)
            if(idx < self.downloads.size()) {
                self.downloads.erase(idx)
            }
        }

        // Clear all completed/failed downloads.
        public func clear_finished(&mut self) : int {
            var removed = 0
            var i : usize = 0
            while(i < self.downloads.size()) {
                var d = self.downloads.get_ptr(i)
                if(d.state == YtDownloadState.Done || d.state == YtDownloadState.Failed || d.state == YtDownloadState.Cancelled) {
                    self.downloads.erase(i)
                    removed = removed + 1
                } else {
                    i = i + 1
                }
            }
            return removed
        }
    }

    // ---- Progress parsing ----

    // Parse yt-dlp's progress output line. Format:
    // [download]  45.2% of  156.72MiB at  2.34MiB/s ETA 00:27
    // [download] 100% of   12.34MiB in 00:05
    // [Merger] Merging formats into "output.mp4"
    // [youtube] Extracting URL: ...
    // [info] ...
    public func parse_yt_progress(line : string_view) : YtProgressUpdate {
        var update = YtProgressUpdate()

        // Check for merge step.
        if(line.find(string_view::make_no_len("[Merger]")) != std::NPOS ||
           line.find(string_view::make_no_len("[ffmpeg]")) != std::NPOS) {
            update.is_merge = true
            update.status = string(line.data(), line.size())
            // Extract output filename from: Merging formats into "output.mp4"
            // Manual search for 'into "' then find closing quote.
            var i : usize = 0
            while(i + 5u < line.size()) {
                if(line.get(i) == 'i' && line.get(i+1u) == 'n' && line.get(i+2u) == 't' && line.get(i+3u) == 'o' && line.get(i+4u) == ' ' && line.get(i+5u) == '"') {
                    var qstart = i + 6u
                    var qend = qstart
                    while(qend < line.size() && line.get(qend) != '"') {
                        qend = qend + 1u
                    }
                    if(qend > qstart) {
                        update.output_file = line.subview(qstart, qend)
                    }
                    break
                }
                i = i + 1u
            }
            return update
        }

        // Check for download progress line.
        var dl_marker = string_view::make_no_len("[download]")
        var dl_idx = line.find(&dl_marker)
        if(dl_idx == std::NPOS) {
            // Not a progress line — pass through as status.
            update.status = string(line.data(), line.size())
            return update
        }

        update.has_progress = true

        // Parse percentage: "XX.X%"
        var pct_marker = string_view::make_no_len("%")
        var pct_idx = line.find(&pct_marker)
        if(pct_idx != std::NPOS) {
            // Find the number before %
            var pct_end = pct_idx
            var pct_start = pct_end
            while(pct_start > 0 && line.get(pct_start - 1u) != ' ') {
                pct_start = pct_start - 1u
            }
            var pct_str = line.subview(pct_start, pct_end)
            update.progress = parse_double_view(pct_str)
        }

        // Parse speed: "at X.XXMiB/s" or "at X.XXKiB/s"
        // Manual search for " at " since find(&ref) may not work with inline temps.
        var si : usize = 0
        while(si + 3u < line.size()) {
            if(line.get(si) == ' ' && line.get(si + 1u) == 'a' && line.get(si + 2u) == 't' && line.get(si + 3u) == ' ') {
                var speed_start = si + 4u
                var speed_end = speed_start
                while(speed_end < line.size() && line.get(speed_end) != ' ') {
                    speed_end = speed_end + 1u
                }
                update.speed = line.subview(speed_start, speed_end)
                break
            }
            si = si + 1u
        }

        // Parse ETA: "ETA HH:MM" or "ETA MM:SS"
        var ei : usize = 0
        while(ei + 3u < line.size()) {
            if(line.get(ei) == 'E' && line.get(ei + 1u) == 'T' && line.get(ei + 2u) == 'A' && line.get(ei + 3u) == ' ') {
                var eta_start = ei + 4u
                var eta_end = eta_start
                while(eta_end < line.size() && line.get(eta_end) != ' ' && line.get(eta_end) != '\n' && line.get(eta_end) != '\r') {
                    eta_end = eta_end + 1u
                }
                update.eta = line.subview(eta_start, eta_end)
                break
            }
            ei = ei + 1u
        }

        update.status = string(line.data(), line.size())
        return update
    }

    public struct YtProgressUpdate {
        var has_progress : bool
        var progress : double        // 0.0 - 100.0
        var speed : string_view      // points into original line
        var eta : string_view        // points into original line
        var status : string          // full line (owned copy)
        var is_merge : bool
        var output_file : string_view

        @constructor func constructor() {
            return YtProgressUpdate {
                has_progress = false,
                progress = 0.0,
                speed = string_view::make_no_len(""),
                eta = string_view::make_no_len(""),
                status = string(),
                is_merge = false,
                output_file = string_view::make_no_len("")
            }
        }
    }

    // Parse a double from a string_view (e.g. "45.2" from "45.2%").
    func parse_double_view(s : string_view) : double {
        var val = 0.0
        var div = 1.0
        var in_decimal = false
        for(var i = 0u; i < s.size(); i++) {
            var c = s.get(i)
            if(c == '.') {
                in_decimal = true
            } else if(c >= '0' && c <= '9') {
                var digit = (c as double) - ('0' as double)
                if(in_decimal) {
                    div = div * 10.0
                    val = val + digit / div
                } else {
                    val = val * 10.0 + digit
                }
            }
        }
        return val
    }

    // ---- yt-dlp download execution ----

    // Build the yt-dlp command line for a download.
    func build_ytdlp_args(dl : &YtDownload, output_dir : string_view, merge_with_ffmpeg : bool) : vector<string> {
        var args = vector<string>()
        args.push_back(ytdlp_resolved_path())
        args.push_back(string::make_no_len("--no-warnings"))
        args.push_back(string::make_no_len("--newline"))          // progress on separate lines
        args.push_back(string::make_no_len("--no-playlist"))     // single video by default
        args.push_back(string::make_no_len("--progress"))        // force progress output

        // Output template.
        var out_template = string(output_dir.data(), output_dir.size())
        out_template.append_view(string_view::make_no_len("/%(title)s.%(ext)s"))
        args.push_back(string::make_no_len("-o"))
        args.push_back(out_template.copy())

        // Format selection.
        if(dl.selected_format.size() > 0) {
            args.push_back(string::make_no_len("-f"))
            args.push_back(dl.selected_format.copy())
        } else {
            // Default: best quality with both video+audio, fallback to separate streams.
            args.push_back(string::make_no_len("-f"))
            args.push_back(string::make_no_len("bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"))
        }

        // Merge output format.
        if(merge_with_ffmpeg) {
            args.push_back(string::make_no_len("--merge-output-format"))
            args.push_back(string::make_no_len("mp4"))
        }

        args.push_back(dl.url.copy())
        return args
    }

    // Build yt-dlp args for a playlist download.
    public func build_ytdlp_playlist_args(url : string_view, output_dir : string_view, format : string_view, min_quality : int, max_quality : int) : vector<string> {
        var args = vector<string>()
        args.push_back(ytdlp_resolved_path())
        args.push_back(string::make_no_len("--no-warnings"))
        args.push_back(string::make_no_len("--newline"))
        args.push_back(string::make_no_len("--progress"))
        args.push_back(string::make_no_len("--yes-playlist"))

        // Output template with playlist numbering.
        var out_template = string(output_dir.data(), output_dir.size())
        out_template.append_view(string_view::make_no_len("/%(playlist_title)s/%(playlist_index)03d - %(title)s.%(ext)s"))
        args.push_back(string::make_no_len("-o"))
        args.push_back(out_template.copy())

        // Format selection.
        if(format.size() > 0) {
            args.push_back(string::make_no_len("-f"))
            args.push_back(string(format.data(), format.size()))
        } else {
            args.push_back(string::make_no_len("-f"))
            args.push_back(string::make_no_len("bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"))
        }

        // Quality filters.
        if(min_quality > 0 || max_quality > 0) {
            var ff = string::make_no_len("-f")
            var fmt = string()
            if(min_quality > 0 && max_quality > 0) {
                fmt = string::make_no_len("bestvideo[height>=")
                var mins = string()
                mins.append_integer(min_quality as bigint)
                fmt.append_string(&mins)
                fmt.append_view(string_view::make_no_len("][height<="))
                var maxs = string()
                maxs.append_integer(max_quality as bigint)
                fmt.append_string(&maxs)
                fmt.append_view(string_view::make_no_len("]+bestaudio/best"))
            } else if(min_quality > 0) {
                fmt = string::make_no_len("bestvideo[height>=")
                var mins = string()
                mins.append_integer(min_quality as bigint)
                fmt.append_string(&mins)
                fmt.append_view(string_view::make_no_len("]+bestaudio/best"))
            } else {
                fmt = string::make_no_len("bestvideo[height<=")
                var maxs = string()
                maxs.append_integer(max_quality as bigint)
                fmt.append_string(&maxs)
                fmt.append_view(string_view::make_no_len("]+bestaudio/best"))
            }
            // Override previous -f.
            args.pop_back()  // remove previous format
            args.pop_back()  // remove previous -f
            args.push_back(ff)
            args.push_back(fmt.copy())
        }

        // Merge output format.
        args.push_back(string::make_no_len("--merge-output-format"))
        args.push_back(string::make_no_len("mp4"))

        args.push_back(string(url.data(), url.size()))
        return args
    }

    // ---- ffmpeg merge ----

    // Merge separate video+audio files using ffmpeg. Returns the output path
    // on success, empty string on failure.
    public func ffmpeg_merge(video_path : string_view, audio_path : string_view, output_path : string_view) : string {
        var ffmpeg = ffmpeg_resolved_path()
        var cfg = process::ProcessConfig.default()
        cfg.args.push_back(ffmpeg.copy())
        cfg.args.push_back(string::make_no_len("-i"))
        cfg.args.push_back(string(video_path.data(), video_path.size()))
        cfg.args.push_back(string::make_no_len("-i"))
        cfg.args.push_back(string(audio_path.data(), audio_path.size()))
        cfg.args.push_back(string::make_no_len("-c"))
        cfg.args.push_back(string::make_no_len("copy"))
        cfg.args.push_back(string::make_no_len("-y"))
        cfg.args.push_back(string(output_path.data(), output_path.size()))
        cfg.capture_stdout = true
        cfg.capture_stderr = true
        var res = process::execute(cfg)
        if(res is Result.Err) {
            return string()
        }
        var Ok(pr) = res else unreachable
        if(!pr.success) {
            return string()
        }
        // Verify the output file exists.
        if(!fs::exists(output_path.data())) {
            return string()
        }
        return string(output_path.data(), output_path.size())
    }

    // ---- Helpers ----

    // Detect if a URL is a YouTube playlist.
    public func is_youtube_playlist_url(url : string_view) : bool {
        // YouTube playlist URLs contain "list=" parameter.
        var list_marker = string_view::make_no_len("list=")
        var list_idx = url.find(&list_marker)
        if(list_idx != std::NPOS) {
            return true
        }
        // Also check for /playlist? path.
        var pl_marker = string_view::make_no_len("/playlist")
        var pl_idx = url.find(&pl_marker)
        if(pl_idx != std::NPOS) {
            return true
        }
        return false
    }

    // Detect if a URL is a YouTube video.
    public func is_youtube_url(url : string_view) : bool {
        var lower = string(url.data(), url.size())
        for(var i = 0u; i < lower.size(); i++) {
            var c = lower.get(i)
            if(c >= 'A' && c <= 'Z') {
                lower.set(i, (c + 32) as char)
            }
        }
        var lv = string_view::make_view(&lower)
        var yt_marker = string_view::make_no_len("youtube.com")
        var ytb_marker = string_view::make_no_len("youtu.be")
        if(lv.find(&yt_marker) != std::NPOS) { return true }
        if(lv.find(&ytb_marker) != std::NPOS) { return true }
        return false
    }

} // end namespace cdm
