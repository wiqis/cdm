using std::string
using std::string_view
using std::vector

// Tool-install status verification: what gets checked (yt-dlp / ffmpeg presence
// on disk or PATH) and whether check_tools_status_json() reports it correctly.
// Mirrors the UI's "Tools" tab flow (refreshTools -> yt_status -> check_tools_status_json).

func tools_temp_dir() : string {
    var d = string("/tmp/cdm_tools_test_")
    d.append_string(&uuid::v4().to_string())
    return d
}

func tools_write_file(path : *char) {
    var f = fopen(path, "wb\0" as *char)
    if(f != null) {
        var b : u8 = 0x7f
        fwrite(&raw mut b as *mut void, 1u, 1u, f)
        fclose(f)
    }
}

// Returns the JSON status for a fresh manager (no active download).
func tools_status_json() : string {
    var dm = cdm::DownloadManager()
    return cdm::check_tools_status_json(&mut dm)
}

// 1) tools_dir() honors CDM_TOOLS_DIR (used to resolve bundled tool paths).
@test
public func CDM_tools_dir_respects_env(env : &mut TestEnv) {
    var dir = tools_temp_dir()
    var set_res = environment::set(string_view::make_no_len("CDM_TOOLS_DIR"), string_view::make_view(&dir))
    if(set_res is std::Result.Err) { env.error("setenv failed"); return }

    var p = cdm::ytdlp_path()
    if(!p.starts_with(string_view::make_view(&dir))) {
        env.error("ytdlp_path does not use CDM_TOOLS_DIR")
        env.error(p.data())
        return
    }
    if(p.find(string_view::make_no_len("yt-dlp")) == std::NPOS) {
        env.error("ytdlp_path missing binary name")
        return
    }
}

// 2) A bundled binary placed in the tools dir makes ytdlp_is_available() true and
//    is reported as "installed".
@test
public func CDM_tools_available_reported(env : &mut TestEnv) {
    var dir = tools_temp_dir()
    var set_res = environment::set(string_view::make_no_len("CDM_TOOLS_DIR"), string_view::make_view(&dir))
    if(set_res is std::Result.Err) { env.error("setenv failed"); return }
    fs::create_dir_all(dir.data())

    var p = cdm::ytdlp_path()
    tools_write_file(p.data())
    if(!cdm::ytdlp_is_available()) { env.error("ytdlp not available after placing binary"); return }

    var json = tools_status_json()
    // The yt-dlp entry must report installed when the binary is present.
    var want = string::make_no_len("\"name\":\"yt-dlp\",\"status\":\"installed\"")
    if(json.find(string_view::make_view(&want)) == std::NPOS) {
        env.error("yt-dlp not reported installed despite binary present")
        env.error(json.data())
        return
    }
    fs::remove_dir_all_recursive(dir.data())
}

// 3) Removing the binary flips the report back to not_installed.
@test
public func CDM_tools_not_installed_reported(env : &mut TestEnv) {
    var dir = tools_temp_dir()
    var set_res = environment::set(string_view::make_no_len("CDM_TOOLS_DIR"), string_view::make_view(&dir))
    if(set_res is std::Result.Err) { env.error("setenv failed"); return }
    fs::create_dir_all(dir.data())

    var p = cdm::ytdlp_path()
    tools_write_file(p.data())
    remove(p.data())
    if(cdm::ytdlp_is_available()) { env.error("ytdlp still available after removing binary"); return }

    var json = tools_status_json()
    var want = string::make_no_len("\"name\":\"yt-dlp\",\"status\":\"not_installed\"")
    if(json.find(string_view::make_view(&want)) == std::NPOS) {
        env.error("yt-dlp not reported not_installed")
        env.error(json.data())
        return
    }
    fs::remove_dir_all_recursive(dir.data())
}

// 4) Status JSON always carries both tool entries + both_ready flag (structure).
@test
public func CDM_tools_status_structure(env : &mut TestEnv) {
    var dir = tools_temp_dir()
    var set_res = environment::set(string_view::make_no_len("CDM_TOOLS_DIR"), string_view::make_view(&dir))
    if(set_res is std::Result.Err) { env.error("setenv failed"); return }
    fs::create_dir_all(dir.data())

    var json = tools_status_json()
    if(json.find(string_view::make_no_len("\"yt_dlp\"")) == std::NPOS) { env.error("missing yt_dlp key"); return }
    if(json.find(string_view::make_no_len("\"ffmpeg\"")) == std::NPOS) { env.error("missing ffmpeg key"); return }
    if(json.find(string_view::make_no_len("\"both_ready\"")) == std::NPOS) { env.error("missing both_ready key"); return }
    if(json.find(string_view::make_no_len("\"status\"")) == std::NPOS) { env.error("missing status field"); return }
    fs::remove_dir_all_recursive(dir.data())
}

// 5) The reported status must MATCH actual availability (correctness, not just presence).
@test
public func CDM_tools_status_matches_availability(env : &mut TestEnv) {
    var dir = tools_temp_dir()
    var set_res = environment::set(string_view::make_no_len("CDM_TOOLS_DIR"), string_view::make_view(&dir))
    if(set_res is std::Result.Err) { env.error("setenv failed"); return }
    fs::create_dir_all(dir.data())

    var json = tools_status_json()
    var yt_avail = cdm::ytdlp_is_available()
    var ff_avail = cdm::ffmpeg_is_available()

    var ytw = string::make_no_len("\"name\":\"yt-dlp\",\"status\":\"")
    if(yt_avail) { ytw.append_view("installed\"") } else { ytw.append_view("not_installed\"") }
    if(json.find(string_view::make_view(&ytw)) == std::NPOS) {
        env.error("yt-dlp reported status does not match availability")
        env.error(json.data())
        return
    }
    var ftw = string::make_no_len("\"name\":\"ffmpeg\",\"status\":\"")
    if(ff_avail) { ftw.append_view("installed\"") } else { ftw.append_view("not_installed\"") }
    if(json.find(string_view::make_view(&ftw)) == std::NPOS) {
        env.error("ffmpeg reported status does not match availability")
        env.error(json.data())
        return
    }
    fs::remove_dir_all_recursive(dir.data())
}

// 6) both_ready is true only when BOTH tools are actually available.
@test
public func CDM_tools_both_ready(env : &mut TestEnv) {
    var dir = tools_temp_dir()
    var set_res = environment::set(string_view::make_no_len("CDM_TOOLS_DIR"), string_view::make_view(&dir))
    if(set_res is std::Result.Err) { env.error("setenv failed"); return }
    fs::create_dir_all(dir.data())

    // No binaries -> both_ready must be false.
    var json = tools_status_json()
    if(cdm::ytdlp_is_available() && cdm::ffmpeg_is_available()) {
        // Both happen to be present system-wide; both_ready should be true.
        if(json.find(string_view::make_no_len("\"both_ready\":true")) == std::NPOS) {
            env.error("both_ready should be true when both available")
            return
        }
    } else {
        if(json.find(string_view::make_no_len("\"both_ready\":false")) == std::NPOS) {
            env.error("both_ready should be false when a tool is missing")
            env.error(json.data())
            return
        }
    }
    fs::remove_dir_all_recursive(dir.data())
}
