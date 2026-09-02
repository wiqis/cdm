using std::string
using std::string_view
using std::vector

// Real-world download verification against a real HTTP server (python, like the
// tls/net/http suites do). Each test forks its own server on 127.0.0.1, drives
// the actual cdm download engine end-to-end, verifies the bytes are byte-for-byte
// identical to the served payload, then tears everything down.

// ─── helpers ────────────────────────────────────────────────────────────────

func http_now_ms() : i64 {
    var st = std::chrono::SystemTime::now()
    return st.as_unix_epoch_nanos() / 1000000
}

func http_payload_path() : string {
    var p = string("/tmp/cdm_http_src_")
    p.append_string(&uuid::v4().to_string())
    p.append_view(".bin")
    return p
}

func http_dl_dir() : string {
    var p = string("/tmp/cdm_http_dl_")
    p.append_string(&uuid::v4().to_string())
    return p
}

func http_write_payload(path : *char, size : size_t) : bool {
    var f = fopen(path, "wb\0" as *char)
    if(f == null) { return false }
    var buf : [4096]u8
    var written : size_t = 0
    while(written < size) {
        var n : size_t = 0
        while(n < 4096u && (written + n) < size) {
            buf[n] = ((written + n) % 251u) as u8
            n = n + 1u
        }
        fwrite(&raw mut buf[0] as *mut void, 1u, n, f)
        written = written + n
    }
    fclose(f)
    return true
}

func http_compare(path : *char, size : size_t) : bool {
    var f = fopen(path, "rb\0" as *char)
    if(f == null) { return false }
    var i : size_t = 0
    while(i < size) {
        var b : u8 = 0
        var n = fread(&raw mut b as *mut void, 1u, 1u, f)
        if(n != 1u) { fclose(f); return false }
        if(b != ((i % 251u) as u8)) { fclose(f); return false }
        i = i + 1u
    }
    fclose(f)
    return true
}

func http_spawn(port : uint, src : string_view) {
    // Clear any leftover listener first.
    var killcmd = string("fuser -k ")
    killcmd.append_integer(port as int)
    killcmd.append_view("/tcp 2>/dev/null")
    system(killcmd.data())

    var cmd = string("setsid python3 tests/http_server.py ")
    cmd.append_view(&src)
    cmd.append_view(" ")
    cmd.append_integer(port as int)
    cmd.append_view(" 2>/dev/null &")
    system(cmd.data())
}

func http_kill(port : uint) {
    var cmd = string("fuser -k ")
    cmd.append_integer(port as int)
    cmd.append_view("/tcp 2>/dev/null")
    system(cmd.data())
}

// Drive one download to a terminal state; returns true if it reached DONE.
func http_drive(dm : &mut cdm::DownloadManager, max_ms : i64) : bool {
    var timeout = http_now_ms() + max_ms
    while(http_now_ms() < timeout) {
        var snap = cdm::snapshot(dm)
        if(snap.size() > 0u) {
            var it = snap.get_ptr(0)
            if(it.state == cdm::STATE_DONE) { return true }
            if(it.state == cdm::STATE_FAILED || it.state == cdm::STATE_CANCELLED) { return false }
        }
        std::concurrent.sleep_ms(50)
    }
    return false
}

func http_run(env : &mut TestEnv, port : uint, size : size_t, label : string_view) : bool {
    var src = http_payload_path()
    if(!http_write_payload(src.data(), size)) { env.error("write payload"); return false }
    var dldir = http_dl_dir()
    fs::create_dir_all(dldir.data())
    // Pre-create so the engine can resolve it even before its own mkdir.
    fs::mkdir(dldir.data())

    http_spawn(port, string_view::make_view(&src))
    std::concurrent.sleep_ms(1000)

    var dm = cdm::DownloadManager()
    dm.download_dir = dldir.copy()
    var url = string("http://127.0.0.1:")
    url.append_integer(port as int)
    url.append_view("/payload.bin")
    cdm::add_task(&mut dm, string_view::make_view(&url))

    var ok = http_drive(&mut dm, 30000)
    http_kill(port)

    if(!ok) {
        var snap = cdm::snapshot(&mut dm)
        if(snap.size() > 0u) {
            var it = snap.get_ptr(0)
            env.error("download did not finish (state ")
            env.error(cdm::format_state(it.state).data())
            env.error(", err=")
            env.error(it.error.data())
            env.error(")")
        } else {
            env.error("no snapshot")
        }
        cdm::shutdown(&mut dm)
        fs::remove_dir_all_recursive(dldir.data())
        remove(src.data())
        return false
    }

    var snap = cdm::snapshot(&mut dm)
    var it = snap.get_ptr(0)
    if(it.total_bytes != (size as i64)) {
        var em = string("size mismatch: got ")
        em.append_integer(it.total_bytes as int)
        em.append_view(" want ")
        em.append_integer(size as int)
        env.error(em.data())
        cdm::shutdown(&mut dm)
        fs::remove_dir_all_recursive(dldir.data())
        remove(src.data())
        return false
    }
    var out_path = dldir.copy()
    out_path.append_view("/payload.bin")
    if(!http_compare(out_path.data(), size)) {
        env.error("byte content mismatch")
        cdm::shutdown(&mut dm)
        fs::remove_dir_all_recursive(dldir.data())
        remove(src.data())
        return false
    }

    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(dldir.data())
    remove(src.data())
    return true
}

// ─── tests ───────────────────────────────────────────────────────────────────

// 1 MiB → large enough that the engine segments via Range requests.
@test
public func CDM_http_python_segmented(env : &mut TestEnv) {
    if(!http_run(env, 0x00002011u, 1024u * 1024u, string_view::make_no_len("segmented"))) { return }
}

// 50 KiB → below the min segment size, so a single 200/streaming GET.
@test
public func CDM_http_python_small_single(env : &mut TestEnv) {
    if(!http_run(env, 0x00002012u, 50u * 1024u, string_view::make_no_len("small"))) { return }
}

// 5 MiB → exercises many segments + assembly under a real server.
@test
public func CDM_http_python_large(env : &mut TestEnv) {
    if(!http_run(env, 0x00002013u, 5u * 1024u * 1024u, string_view::make_no_len("large"))) { return }
}
