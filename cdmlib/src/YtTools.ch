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

    // Note: ToolInfo has strings, so returning it by value triggers
    // TCC's compound-expression double-free. Callers must use
    // check_tools_status_json() or call primitives directly instead.
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

    // Build a ProcessConfig for a single command + args. Uses push instead of
    // vector assignment to avoid triggering delete on the compound-literal
    // returned vectors from ProcessConfig.default() (TCC codegen issue).
    public func make_exec_cfg(args_ : vector<string>) : process::ProcessConfig {
        var cfg = process::ProcessConfig.default()
        var i = 0u
        while(i < args_.size()) {
            // Use get_ptr(i) instead of get(i) to avoid the TCC compound-expression
            // double-free: get() returns a bitwise copy sharing heap pointers with
            // the vector element, and the temp's destruction frees the shared data.
            cfg.args.push_back(args_.get_ptr(i).copy())
            i = i + 1u
        }
        cfg.capture_stdout = true
        cfg.capture_stderr = true
        return cfg
    }

    // Check if a binary exists at a given directory path.
    // Builds the full path without using vector<string>.get(i).copy()
    // to avoid the TCC compound-expression double-free bug where get()
    // returns a bitwise copy sharing heap pointers with the vector element,
    // and the temp cleanup frees the shared data, leaving the vector with
    // dangling pointers.
    func check_path(dir : string_view, name : string_view) : bool {
        var p = string()
        p.append_view(&dir)
        p.append_view(&name)
        return fs::exists(p.data())
    }

    // Check if a binary exists on common system paths.
    // This avoids process::execute() which can deadlock when fork() is called
    // from a multi-threaded process (e.g. WebKitGTK webview).
    // NOTE: Does NOT use vector<string>.get(i).copy() — that pattern triggers
    // a TCC compound-expression double-free.
    func find_binary(name : string_view) : bool {
        // Check /usr/bin/
        if(check_path(string_view::make_no_len("/usr/bin/"), name)) { return true }
        // Check /usr/local/bin/
        if(check_path(string_view::make_no_len("/usr/local/bin/"), name)) { return true }
        // Check /usr/bin/local/
        if(check_path(string_view::make_no_len("/usr/bin/local/"), name)) { return true }
        // Check ~/.local/bin/
        var home_opt = std::get_env(string_view::make_no_len("HOME"))
        if(home_opt is Option.Some) {
            var Some(home) = home_opt else unreachable
            var local_bin = home.copy()
            local_bin.append_view(string_view::make_no_len("/.local/bin/"))
            if(check_path(string_view::make_view(&local_bin), name)) { return true }
        } else {}
        // Check $CDM_TOOLS_DIR
        var tools = tools_dir()
        if(check_path(string_view::make_view(&tools), name)) { return true }
        return false
    }

    // Check if yt-dlp is available (bundled binary exists and is executable,
    // or system yt-dlp is on PATH).
    public func ytdlp_is_available() : bool {
        // Check bundled binary first.
        var bundled = ytdlp_path()
        if(fs::exists(bundled.data())) {
            return true
        }
        // Check common filesystem paths (avoids fork() in multi-threaded context).
        return find_binary(string_view::make_no_len("yt-dlp"))
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
        var cfg = make_exec_cfg(args)
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
    // WARNING: Returns by value — may trigger TCC compound-expression double-free.
    // Prefer check_tools_status_json() or calling primitives directly.
    public func ytdlp_tool_info() : ToolInfo {
        var info = ToolInfo(string::make_no_len("yt-dlp"))
        info.path = ytdlp_resolved_path()
        if(ytdlp_is_available()) {
            info.status = ToolStatus.Installed
            info.version = ytdlp_version()
        }
        return info
    }

    // ---- Async tool download with progress ----

    public var g_tool_dl_progress : double = 0.0
    public var g_tool_dl_status : int = 0  // 0=idle, 1=downloading(yt-dlp), 2=downloading(ffmpeg), 10=done, 11=error

    public func tool_download_in_progress() : bool {
        return g_tool_dl_status == 1 || g_tool_dl_status == 2
    }

    func parse_curl_pct(line : string_view, out_pct : *mut double) : bool {
        var i = 0u
        while(i < line.size()) {
            var c = line.get(i)
            if(c >= '0' && c <= '9') {
                var val = 0.0
                var div = 1.0
                var in_dec = false
                var j = i
                while(j < line.size()) {
                    var cc = line.get(j)
                    if(cc == '.') { in_dec = true }
                    else if(cc >= '0' && cc <= '9') {
                        var digit = (cc as double) - ('0' as double)
                        if(in_dec) { div = div * 10.0; val = val + digit / div }
                        else { val = val * 10.0 + digit }
                    } else { break }
                    j = j + 1u
                }
                if(j < line.size() && line.get(j) == '%') {
                    *out_pct = val
                    return true
                }
            }
            i = i + 1u
        }
        return false
    }

    func download_tool_bg(url : string_view, target : string_view) : string {
        ensure_tools_dir()
        var cmd = string()
        cmd.append_view(string_view::make_no_len("curl -L --fail -s -o \""))
        cmd.append_view(&target)
        cmd.append_view(string_view::make_no_len("\" \""))
        cmd.append_view(&url)
        cmd.append_view(string_view::make_no_len("\" 2>&1"))
        var f = popen(cmd.data(), "r")
        if(f == null) { return string::make_no_len("failed to start curl") }
        var line_buf = string()
        while(true) {
            unsafe var c_buf : [1u]char
            var n = fread(&raw mut c_buf[0], 1, 1u, f)
            if(n == 0u) { break }
            var c = c_buf[0]
            if(c == '\r' || c == '\n') {
                if(line_buf.size() > 0) {
                    var pct = 0.0
                    if(parse_curl_pct(string_view::make_view(&line_buf), &raw mut pct)) {
                        g_tool_dl_progress = pct / 100.0
                    }
                }
                line_buf = string()
            } else {
                line_buf.append(c)
            }
        }
        var rc = pclose(f)
        if(rc != 0) { return string::make_no_len("curl failed") }
        return string()
    }

    func tool_download_thread(arg : *void) : *void {
        var err = string()
        var is_yt = (g_tool_dl_status == 1)
        if(is_yt) {
            var url = string::make_no_len(YTDLP_LINUX_URL)
            if(def.macos) { url = string::make_no_len(YTDLP_MACOS_URL) }
            if(def.windows) { url = string::make_no_len(YTDLP_WIN_URL) }
            err = download_tool_bg(string_view::make_view(&url), string_view::make_view(&ytdlp_path()))
            if(err.empty() && !def.windows) {
                var ca = vector<string>()
                ca.push_back(string::make_no_len("chmod"))
                ca.push_back(string::make_no_len("+x"))
                ca.push_back(ytdlp_path().copy())
                process::execute(make_exec_cfg(ca))
            }
            if(err.empty()) { var ver = ytdlp_version(); if(ver.empty()) { err = string::make_no_len("binary not functional") } }
        } else {
            var url = string::make_no_len(FFMPEG_LINUX_URL)
            if(def.macos) { url = string::make_no_len(FFMPEG_MACOS_URL) }
            if(def.windows) { url = string::make_no_len(FFMPEG_WIN_URL) }
            err = download_tool_bg(string_view::make_view(&url), string_view::make_view(&ffmpeg_path()))
            if(err.empty() && !def.windows) {
                var ca = vector<string>()
                ca.push_back(string::make_no_len("chmod"))
                ca.push_back(string::make_no_len("+x"))
                ca.push_back(ffmpeg_path().copy())
                process::execute(make_exec_cfg(ca))
            }
            if(err.empty()) { var ver = ffmpeg_version(); if(ver.empty()) { err = string::make_no_len("binary not functional") } }
        }
        if(err.empty()) { g_tool_dl_status = 10; g_tool_dl_progress = 1.0 }
        else { g_tool_dl_status = 11 }
        return null
    }

    public func ytdlp_download_async() : string {
        if(tool_download_in_progress()) { return string::make_no_len("download already in progress") }
        g_tool_dl_status = 1; g_tool_dl_progress = 0.0
        var t = std::concurrent::spawn(tool_download_thread, null)
        return string()
    }

    public func ffmpeg_download_async() : string {
        if(tool_download_in_progress()) { return string::make_no_len("download already in progress") }
        g_tool_dl_status = 2; g_tool_dl_progress = 0.0
        var t = std::concurrent::spawn(tool_download_thread, null)
        return string()
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
        var curl_args = vector<string>()
        curl_args.push_back(string::make_no_len("curl"))
        curl_args.push_back(string::make_no_len("-L"))
        curl_args.push_back(string::make_no_len("-o"))
        curl_args.push_back(target.copy())
        curl_args.push_back(string::make_no_len("--fail"))
        curl_args.push_back(string::make_no_len("--silent"))
        curl_args.push_back(string::make_no_len("--show-error"))
        curl_args.push_back(url.copy())
        var cfg = make_exec_cfg(curl_args)
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
            var chmod_args = vector<string>()
            chmod_args.push_back(string::make_no_len("chmod"))
            chmod_args.push_back(string::make_no_len("+x"))
            chmod_args.push_back(target.copy())
            process::execute(make_exec_cfg(chmod_args))
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
        // Check common filesystem paths (avoids fork() in multi-threaded context).
        return find_binary(string_view::make_no_len("ffmpeg"))
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
        var cfg = make_exec_cfg(args)
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
    // WARNING: Returns by value — may trigger TCC compound-expression double-free.
    // Prefer check_tools_status_json() or calling primitives directly.
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

        var curl_args = vector<string>()
        curl_args.push_back(string::make_no_len("curl"))
        curl_args.push_back(string::make_no_len("-L"))
        curl_args.push_back(string::make_no_len("-o"))
        curl_args.push_back(target.copy())
        curl_args.push_back(string::make_no_len("--fail"))
        curl_args.push_back(string::make_no_len("--silent"))
        curl_args.push_back(string::make_no_len("--show-error"))
        curl_args.push_back(url.copy())
        var cfg = make_exec_cfg(curl_args)
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
            var chmod_args = vector<string>()
            chmod_args.push_back(string::make_no_len("chmod"))
            chmod_args.push_back(string::make_no_len("+x"))
            chmod_args.push_back(target.copy())
            process::execute(make_exec_cfg(chmod_args))
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

    // Build a ToolInfo JSON object string from individual fields.
    // Avoids returning ToolInfo by value (TCC double-free issue).
    func tool_info_json(name : string_view, available : bool, ver : string_view, path_ : string_view) : string {
        var out = string::make_no_len("{\"name\":")
        out.append_string(&json_string(name))
        out.append_string(&string::make_no_len(",\"status\":\""))
        if(available) {
            out.append_string(&string::make_no_len("installed"))
        } else {
            out.append_string(&string::make_no_len("not_installed"))
        }
        out.append_string(&string::make_no_len("\",\"version\":\""))
        out.append_string(&json_string(ver))
        out.append_string(&string::make_no_len("\",\"path\":\""))
        out.append_string(&json_string(path_))
        out.append_string(&string::make_no_len("\",\"error\":\"\",\"progress\":0}"))
        return out
    }

    // Check status of both tools.
    // Builds JSON directly to avoid double-free from struct return pattern
    // with destructible types (ToolInfo contains strings).
    // DO NOT call ytdlp_tool_info() or ffmpeg_tool_info() here — returning
    // ToolInfo by value triggers TCC compound-expression double-free.
    public func check_tools_status_json() : string {
        var yt_avail = ytdlp_is_available()
        var ff_avail = ffmpeg_is_available()
        var yt_ver = string()
        var ff_ver = string()
        var yt_p = ytdlp_resolved_path()
        var ff_p = ffmpeg_resolved_path()
        if(yt_avail) { yt_ver = ytdlp_version() }
        if(ff_avail) { ff_ver = ffmpeg_version() }

        var dl_active = tool_download_in_progress()
        var dl_done = (g_tool_dl_status == 10)
        var dl_err = (g_tool_dl_status == 11)
        var dl_pct = g_tool_dl_progress
        var dl_is_yt = (g_tool_dl_status == 1)
        var dl_is_ff = (g_tool_dl_status == 2)

        // Build yt_dlp entry
        var yt_json = string::make_no_len("{\"name\":\"yt-dlp\",\"status\":\"")
        if(dl_is_yt && (dl_active || dl_done || dl_err)) {
            if(dl_active) { yt_json.append_view(string_view::make_no_len("downloading")) }
            else if(dl_done) { yt_json.append_view(string_view::make_no_len("installed")) }
            else { yt_json.append_view(string_view::make_no_len("error")) }
        } else if(yt_avail) { yt_json.append_view(string_view::make_no_len("installed")) }
        else { yt_json.append_view(string_view::make_no_len("not_installed")) }
        yt_json.append_view(string_view::make_no_len("\",\"version\":\""))
        yt_json.append_string(&json_string(string_view::make_view(&yt_ver)))
        yt_json.append_view(string_view::make_no_len("\",\"path\":\""))
        yt_json.append_string(&json_string(string_view::make_view(&yt_p)))
        yt_json.append_view(string_view::make_no_len("\",\"error\":\"\",\"progress\":"))
        var pstr_yt = string()
        if(dl_is_yt) { pstr_yt.append_double(dl_pct * 100.0, 1) } else { pstr_yt.append_double(0.0, 1) }
        yt_json.append_string(&pstr_yt)
        yt_json.append_view(string_view::make_no_len(",\"speed\":\"\"}"))

        // Build ffmpeg entry
        var ff_json = string::make_no_len("{\"name\":\"ffmpeg\",\"status\":\"")
        if(dl_is_ff && (dl_active || dl_done || dl_err)) {
            if(dl_active) { ff_json.append_view(string_view::make_no_len("downloading")) }
            else if(dl_done) { ff_json.append_view(string_view::make_no_len("installed")) }
            else { ff_json.append_view(string_view::make_no_len("error")) }
        } else if(ff_avail) { ff_json.append_view(string_view::make_no_len("installed")) }
        else { ff_json.append_view(string_view::make_no_len("not_installed")) }
        ff_json.append_view(string_view::make_no_len("\",\"version\":\""))
        ff_json.append_string(&json_string(string_view::make_view(&ff_ver)))
        ff_json.append_view(string_view::make_no_len("\",\"path\":\""))
        ff_json.append_string(&json_string(string_view::make_view(&ff_p)))
        ff_json.append_view(string_view::make_no_len("\",\"error\":\"\",\"progress\":"))
        var pstr_ff = string()
        if(dl_is_ff) { pstr_ff.append_double(dl_pct * 100.0, 1) } else { pstr_ff.append_double(0.0, 1) }
        ff_json.append_string(&pstr_ff)
        ff_json.append_view(string_view::make_no_len(",\"speed\":\"\"}"))

        var out = string::make_no_len("{\"yt_dlp\":")
        out.append_string(&yt_json)
        out.append_view(string_view::make_no_len(",\"ffmpeg\":"))
        out.append_string(&ff_json)
        out.append_view(string_view::make_no_len(",\"both_ready\":"))
        if(yt_avail && ff_avail && !dl_active) {
            out.append_view(string_view::make_no_len("true"))
        } else {
            out.append_view(string_view::make_no_len("false"))
        }
        out.append('}')
        return out
    }

} // end namespace cdm
