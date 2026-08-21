// ChemicalDM — yt-dlp and ffmpeg tool management.
//
// Handles automatic downloading of yt-dlp and ffmpeg binaries from their
// official releases, version checking, and path resolution. Both tools
// are optional: yt-dlp enables YouTube/video downloads, ffmpeg enables
// merging separate video+audio streams.

public namespace cdm {

using std::string;
using std::string_view;
using std::Result;
using std::Option;
using std::vector;

    // ---- Tool status ----

    public enum ToolStatus {
        NotInstalled = 0,
        Installed = 1,
        Downloading = 2,
        Error = 3
    }

    public struct ToolInfo {
        var name : string
        var status : ToolStatus
        var version : string
        var path : string
        var error : string
        var download_progress : double    // 0.0 - 1.0
        var download_bytes : i64
        var download_total : i64

        @constructor func constructor(n : string) {
            return ToolInfo {
                name = n,
                status = ToolStatus.NotInstalled,
                version = string(),
                path = string(),
                error = string(),
                download_progress = 0.0,
                download_bytes = 0,
                download_total = 0
            }
        }

        public func is_available(&self) : bool {
            return self.status == ToolStatus.Installed
        }

        public func to_json(&self) : string {
            var out = string::make_no_len("{\"name\":")
            out.append_string(&json_string(string_view::make_view(&self.name)))
            out.append_string(&string::make_no_len(",\"status\":\""))
            var status_name = string()
            if(self.status == ToolStatus.Installed) { status_name = string::make_no_len("installed") }
            else if(self.status == ToolStatus.Downloading) { status_name = string::make_no_len("downloading") }
            else if(self.status == ToolStatus.Error) { status_name = string::make_no_len("error") }
            else { status_name = string::make_no_len("not_installed") }
            out.append_string(&status_name)
            out.append_string(&string::make_no_len("\",\"version\":\""))
            out.append_string(&json_string(string_view::make_view(&self.version)))
            out.append_string(&string::make_no_len("\",\"path\":\""))
            out.append_string(&json_string(string_view::make_view(&self.path)))
            out.append_string(&string::make_no_len("\",\"error\":\""))
            out.append_string(&json_string(string_view::make_view(&self.error)))
            out.append_string(&string::make_no_len("\",\"progress\":"))
            var pstr = string()
            pstr.append_double(self.download_progress * 100.0, 1)
            out.append_string(&pstr)
            out.append('}')
            return out
        }
    }

    // ---- Tool paths and directories ----

    // Base directory for tool binaries. Uses $CDM_TOOLS_DIR if set,
    // otherwise falls back to $HOME/.chemicaldm/tools/.
    func tools_dir() : string {
        var env_opt = std::get_env(string_view::make_no_len("CDM_TOOLS_DIR"))
        if(env_opt is Option.Some) {
            var Some(dir) = env_opt else unreachable
            return dir.copy()
        }
        var home = string()
        var home_opt = std::get_env(string_view::make_no_len("HOME"))
        if(home_opt is Option.Some) {
            var Some(h) = home_opt else unreachable
            home = h.copy()
        } else {
            home = string::make_no_len(".")
        }
        home.append_view(string_view::make_no_len("/.chemicaldm/tools"))
        return home
    }

    // Ensure the tools directory exists.
    func ensure_tools_dir() {
        var dir = tools_dir()
        fs::create_dir_all(dir.data())
    }

    // ---- yt-dlp ----

    public const YTDLP_LINUX_URL : *char = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
    public const YTDLP_MACOS_URL : *char = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
    public const YTDLP_WIN_URL : *char = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"

    func ytdlp_binary_name() : string {
        if(def.windows) {
            return string::make_no_len("yt-dlp.exe")
        }
        return string::make_no_len("yt-dlp")
    }

    // Get the full path to the bundled yt-dlp binary (inside tools dir).
    public func ytdlp_path() : string {
        var dir = tools_dir()
        var name = ytdlp_binary_name()
        var path = dir.copy()
        path.append('/')
        path.append_string(&name)
        return path
    }

    // Check if yt-dlp is available (bundled binary exists and is executable,
    // or system yt-dlp is on PATH).
    public func ytdlp_is_available() : bool {
        // Check bundled binary first.
        var bundled = ytdlp_path()
        if(fs::exists(bundled.data())) {
            return true
        }
        // Fall back to system PATH.
        var cfg = process::ProcessConfig.default()
        cfg.args.push_back(string::make_no_len("yt-dlp"))
        cfg.args.push_back(string::make_no_len("--version"))
        cfg.capture_stdout = true
        cfg.capture_stderr = true
        var res = process::execute(cfg)
        if(res is Result.Err) {
            return false
        }
        var Ok(pr) = res else unreachable
        return pr.success
    }

    // Get the yt-dlp version string (empty if not available).
    public func ytdlp_version() : string {
        var path = ytdlp_path()
        var args = vector<string>()
        if(fs::exists(path.data())) {
            args.push_back(path.copy())
        } else {
            args.push_back(string::make_no_len("yt-dlp"))
        }
        args.push_back(string::make_no_len("--version"))
        var cfg = process::ProcessConfig.default()
        cfg.args = args
        cfg.capture_stdout = true
        cfg.capture_stderr = true
        var res = process::execute(cfg)
        if(res is Result.Err) {
            return string()
        }
        var Ok(pr) = res else unreachable
        if(!pr.success) { return string() }
        // stdout contains the version on the first line.
        var out = string()
        for(var i = 0u; i < pr.output.stdout_data.size(); i++) {
            var c = pr.output.stdout_data.get(i)
            if(c == '\n' as u8 || c == '\r' as u8) { break }
            out.append(c as char)
        }
        return out
    }

    // Get the resolved path to use for yt-dlp execution.
    public func ytdlp_resolved_path() : string {
        var bundled = ytdlp_path()
        if(fs::exists(bundled.data())) {
            return bundled
        }
        return string::make_no_len("yt-dlp")
    }

    // Get the full ToolInfo for yt-dlp.
    public func ytdlp_tool_info() : ToolInfo {
        var info = ToolInfo(string::make_no_len("yt-dlp"))
        info.path = ytdlp_resolved_path()
        if(ytdlp_is_available()) {
            info.status = ToolStatus.Installed
            info.version = ytdlp_version()
        }
        return info
    }

    // Download yt-dlp binary. This blocks until complete. Returns an error
    // message on failure, empty string on success.
    public func ytdlp_download() : string {
        ensure_tools_dir()
        var url = string::make_no_len(YTDLP_LINUX_URL)
        if(def.macos) {
            url = string::make_no_len(YTDLP_MACOS_URL)
        }
        if(def.windows) {
            url = string::make_no_len(YTDLP_WIN_URL)
        }
        var target = ytdlp_path()

        // Use curl to download the binary.
        var cfg = process::ProcessConfig.default()
        cfg.args.push_back(string::make_no_len("curl"))
        cfg.args.push_back(string::make_no_len("-L"))
        cfg.args.push_back(string::make_no_len("-o"))
        cfg.args.push_back(target.copy())
        cfg.args.push_back(string::make_no_len("--fail"))
        cfg.args.push_back(string::make_no_len("--silent"))
        cfg.args.push_back(string::make_no_len("--show-error"))
        cfg.args.push_back(url.copy())
        cfg.capture_stdout = true
        cfg.capture_stderr = true
        var res = process::execute(cfg)
        if(res is Result.Err) {
            var Err(e) = res else unreachable
            return e.message()
        }
        var Ok(pr) = res else unreachable
        if(!pr.success) {
            var err_out = string()
            for(var i = 0u; i < pr.output.stderr_data.size(); i++) {
                err_out.append(pr.output.stderr_data.get(i) as char)
            }
            return err_out
        }

        // Make executable on Unix.
        if(!def.windows) {
            var chmod_cfg = process::ProcessConfig.default()
            chmod_cfg.args.push_back(string::make_no_len("chmod"))
            chmod_cfg.args.push_back(string::make_no_len("+x"))
            chmod_cfg.args.push_back(target.copy())
            process::execute(chmod_cfg)
        }

        // Verify the downloaded binary works.
        var ver = ytdlp_version()
        if(ver.empty()) {
            return string::make_no_len("downloaded binary is not functional")
        }
        return string()
    }

    // ---- ffmpeg ----

    public const FFMPEG_LINUX_URL : *char = "https://github.com/eugeneware/ffmpeg-static/releases/download/b6.0/ffmpeg-linux-x64"
    public const FFMPEG_MACOS_URL : *char = "https://github.com/eugeneware/ffmpeg-static/releases/download/b6.0/ffmpeg-darwin-x64"
    public const FFMPEG_WIN_URL : *char = "https://github.com/eugeneware/ffmpeg-static/releases/download/b6.0/ffmpeg-win32-x64"

    func ffmpeg_binary_name() : string {
        if(def.windows) {
            return string::make_no_len("ffmpeg.exe")
        }
        return string::make_no_len("ffmpeg")
    }

    // Get the full path to the bundled ffmpeg binary.
    public func ffmpeg_path() : string {
        var dir = tools_dir()
        var name = ffmpeg_binary_name()
        var path = dir.copy()
        path.append('/')
        path.append_string(&name)
        return path
    }

    // Check if ffmpeg is available (bundled or system).
    public func ffmpeg_is_available() : bool {
        var bundled = ffmpeg_path()
        if(fs::exists(bundled.data())) {
            return true
        }
        // Fall back to system PATH.
        var cfg = process::ProcessConfig.default()
        cfg.args.push_back(string::make_no_len("ffmpeg"))
        cfg.args.push_back(string::make_no_len("-version"))
        cfg.capture_stdout = true
        cfg.capture_stderr = true
        var res = process::execute(cfg)
        if(res is Result.Err) {
            return false
        }
        var Ok(pr) = res else unreachable
        return pr.success
    }

    // Get the ffmpeg version string.
    public func ffmpeg_version() : string {
        var path = ffmpeg_path()
        var args = vector<string>()
        if(fs::exists(path.data())) {
            args.push_back(path.copy())
        } else {
            args.push_back(string::make_no_len("ffmpeg"))
        }
        args.push_back(string::make_no_len("-version"))
        var cfg = process::ProcessConfig.default()
        cfg.args = args
        cfg.capture_stdout = true
        cfg.capture_stderr = true
        var res = process::execute(cfg)
        if(res is Result.Err) {
            return string()
        }
        var Ok(pr) = res else unreachable
        if(!pr.success) { return string() }
        // First line: "ffmpeg version 6.0 Copyright ..."
        var out = string()
        var started_version = false
        for(var i = 0u; i < pr.output.stdout_data.size(); i++) {
            var c = pr.output.stdout_data.get(i) as char
            if(c == '\n' || c == '\r') { break }
            // Extract "version X.Y" prefix.
            if(!started_version) {
                // Skip "ffmpeg version "
                var sub = string()
                var j = i
                while(j < pr.output.stdout_data.size() && j < i + 20u) {
                    sub.append(pr.output.stdout_data.get(j) as char)
                    j = j + 1u
                }
                var sv = string_view::make_view(&sub)
                var idx = sv.find(string_view::make_no_len("version "))
                if(idx != std::NPOS) {
                    started_version = true
                    // Skip past "version "
                    i = i + idx + 7u
                    continue
                }
                // If no "version" found on this line, just take the whole line.
                out.append(c)
            } else {
                if(c == ' ') { break }
                out.append(c)
            }
        }
        return out
    }

    // Get the resolved path for ffmpeg execution.
    public func ffmpeg_resolved_path() : string {
        var bundled = ffmpeg_path()
        if(fs::exists(bundled.data())) {
            return bundled
        }
        return string::make_no_len("ffmpeg")
    }

    // Get the full ToolInfo for ffmpeg.
    public func ffmpeg_tool_info() : ToolInfo {
        var info = ToolInfo(string::make_no_len("ffmpeg"))
        info.path = ffmpeg_resolved_path()
        if(ffmpeg_is_available()) {
            info.status = ToolStatus.Installed
            info.version = ffmpeg_version()
        }
        return info
    }

    // Download ffmpeg binary. Returns error message on success.
    public func ffmpeg_download() : string {
        ensure_tools_dir()
        var url = string::make_no_len(FFMPEG_LINUX_URL)
        if(def.macos) {
            url = string::make_no_len(FFMPEG_MACOS_URL)
        }
        if(def.windows) {
            url = string::make_no_len(FFMPEG_WIN_URL)
        }
        var target = ffmpeg_path()

        var cfg = process::ProcessConfig.default()
        cfg.args.push_back(string::make_no_len("curl"))
        cfg.args.push_back(string::make_no_len("-L"))
        cfg.args.push_back(string::make_no_len("-o"))
        cfg.args.push_back(target.copy())
        cfg.args.push_back(string::make_no_len("--fail"))
        cfg.args.push_back(string::make_no_len("--silent"))
        cfg.args.push_back(string::make_no_len("--show-error"))
        cfg.args.push_back(url.copy())
        cfg.capture_stdout = true
        cfg.capture_stderr = true
        var res = process::execute(cfg)
        if(res is Result.Err) {
            var Err(e) = res else unreachable
            return e.message()
        }
        var Ok(pr) = res else unreachable
        if(!pr.success) {
            var err_out = string()
            for(var i = 0u; i < pr.output.stderr_data.size(); i++) {
                err_out.append(pr.output.stderr_data.get(i) as char)
            }
            return err_out
        }

        // Make executable.
        if(!def.windows) {
            var chmod_cfg = process::ProcessConfig.default()
            chmod_cfg.args.push_back(string::make_no_len("chmod"))
            chmod_cfg.args.push_back(string::make_no_len("+x"))
            chmod_cfg.args.push_back(target.copy())
            process::execute(chmod_cfg)
        }

        var ver = ffmpeg_version()
        if(ver.empty()) {
            return string::make_no_len("downloaded binary is not functional")
        }
        return string()
    }

    // ---- Combined status ----

    public struct ToolsStatus {
        var yt_info : ToolInfo
        var ff_info : ToolInfo

        @constructor func constructor() {
            return ToolsStatus {
                yt_info = ToolInfo(string::make_no_len("yt-dlp")),
                ff_info = ToolInfo(string::make_no_len("ffmpeg"))
            }
        }

        public func both_available(&self) : bool {
            return self.yt_info.is_available() && self.ff_info.is_available()
        }

        public func yt_dlp_available(&self) : bool {
            return self.yt_info.is_available()
        }

        public func to_json(&self) : string {
            var out = string::make_no_len("{\"yt_dlp\":")
            out.append_string(&self.yt_info.to_json())
            out.append_string(&string::make_no_len(",\"ffmpeg\":"))
            out.append_string(&self.ff_info.to_json())
            out.append_string(&string::make_no_len(",\"both_ready\":"))
            if(self.both_available()) {
                out.append_string(&string::make_no_len("true"))
            } else {
                out.append_string(&string::make_no_len("false"))
            }
            out.append('}')
            return out
        }
    }

    // Check status of both tools.
    public func check_tools_status() : ToolsStatus {
        var status = ToolsStatus()
        status.yt_info = ytdlp_tool_info()
        status.ff_info = ffmpeg_tool_info()
        return status
    }

} // end namespace cdm
