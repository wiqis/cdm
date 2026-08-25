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

// 3) Removing OUR binary flips availability back to the baseline (which is
//    "not installed" on a clean machine, but may be "installed" if a system
//    yt-dlp exists on PATH). The test asserts the flip, not an absolute value,
//    so it stays valid whether or not the host already has yt-dlp installed.
@test
public func CDM_tools_not_installed_reported(env : &mut TestEnv) {
    var dir = tools_temp_dir()
    var set_res = environment::set(string_view::make_no_len("CDM_TOOLS_DIR"), string_view::make_view(&dir))
    if(set_res is std::Result.Err) { env.error("setenv failed"); return }
    fs::create_dir_all(dir.data())

    // Baseline = availability WITHOUT our binary present (only a possible system install).
    var baseline_avail = cdm::ytdlp_is_available()

    // Place our binary, confirm it makes yt-dlp available.
    var p = cdm::ytdlp_path()
    tools_write_file(p.data())
    if(!cdm::ytdlp_is_available()) { env.error("ytdlp not available after placing binary"); return }

    // Remove our binary; availability must return to the baseline.
    remove(p.data())
    if(cdm::ytdlp_is_available() != baseline_avail) {
        env.error("ytdlp availability did not return to baseline after removal")
        return
    }

    var json = tools_status_json()
    var want = string::make_no_len("\"name\":\"yt-dlp\",\"status\":\"")
    if(baseline_avail) { want.append_view(string_view::make_no_len("installed\"")) }
    else { want.append_view(string_view::make_no_len("not_installed\"")) }
    if(json.find(string_view::make_view(&want)) == std::NPOS) {
        env.error("yt-dlp status json does not match baseline availability")
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

// 7) A tool binary already on disk at the canonical path must be reported as
//    installed (status "installed" + ytdlp_is_available()). Reproduces "downloaded
//    but the app says not installed".
@test
@test.timeout(30000)
public func CDM_tools_detect_after_install(env : &mut TestEnv) {
    // A tool binary already present on disk at the canonical path must be reported
    // as installed (status "installed" + ytdlp_is_available()). This is the exact
    // "downloaded but the app says not installed" complaint: the status reporting
    // must read the binary from disk rather than lose track of it.
    var tools = br_tmp_dir(string_view::make_no_len("tools-det"))
    if(tools.size() == 0u) { env.error("tmpdir"); return }
    var setr = environment::set(string_view::make_no_len("CDM_TOOLS_DIR"), string_view::make_view(&tools))
    if(setr is std::Result.Err) { env.error("setenv failed"); return }

    // Simulate a completed install: place the binary at the canonical path.
    var yp = cdm::ytdlp_path()
    if(!br_write_pattern(yp.data(), 256 * 1024)) { env.error("write binary"); return }

    if(!cdm::ytdlp_is_available()) {
        env.error("ytdlp_is_available() false after binary placed on disk"); return
    }
    var dm = cdm::DownloadManager()
    var json = cdm::check_tools_status_json(&mut dm)
    var want = string::make_no_len("\"name\":\"yt-dlp\",\"status\":\"installed\"")
    if(json.find(string_view::make_view(&want)) == std::NPOS) {
        env.error("status json not 'installed' after binary placed on disk")
        env.error(json.data())
        return
    }
}

// 8) Queueing the install must target the canonical binary name ("yt-dlp") even
//    when a stale binary already occupies that path. Previously the duplicate-name
//    policy renamed the completed download to "yt-dlp (1)", so ytdlp_path() pointed
//    at a missing file and the app reported "not installed".
@test
@test.timeout(30000)
public func CDM_tools_install_uses_canonical_name(env : &mut TestEnv) {
    // Queueing the install must target the canonical binary name ("yt-dlp"), even
    // when a stale binary already exists there. Previously the duplicate-name
    // policy renamed the completed download to "yt-dlp (1)", so ytdlp_path()
    // pointed at a missing file and the app reported "not installed".
    var tools = br_tmp_dir(string_view::make_no_len("tools-canon"))
    if(tools.size() == 0u) { env.error("tmpdir"); return }
    var setr = environment::set(string_view::make_no_len("CDM_TOOLS_DIR"), string_view::make_view(&tools))
    if(setr is std::Result.Err) { env.error("setenv failed"); return }

    // Pre-place a STALE partial yt-dlp — this previously triggered the rename.
    var stale = tools.copy()
    stale.append_view(string_view::make_no_len("/yt-dlp"))
    if(!br_write_pattern(stale.data(), 1024)) { env.error("stale write"); return }

    var dl = br_tmp_dir(string_view::make_no_len("tool-dl-canon"))
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()

    // Queue the install. The worker runs asynchronously (and fails with no
    // network here); we only inspect the queued task name, captured synchronously.
    var inst_err = cdm::ytdlp_download_async(&mut dm)
    if(!inst_err.empty()) { env.error("ytdlp_download_async: "); env.error(inst_err.data()); return }

    var snap = cdm::snapshot(&mut dm)
    if(snap.size() == 0u) { env.error("no task was queued"); return }
    var fn = snap.get_ptr(0u).filename.copy()
    if(fn.find(string_view::make_no_len(" (1)")) != std::NPOS) {
        env.error("tool queued under a renamed path (duplicate-name bug)"); return
    }
    var want = string::make_no_len("yt-dlp")
    if(!fn.equals(&want)) {
        env.error("tool not queued under canonical name 'yt-dlp'"); return
    }
}

// 9) A yt-dlp binary located in a $PATH directory that is NOT one of the
//    hardcoded locations must still be detected as installed. This reproduces
//    the "I downloaded yt-dlp but the app says not installed" bug where the
//    tool lived in a custom PATH directory (e.g. a conda env, ~/bin, or
//    /opt/homebrew/bin) that the old hardcoded check never scanned.
@test
public func CDM_tools_detect_via_path(env : &mut TestEnv) {
    // Isolate from any bundled/system install: empty tools dir + empty PATH,
    // so the only thing that can flip availability is our PATH directory.
    var td = tools_temp_dir()
    if(environment::set(string_view::make_no_len("CDM_TOOLS_DIR"), string_view::make_view(&td)) is std::Result.Err) {
        env.error("setenv CDM_TOOLS_DIR"); return
    }
    if(environment::set(string_view::make_no_len("PATH"), string_view::make_no_len("")) is std::Result.Err) {
        env.error("setenv PATH"); return
    }
    // Baseline with empty PATH + empty tools dir = only hardcoded system dirs.
    var sys_baseline = cdm::ytdlp_is_available()

    // Place a fake yt-dlp ONLY in a temp dir and expose that dir via $PATH.
    var pdir = tools_temp_dir()
    fs::create_dir_all(pdir.data())
    var fake = pdir.copy()
    fake.append_view(string_view::make_no_len("/yt-dlp"))
    tools_write_file(fake.data())
    if(environment::set(string_view::make_no_len("PATH"), string_view::make_view(&pdir)) is std::Result.Err) {
        env.error("setenv PATH pdir"); return
    }

    if(!cdm::ytdlp_is_available()) {
        env.error("ytdlp not detected via $PATH directory"); return
    }

    // Removing it must drop availability back to the system baseline.
    remove(fake.data())
    if(cdm::ytdlp_is_available() != sys_baseline) {
        env.error("availability did not return to system baseline after removing PATH binary")
        return
    }
    fs::remove_dir_all_recursive(pdir.data())
    fs::remove_dir_all_recursive(td.data())
}

// 10) ytdlp_resolved_path() should return the actual discovered location
//     (including a $PATH directory) rather than always the bare "yt-dlp", so
//     the Tools tab shows the real path and execution does not depend on $PATH
//     at exec time. When no binary is found it falls back to the bare name.
@test
public func CDM_tools_resolved_path_uses_discovered(env : &mut TestEnv) {
    var td = tools_temp_dir()
    if(environment::set(string_view::make_no_len("CDM_TOOLS_DIR"), string_view::make_view(&td)) is std::Result.Err) {
        env.error("setenv CDM_TOOLS_DIR"); return
    }
    var pdir = tools_temp_dir()
    fs::create_dir_all(pdir.data())
    var fake = pdir.copy()
    fake.append_view(string_view::make_no_len("/yt-dlp"))
    tools_write_file(fake.data())
    if(environment::set(string_view::make_no_len("PATH"), string_view::make_view(&pdir)) is std::Result.Err) {
        env.error("setenv PATH"); return
    }

    var resolved = cdm::ytdlp_resolved_path()
    var expected = pdir.copy()
    expected.append_view(string_view::make_no_len("/yt-dlp"))
    if(!resolved.equals(&expected)) {
        env.error("ytdlp_resolved_path did not return the discovered PATH location")
        env.error(resolved.data())
        return
    }

    // Without the binary, fall back to the bare command name.
    remove(fake.data())
    var fallback = cdm::ytdlp_resolved_path()
    var bare = string::make_no_len("yt-dlp")
    if(!fallback.equals(&bare)) {
        env.error("ytdlp_resolved_path should fall back to bare name when not found")
        env.error(fallback.data())
        return
    }
    fs::remove_dir_all_recursive(pdir.data())
    fs::remove_dir_all_recursive(td.data())
}

// 11) Installing (or checking) a tool cleans up stale "name (N)" duplicates
//     left by older installs, so only the canonical binary remains. Regression
//     for a confusing leftover `yt-dlp (1)` sitting next to the real binary.
@test
public func CDM_tools_stale_duplicate_cleaned(env : &mut TestEnv) {
    var tools = tools_temp_dir()
    if(environment::set(string_view::make_no_len("CDM_TOOLS_DIR"), string_view::make_view(&tools)) is std::Result.Err) {
        env.error("setenv CDM_TOOLS_DIR"); return
    }
    fs::create_dir_all(tools.data())
    // Stale duplicate artifact from an older install.
    var stale = tools.copy()
    stale.append_view(string_view::make_no_len("/yt-dlp (1)"))
    if(!br_write_pattern(stale.data(), 1024)) { env.error("stale write"); return }
    // A canonical file so the dir looks real.
    var canon = tools.copy()
    canon.append_view(string_view::make_no_len("/yt-dlp"))
    tools_write_file(canon.data())

    var dm = cdm::DownloadManager()
    var inst_err = cdm::ytdlp_download_async(&mut dm)
    if(!inst_err.empty()) { env.error("ytdlp_download_async: "); env.error(inst_err.data()); return }

    if(fs::exists(stale.data())) {
        env.error("stale 'yt-dlp (1)' was not cleaned up")
        return
    }
    fs::remove_dir_all_recursive(tools.data())
}

// 12) check_tools_status_json() MUST emit VALID JSON. A prior bug double-wrapped
//     string values (json_string already adds quotes, but the builder also added
//     a leading quote), producing ""yt-dlp"" — invalid JSON that the webview
//     bridge failed to parse, leaving the Tools tab stuck on "Not Installed".
@test
public func CDM_tools_status_json_parseable(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    var json_str = cdm::check_tools_status_json(&mut dm)

    var parser = JsonParser(256, 4096)
    var ph = ASTJsonHandler.make()
    var res = parser.parse(json_str.data(), json_str.size(), &mut ph)
    if(!res.ok) {
        env.error("check_tools_status_json produced INVALID JSON")
        env.error(res.msg)
        return
    }
    if(ph.root is JsonValue.Null) {
        env.error("check_tools_status_json parsed to a null root")
        return
    }
    if(ph.root is JsonValue.Object) {
        var Object(m) = ph.root else unreachable
        if(m.get_ptr(string("yt_dlp")) == null) { env.error("status JSON missing yt_dlp"); return }
        if(m.get_ptr(string("ffmpeg")) == null) { env.error("status JSON missing ffmpeg"); return }
        if(m.get_ptr(string("both_ready")) == null) { env.error("status JSON missing both_ready"); return }
        var ytp = m.get_ptr(string("yt_dlp"))
        if(ytp != null && ytp is JsonValue.Object) {
            var Object(ym) = *ytp else unreachable
            if(ym.get_ptr(string("status")) == null) { env.error("yt_dlp missing status"); return }
            if(ym.get_ptr(string("name")) == null) { env.error("yt_dlp missing name"); return }
        } else {
            env.error("yt_dlp is not an object")
            return
        }
    } else {
        env.error("status JSON root is not an object")
        return
    }
}
