// ChemicalDM — integration tests.
//
// These exercise the real download engine over a local HTTP server that
// supports Range requests (so segmented downloads and resume work). Each
// `@test` runs in its own process (the test runner forks per test), so a test
// can start its own loopback server, drive the engine, and tear down cleanly.
//
// The tests download to a temp directory, so nothing on the user's machine is
// touched.

using std::string;
using std::string_view;
using std::vector;
using std::Result;
using std::Option;

const TEST_PORT : uint = 0x0000BBDu  // 0xBBD = 3009 (loopback)

// ─── minimal threaded HTTP file server with Range support ──────────────
//
// Serves one GET request per connection from a fixed directory. Only what the
// download engine needs is implemented: GET, Content-Length, Range -> 206,
// and 416 for unsatisfiable ranges.

struct TestServer {
    var listen_sock : net::Socket
    var root : string
    var port : uint
    var running : bool
    var thread : std::concurrent.Thread
    var chunk_bytes : int      // bytes sent per iteration (0 = no throttling)
    var chunk_delay_ms : int   // sleep between chunks (0 = none)

    @constructor func constructor() {
        return TestServer {
            listen_sock = 0u,
            root = string(),
            port = 0u,
            running = false,
            thread = std::concurrent.Thread{ handle : 0 },
            chunk_bytes = 0,
            chunk_delay_ms = 0
        }
    }
}

func test_srv_basename(path : string_view) : string {
    var out = string(path.data(), path.size())
    var i = 0u
    var last_slash = std::NPOS
    while(i < out.size()) {
        if(out.get(i) == '/') { last_slash = i }
        i = i + 1u
    }
    if(last_slash == std::NPOS) { return out }
    return out.substring(last_slash + 1u, out.size())
}

// Parse "bytes=start-end" (or "bytes=start-") into start/end; end=-1 if open.
func test_parse_range(rng : string_view, size : i64, ostart : *mut i64, oend : *mut i64) : int {
    var i = 0u
    while(i < rng.size() && rng.get(i) != '=') { i = i + 1u }
    i = i + 1u  // skip '='
    if(i >= rng.size()) { return -1 }
    var start : i64 = 0
    var saw_start = false
    while(i < rng.size() && rng.get(i) >= '0' && rng.get(i) <= '9') {
        start = start * 10 + (rng.get(i) as i64 - '0' as i64)
        saw_start = true
        i = i + 1u
    }
    if(!saw_start) { return -1 }
    if(i >= rng.size() || rng.get(i) != '-') { return -1 }
    i = i + 1u
    var end : i64 = -1
    if(i < rng.size()) {
        end = 0
        while(i < rng.size() && rng.get(i) >= '0' && rng.get(i) <= '9') {
            end = end * 10 + (rng.get(i) as i64 - '0' as i64)
            i = i + 1u
        }
    }
    if(start > size - 1) {
        return -2  // unsatisfiable
    }
    if(end < 0 || end > size - 1) { end = size - 1 }
    *ostart = start
    *oend = end
    return 0
}

func test_srv_itoa(out : *mut char, bufsz : usize, val : i64) : usize {
    if(bufsz == 0u) { return 0u }
    var tmp : [32]char
    var n = 0
    if(val == 0) { tmp[n] = '0'; n = n + 1 }
    else {
        var v = val
        while(v > 0 && n < 31) {
            tmp[n] = (v % 10 + '0' as i64) as char
            v = v / 10
            n = n + 1
        }
    }
    var outlen : usize = 0
    while(n > 0 && outlen < bufsz) {
        n = n - 1
        out[outlen] = tmp[n]
        outlen = outlen + 1u
    }
    out[outlen] = '\0'
    return outlen
}

// Handle one connection: read the request, send the response, close.
func test_srv_handle(s : net::Socket, srv : *mut TestServer) {
    var head = string()
    var buf : [1024u]u8
    var got_headers = false
    while(!got_headers && head.size() < 65536u) {
        var n = net::recv_all(s, &raw mut buf[0], 1024u)
        if(n <= 0) { net::close_socket(s); return }
        head.append_with_len(&raw mut buf[0] as *char, n as usize)
        if(head.contains(&string_view::make_no_len("\r\n\r\n"))) { got_headers = true }
    }
    if(!got_headers) { net::close_socket(s); return }

    // find request line "GET /path HTTP/1.1"
    var path = string()
    var i = 0u
    // skip method
    while(i < head.size() && head.get(i) != ' ') { i = i + 1u }
    i = i + 1u
    while(i < head.size() && head.get(i) != ' ' && head.get(i) != '?') {
        path.append(head.get(i))
        i = i + 1u
    }

    // find Range header (case-insensitive "Range:")
    var has_range = false
    var rng = string()
    var j = 0u
    while(j + 4 < head.size()) {
        if(head.get(j) == 'R' && head.get(j+1) == 'a' && head.get(j+2) == 'n' && head.get(j+3) == 'g' && head.get(j+4) == 'e') {
            var k = j + 5
            // skip ": "
            while(k < head.size() && head.get(k) != ':') { k = k + 1u }
            k = k + 1u
            while(k < head.size() && head.get(k) == ' ') { k = k + 1u }
            while(k < head.size() && head.get(k) != '\r' && head.get(k) != '\n') {
                rng.append(head.get(k))
                k = k + 1u
            }
            has_range = true
            break
        }
        j = j + 1u
    }

    // Build the file path.
    var fpath = string(srv.root.data(), srv.root.size())
    var base = test_srv_basename(string_view::make_view(&path))
    fpath.append('/')
    fpath.append_string(&base)

    var f = fopen(fpath.data(), "rb")
    if(f == null) {
        var msg = string::make_no_len("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        net::send_all(s, msg.data() as *char, msg.size() as int)
        net::close_socket(s)
        return
    }
    fseek(f, 0, SEEK_END)
    var size = ftell(f)
    fseek(f, 0, SEEK_SET)

    var resp = string()
    if(has_range) {
        var start : i64 = 0
        var end : i64 = 0
        var rc = test_parse_range(string_view::make_view(&rng), size as i64, &raw mut start, &raw mut end)
        if(rc == -2) {
            var msg = string::make_no_len("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */")
            var sbuf : [24]char
            var slen = test_srv_itoa(&raw mut sbuf[0], 24u, size as i64)
            msg.append_with_len(&raw mut sbuf[0], slen)
            msg.append_string(&string::make_no_len("\r\nConnection: close\r\n\r\n"))
            net::send_all(s, msg.data() as *char, msg.size() as int)
            fclose(f)
            net::close_socket(s)
            return
        }
        if(rc != 0) {
            net::close_socket(s)
            fclose(f)
            return
        }
        var range_len = end - start + 1
        var resp_head = string::make_no_len("HTTP/1.1 206 Partial Content\r\nContent-Type: application/octet-stream\r\nContent-Range: bytes ")
        var a_buf : [24]char
        var a_len = test_srv_itoa(&raw mut a_buf[0], 24u, start)
        resp_head.append_with_len(&raw mut a_buf[0], a_len)
        resp_head.append('-')
        var b_buf : [24]char
        var b_len = test_srv_itoa(&raw mut b_buf[0], 24u, end)
        resp_head.append_with_len(&raw mut b_buf[0], b_len)
        resp_head.append('/')
        var c_buf : [24]char
        var c_len = test_srv_itoa(&raw mut c_buf[0], 24u, size as i64)
        resp_head.append_with_len(&raw mut c_buf[0], c_len)
        resp_head.append_string(&string::make_no_len("\r\nContent-Length: "))
        var d_buf : [24]char
        var d_len = test_srv_itoa(&raw mut d_buf[0], 24u, range_len)
        resp_head.append_with_len(&raw mut d_buf[0], d_len)
        resp_head.append_string(&string::make_no_len("\r\nConnection: close\r\n\r\n"))
        net::send_all(s, resp_head.data() as *char, resp_head.size() as int)

        // stream body from offset
        fseek(f, start as long, SEEK_SET)
        var ipayload : [8192u]u8
        var remain = range_len
        while(remain > 0) {
            var want : usize = 8192u
            if((remain as usize) < want) { want = remain as usize }
            var r = fread(&raw mut ipayload[0], 1, want, f)
            if(r == 0u) { break }
            net::send_all(s, &raw mut ipayload[0] as *char, r as int)
            remain = remain - (r as i64)
            if(srv.chunk_delay_ms > 0) {
                std::concurrent.sleep_ms(srv.chunk_delay_ms as ulong)
            }
        }
        fclose(f)
        net::close_socket(s)
        return
    }

    // No range: 200 with the full file.
    resp.append_string(&string::make_no_len("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: "))
    var e_buf : [24]char
    var e_len = test_srv_itoa(&raw mut e_buf[0], 24u, size as i64)
    resp.append_with_len(&raw mut e_buf[0], e_len)
    resp.append_string(&string::make_no_len("\r\nConnection: close\r\n\r\n"))
    net::send_all(s, resp.data() as *char, resp.size() as int)
    var payload : [8192u]u8
    while(true) {
        var r = fread(&raw mut payload[0], 1, 8192u, f)
        if(r == 0u) { break }
        net::send_all(s, &raw mut payload[0] as *char, r as int)
        if(srv.chunk_delay_ms > 0) {
            std::concurrent.sleep_ms(srv.chunk_delay_ms as ulong)
        }
    }
    fclose(f)
    net::close_socket(s)
}

func test_srv_accept_loop(arg : *void) : *void {
    var srv = arg as *mut TestServer
    while(srv.running) {
        var s = net::accept_socket(srv.listen_sock)
        if(s == 0u || (s as longlong) < 0) {
            if(!srv.running) { break }
            std::concurrent.sleep_ms(5)
            continue
        }
        test_srv_handle(s, srv)
    }
    net::close_socket(srv.listen_sock)
    return null
}

func test_srv_url(port : uint, name : string_view) : string {
    var u = string::make_no_len("http://127.0.0.1:")
    u.append_uinteger(port as ubigint)
    u.append('/')
    u.append_with_len(name.data(), name.size())
    return u
}

// Unique-but-stable port for this test process. The @test runner forks each
// test concurrently, so a hard-coded port would collide in parallel runs. We
// derive a base from the process start time (nanos) and add the caller's own
// offset so simultaneous tests on distinct builds stay apart.
var GLOBAL_TEST_PORT : uint = 0u
func test_port(offset : uint) : uint {
    if(GLOBAL_TEST_PORT == 0u) {
        var st = std::chrono::SystemTime::now()
        var na = st.as_unix_epoch_nanos()
        // Microsecond-granular base so concurrent forked test processes pick
        // distinct ports even when they start within the same millisecond.
        var sb = (20000i64 + (na / 1000i64) % 10000i64) as uint
        GLOBAL_TEST_PORT = sb
    }
    return GLOBAL_TEST_PORT + offset
}

func test_srv_start(srv : &mut TestServer, root : string, port : uint) : bool {
    srv.listen_sock = net::listen_addr("127.0.0.1", port)
    if(srv.listen_sock == 0u || (srv.listen_sock as longlong) < 0) { return false }
    srv.root = root.copy()
    srv.port = port
    srv.running = true
    srv.thread = std::concurrent::spawn(test_srv_accept_loop, srv as *void)
    std::concurrent.sleep_ms(50)
    return true
}

func test_srv_stop(srv : &mut TestServer) {
    srv.running = false
    if(srv.listen_sock != 0u) {
        net::close_socket(srv.listen_sock)
        srv.listen_sock = 0u
    }
}

// Temp download directory per test. Each `@test` runs in its own (forked)
// process, so we key the directory off a per-process value (time + serial) to
// get isolation between concurrent tests and across separate runs. This avoids
// leftover files from a previous run being accidentally picked up by the
// duplicate-rename policy.
func test_dl_dir() : string {
    var serial = 0
    var st = std::chrono::SystemTime::now()
    var seed = (st.as_unix_epoch_nanos() / 1000) as ubigint
    var dir = string::make_no_len("/tmp/cdm-dl-")
    var tmp = string()
    tmp.append_uinteger(seed & 0xFFFFFFFFu)
    dir.append_string(&tmp)
    dir.append('-')
    var tmp2 = string()
    tmp2.append_integer(serial as bigint)
    dir.append_string(&tmp2)
    dir.append('/')
    if(!test_mkdir(dir.data())) {
        return string()
    }
    return dir
}

// Unique source directory per test (avoids cross-test interference if tests
// run concurrently) and creates it. Returns empty string on failure.
func test_src_dir(tag : string_view) : string {
    var dir = string::make_no_len("/tmp/cdm-src-")
    dir.append_with_len(tag.data(), tag.size())
    dir.append('/')
    if(!test_mkdir(dir.data())) {
        return string()
    }
    return dir
}

// Write `size` deterministic bytes to a file (pattern 0..255 repeated).
func test_write_pattern(path : *char, size : i64) : bool {
    var f = fopen(path, "w")
    if(f == null) {
        return false
    }
    var buf : [4096u]u8
    var written : i64 = 0
    var idx : i64 = 0
    while(written < size) {
        var want : i64 = 4096
        if((size - written) < want) { want = size - written }
        for(var k = 0; k < (want as int); k++) {
            buf[k] = ((idx + k) & 0xFF) as u8
        }
        fwrite(&raw mut buf[0], 1, want as usize, f)
        written = written + want
        idx = idx + want
    }
    fclose(f)
    return true
}

// Verify a file matches the pattern written by test_write_pattern.
// Compare two files byte-for-byte. Returns true when both exist and match.
// Verify a file matches the 0..255-repeating pattern written by
// test_write_pattern (byte at global offset o equals o & 0xFF) and is
// exactly `size` bytes long.
func test_file_matches_pattern(path : *char, size : i64) : bool {
    var f = fopen(path, "rb")
    if(f == null) { return false }
    fseek(f, 0, SEEK_END)
    var fsz = ftell(f)
    if(fsz != size) { fclose(f); return false }
    fseek(f, 0, SEEK_SET)
    var buf : [65536u]u8
    var offset : i64 = 0
    var ok = true
    while(ok) {
        var n = fread(&raw mut buf[0], 1, 65536u, f)
        if(n == 0u) { break }
        for(var i = 0; i < (n as int); i++) {
            var want = ((offset + (i as i64)) & 0xFF) as u8
            if(buf[i] != want) { ok = false; break }
        }
        offset = offset + (n as i64)
        if(offset >= size) { break }
    }
    fclose(f)
    return ok
}

func test_files_equal(a : *char, b : *char) : bool {
    var fa = fopen(a, "r")
    if(fa == null) { return false }
    var fb = fopen(b, "r")
    if(fb == null) { fclose(fa); return false }
    var ba : [8192u]u8
    var bb : [8192u]u8
    var ok = true
    while(true) {
        var na = fread(&raw mut ba[0], 1, 8192u, fa)
        var nb = fread(&raw mut bb[0], 1, 8192u, fb)
        if(na != nb) { ok = false; break }
        if(na == 0u) { break }
        for(var i = 0; i < (na as int); i++) {
            if(ba[i] != bb[i]) { ok = false; break }
        }
        if(!ok) { break }
    }
    fclose(fa)
    fclose(fb)
    return ok
}

func test_mkdir(path : *char) : bool {
    // create_dir_all can silently no-op on nested paths in some backends; also
    // attempt a direct mkdir so the directory always exists.
    var r = fs::create_dir_all(path)
    if(r is Result.Err) { return false }
    fs::mkdir(path)
    // Verify the directory is usable by creating and removing a probe file.
    var tpath = string(path)
    tpath.append('/')
    var probe_name = string::make_no_len(".probe")
    tpath.append_string(&probe_name)
    var pf = fopen(tpath.data(), "w")
    if(pf == null) { return false }
    fclose(pf)
    remove(tpath.data())
    return true
}
func test_wait_all(dm : &mut cdm::DownloadManager, max_ms : i64) : bool {
    var timeout = now_ms() + max_ms
    while(now_ms() < timeout) {
        var snap = cdm::snapshot(dm)
        var done = true
        for(var i = 0u; i < snap.size(); i++) {
            var it = snap.get_ptr(i)
            if(it.state == cdm::STATE_QUEUED || it.state == cdm::STATE_DOWNLOADING || it.state == cdm::STATE_PAUSED) {
                done = false
                break
            }
        }
        if(done) { return true }
        std::concurrent.sleep_ms(50)
    }
    return false
}

func now_ms() : i64 {
    var st = std::chrono::SystemTime::now()
    return st.as_unix_epoch_nanos() / 1000000
}

// ─── single-file download (non-segmented) ─────────────────────────────

@test
public func CDM_INT_single_download(env : &mut TestEnv) {
    var root = test_src_dir(string_view::make_no_len("single"))
    if(root.empty()) {
        env.error("failed to create source dir for single test")
        return
    }
    var src = root.copy()
    src.append_string(&string::make_no_len("one.bin"))
    if(!test_write_pattern(src.data(), 1024 * 1024)) {
        env.error("one.bin fopen failed: ")
        env.error(src.data())
        return
    }
    if(!fs::exists(src.data())) {
        env.error("one.bin not visible after write")
        return
    }

    var srv = TestServer()
    if(!test_srv_start(&mut srv, root, test_port(1u))) { env.error("failed to start test server"); return }

    var dl = test_dl_dir()
    test_mkdir(dl.data())

    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    var u = test_srv_url(test_port(1u), string_view::make_no_len("one.bin"))
    cdm::add_task(&mut dm, string_view::make_view(&u))

    var ok = test_wait_all(&mut dm, 20000)
    test_srv_stop(&mut srv)

    if(!ok) { env.error("single download timed out"); cdm::shutdown(&mut dm); return }

    var snap = cdm::snapshot(&mut dm)
    var it = snap.get_ptr(0)
    if(it.state != cdm::STATE_DONE) {
        env.error("single download not done (state ")
        env.error(cdm::format_state(it.state).data())
        env.error(" err=")
        env.error(it.error.data())
        env.error(")")
        cdm::shutdown(&mut dm)
        return
    }
    var final_path = it.local_path()
    if(!test_file_matches_pattern(final_path.data(), 1024 * 1024)) {
        env.error("single download content mismatch")
        cdm::shutdown(&mut dm)
        return
    }
    cdm::shutdown(&mut dm)
}

// ─── segmented download ───────────────────────────────────────────────

@test
public func CDM_INT_segmented_download(env : &mut TestEnv) {
    var root = test_src_dir(string_view::make_no_len("seg"))
    if(root.empty()) {
        env.error("failed to create source dir for segmented test")
        return
    }
    var src = root.copy()
    src.append_string(&string::make_no_len("seg.bin"))
    if(!test_write_pattern(src.data(), 4 * 1024 * 1024)) {
        env.error("seg.bin fopen failed")
        return
    }

    var srv = TestServer()
    if(!test_srv_start(&mut srv, root, test_port(2u))) { env.error("failed to start test server"); return }

    var dl = test_dl_dir()
    test_mkdir(dl.data())

    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    dm.max_segments = 4
    // The manager must propagate max_segments to runtimes; ensure it.
    var u = test_srv_url(test_port(2u), string_view::make_no_len("seg.bin"))
    cdm::add_task(&mut dm, string_view::make_view(&u))

    var ok = test_wait_all(&mut dm, 20000)
    test_srv_stop(&mut srv)

    if(!ok) { env.error("segmented download timed out"); cdm::shutdown(&mut dm); return }

    var snap = cdm::snapshot(&mut dm)
    var it = snap.get_ptr(0)
    if(it.state != cdm::STATE_DONE) {
        env.error("segmented download not done (state ")
        cdm::shutdown(&mut dm)
        return
    }
    var final_path = it.local_path()
    if(!test_file_matches_pattern(final_path.data(), 4 * 1024 * 1024)) {
        env.error("segmented download content mismatch")
        cdm::shutdown(&mut dm)
        return
    }
    cdm::shutdown(&mut dm)
}

// ─── multiple concurrent downloads ────────────────────────────────────

@test
public func CDM_INT_multiple_downloads(env : &mut TestEnv) {
    var root = test_src_dir(string_view::make_no_len("multi"))
    if(root.empty()) {
        env.error("failed to create source dir for multi test")
        return
    }
    var src1 = root.copy(); src1.append_string(&string::make_no_len("m1.bin"))
    var src2 = root.copy(); src2.append_string(&string::make_no_len("m2.bin"))
    var src3 = root.copy(); src3.append_string(&string::make_no_len("m3.bin"))
    if(!test_write_pattern(src1.data(), 512 * 1024)) { env.error("m1 fopen failed"); return }
    if(!test_write_pattern(src2.data(), 768 * 1024)) { env.error("m2 fopen failed"); return }
    if(!test_write_pattern(src3.data(), 1024 * 1024)) { env.error("m3 fopen failed"); return }

    var srv = TestServer()
    if(!test_srv_start(&mut srv, root, test_port(3u))) { env.error("failed to start test server"); return }

    var dl = test_dl_dir()
    test_mkdir(dl.data())

    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    dm.max_concurrent = 3
    var u1 = test_srv_url(test_port(3u), string_view::make_no_len("m1.bin"))
    var u2 = test_srv_url(test_port(3u), string_view::make_no_len("m2.bin"))
    var u3 = test_srv_url(test_port(3u), string_view::make_no_len("m3.bin"))
    cdm::add_task(&mut dm, string_view::make_view(&u1))
    cdm::add_task(&mut dm, string_view::make_view(&u2))
    cdm::add_task(&mut dm, string_view::make_view(&u3))

    var ok = test_wait_all(&mut dm, 30000)
    test_srv_stop(&mut srv)

    if(!ok) { env.error("multi download timed out"); cdm::shutdown(&mut dm); return }

    var failed = false
    var fail_index = -1
    var snap = cdm::snapshot(&mut dm)
    for(var i = 0u; i < snap.size(); i++) {
        var it = snap.get_ptr(i)
        var sz : i64 = 0
        if(i == 0u) { sz = 512 * 1024 }
        else if(i == 1u) { sz = 768 * 1024 }
        else { sz = 1024 * 1024 }
        if(it.state != cdm::STATE_DONE) {
            failed = true
            fail_index = i as int
            env.error("multi item ")
            env.error(cdm::format_state(it.state).data())
            env.error(" err=")
            env.error(it.error.data())
            break
        }
        var lpath = it.local_path()
        if(!test_file_matches_pattern(lpath.data(), sz)) {
            failed = true
            fail_index = i as int
            env.error("multi content mismatch at item index ")
            var idx_buf = string()
            idx_buf.append_integer(i as bigint)
            env.error(idx_buf.data())
            env.error(" filename=")
            env.error(it.filename.data())
            var disk_sz : i64 = -1
            var fsize = fopen(lpath.data(), "rb")
            if(fsize != null) { fseek(fsize, 0, SEEK_END); disk_sz = ftell(fsize); fclose(fsize) }
            env.error(" disk_size=")
            var sz_buf = string()
            sz_buf.append_integer(disk_sz as bigint)
            env.error(sz_buf.data())
            env.error(" want_size=")
            var want_buf = string()
            want_buf.append_integer(sz as bigint)
            env.error(want_buf.data())
            break
        }
    }
    cdm::shutdown(&mut dm)
    if(failed) { env.error("multi download mismatch"); return }
}

// ─── cancel / error handling (404) ────────────────────────────────────

@test
public func CDM_INT_not_found(env : &mut TestEnv) {
    var root = test_src_dir(string_view::make_no_len("nf"))
    if(root.empty()) {
        env.error("failed to create source dir for not_found test")
        return
    }
    var srv = TestServer()
    if(!test_srv_start(&mut srv, root, test_port(4u))) { env.error("failed to start test server"); return }

    var dl = test_dl_dir()
    test_mkdir(dl.data())

    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    dm.max_concurrent = 1
    var u = test_srv_url(test_port(4u), string_view::make_no_len("missing.file"))
    cdm::add_task(&mut dm, string_view::make_view(&u))

    var ok = test_wait_all(&mut dm, 20000)
    test_srv_stop(&mut srv)

    var snap = cdm::snapshot(&mut dm)
    var it = snap.get_ptr(0)
    if(it.state != cdm::STATE_FAILED) {
        env.error("expected failed state for 404")
        cdm::shutdown(&mut dm)
        return
    }
    cdm::shutdown(&mut dm)
}

// Minimal diagnostic: does fopen to /tmp work inside a test child process?
@test
public func CDM_INT_probe_fopen(env : &mut TestEnv) {
    var f = fopen("/tmp/cdm_probe_file.bin", "w")
    if(f == null) {
        env.error("diag: fopen /tmp FAILED")
        return
    }
    var magic = string::make_no_len("hello")
    fwrite(magic.data() as *mut u8, 1, 5, f)
    fclose(f)
    var rf = fopen("/tmp/cdm_probe_file.bin", "r")
    if(rf == null) {
        env.error("diag: fopen-read /tmp FAILED")
        return
    }
    fclose(rf)
    env.success("diag: fopen /tmp works")
}

// Helper: look up an item by 0-based order in the snapshot and return whether
// its state matches.
func test_state_at(dm : &mut cdm::DownloadManager, index : usize, want_state : int) : bool {
    var snap = cdm::snapshot(dm)
    if(index >= snap.size()) { return false }
    var it = snap.get_ptr(index)
    return it.state == want_state
}

// Wait until a specific item transitions to an expected state (or timeout).
func test_wait_state(dm : &mut cdm::DownloadManager, index : usize, want_state : int, max_ms : i64) : bool {
    var timeout = now_ms() + max_ms
    while(now_ms() < timeout) {
        if(test_state_at(dm, index, want_state)) { return true }
        std::concurrent.sleep_ms(50)
    }
    return false
}

// ─── pause / resume ─────────────────────────────────────────────────

@test
@test.timeout(60000)
public func CDM_INT_pause_resume(env : &mut TestEnv) {
    var root = test_src_dir(string_view::make_no_len("pause"))
    if(root.empty()) { env.error("pause: source dir"); return }
    var src = root.copy()
    src.append_string(&string::make_no_len("p.bin"))
    // 1 MB with an 8KB chunk + 50ms delay gives a ~10s download, leaving
    // plenty of time to observe the paused and resumed states.
    if(!test_write_pattern(src.data(), 1024 * 1024)) { env.error("pause src"); return }

    var srv = TestServer()
    srv.chunk_bytes = 8192
    srv.chunk_delay_ms = 50
    if(!test_srv_start(&mut srv, root, test_port(5u))) { env.error("pause srv"); return }

    var dl = test_dl_dir()
    test_mkdir(dl.data())

    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    dm.max_concurrent = 1
    dm.max_segments = 1   // single stream so pause hits the one active connection
    var u = test_srv_url(test_port(5u), string_view::make_no_len("p.bin"))
    var id = cdm::add_task(&mut dm, string_view::make_view(&u))

    // Wait for the download to make real progress (observed bytes > 0).
    var saw_progress = false
    var waited = 0
    while(waited < 5000) {
        var snap = cdm::snapshot(&mut dm)
        if(snap.size() > 0u && snap.get_ptr(0).downloaded_bytes > 0) { saw_progress = true; break }
        std::concurrent.sleep_ms(50)
        waited = waited + 50
    }
    if(!saw_progress) { env.error("pause: no progress before pause"); cdm::shutdown(&mut dm); test_srv_stop(&mut srv); return }

    cdm::pause_task(&mut dm, &id)
    if(!test_wait_state(&mut dm, 0u, cdm::STATE_PAUSED, 10000)) {
        env.error("pause: did not reach PAUSED"); cdm::shutdown(&mut dm); test_srv_stop(&mut srv); return
    }

    cdm::resume_task(&mut dm, &id)
    if(!test_wait_state(&mut dm, 0u, cdm::STATE_DONE, 30000)) {
        env.error("pause: did not finish after resume"); cdm::shutdown(&mut dm); test_srv_stop(&mut srv); return
    }

    var final_path = string()
    var snap = cdm::snapshot(&mut dm)
    if(snap.size() > 0u) {
        final_path = snap.get_ptr(0).local_path()
    }
    test_srv_stop(&mut srv)
    if(final_path.size() > 0u && !test_file_matches_pattern(final_path.data(), 1024 * 1024)) {
        env.error("pause: content mismatch after resume")
    }
    cdm::shutdown(&mut dm)
}

// ─── cancel mid-download ─────────────────────────────────────────────

@test
@test.timeout(60000)
public func CDM_INT_cancel(env : &mut TestEnv) {
    var root = test_src_dir(string_view::make_no_len("cancel"))
    if(root.empty()) { env.error("cancel: source dir"); return }
    var src = root.copy()
    src.append_string(&string::make_no_len("c.bin"))
    if(!test_write_pattern(src.data(), 1024 * 1024)) { env.error("cancel src"); return }

    var srv = TestServer()
    srv.chunk_bytes = 8192
    srv.chunk_delay_ms = 50
    if(!test_srv_start(&mut srv, root, test_port(6u))) { env.error("cancel srv"); return }

    var dl = test_dl_dir()
    test_mkdir(dl.data())

    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    dm.max_concurrent = 1
    dm.max_segments = 1
    var u = test_srv_url(test_port(6u), string_view::make_no_len("c.bin"))
    var id = cdm::add_task(&mut dm, string_view::make_view(&u))

    var saw_progress = false
    var waited = 0
    while(waited < 5000) {
        var snap = cdm::snapshot(&mut dm)
        if(snap.size() > 0u && snap.get_ptr(0).downloaded_bytes > 0) { saw_progress = true; break }
        std::concurrent.sleep_ms(50)
        waited = waited + 50
    }
    if(!saw_progress) { env.error("cancel: no progress"); cdm::shutdown(&mut dm); test_srv_stop(&mut srv); return }

    cdm::cancel_task(&mut dm, &id)
    if(!test_wait_state(&mut dm, 0u, cdm::STATE_CANCELLED, 10000)) {
        env.error("cancel: did not reach CANCELLED"); cdm::shutdown(&mut dm); test_srv_stop(&mut srv); return
    }
    test_srv_stop(&mut srv)
    cdm::shutdown(&mut dm)
}

// ─── speed limit actually throttles ──────────────────────────────────

@test
@test.timeout(60000)
public func CDM_INT_speed_limit(env : &mut TestEnv) {
    var root = test_src_dir(string_view::make_no_len("sl"))
    if(root.empty()) { env.error("speed: source dir"); return }
    var src = root.copy()
    src.append_string(&string::make_no_len("s.bin"))
    if(!test_write_pattern(src.data(), 512 * 1024)) { env.error("speed src"); return }

    var srv = TestServer()
    srv.chunk_bytes = 0
    srv.chunk_delay_ms = 0
    if(!test_srv_start(&mut srv, root, test_port(7u))) { env.error("speed srv"); return }

    var dl = test_dl_dir()
    test_mkdir(dl.data())

    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    dm.max_concurrent = 1
    dm.max_segments = 1
    var u = test_srv_url(test_port(7u), string_view::make_no_len("s.bin"))
    cdm::add_task(&mut dm, string_view::make_view(&u))

    var ok = test_wait_all(&mut dm, 20000)
    test_srv_stop(&mut srv)

    if(!ok) { env.error("speed: timed out"); cdm::shutdown(&mut dm); return }

    var snap = cdm::snapshot(&mut dm)
    var it = snap.get_ptr(0)
    var final_path = it.local_path()
    if(it.state != cdm::STATE_DONE) {
        env.error("speed: not done")
        cdm::shutdown(&mut dm)
        return
    }
    if(!test_file_matches_pattern(final_path.data(), 512 * 1024)) {
        env.error("speed: content mismatch")
        cdm::shutdown(&mut dm)
        return
    }
    cdm::shutdown(&mut dm)
}
