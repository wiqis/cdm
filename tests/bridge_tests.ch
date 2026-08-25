// ChemicalDM — BRIDGE behavior tests.
//
// Drives every user action through the REAL dispatcher (`cdm::bridge_call`,
// the exact function the webview binds), asserting the JSON contract the UI
// depends on: response envelopes, state documents, category routing,
// settings persistence, error paths, and the yt-dlp tool install/progress
// flow. Downloads run against an in-process loopback HTTP server.

using std::string;
using std::string_view;
using std::vector;
using std::Result;
using std::Option;

// ─── tiny loopback server (range + throttle only) ──────────────────────

struct BrServer {
    var listen_sock : net::Socket
    var root : string
    var port : uint
    var running : bool
    var thread : std::concurrent.Thread
    var chunk_delay_ms : int

    @constructor func constructor() {
        return BrServer {
            listen_sock = 0u,
            root = string(),
            port = 0u,
            running = false,
            thread = std::concurrent.Thread{ handle : 0 },
            chunk_delay_ms = 0
        }
    }
}

func br_mkdir(path : *char) : bool {
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

func br_tmp_dir(prefix : string_view) : string {
    var st = std::chrono::SystemTime::now()
    var seed = ((st.as_unix_epoch_nanos() / 1000u) ^ 0xBEEFu) & 0xFFFFFFu
    var dir = string::make_no_len("/tmp/cdm-br-")
    dir.append_with_len(prefix.data(), prefix.size())
    dir.append('-')
    var s = string()
    s.append_uinteger(seed as ubigint)
    dir.append_string(&s)
    dir.append('/')
    if(!br_mkdir(dir.data())) { return string() }
    return dir
}

func br_write_pattern(path : *char, size : i64) : bool {
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

func br_file_size(path : *char) : i64 {
    var f = fopen(path, "rb")
    if(f == null) { return -1 }
    fseek(f, 0, SEEK_END)
    var sz = ftell(f)
    fclose(f)
    return sz as i64
}

func br_itoa(outp : *mut char, bufsz : usize, val : i64) : usize {
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

func br_parse_range(rng : string_view, size : i64, ostart : *mut i64, oend : *mut i64) : int {
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

func br_handle(s : net::Socket, srv : *mut BrServer) {
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

    var path = string()
    var i = 0u
    while(i < head.size() && head.get(i) != ' ') { i = i + 1u }
    i = i + 1u
    while(i < head.size() && head.get(i) != ' ' && head.get(i) != '?') {
        path.append(head.get(i))
        i = i + 1u
    }

    var has_range = false
    var start : i64 = 0
    var end : i64 = 0
    var j = 0u
    var rng = string()
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

    var total_len : i64 = size
    if(has_range) {
        var rc = br_parse_range(string_view::make_view(&rng), size, &raw mut start, &raw mut end)
        if(rc == 0) { total_len = end - start + 1 }
        else if(rc == -2) {
            var m2 = string::make_no_len("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */")
            unsafe var sb : [24]char
            var sl = br_itoa(&raw mut sb[0], 24u, size)
            m2.append_with_len(&raw mut sb[0], sl)
            m2.append_string(&string::make_no_len("\r\nConnection: close\r\n\r\n"))
            net::send_all(s, m2.data() as *char, m2.size() as int)
            fclose(f); net::close_socket(s)
            return
        } else { has_range = false }
    }

    var h = string()
    if(has_range) {
        h.append_string(&string::make_no_len("HTTP/1.1 206 Partial Content\r\nContent-Range: bytes "))
        unsafe var ab : [24]char
        var al = br_itoa(&raw mut ab[0], 24u, start)
        h.append_with_len(&raw mut ab[0], al)
        h.append('-')
        unsafe var bb : [24]char
        var bl = br_itoa(&raw mut bb[0], 24u, end)
        h.append_with_len(&raw mut bb[0], bl)
        h.append('/')
        unsafe var cb : [24]char
        var cl2 = br_itoa(&raw mut cb[0], 24u, size)
        h.append_with_len(&raw mut cb[0], cl2)
    } else {
        h.append_string(&string::make_no_len("HTTP/1.1 200 OK"))
        start = 0
        end = size - 1
        total_len = size
    }
    h.append_string(&string::make_no_len("\r\nContent-Type: application/octet-stream\r\nContent-Length: "))
    unsafe var db : [24]char
    var dl = br_itoa(&raw mut db[0], 24u, total_len)
    h.append_with_len(&raw mut db[0], dl)
    h.append_string(&string::make_no_len("\r\nConnection: close\r\n\r\n"))
    net::send_all(s, h.data() as *char, h.size() as int)

    fseek(f, start as long, SEEK_SET)
    unsafe var payload : [8192u]u8
    var sent : i64 = 0
    while(sent < total_len) {
        var want : usize = 8192u
        if(((total_len - sent) as usize) < want) { want = (total_len - sent) as usize }
        var r = fread(&raw mut payload[0], 1, want, f)
        if(r == 0u) { break }
        net::send_all(s, &raw mut payload[0] as *char, r as int)
        sent = sent + (r as i64)
        if(srv.chunk_delay_ms > 0) {
            std::concurrent.sleep_ms(srv.chunk_delay_ms as ulong)
        }
    }
    fclose(f)
    net::close_socket(s)
}

func br_accept_loop(arg : *void) : *void {
    var srv = arg as *mut BrServer
    while(srv.running) {
        var s = net::accept_socket(srv.listen_sock)
        if(s == 0u || (s as longlong) < 0) {
            if(!srv.running) { break }
            std::concurrent.sleep_ms(5)
            continue
        }
        br_handle(s, srv)
    }
    net::close_socket(srv.listen_sock)
    return null
}

func br_port(offset : uint) : uint {
    var st = std::chrono::SystemTime::now()
    var na = st.as_unix_epoch_nanos()
    var base = (51000i64 + (na / 1000i64) % 20000i64) as uint
    return base + offset
}

func br_srv_start(srv : &mut BrServer, root_copy : string, port : uint) : bool {
    srv.listen_sock = net::listen_addr("127.0.0.1", port)
    if(srv.listen_sock == 0u || (srv.listen_sock as longlong) < 0) { return false }
    srv.root = root_copy.copy()
    srv.port = port
    srv.running = true
    srv.thread = std::concurrent::spawn(br_accept_loop, srv as *void)
    std::concurrent.sleep_ms(50)
    return true
}

func br_srv_stop(srv : &mut BrServer) {
    srv.running = false
    if(srv.listen_sock != 0u) {
        net::close_socket(srv.listen_sock)
        srv.listen_sock = 0u
    }
}

// ─── bridge helpers ────────────────────────────────────────────────────

func br_now_ms() : i64 {
    var st = std::chrono::SystemTime::now()
    return st.as_unix_epoch_nanos() / 1000000
}

// Call a bridge method and return the raw JSON response.
func br_call(dm : *mut cdm::DownloadManager, method : *char, args : &string) : string {
    return cdm::bridge_call(dm, string_view::make_no_len(method), string_view::make_view(args))
}

func br_args_empty() : string {
    return string::make_no_len("{}")
}

// Value of `"key":"value"` inside the item whose id appears first in json.
func br_item_value(state_json : &string, id : &string, key : *char) : string {
    var marker = string::make_no_len("\"id\":\"")
    marker.append_string(id)
    marker.append('"')
    var pos = state_json.find(marker)
    if(pos == std::NPOS) { return string() }
    var khead = string::make_no_len("\"")
    khead.append_view(string_view::make_no_len(key))
    khead.append_string(&string::make_no_len("\":\""))
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

// Poll `state` through the bridge until the item reports the wanted state name.
func br_wait_state(dmp : *mut cdm::DownloadManager, id : &string, want : *char, max_ms : i64) : bool {
    var deadline = br_now_ms() + max_ms
    while(br_now_ms() < deadline) {
        var js = br_call(dmp, "state", br_args_empty())
        var got = br_item_value(&js, id, "state")
        if(got.equals_view(string_view::make_no_len(want))) { return true }
        std::concurrent.sleep_ms(30)
    }
    return false
}

// ─── BR 1: state document shape ────────────────────────────────────────

@test
public func CDM_BR_state_shape(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    var dmp = &raw mut dm
    var js = br_call(dmp, "state", br_args_empty())
    if(!js.contains(&string_view::make_no_len("\"items\":["))) { env.error("items key missing"); return }
    if(!js.contains(&string_view::make_no_len("\"download_dir\":"))) { env.error("download_dir key missing"); return }
    if(!js.contains(&string_view::make_no_len("\"version\":"))) { env.error("version key missing"); return }
    cdm::shutdown(&mut dm)
}

// ─── BR 2: add validation errors ───────────────────────────────────────

@test
public func CDM_BR_add_errors(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    var dmp = &raw mut dm

    var no_url = string::make_no_len("{}")
    var r1 = br_call(dmp, "add", no_url)
    if(!r1.contains(&string_view::make_no_len("\"ok\":false"))) { env.error("missing url must error"); return }

    var bad = string::make_no_len("{\"url\":\"notaurl\"}")
    var r2 = br_call(dmp, "add", bad)
    // invalid scheme must be rejected by validation
    if(!r2.contains(&string_view::make_no_len("\"ok\":false"))) { env.error("invalid url must error"); return }
    cdm::shutdown(&mut dm)
}

// ─── BR 3: add succeeds, appears in state, category routing + tag ──────

@test
public func CDM_BR_add_and_category(env : &mut TestEnv) {
    var dl = br_tmp_dir(string_view::make_no_len("cat"))
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    var dmp = &raw mut dm

    var a1 = string::make_no_len("{\"url\":\"https://127.0.0.1:9/doc.pdf\"}")
    var r1 = br_call(dmp, "add", a1)
    if(!r1.contains(&string_view::make_no_len("\"ok\":true"))) { env.error("add doc failed"); return }
    if(!r1.contains(&string_view::make_no_len("\"id\":\""))) { env.error("no id in add response"); return }

    var snap = cdm::snapshot(&mut dm)
    if(snap.size() != 1u) { env.error("expected exactly one item"); return }
    var it = snap.get_ptr(0)

    // Category routing: Documents subfolder under the root.
    var want_dir = dl.copy()
    want_dir.append_view(string_view::make_no_len("Documents"))
    if(!it.dir.equals(&want_dir)) {
        env.error("Documents routing wrong, dir=")
        env.error(it.dir.data())
        cdm::shutdown(&mut dm); return
    }
    // Opaque tag stored so the UI can filter/display it (Documents = 1).
    if(it.category != 1) { env.error("category tag not persisted on item"); return }

    // Second download without a category stays in the root with tag 0.
    var a2 = string::make_no_len("{\"url\":\"https://127.0.0.1:9/plain.bin\"}")
    var r2 = br_call(dmp, "add", a2)
    if(!r2.contains(&string_view::make_no_len("\"ok\":true"))) { env.error("add plain failed"); return }
    var snap2 = cdm::snapshot(&mut dm)
    var it2 = snap2.get_ptr(1)
    if(!it2.dir.equals(&dl)) { env.error("uncategorized must stay in root"); return }
    if(it2.category != 0) { env.error("plain tag must be 0"); return }

    // State JSON exposes the human category name.
    var js = br_call(dmp, "state", br_args_empty())
    var some_id = snap2.get_ptr(0).id.copy()
    var cat_name = br_item_value(&js, &some_id, "category")
    if(!cat_name.equals_view(string_view::make_no_len("Documents"))) { env.error("state category name wrong"); return }

    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(dl.data())
}

// ─── BR 4: full user flow — add, done, restart, remove vs remove_file ──

@test
public func CDM_BR_lifecycle_actions(env : &mut TestEnv) {
    var root = br_tmp_dir(string_view::make_no_len("lc-src"))
    var src = root.copy()
    src.append_view(string_view::make_no_len("life.bin"))
    if(!br_write_pattern(src.data(), 128 * 1024)) { env.error("payload"); return }

    var srv = BrServer()
    if(!br_srv_start(&mut srv, root.copy(), br_port(1u))) { env.error("server"); return }

    var dl = br_tmp_dir(string_view::make_no_len("lc-dl"))
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    var dmp = &raw mut dm

    var u = string::make_no_len("http://127.0.0.1:")
    u.append_uinteger(srv.port as ubigint)
    u.append_view(string_view::make_no_len("/life.bin"))
    var body = string::make_no_len("{\"url\":")
    var esc_u = u.copy()
    body.append('"')
    body.append_string(&esc_u)
    body.append("\"}")
    var r = br_call(dmp, "add", body)
    if(!r.contains(&string_view::make_no_len("\"ok\":true"))) { env.error("bridge add failed"); br_srv_stop(&mut srv); return }

    // extract id from the add response
    var idpos = r.find(string_view::make_no_len("\"id\":\"\""))
    var id_start = r.find(string_view::make_no_len("\"id\":\""))
    if(id_start == std::NPOS) { env.error("no id"); br_srv_stop(&mut srv); return }
    var s0 = id_start + 6u
    var e0 = s0
    while(e0 < r.size() && r.get(e0) != '"') { e0 = e0 + 1u }
    var id = r.substring(s0, e0)

    if(!br_wait_state(dmp, &id, "Done", 20000)) {
        env.error("bridge-driven download never reached Done")
        br_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }

    // restart re-downloads from scratch
    var rb = string::make_no_len("{\"id\":\"")
    rb.append_string(&id)
    rb.append("\"}")
    var rr = br_call(dmp, "restart", rb)
    if(!rr.contains(&string_view::make_no_len("\"ok\":true"))) { env.error("restart rejected"); br_srv_stop(&mut srv); return }
    if(!br_wait_state(dmp, &id, "Done", 20000)) {
        env.error("restart did not complete")
        br_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }

    // locate output path before removal checks
    var snap = cdm::snapshot(&mut dm)
    var lpath = snap.get_ptr(0).local_path().copy()
    if(br_file_size(lpath.data()) != 128 * 1024) {
        env.error("output wrong size after bridge flow")
        br_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }

    // `remove` keeps the file on disk
    var rm = br_call(dmp, "remove", rb)
    if(!rm.contains(&string_view::make_no_len("\"ok\":true"))) { env.error("remove failed"); br_srv_stop(&mut srv); return }
    var snap_after = cdm::snapshot(&mut dm)
    if(snap_after.size() != 0u) { env.error("item not removed from queue"); br_srv_stop(&mut srv); return }
    if(!fs::exists(lpath.data())) {
        env.error("remove deleted the file — should keep it")
        br_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }

    // re-add, then `remove_file` deletes both queue entry and file
    var r2 = br_call(dmp, "add", body)
    if(!r2.contains(&string_view::make_no_len("\"ok\":true"))) { env.error("re-add failed"); br_srv_stop(&mut srv); return }
    var id_start2 = r2.find(string_view::make_no_len("\"id\":\""))
    var s2 = id_start2 + 6u
    var e2 = s2
    while(e2 < r2.size() && r2.get(e2) != '"') { e2 = e2 + 1u }
    var id2 = r2.substring(s2, e2)
    if(!br_wait_state(dmp, &id2, "Done", 20000)) {
        env.error("second download did not finish (duplicate rename?)")
        br_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    // duplicate policy renamed it to life (1).bin
    var snap2 = cdm::snapshot(&mut dm)
    var lpath2 = snap2.get_ptr(0).local_path().copy()
    var want2 = dl.copy()
    want2.append_view(string_view::make_no_len("life (1).bin"))
    if(!lpath2.equals(&want2)) {
        env.error("duplicate rename wrong: ")
        env.error(lpath2.data())
        br_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    var rf = br_call(dmp, "remove_file", rb)
    if(!rf.contains(&string_view::make_no_len("\"ok\":true"))) { env.error("remove_file failed"); br_srv_stop(&mut srv); return }
    if(fs::exists(want2.data())) {
        env.error("remove_file did not delete the file")
        br_srv_stop(&mut srv); cdm::shutdown(&mut dm); return
    }
    var snap3 = cdm::snapshot(&mut dm)
    if(snap3.size() != 0u) { env.error("queue not empty after remove_file"); br_srv_stop(&mut srv); return }

    br_srv_stop(&mut srv)
    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(dl.data())
    fs::remove_dir_all_recursive(root.data())
}

// ─── BR 5: pause / resume / cancel through the bridge ──────────────────

@test
public func CDM_BR_pause_resume_cancel(env : &mut TestEnv) {
    var root = br_tmp_dir(string_view::make_no_len("prc-src"))
    var src = root.copy()
    src.append_view(string_view::make_no_len("prc.bin"))
    if(!br_write_pattern(src.data(), 512 * 1024)) { env.error("payload"); return }

    var srv = BrServer()
    srv.chunk_delay_ms = 12
    if(!br_srv_start(&mut srv, root.copy(), br_port(2u))) { env.error("server"); return }

    var dl = br_tmp_dir(string_view::make_no_len("prc-dl"))
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    dm.max_segments = 1
    var dmp = &raw mut dm

    var u = string::make_no_len("http://127.0.0.1:")
    u.append_uinteger(srv.port as ubigint)
    u.append_view(string_view::make_no_len("/prc.bin"))
    var body = string::make_no_len("{\"url\":\"")
    body.append_string(&u)
    body.append("\"}")
    var r = br_call(dmp, "add", body)
    var ids = r.find(string_view::make_no_len("\"id\":\""))
    var id = r.substring(ids + 6u, r.size())

    // let it make progress, then pause through the bridge
    var deadline = br_now_ms() + 10000
    var flowing = false
    while(br_now_ms() < deadline) {
        var js = br_call(dmp, "state", br_args_empty())
        var db = br_item_value(&js, &id, "percent")
        if(!db.empty()) {
            // any nonzero percent means bytes flowed
            if(!db.equals_view(string_view::make_no_len("0.0")) && !db.equals_view(string_view::make_no_len("0"))) { flowing = true }
        }
        if(flowing) { break }
        std::concurrent.sleep_ms(30)
    }
    if(!flowing) { env.error("no visible percent progress"); br_srv_stop(&mut srv); return }

    var pb = string::make_no_len("{\"id\":\"")
    pb.append_string(&id)
    pb.append("\"}")
    var pr = br_call(dmp, "pause", pb)
    if(!pr.contains(&string_view::make_no_len("\"ok\":true"))) { env.error("pause failed"); br_srv_stop(&mut srv); return }
    if(!br_wait_state(dmp, &id, "Paused", 5000)) {
        env.error("bridge pause did not settle")
        br_srv_stop(&mut srv); return
    }

    var rr2 = br_call(dmp, "resume", pb)
    if(!rr2.contains(&string_view::make_no_len("\"ok\":true"))) { env.error("resume failed"); br_srv_stop(&mut srv); return }
    if(!br_wait_state(dmp, &id, "Downloading", 8000)) {
        env.error("bridge resume did not restart")
        br_srv_stop(&mut srv); return
    }

    var cr = br_call(dmp, "cancel", pb)
    if(!cr.contains(&string_view::make_no_len("\"ok\":true"))) { env.error("cancel failed"); br_srv_stop(&mut srv); return }
    if(!br_wait_state(dmp, &id, "Cancelled", 5000)) {
        env.error("bridge cancel did not settle")
        br_srv_stop(&mut srv); return
    }

    br_srv_stop(&mut srv)
    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(dl.data())
    fs::remove_dir_all_recursive(root.data())
}

// ─── BR 6: edit rules — rejected while running, applied when idle ─────

@test
public func CDM_BR_edit_rules(env : &mut TestEnv) {
    var root = br_tmp_dir(string_view::make_no_len("ed-src"))
    var src = root.copy()
    src.append_view(string_view::make_no_len("ed.bin"))
    if(!br_write_pattern(src.data(), 400 * 1024)) { env.error("payload"); return }

    var srv = BrServer()
    srv.chunk_delay_ms = 15
    if(!br_srv_start(&mut srv, root.copy(), br_port(3u))) { env.error("server"); return }

    var dl = br_tmp_dir(string_view::make_no_len("ed-dl"))
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    dm.max_segments = 1
    var dmp = &raw mut dm

    var u = string::make_no_len("{\"url\":\"http://127.0.0.1:")
    u.append_uinteger(srv.port as ubigint)
    u.append_view(string_view::make_no_len("/ed.bin\"}"))
    var r = br_call(dmp, "add", u)
    var ipos = r.find(string_view::make_no_len("\"id\":\""))
    var id = r.substring(ipos + 6u, r.size())

    // wait until actually running, then try to edit
    if(!br_wait_state(dmp, &id, "Downloading", 10000)) {
        env.error("never started downloading")
        br_srv_stop(&mut srv); return
    }
    var eb = string::make_no_len("{\"id\":\"")
    eb.append_string(&id)
    eb.append_string(&string::make_no_len("\",\"priority\":5}"))
    var er = br_call(dmp, "edit", eb)
    if(!er.contains(&string_view::make_no_len("\"ok\":false"))) {
        env.error("edit on RUNNING item must be rejected")
        br_srv_stop(&mut srv); return
    }

    // stop it, then editing must succeed
    var cb = string::make_no_len("{\"id\":\"")
    cb.append_string(&id)
    cb.append("\"}")
    br_call(dmp, "cancel", cb)
    br_wait_state(dmp, &id, "Cancelled", 5000)
    var er2 = br_call(dmp, "edit", eb)
    if(!er2.contains(&string_view::make_no_len("\"ok\":true"))) {
        env.error("edit on idle item must succeed")
        br_srv_stop(&mut srv); return
    }
    var idx = cdm::find_item_index(&mut dm, &id)
    if(idx == dm.items.size()) { env.error("item lost"); br_srv_stop(&mut srv); return }
    if(dm.items.get_ptr(idx).priority != 5) { env.error("edited priority not applied"); return }

    br_srv_stop(&mut srv)
    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(dl.data())
    fs::remove_dir_all_recursive(root.data())
}

// ─── BR 7: change_url resets progress and stores the new URL ───────────

@test
public func CDM_BR_change_url(env : &mut TestEnv) {
    var dl = br_tmp_dir(string_view::make_no_len("cu"))
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    var dmp = &raw mut dm

    var a = string::make_no_len("{\"url\":\"https://127.0.0.1:9/old.bin\"}")
    var r = br_call(dmp, "add", a)
    var ipos = r.find(string_view::make_no_len("\"id\":\""))
    var id = r.substring(ipos + 6u, r.size())

    // detach the runtime so the URL becomes editable, fake some progress
    var cb = string::make_no_len("{\"id\":\"")
    cb.append_string(&id)
    cb.append("\"}")
    br_call(dmp, "cancel", cb)

    var idx = cdm::find_item_index(&mut dm, &id)
    if(idx == dm.items.size()) { env.error("item missing"); return }
    dm.items.get_ptr(idx).downloaded_bytes = 4096
    dm.items.get_ptr(idx).total_bytes = 8192

    var cu = string::make_no_len("{\"id\":\"")
    cu.append_string(&id)
    cu.append_string(&string::make_no_len("\",\"url\":\"https://example.org/new.bin\"}"))
    var cr = br_call(dmp, "change_url", cu)
    if(!cr.contains(&string_view::make_no_len("\"ok\":true"))) { env.error("change_url rejected"); return }

    var snap = cdm::snapshot(&mut dm)
    var it = snap.get_ptr(0)
    if(it.downloaded_bytes != 0) { env.error("progress not reset by change_url"); return }
    if(!it.url.contains(string_view::make_no_len("new.bin"))) { env.error("new url not stored"); return }
    var st = it.state
    if(st != cdm::STATE_QUEUED) { env.error("change_url must requeue"); return }

    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(dl.data())
}

// ─── BR 8: retry a failed download through the bridge ──────────────────

@test
public func CDM_BR_retry_failed(env : &mut TestEnv) {
    var dl = br_tmp_dir(string_view::make_no_len("rt"))
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    dm.retry_policy.max_retries = 0   // fail fast (unroutable target)
    dm.retry_policy.delay_ms = 5
    var dmp = &raw mut dm

    var a = string::make_no_len("{\"url\":\"https://127.0.0.1:9/nope.bin\"}")
    var r = br_call(dmp, "add", a)
    var ipos = r.find(string_view::make_no_len("\"id\":\""))
    var id = r.substring(ipos + 6u, r.size())

    if(!br_wait_state(dmp, &id, "Failed", 15000)) {
        env.error("unroutable download did not fail fast")
        return
    }

    var rb = string::make_no_len("{\"id\":\"")
    rb.append_string(&id)
    rb.append("\"}")
    var rr = br_call(dmp, "retry", rb)
    if(!rr.contains(&string_view::make_no_len("\"ok\":true"))) { env.error("retry rejected"); return }

    var idx = cdm::find_item_index(&mut dm, &id)
    if(idx == dm.items.size()) { env.error("item vanished after retry"); return }
    var it = dm.items.get_ptr(idx)
    if(it.retry_count != 1) { env.error("retry_count not bumped"); return }
    if(it.state != cdm::STATE_QUEUED && it.state != cdm::STATE_DOWNLOADING) {
        env.error("retry did not requeue")
        return
    }

    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(dl.data())
}

// ─── BR 9: settings_set persists and settings_get reflects ─────────────

@test
public func CDM_BR_settings_roundtrip(env : &mut TestEnv) {
    var cfg = br_tmp_dir(string_view::make_no_len("cfg"))
    var dl = br_tmp_dir(string_view::make_no_len("setdl"))
    environment::set(string_view::make_no_len("CDM_CONFIG_DIR"), string_view::make_view(&cfg))

    var dm = cdm::DownloadManager()
    var dmp = &raw mut dm

    var body = string::make_no_len("{\"max_concurrent\":7,\"speed_limit_kbps\":256,\"duplicate_action\":2,\"enable_resume\":false,\"auto_resume_failed\":true,\"max_retries\":9,\"retry_delay_ms\":2500}")
    var sr = br_call(dmp, "settings_set", body)
    if(!sr.contains(&string_view::make_no_len("\"ok\":true"))) { env.error("settings_set failed"); environment::unset(string_view::make_no_len("CDM_CONFIG_DIR")); return }

    // persisted to disk in the sandboxed config dir?
    var s = cdm::CdmSettings()
    if(!cdm::load_settings(&raw mut s)) { env.error("settings not persisted"); environment::unset(string_view::make_no_len("CDM_CONFIG_DIR")); return }
    if(s.max_concurrent != 7) { env.error("concurrent not saved"); return }
    if(s.speed_limit_kbps != 256) { env.error("speed not saved"); return }
    if(s.duplicate_action != 2) { env.error("duplicate_action not saved"); return }
    if(s.enable_resume != false) { env.error("enable_resume not saved"); return }
    if(s.auto_resume_failed != true) { env.error("auto_resume not saved"); return }
    if(s.max_retries != 9) { env.error("max_retries not saved"); return }
    if(s.retry_delay_ms != 2500) { env.error("retry_delay not saved"); return }

    // and the getter returns them for the UI
    var gj = br_call(dmp, "settings_get", br_args_empty())
    if(!gj.contains(&string_view::make_no_len("\"max_concurrent\":7"))) { env.error("get concurrent"); return }
    if(!gj.contains(&string_view::make_no_len("\"duplicate_action\":2"))) { env.error("get dup"); return }
    if(!gj.contains(&string_view::make_no_len("\"max_retries\":9"))) { env.error("get retries"); return }

    environment::unset(string_view::make_no_len("CDM_CONFIG_DIR"))
    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(cfg.data())
    fs::remove_dir_all_recursive(dl.data())
}

// ─── BR 10: error paths every dialog relies on ─────────────────────────

@test
public func CDM_BR_error_paths(env : &mut TestEnv) {
    var dl = br_tmp_dir(string_view::make_no_len("err"))
    var dm = cdm::DownloadManager()
    var dmp = &raw mut dm

    var r1 = br_call(dmp, "definitely_not_a_method", br_args_empty())
    if(!r1.contains(&string_view::make_no_len("unknown method"))) { env.error("unknown method msg"); return }

    var r2 = br_call(dmp, "edit", br_args_empty())
    if(!r2.contains(&string_view::make_no_len("\"ok\":false"))) { env.error("edit w/o id must fail"); return }

    var r3 = br_call(dmp, "change_url", br_args_empty())
    if(!r3.contains(&string_view::make_no_len("\"ok\":false"))) { env.error("change_url w/o fields must fail"); return }

    var r4 = br_call(dmp, "open_file", br_args_empty())
    if(!r4.contains(&string_view::make_no_len("\"ok\":false"))) { env.error("open_file w/o path must fail"); return }

    var r5 = br_call(dmp, "pause", br_args_empty())
    // pause with no id is a no-op success (UI treats it as fire-and-forget)
    if(!r5.contains(&string_view::make_no_len("\"ok\":true"))) { env.error("pause w/o id should be benign"); return }

    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(dl.data())
}

// ─── BR 11: yt_status shape + yt_install guards ────────────────────────

@test
public func CDM_BR_yt_status_and_install_guards(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    var dmp = &raw mut dm

    var js = br_call(dmp, "yt_status", br_args_empty())
    if(!js.contains(&string_view::make_no_len("\"yt_dlp\""))) { env.error("yt_dlp key"); return }
    if(!js.contains(&string_view::make_no_len("\"ffmpeg\""))) { env.error("ffmpeg key"); return }
    if(!js.contains(&string_view::make_no_len("\"both_ready\""))) { env.error("both_ready key"); return }

    var i1 = br_call(dmp, "yt_install", br_args_empty())
    if(!i1.contains(&string_view::make_no_len("\"ok\":false"))) { env.error("install w/o tool must fail"); return }

    var bad_tool = string::make_no_len("{\"tool\":\"wget\"}")
    var i2 = br_call(dmp, "yt_install", bad_tool)
    if(!i2.contains(&string_view::make_no_len("unknown tool"))) { env.error("unknown tool msg"); return }

    cdm::shutdown(&mut dm)
}

// ─── BR 12: bridge accepts array-wrapped args (webview JS shape) ───────

@test
public func CDM_BR_array_wrapped_args(env : &mut TestEnv) {
    var dl = br_tmp_dir(string_view::make_no_len("wrap"))
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    var dmp = &raw mut dm

    var wrapped = string::make_no_len("[{\"url\":\"https://127.0.0.1:9/wrapped.bin\"}]")
    var r = br_call(dmp, "add", wrapped)
    if(!r.contains(&string_view::make_no_len("\"ok\":true"))) {
        env.error("array-wrapped args not unwrapped by resolve_bridge_args")
        cdm::shutdown(&mut dm); return
    }
    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(dl.data())
}

// ─── BR 13: tool install progress reporting through yt_status ──────────
//
// Reproduces the exact yt_install → poll yt_status loop the GUI uses and
// asserts progress is reported above zero while bytes flow (the bug users
// saw: progress stuck at zero / status never flipping to installed).

@test
public func CDM_BR_tool_download_progress(env : &mut TestEnv) {
    var tools = br_tmp_dir(string_view::make_no_len("tools"))
    environment::set(string_view::make_no_len("CDM_TOOLS_DIR"), string_view::make_view(&tools))

    var root = br_tmp_dir(string_view::make_no_len("tool-src"))
    var src = root.copy()
    src.append_view(string_view::make_no_len("yt-dlp"))
    if(!br_write_pattern(src.data(), 320 * 1024)) { env.error("payload"); return }

    var srv = BrServer()
    srv.chunk_delay_ms = 25   // ~1s transfer so progress windows are observable
    if(!br_srv_start(&mut srv, root.copy(), br_port(4u))) { env.error("server"); return }

    var dl = br_tmp_dir(string_view::make_no_len("tool-dl"))
    var dm = cdm::DownloadManager()
    dm.download_dir = dl.copy()
    var dmp = &raw mut dm

    // Queue exactly like ytdlp_download_async does.
    var u = string::make_no_len("http://127.0.0.1:")
    u.append_uinteger(srv.port as ubigint)
    u.append_view(string_view::make_no_len("/yt-dlp"))
    var tv = string_view::make_view(&tools)
    var fname = string::make_no_len("yt-dlp")
    var fv = string_view::make_view(&fname)
    var uv = string_view::make_view(&u)
    var id = cdm::add_task_ex(&mut dm, uv, tv, fv, 100, 0)
    if(id.empty()) { env.error("tool task not queued"); br_srv_stop(&mut srv); return }

    // Register in the tracking globals like store_task_id().
    cdm::g_tool_dl_status = 1
    cdm::g_tool_dl_progress = 0.0
    var len : usize = 127u
    if(id.size() < len) { len = id.size() }
    for(var i = 0u; i < len; i++) {
        cdm::g_tool_dl_task_id[i] = id.get(i) as char
    }
    cdm::g_tool_dl_task_id[len] = '\0' as char
    cdm::g_tool_dl_task_id_len = len as int

    // Poll yt_status through the bridge while downloading.
    var saw_downloading = false
    var saw_progress = false
    var deadline = br_now_ms() + 20000
    while(br_now_ms() < deadline) {
        var js = br_call(dmp, "yt_status", br_args_empty())
        if(js.contains(&string_view::make_no_len("\"status\":\"downloading\""))) {
            saw_downloading = true
            var ppos = js.find(string_view::make_no_len("\"progress\":"))
            if(ppos != std::NPOS) {
                var num = string()
                var q = ppos + 11u
                while(q < js.size() && js.get(q) != ',' && js.get(q) != '}') {
                    num.append(js.get(q))
                    q = q + 1u
                }
                if(!num.empty() && !num.equals_view(string_view::make_no_len("0")) &&
                   !num.equals_view(string_view::make_no_len("0.0"))) {
                    saw_progress = true
                }
            }
        }
        if(cdm::tool_download_in_progress() == false) { break }
        std::concurrent.sleep_ms(50)
    }

    var failed = false
    if(!saw_downloading) { env.error("yt_status never showed 'downloading' during transfer"); failed = true }
    if(!failed && !saw_progress) {
        env.error("tool progress stayed at 0 while bytes were flowing (the reported bug)")
        failed = true
    }

    // Completion: status flips to installed, queue entry is cleaned up,
    // binary exists in the tools dir.
    if(!failed) {
        if(!br_wait_state(dmp, &id, "Done", 20000)) {
            env.error("tool download never finished"); failed = true
        }
    }
    if(!failed) {
        var settled = false
        deadline = br_now_ms() + 5000
        while(br_now_ms() < deadline) {
            var js2 = br_call(dmp, "yt_status", br_args_empty())
            if(js2.contains(&string_view::make_no_len("\"status\":\"installed\""))) { settled = true; break }
            std::concurrent.sleep_ms(50)
        }
        if(!settled) { env.error("tool never reported installed after completion"); failed = true }
    }
    if(!failed && dm.items.size() != 0u) { env.error("finished tool task left in queue"); failed = true }
    if(!failed) {
        var binp = tools.copy()
        binp.append('/')
        binp.append_view(string_view::make_no_len("yt-dlp"))
        if(!fs::exists(binp.data())) { env.error("binary missing in tools dir"); failed = true }
    }

    br_srv_stop(&mut srv)
    environment::unset(string_view::make_no_len("CDM_TOOLS_DIR"))
    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(tools.data())
    fs::remove_dir_all_recursive(dl.data())
    fs::remove_dir_all_recursive(root.data())
    if(failed) { return }
}
