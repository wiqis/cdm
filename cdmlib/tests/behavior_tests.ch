// ChemicalDM — BEHAVIORAL integration tests.
//
// These exercise real end-to-end download behavior against an in-process HTTP
// server, focusing on the flows users actually hit and that have broken
// before: progress reporting, pause/resume, cancel, shutdown-then-resume,
// redirects, servers without Content-Length, servers that ignore Range,
// connections dropped mid-body (retry path), segmented assembly of large
// files, tool-download progress reporting, and rapid action stress (crash
// regressions under TCC).
//
// Every @test runs in its own forked process; each test starts its own server
// on its own port and downloads into its own temp dir.

using std::string;
using std::string_view;
using std::vector;
using std::Result;
using std::Option;

// ─── extended test HTTP server ─────────────────────────────────────────
//
// One GET per connection from a fixed directory. Modes:
//   ignore_range        : always answer 200 full content (Range-hostile server)
//   send_content_length : omit the header entirely when false (EOF framing)
//   do_redirect         : paths starting "/redir/" answer 302 → absolute URL
//   drop_after_bytes    : when >0 and drops_left>0, send that many body bytes
//                         then abruptly close (connection-lost retry path).
//                         Probe (bytes=0-0) and first-attempt fresh GETs
//                         (bytes=0-) are never dropped so probing still works.
//   chunk_bytes/delay   : throttling for pause-window tests

struct BtServer {
    var listen_sock : net::Socket
    var root : string
    var port : uint
    var running : bool
    var thread : std::concurrent.Thread
    var chunk_bytes : int
    var chunk_delay_ms : int
    var ignore_range : bool
    var send_content_length : bool
    var do_redirect : bool
    var drop_after_bytes : i64
    var drops_left : int

    @constructor func constructor() {
        return BtServer {
            listen_sock = 0u,
            root = string(),
            port = 0u,
            running = false,
            thread = std::concurrent.Thread{ handle : 0 },
            chunk_bytes = 0,
            chunk_delay_ms = 0,
            ignore_range = false,
            send_content_length = true,
            do_redirect = false,
            drop_after_bytes = 0,
            drops_left = 0
        }
    }
}

func bt_mkdir(path : *char) : bool {
    var r = fs::create_dir_all(path)
    if(r is Result.Err) { return false }
    fs::mkdir(path)
    var tpath = string(path)
    tpath.append('/')
    tpath.append_view(string_view::make_no_len(".probe"))
    var pf = fopen(tpath.data(), "w")
    if(pf == null) { return false }
    fclose(pf)
    remove(tpath.data())
    return true
}

func bt_src_dir(tag : string_view) : string {
    var st = std::chrono::SystemTime::now()
    var seed = (st.as_unix_epoch_nanos() / 1000u) & 0xFFFFFFu
    var dir = string::make_no_len("/tmp/cdm-bt-src-")
    dir.append_with_len(tag.data(), tag.size())
    dir.append('-')
    var s = string()
    s.append_uinteger(seed as ubigint)
    dir.append_string(&s)
    dir.append('/')
    if(!bt_mkdir(dir.data())) { return string() }
    return dir
}

func bt_dl_dir() : string {
    var st = std::chrono::SystemTime::now()
    var seed = ((st.as_unix_epoch_nanos() / 1000u) ^ 0x5A5A5Au) & 0xFFFFFFu
    var dir = string::make_no_len("/tmp/cdm-bt-dl-")
    var s = string()
    s.append_uinteger(seed as ubigint)
    dir.append_string(&s)
    dir.append('/')
    if(!bt_mkdir(dir.data())) { return string() }
    return dir
}

func bt_cleanup_dir(path : *char) {
    fs::remove_dir_all_recursive(path)
}

// Deterministic payload: byte at offset o == o & 0xFF (matches bt_matches).
func bt_write_pattern(path : *char, size : i64) : bool {
    var f = fopen(path, "w")
    if(f == null) { return false }
    unsafe var buf : [4096u]u8
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

func bt_file_size(path : *char) : i64 {
    var f = fopen(path, "rb")
    if(f == null) { return -1 }
    fseek(f, 0, SEEK_END)
    var sz = ftell(f)
    fclose(f)
    return sz as i64
}

func bt_matches(path : *char, size : i64) : bool {
    var f = fopen(path, "rb")
    if(f == null) { return false }
    fseek(f, 0, SEEK_END)
    var fsz = ftell(f)
    if(fsz != size) { fclose(f); return false }
    fseek(f, 0, SEEK_SET)
    unsafe var buf : [65536u]u8
    var offset : i64 = 0
    while(true) {
        var n = fread(&raw mut buf[0], 1, 65536u, f)
        if(n == 0u) { break }
        for(var i = 0; i < (n as int); i++) {
            var expect = ((offset + (i as i64)) & 0xFF) as u8
            if(buf[i] != expect) {
                fprintf(stderr, "[BT-MATCH] mismatch at off=%lld got=%d want=%d\n", (offset + (i as i64)) as bigint, buf[i] as int, expect as int)
                fclose(f); return false
            }
        }
        offset = offset + (n as i64)
        if(offset >= size) { break }
    }
    fclose(f)
    return true
}

func bt_itoa(outp : *mut char, bufsz : usize, val : i64) : usize {
    if(bufsz == 0u) { return 0u }
    unsafe var tmp : [32]char
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
        outp[outlen] = tmp[n]
        outlen = outlen + 1u
    }
    outp[outlen] = '\0'
    return outlen
}

func bt_parse_range(rng : string_view, size : i64, ostart : *mut i64, oend : *mut i64) : int {
    var i = 0u
    while(i < rng.size() && rng.get(i) != '=') { i = i + 1u }
    i = i + 1u
    if(i >= rng.size()) { return -1 }
    var start : i64 = 0
    var saw = false
    while(i < rng.size() && rng.get(i) >= '0' && rng.get(i) <= '9') {
        start = start * 10 + (rng.get(i) as i64 - '0' as i64)
        saw = true
        i = i + 1u
    }
    if(!saw) { return -1 }
    if(i >= rng.size() || rng.get(i) != '-') { return -1 }
    i = i + 1u
    var end : i64 = -1
    while(i < rng.size() && rng.get(i) >= '0' && rng.get(i) <= '9') {
        end = end * 10 + (rng.get(i) as i64 - '0' as i64)
        i = i + 1u
    }
    if(start > size - 1) { return -2 }
    if(end < 0 || end > size - 1) { end = size - 1 }
    *ostart = start
    *oend = end
    return 0
}

func bt_send_chunked(s : net::Socket, f : *mut FILE, srv : *mut BtServer, total : i64, count_dropped : *mut bool) {
    unsafe var payload : [8192u]u8
    var sent : i64 = 0
    while(sent < total) {
        var want : usize = 8192u
        if(((total - sent) as usize) < want) { want = (total - sent) as usize }
        var r = fread(&raw mut payload[0], 1, want, f)
        if(r == 0u) { break }
        net::send_all(s, &raw mut payload[0] as *char, r as int)
        sent = sent + (r as i64)
        // Drop mode: cut the connection mid-body once per configured attempt.
        // Client sees a short body vs Content-Length -> read error -> retry.
        if(srv.drop_after_bytes > 0 && srv.drops_left > 0 && sent >= srv.drop_after_bytes) {
            srv.drops_left = srv.drops_left - 1
            *count_dropped = true
            break
        }
        if(srv.chunk_delay_ms > 0) {
            std::concurrent.sleep_ms(srv.chunk_delay_ms as ulong)
        }
    }
}

func bt_handle(s : net::Socket, srv : *mut BtServer) {
    var head = string()
    unsafe var buf : [1024u]u8
    var got_headers = false
    while(!got_headers && head.size() < 65536u) {
        var n = net::recv_all(s, &raw mut buf[0], 1024u)
        if(n <= 0) { net::close_socket(s); return }
        head.append_with_len(&raw mut buf[0] as *char, n as usize)
        if(head.contains(&string_view::make_no_len("\r\n\r\n"))) { got_headers = true }
    }
    if(!got_headers) { net::close_socket(s); return }

    // request-line path
    var path = string()
    var i = 0u
    while(i < head.size() && head.get(i) != ' ') { i = i + 1u }
    i = i + 1u
    while(i < head.size() && head.get(i) != ' ' && head.get(i) != '?') {
        path.append(head.get(i))
        i = i + 1u
    }

    // Range header
    var has_range = false
    var rng = string()
    var j = 0u
    while(j + 5 < head.size()) {
        if(head.get(j) == 'R' && head.get(j+1u) == 'a' && head.get(j+2u) == 'n' && head.get(j+3u) == 'g' && head.get(j+4u) == 'e') {
            var k = j + 5
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

    // Redirect mode: /redir/<file> answers with an absolute Location.
    var redir_prefix = string::make_no_len("/redir/")
    var is_redir = path.size() >= 7u
    if(is_redir) {
        for(var q = 0u; q < 7u; q++) {
            if(path.get(q) != redir_prefix.get(q)) { is_redir = false }
        }
    }
    if(srv.do_redirect && is_redir) {
        var base = path.substring(7u, path.size())
        var loc = string::make_no_len("http://127.0.0.1:")
        loc.append_uinteger(srv.port as ubigint)
        loc.append('/')
        loc.append_string(&base)
        var msg = string::make_no_len("HTTP/1.1 302 Found\r\nLocation: ")
        msg.append_string(&loc)
        msg.append_string(&string::make_no_len("\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"))
        net::send_all(s, msg.data() as *char, msg.size() as int)
        net::close_socket(s)
        return
    }

    // basename only
    var base = path.copy()
    var last_slash = std::NPOS
    for(var c = 0u; c < base.size(); c++) {
        if(base.get(c) == '/') { last_slash = c }
    }
    if(last_slash != std::NPOS) { base = base.substring(last_slash + 1u, base.size()) }

    var fpath = string(srv.root.data(), srv.root.size())
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
    var size = ftell(f) as i64
    fseek(f, 0, SEEK_SET)

    var use_range = has_range && !srv.ignore_range

    if(use_range) {
        var start : i64 = 0
        var end : i64 = 0
        var rc = bt_parse_range(string_view::make_view(&rng), size, &raw mut start, &raw mut end)
        if(rc == -2) {
            var msg = string::make_no_len("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */")
            unsafe var sb : [24]char
            var sl = bt_itoa(&raw mut sb[0], 24u, size)
            msg.append_with_len(&raw mut sb[0], sl)
            msg.append_string(&string::make_no_len("\r\nConnection: close\r\n\r\n"))
            net::send_all(s, msg.data() as *char, msg.size() as int)
            fclose(f)
            net::close_socket(s)
            return
        }
        if(rc != 0) { fclose(f); net::close_socket(s); return }
        var range_len = end - start + 1
        var h = string::make_no_len("HTTP/1.1 206 Partial Content\r\nContent-Type: application/octet-stream\r\nContent-Range: bytes ")
        unsafe var ab : [24]char
        var al = bt_itoa(&raw mut ab[0], 24u, start)
        h.append_with_len(&raw mut ab[0], al)
        h.append('-')
        unsafe var bb : [24]char
        var bl = bt_itoa(&raw mut bb[0], 24u, end)
        h.append_with_len(&raw mut bb[0], bl)
        h.append('/')
        unsafe var cb : [24]char
        var cl2 = bt_itoa(&raw mut cb[0], 24u, size)
        h.append_with_len(&raw mut cb[0], cl2)
        h.append_string(&string::make_no_len("\r\nContent-Length: "))
        unsafe var db : [24]char
        var dl = bt_itoa(&raw mut db[0], 24u, range_len)
        h.append_with_len(&raw mut db[0], dl)
        h.append_string(&string::make_no_len("\r\nConnection: close\r\n\r\n"))
        net::send_all(s, h.data() as *char, h.size() as int)
        fseek(f, start as long, SEEK_SET)
        var dropped = false
        bt_send_chunked(s, f, srv, range_len, &raw mut dropped)
        fclose(f)
        net::close_socket(s)
        return
    }

    // Full-content 200 response.
    var h2 = string::make_no_len("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream")
    if(srv.send_content_length) {
        h2.append_string(&string::make_no_len("\r\nContent-Length: "))
        unsafe var eb : [24]char
        var el = bt_itoa(&raw mut eb[0], 24u, size)
        h2.append_with_len(&raw mut eb[0], el)
    }
    h2.append_string(&string::make_no_len("\r\nConnection: close\r\n\r\n"))
    net::send_all(s, h2.data() as *char, h2.size() as int)
    var dropped2 = false
    bt_send_chunked(s, f, srv, size, &raw mut dropped2)
    fclose(f)
    net::close_socket(s)
}

func bt_accept_loop(arg : *void) : *void {
    var srv = arg as *mut BtServer
    while(srv.running) {
        var s = net::accept_socket(srv.listen_sock)
        if(s == 0u || (s as longlong) < 0) {
            if(!srv.running) { break }
            std::concurrent.sleep_ms(5)
            continue
        }
        bt_handle(s, srv)
    }
    net::close_socket(srv.listen_sock)
    return null
}

func bt_port(offset : uint) : uint {
    var st = std::chrono::SystemTime::now()
    var na = st.as_unix_epoch_nanos()
    var base = (31000i64 + (na / 1000i64) % 20000i64) as uint
    return base + offset
}

func bt_srv_start(srv : &mut BtServer, root : string, port : uint) : bool {
    srv.listen_sock = net::listen_addr("127.0.0.1", port)
    if(srv.listen_sock == 0u || (srv.listen_sock as longlong) < 0) { return false }
    srv.root = root.copy()
    srv.port = port
    srv.running = true
    srv.thread = std::concurrent::spawn(bt_accept_loop, srv as *void)
    std::concurrent.sleep_ms(50)
    return true
}

func bt_srv_stop(srv : &mut BtServer) {
    srv.running = false
    if(srv.listen_sock != 0u) {
        net::close_socket(srv.listen_sock)
        srv.listen_sock = 0u
    }
}

func bt_url(port : uint, name : string_view) : string {
    var u = string::make_no_len("http://127.0.0.1:")
    u.append_uinteger(port as ubigint)
    u.append('/')
    u.append_with_len(name.data(), name.size())
    return u
}

// ─── wait/assert helpers ───────────────────────────────────────────────

func bt_now_ms() : i64 {
    var st = std::chrono::SystemTime::now()
    return st.as_unix_epoch_nanos() / 1000000
}

func bt_state_of(dm : &mut cdm::DownloadManager, id : &string) : int {
    var snap = cdm::snapshot(dm)
    for(var i = 0u; i < snap.size(); i++) {
        var it = snap.get_ptr(i)
        if(it.id.equals(id)) { return it.state }
    }
    return -999
}

func bt_downloaded_of(dm : &mut cdm::DownloadManager, id : &string) : i64 {
    var snap = cdm::snapshot(dm)
    for(var i = 0u; i < snap.size(); i++) {
        var it = snap.get_ptr(i)
        if(it.id.equals(id)) { return it.downloaded_bytes }
    }
    return -1
}

func bt_total_of(dm : &mut cdm::DownloadManager, id : &string) : i64 {
    var snap = cdm::snapshot(dm)
    for(var i = 0u; i < snap.size(); i++) {
        var it = snap.get_ptr(i)
        if(it.id.equals(id)) { return it.total_bytes }
    }
    return -1
}

func bt_speed_of(dm : &mut cdm::DownloadManager, id : &string) : i64 {
    var snap = cdm::snapshot(dm)
    for(var i = 0u; i < snap.size(); i++) {
        var it = snap.get_ptr(i)
        if(it.id.equals(id)) { return it.speed_bytes_per_sec }
    }
    return -1
}

// Wait until the item reports `want`; returns final state on timeout.
func bt_wait_state(dm : &mut cdm::DownloadManager, id : &string, want : int, max_ms : i64) : bool {
    var deadline = bt_now_ms() + max_ms
    while(bt_now_ms() < deadline) {
        if(bt_state_of(dm, id) == want) { return true }
        std::concurrent.sleep_ms(20)
    }
    return bt_state_of(dm, id) == want
}

// Wait until downloaded_bytes reaches at least `min` while downloading.
func bt_wait_downloaded_above(dm : &mut cdm::DownloadManager, id : &string, min : i64, max_ms : i64) : bool {
    var deadline = bt_now_ms() + max_ms
    while(bt_now_ms() < deadline) {
        if(bt_downloaded_of(dm, id) >= min) { return true }
        std::concurrent.sleep_ms(20)
    }
    return bt_downloaded_of(dm, id) >= min
}

func bt_wait_terminal(dm : &mut cdm::DownloadManager, id : &string, max_ms : i64) : bool {
    var deadline = bt_now_ms() + max_ms
    while(bt_now_ms() < deadline) {
        var st = bt_state_of(dm, id)
        if(st == cdm::STATE_DONE || st == cdm::STATE_FAILED || st == cdm::STATE_CANCELLED) { return true }
        std::concurrent.sleep_ms(25)
    }
    return false
}

// Extract `"key":"value"` following the item whose id appears in the state
// JSON (used by bridge-level tests in the app suite too).
func bt_json_item_string(state_json : &string, id : &string, key : string_view) : string {
    var marker = string::make_no_len("\"id\":\"")
    marker.append_string(id)
    marker.append('"')
    var pos = state_json.find(&string_view::make_view(&marker))
    if(pos == std::NPOS) { return string() }
    var khead = string::make_no_len("\"")
    khead.append_with_len(key.data(), key.size())
    khead.append_string(&string::make_no_len("\":\""))
    // manual forward search for khead starting after pos
    var found = std::NPOS
    var i = pos + 1u
    while(i + khead.size() <= state_json.size()) {
        var match = true
        for(var q = 0u; q < khead.size(); q++) {
            if(state_json.get(i + q) != khead.get(q)) { match = false }
        }
        if(match) { found = i }
        else { i = i + 1u }
    }
    if(found == std::NPOS) { return string() }
    var vs = found + khead.size()
    var ve = vs
    while(ve < state_json.size() && state_json.get(ve) != '"') { ve = ve + 1u }
    return state_json.substring(vs, ve)
}

// ─── BT 1: small single-stream file, full lifecycle smoke ──────────────

@test
public func CDM_BT_single_small_file(env : &mut TestEnv) {
    var root = bt_src_dir(string_view::make_no_len("small"))
    if(root.empty()) { env.error("src dir"); return }
    var src = root.copy()
    src.append_view(string_view::make_no_len("tiny.bin"))
    if(!bt_write_pattern(src.data(), 128 * 1024)) { env.error("payload"); return }

    var srv = BtServer()
    if(!bt_srv_start(&mut srv, root.copy(), bt_port(1u))) { env.error("server"); return }

    var dl = bt_dl_dir()
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()

    var u = bt_url(srv.port, string_view::make_no_len("tiny.bin"))
    var uv = string_view::make_view(&u)
    var id = cdm::add_task(&mut dm, uv)
    if(id.empty()) { env.error("add failed"); bt_srv_stop(&mut srv); return }

    if(!bt_wait_terminal(&mut dm, &id, 15000)) {
        env.error("download did not reach terminal state")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    var st = bt_state_of(&mut dm, &id)
    if(st != cdm::STATE_DONE) {
        env.error("expected DONE, got state code")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }

    // Output must exist at dir/filename and match the pattern exactly.
    var snap = cdm::snapshot(&mut dm)
    var it = snap.get_ptr(0)
    var lpath = it.local_path()
    if(!bt_matches(lpath.data(), 128 * 1024)) {
        env.error("output content mismatch")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    // Progress bookkeeping must be consistent after completion.
    if(it.downloaded_bytes != 128 * 1024) { env.error("final downloaded_bytes wrong"); return }
    if(it.total_bytes != 128 * 1024) { env.error("final total_bytes wrong"); return }

    bt_srv_stop(&mut srv)
    cdm::shutdown(&mut dm)
    bt_cleanup_dir(dl.data())
    bt_cleanup_dir(root.data())
}

// ─── BT 2: large file goes through segmentation and assembles correctly ─

@test
public func CDM_BT_segmented_large_file(env : &mut TestEnv) {
    var root = bt_src_dir(string_view::make_no_len("seg"))
    if(root.empty()) { env.error("src dir"); return }
    var total : i64 = 2560 * 1024   // 2.5 MB -> 4 segments at defaults
    var src = root.copy()
    src.append_view(string_view::make_no_len("big.bin"))
    if(!bt_write_pattern(src.data(), total)) { env.error("payload"); return }

    var srv = BtServer()
    if(!bt_srv_start(&mut srv, root.copy(), bt_port(2u))) { env.error("server"); return }

    var dl = bt_dl_dir()
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    dm.max_segments = 4

    var u = bt_url(srv.port, string_view::make_no_len("big.bin"))
    var uv = string_view::make_view(&u)
    var id = cdm::add_task(&mut dm, uv)

    // While running, the item should expose segment progress JSON.
    var saw_segments_json = false
    var deadline = bt_now_ms() + 30000
    var done = false
    while(bt_now_ms() < deadline && !done) {
        var snap = cdm::snapshot(&mut dm)
        var it = snap.get_ptr(0)
        if(!it.segments_json.empty() && it.segments_json.contains(&string_view::make_no_len("\"copied\":"))) {
            saw_segments_json = true
        }
        if(it.state == cdm::STATE_DONE) { done = true }
        std::concurrent.sleep_ms(15)
    }
    bt_srv_stop(&mut srv)
    if(!done) {
        env.error("segmented download timed out, err=")
        var snap2 = cdm::snapshot(&mut dm)
        env.error(snap2.get_ptr(0).error.data())
        cdm::shutdown(&mut dm); return
    }

    var snap = cdm::snapshot(&mut dm)
    var it = snap.get_ptr(0)
    var lpath = it.local_path()
    if(!bt_matches(lpath.data(), total)) {
        env.error("assembled output mismatch - segment order or ranges wrong")
        cdm::shutdown(&mut dm); return
    }
    // All part files must be gone after assembly.
    for(var i = 0; i < 4; i++) {
        var pf = lpath.copy()
        pf.append('.')
        pf.append_integer(i as bigint)
        pf.append_view(string_view::make_no_len(".part"))
        if(fs::exists(pf.data())) {
            env.error("leftover .part file after assembly")
            cdm::shutdown(&mut dm); return
        }
    }
    if(it.downloaded_bytes != total) { env.error("segmented progress sum wrong"); return }
    if(!saw_segments_json) {
        // Not fatal (fast machines can finish between polls) but suspicious.
        fprintf(stderr, "[BT] note: segments json never observed during run\n")
    }

    cdm::shutdown(&mut dm)
    bt_cleanup_dir(dl.data())
    bt_cleanup_dir(root.data())
}

// ─── BT 3: pause mid-download keeps partial data, resume completes ─────

@test
public func CDM_BT_pause_resume_midstream(env : &mut TestEnv) {
    var root = bt_src_dir(string_view::make_no_len("pause"))
    if(root.empty()) { env.error("src dir"); return }
    var total : i64 = 512 * 1024
    var src = root.copy()
    src.append_view(string_view::make_no_len("slow.bin"))
    if(!bt_write_pattern(src.data(), total)) { env.error("payload"); return }

    var srv = BtServer()
    srv.chunk_delay_ms = 12          // ~650 KB/s -> ~0.8s transfer window
    if(!bt_srv_start(&mut srv, root.copy(), bt_port(3u))) { env.error("server"); return }

    var dl = bt_dl_dir()
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    dm.max_segments = 1   // target the single-stream resume logic

    var u = bt_url(srv.port, string_view::make_no_len("slow.bin"))
    var uv = string_view::make_view(&u)
    var id = cdm::add_task(&mut dm, uv)

    // Wait for real progress, then pause.
    if(!bt_wait_downloaded_above(&mut dm, &id, 32 * 1024, 10000)) {
        env.error("no progress before pause")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    cdm::pause_task(&mut dm, &id)
    if(!bt_wait_state(&mut dm, &id, cdm::STATE_PAUSED, 5000)) {
        env.error("item did not become PAUSED")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }

    // Partial data must be on disk and preserved.
    var snap0 = cdm::snapshot(&mut dm)
    var it0 = snap0.get_ptr(0)
    var partial = it0.local_path()
    var partial_size = bt_file_size(partial.data())
    if(partial_size <= 0) { env.error("no partial bytes on disk while paused"); return }
    var paused_at = bt_downloaded_of(&mut dm, &id)
    std::concurrent.sleep_ms(400)
    if(bt_downloaded_of(&mut dm, &id) != paused_at) {
        env.error("progress moved while paused")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }

    cdm::resume_task(&mut dm, &id)
    if(!bt_wait_terminal(&mut dm, &id, 20000)) {
        env.error("resume did not finish")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    if(bt_state_of(&mut dm, &id) != cdm::STATE_DONE) {
        env.error("resume did not complete DONE")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }

    var snap = cdm::snapshot(&mut dm)
    var it = snap.get_ptr(0)
    var lpath = it.local_path()
    if(!bt_matches(lpath.data(), total)) {
        env.error("resumed output mismatch — resume-from-offset logic broken")
        cdm::shutdown(&mut dm); return
    }
    if(it.downloaded_bytes != total) { env.error("resumed counter wrong"); return }

    bt_srv_stop(&mut srv)
    cdm::shutdown(&mut dm)
    bt_cleanup_dir(dl.data())
    bt_cleanup_dir(root.data())
}

// ─── BT 4: cancel mid-download settles promptly and cleans up ──────────

@test
public func CDM_BT_cancel_midstream(env : &mut TestEnv) {
    var root = bt_src_dir(string_view::make_no_len("cancel"))
    if(root.empty()) { env.error("src dir"); return }
    var src = root.copy()
    src.append_view(string_view::make_no_len("canc.bin"))
    if(!bt_write_pattern(src.data(), 512 * 1024)) { env.error("payload"); return }

    var srv = BtServer()
    srv.chunk_delay_ms = 12
    if(!bt_srv_start(&mut srv, root.copy(), bt_port(4u))) { env.error("server"); return }

    var dl = bt_dl_dir()
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()

    var u = bt_url(srv.port, string_view::make_no_len("canc.bin"))
    var uv = string_view::make_view(&u)
    var id = cdm::add_task(&mut dm, uv)

    if(!bt_wait_downloaded_above(&mut dm, &id, 16 * 1024, 10000)) {
        env.error("no progress before cancel")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    cdm::cancel_task(&mut dm, &id)
    if(!bt_wait_state(&mut dm, &id, cdm::STATE_CANCELLED, 5000)) {
        env.error("cancel did not settle to CANCELLED")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    // Runtime must be detached after cancel (worker joined + erased).
    var idx = cdm::find_item_index(&mut dm, &id)
    if(idx == dm.items.size()) { env.error("cancelled item vanished"); return }
    var id_for_rt = dm.items.get_ptr(idx).id.copy()
    var rtpp = dm.runtimes.get_ptr(&id_for_rt)
    if(rtpp != null && *rtpp != null) {
        env.error("runtime not cleaned up after cancel")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }

    bt_srv_stop(&mut srv)
    cdm::shutdown(&mut dm)
    bt_cleanup_dir(dl.data())
    bt_cleanup_dir(root.data())
}

// ─── BT 5: shutdown during download marks interrupted; auto-resume works ─

@test
public func CDM_BT_shutdown_marks_interrupted_and_resumes(env : &mut TestEnv) {
    var root = bt_src_dir(string_view::make_no_len("shut"))
    if(root.empty()) { env.error("src dir"); return }
    var total : i64 = 512 * 1024
    var src = root.copy()
    src.append_view(string_view::make_no_len("kill.bin"))
    if(!bt_write_pattern(src.data(), total)) { env.error("payload"); return }

    var srv = BtServer()
    srv.chunk_delay_ms = 12
    if(!bt_srv_start(&mut srv, root.copy(), bt_port(5u))) { env.error("server"); return }

    var dl = bt_dl_dir()
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    dm.max_segments = 1   // cover single-stream interrupted-resume here

    var u = bt_url(srv.port, string_view::make_no_len("kill.bin"))
    var uv = string_view::make_view(&u)
    var id = cdm::add_task(&mut dm, uv)

    if(!bt_wait_downloaded_above(&mut dm, &id, 32 * 1024, 10000)) {
        env.error("no progress before shutdown")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }

    // Simulate app exit while downloading.
    cdm::shutdown(&mut dm)
    var st = bt_state_of(&mut dm, &id)
    if(st != cdm::STATE_FAILED) {
        env.error("shutdown did not mark item FAILED")
        bt_srv_stop(&mut srv); return
    }
    var snap0 = cdm::snapshot(&mut dm)
    var it0 = snap0.get_ptr(0)
    if(!it0.was_interrupted) { env.error("was_interrupted flag missing"); bt_srv_stop(&mut srv); return }
    if(!it0.error.contains(&string_view::make_no_len("interrupted by shutdown"))) {
        env.error("wrong shutdown error text")
        bt_srv_stop(&mut srv); return
    }
    // Progress must be preserved for the auto-resume to pick up from disk.
    if(it0.downloaded_bytes <= 0) { env.error("progress lost across shutdown"); bt_srv_stop(&mut srv); return }

    // Next launch: poll_auto_resume re-queues interrupted items only.
    var requeued = cdm::poll_auto_resume(&mut dm)
    if(requeued != 1) {
        env.error("poll_auto_resume requeued wrong count")
        bt_srv_stop(&mut srv); return
    }

    // The resumed worker continues from disk and finishes the file.
    if(!bt_wait_terminal(&mut dm, &id, 25000)) {
        env.error("auto-resumed download did not finish")
        bt_srv_stop(&mut srv); return
    }
    if(bt_state_of(&mut dm, &id) != cdm::STATE_DONE) {
        env.error("auto-resume did not complete")
        bt_srv_stop(&mut srv); return
    }
    var snap = cdm::snapshot(&mut dm)
        var lpath_x = snap.get_ptr(0).local_path()
    if(!bt_matches(lpath_x.data(), total)) {
        env.error("auto-resumed output mismatch")
        bt_srv_stop(&mut srv); return
    }

    bt_srv_stop(&mut srv)
    bt_cleanup_dir(dl.data())
    bt_cleanup_dir(root.data())
}

// ─── BT 6: 302 redirect is followed transparently ──────────────────────

@test
public func CDM_BT_redirect_followed(env : &mut TestEnv) {
    var root = bt_src_dir(string_view::make_no_len("redir"))
    if(root.empty()) { env.error("src dir"); return }
    var total : i64 = 192 * 1024
    var src = root.copy()
    src.append_view(string_view::make_no_len("moved.bin"))
    if(!bt_write_pattern(src.data(), total)) { env.error("payload"); return }

    var srv = BtServer()
    srv.do_redirect = true
    if(!bt_srv_start(&mut srv, root.copy(), bt_port(6u))) { env.error("server"); return }

    var dl = bt_dl_dir()
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()

    var u = bt_url(srv.port, string_view::make_no_len("redir/moved.bin"))
    var uv = string_view::make_view(&u)
    var id = cdm::add_task(&mut dm, uv)

    if(!bt_wait_terminal(&mut dm, &id, 15000) || bt_state_of(&mut dm, &id) != cdm::STATE_DONE) {
        env.error("redirected download failed")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    var snap = cdm::snapshot(&mut dm)
        var lpath_x = snap.get_ptr(0).local_path()
    if(!bt_matches(lpath_x.data(), total)) {
        env.error("redirected content mismatch")
        cdm::shutdown(&mut dm); return
    }

    bt_srv_stop(&mut srv)
    cdm::shutdown(&mut dm)
    bt_cleanup_dir(dl.data())
    bt_cleanup_dir(root.data())
}

// ─── BT 7: response without Content-Length streams until EOF ───────────

@test
public func CDM_BT_missing_content_length(env : &mut TestEnv) {
    var root = bt_src_dir(string_view::make_no_len("nocl"))
    if(root.empty()) { env.error("src dir"); return }
    var total : i64 = 160 * 1024
    var src = root.copy()
    src.append_view(string_view::make_no_len("eof.bin"))
    if(!bt_write_pattern(src.data(), total)) { env.error("payload"); return }

    var srv = BtServer()
    srv.ignore_range = true          // else probe's Range gets a 206+CL and size becomes known
    srv.send_content_length = false  // EOF-framed body
    if(!bt_srv_start(&mut srv, root.copy(), bt_port(7u))) { env.error("server"); return }

    var dl = bt_dl_dir()
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()

    var u = bt_url(srv.port, string_view::make_no_len("eof.bin"))
    var uv = string_view::make_view(&u)
    var id = cdm::add_task(&mut dm, uv)

    if(!bt_wait_terminal(&mut dm, &id, 15000) || bt_state_of(&mut dm, &id) != cdm::STATE_DONE) {
        env.error("EOF-framed download failed")
        var snapE = cdm::snapshot(&mut dm)
        env.error("err=")
        env.error(snapE.get_ptr(0).error.data())
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    var snap = cdm::snapshot(&mut dm)
        var lpath_x = snap.get_ptr(0).local_path()
    if(!bt_matches(lpath_x.data(), total)) {
        env.error("EOF-framed content mismatch")
        cdm::shutdown(&mut dm); return
    }

    bt_srv_stop(&mut srv)
    cdm::shutdown(&mut dm)
    bt_cleanup_dir(dl.data())
    bt_cleanup_dir(root.data())
}

// ─── BT 8: server ignoring Range still yields a correct complete file ──

@test
public func CDM_BT_server_ignores_range(env : &mut TestEnv) {
    var root = bt_src_dir(string_view::make_no_len("ignr"))
    if(root.empty()) { env.error("src dir"); return }
    var total : i64 = 384 * 1024
    var src = root.copy()
    src.append_view(string_view::make_no_len("ignr.bin"))
    if(!bt_write_pattern(src.data(), total)) { env.error("payload"); return }

    var srv = BtServer()
    srv.ignore_range = true
    srv.chunk_delay_ms = 10           // leave a window to pause inside
    if(!bt_srv_start(&mut srv, root.copy(), bt_port(8u))) { env.error("server"); return }

    var dl = bt_dl_dir()
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    dm.max_segments = 1

    var u = bt_url(srv.port, string_view::make_no_len("ignr.bin"))
    var uv = string_view::make_view(&u)
    var id = cdm::add_task(&mut dm, uv)

    // Pause mid-stream, then resume. The reconnect will get another 200
    // (server ignores Range) — the engine must reset to 0, truncate, and
    // rewrite instead of appending garbage.
    if(!bt_wait_downloaded_above(&mut dm, &id, 48 * 1024, 10000)) {
        env.error("no progress before pause")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    cdm::pause_task(&mut dm, &id)
    if(!bt_wait_state(&mut dm, &id, cdm::STATE_PAUSED, 5000)) {
        env.error("not paused in time")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    std::concurrent.sleep_ms(200)
    cdm::resume_task(&mut dm, &id)

    if(!bt_wait_terminal(&mut dm, &id, 25000) || bt_state_of(&mut dm, &id) != cdm::STATE_DONE) {
        env.error("range-hostile server download did not complete")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    var snap = cdm::snapshot(&mut dm)
        var lpath_x = snap.get_ptr(0).local_path()
    if(!bt_matches(lpath_x.data(), total)) {
        env.error("output corrupted after 200-on-resume — truncate/reset logic broken")
        cdm::shutdown(&mut dm); return
    }

    bt_srv_stop(&mut srv)
    cdm::shutdown(&mut dm)
    bt_cleanup_dir(dl.data())
    bt_cleanup_dir(root.data())
}

// ─── BT 9: dropped connections are retried and complete ────────────────

@test
public func CDM_BT_connection_drop_retries(env : &mut TestEnv) {
    var root = bt_src_dir(string_view::make_no_len("drop"))
    if(root.empty()) { env.error("src dir"); return }
    var total : i64 = 320 * 1024      // < 512 KB: single stream, no segments
    var src = root.copy()
    src.append_view(string_view::make_no_len("flaky.bin"))
    if(!bt_write_pattern(src.data(), total)) { env.error("payload"); return }

    var srv = BtServer()
    srv.drop_after_bytes = 64 * 1024
    srv.drops_left = 2                // fail the first two body attempts
    if(!bt_srv_start(&mut srv, root.copy(), bt_port(9u))) { env.error("server"); return }

    var dl = bt_dl_dir()
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    dm.max_segments = 1
    dm.retry_policy.max_retries = 5
    dm.retry_policy.delay_ms = 50     // keep the test fast

    var u = bt_url(srv.port, string_view::make_no_len("flaky.bin"))
    var uv = string_view::make_view(&u)
    var id = cdm::add_task(&mut dm, uv)

    if(!bt_wait_terminal(&mut dm, &id, 20000) || bt_state_of(&mut dm, &id) != cdm::STATE_DONE) {
        env.error("download did not survive connection drops")
        var snapE = cdm::snapshot(&mut dm)
        var stx = string()
        stx.append_integer(bt_state_of(&mut dm, &id) as bigint)
        env.error(stx.data())
        env.error(" err=")
        env.error(snapE.get_ptr(0).error.data())
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    if(srv.drops_left != 0) {
        env.error("server never triggered its drops — test invalid")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    var snap = cdm::snapshot(&mut dm)
        var lpath_x = snap.get_ptr(0).local_path()
    if(!bt_matches(lpath_x.data(), total)) {
        env.error("content mismatch after retries — resume offset wrong?")
        cdm::shutdown(&mut dm); return
    }

    bt_srv_stop(&mut srv)
    cdm::shutdown(&mut dm)
    bt_cleanup_dir(dl.data())
    bt_cleanup_dir(root.data())
}

// ─── BT 10: live progress counters behave (the UI depends on this) ─────

@test
public func CDM_BT_progress_counters_monotonic(env : &mut TestEnv) {
    var root = bt_src_dir(string_view::make_no_len("prog"))
    if(root.empty()) { env.error("src dir"); return }
    var total : i64 = 384 * 1024
    var src = root.copy()
    src.append_view(string_view::make_no_len("prog.bin"))
    if(!bt_write_pattern(src.data(), total)) { env.error("payload"); return }

    var srv = BtServer()
    // slow enough that the engine's 500 ms speed sampling window fires
    srv.chunk_delay_ms = 25
    if(!bt_srv_start(&mut srv, root.copy(), bt_port(10u))) { env.error("server"); return }

    var dl = bt_dl_dir()
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()

    var u = bt_url(srv.port, string_view::make_no_len("prog.bin"))
    var uv = string_view::make_view(&u)
    var id = cdm::add_task(&mut dm, uv)

    var prev : i64 = 0
    var saw_running = false
    var observed_speed_gt0 = false
    var monotonic = true
    var deadline = bt_now_ms() + 15000
    var finished = false
    while(bt_now_ms() < deadline && !finished) {
        var d = bt_downloaded_of(&mut dm, &id)
        if(d < prev) { monotonic = false }
        if(d > prev) { prev = d }
        var sp = bt_speed_of(&mut dm, &id)
        if(sp > 0) { observed_speed_gt0 = true }
        if(bt_state_of(&mut dm, &id) == cdm::STATE_DOWNLOADING) { saw_running = true }
        if(d > 0) {
            var t = bt_total_of(&mut dm, &id)
            if(t <= 0) {
                env.error("total_bytes never populated while bytes flowed")
                bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
            }
            if(d > t) {
                env.error("downloaded exceeded total")
                bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
            }
        }
        if(bt_state_of(&mut dm, &id) == cdm::STATE_DONE) { finished = true }
        std::concurrent.sleep_ms(25)
    }
    bt_srv_stop(&mut srv)
    if(!finished) { env.error("timed out waiting for completion"); cdm::shutdown(&mut dm); return }
    if(!saw_running) { env.error("task never entered DOWNLOADING"); cdm::shutdown(&mut dm); return }
    if(!monotonic) { env.error("downloaded_bytes went backwards - UI progress would jump") ; cdm::shutdown(&mut dm); return }
    if(prev != total) { env.error("final sampled progress != payload size"); cdm::shutdown(&mut dm); return }
    if(!observed_speed_gt0) { env.error("speed was never reported above zero"); cdm::shutdown(&mut dm); return }

    cdm::shutdown(&mut dm)
    bt_cleanup_dir(dl.data())
    bt_cleanup_dir(root.data())
}

// NOTE: tool-download progress reporting (yt_install / yt_status flow) is
// tested in the APP suite (tests/bridge_tests.ch) because YtTools lives
// app-side, not in cdmlib.

// ─── BT 11: rapid user actions must never crash or corrupt state ───────

@test
public func CDM_BT_rapid_actions_stress(env : &mut TestEnv) {
    var root = bt_src_dir(string_view::make_no_len("stress"))
    if(root.empty()) { env.error("src dir"); return }
    var src = root.copy()
    src.append_view(string_view::make_no_len("stress.bin"))
    if(!bt_write_pattern(src.data(), 700 * 1024)) { env.error("payload"); return }

    var srv = BtServer()
    srv.chunk_delay_ms = 8
    if(!bt_srv_start(&mut srv, root.copy(), bt_port(12u))) { env.error("server"); return }

    var dl = bt_dl_dir()
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()

    var u = bt_url(srv.port, string_view::make_no_len("stress.bin"))
    var uv = string_view::make_view(&u)
    var id = cdm::add_task(&mut dm, uv)

    // Hammer the action buttons the way an impatient user does, with
    // snapshots interleaved (this is where races/TCC temp bugs crash).
    for(var round = 0; round < 6; round++) {
        cdm::pause_task(&mut dm, &id)
        std::concurrent.sleep_ms(60)
        var junk1 = cdm::snapshot(&mut dm)
        cdm::resume_task(&mut dm, &id)
        std::concurrent.sleep_ms(60)
        var junk2 = cdm::snapshot(&mut dm)
        // edit while running must be rejected, not crash
        var nd = string_view::make_no_len("")
        var ok_edit = cdm::edit_item(&mut dm, &id, nd, nd, 3, 0, 0, 0)
        if(ok_edit) {
            env.error("edit_item succeeded on a RUNNING item")
            bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
        }
    }

    cdm::cancel_task(&mut dm, &id)
    if(!bt_wait_state(&mut dm, &id, cdm::STATE_CANCELLED, 8000)) {
        env.error("stress: cancel did not settle")
        bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    // Queue ops after cancel must work.
    var removed = cdm::clear_finished(&mut dm)
    if(removed != 1) { env.error("clear_finished removed wrong count"); bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return }
    if(dm.items.size() != 0u) { env.error("items left after clear_finished"); bt_srv_stop(&mut srv); cdm::shutdown(&mut dm); return }

    bt_srv_stop(&mut srv)
    cdm::shutdown(&mut dm)
    bt_cleanup_dir(dl.data())
    bt_cleanup_dir(root.data())
}

// ─── BT 12: duplicate naming against real files on disk ────────────────

@test
public func CDM_BT_duplicate_rename_on_disk(env : &mut TestEnv) {
    var dl = bt_dl_dir()
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()

    // Pre-create the exact output file so the rename policy must kick in.
    var existing = dl.copy()
    existing.append_view(string_view::make_no_len("report.pdf"))
    if(!bt_write_pattern(existing.data(), 1024)) { env.error("precreate"); return }

    var u = string::make_no_len("https://127.0.0.1:9/report.pdf")   // unroutable; never runs
    var uv = string_view::make_view(&u)
    var id = cdm::add_task(&mut dm, uv)
    if(id.empty()) { env.error("add failed"); return }

    var idx = cdm::find_item_index(&mut dm, &id)
    if(idx == dm.items.size()) { env.error("item missing"); return }
    var it = dm.items.get_ptr(idx)
    var want_name = string::make_no_len("report (1).pdf")
    if(!it.filename.equals(&want_name)) {
        env.error("duplicate rename produced wrong physical filename: ")
        env.error(it.filename.data())
        cdm::shutdown(&mut dm); bt_cleanup_dir(dl.data()); return
    }
    var got_disp = it.display_filename()
    if(!got_disp.equals(&want_name)) {
        env.error("display name must equal the physical name (no double suffix)")
        cdm::shutdown(&mut dm); bt_cleanup_dir(dl.data()); return
    }
    if(it.duplicate_suffix != 1) { env.error("suffix metadata not recorded"); return }

    cdm::shutdown(&mut dm)
    bt_cleanup_dir(dl.data())
}
