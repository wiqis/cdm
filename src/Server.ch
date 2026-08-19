using std::string;

public namespace server {

using net::Socket;

public struct HttpServer {
    var port : int
    var listen_sock : net::Socket
    var running : bool
    var dm : download::DownloadManager
}

public func find_free_port() : int {
    return 18080
}

public func start_server(ctx : *mut void) : *void {
    var srv = ctx as *mut HttpServer
    srv.running = true

    while(srv.running) {
        var client = net::accept_socket(srv.listen_sock)
        if(client == 0 as net::Socket) {
            continue
        }
        handle_client(client, srv)
    }
    return null as *void
}

func handle_client(client : net::Socket, srv : *mut HttpServer) {
    var buf : [16384]u8
    var n = net::recv_all(client, &raw mut buf[0], 16383)
    if(n <= 0) {
        net::close_socket(client)
        return
    }
    buf[n] = 0 as u8

    var method_end = 0
    while(method_end < n && buf[method_end] != ' ' as u8) { method_end = method_end + 1 }

    var method_buf : [8]char
    var mi = 0
    while(mi < method_end && mi < 7) {
        method_buf[mi] = buf[mi] as char
        mi = mi + 1
    }
    method_buf[mi] = '\0'
    var is_post = (mi == 4 && method_buf[0] == 'P' && method_buf[1] == 'O' && method_buf[2] == 'S' && method_buf[3] == 'T')

    var path_start = method_end + 1
    var path_end = path_start
    while(path_end < n && buf[path_end] != ' ' as u8 && buf[path_end] != '?' as u8) { path_end = path_end + 1 }

    var path_buf : [256]char
    var path_len = path_end - path_start
    if(path_len > 255) { path_len = 255 }
    var pi = 0
    while(pi < path_len) {
        path_buf[pi] = buf[path_start + pi] as char
        pi = pi + 1
    }
    path_buf[path_len] = '\0'

    var body : string = string()
    if(is_post) {
        var header_end = find_body_start(&raw buf[0] as *char, n)
        if(header_end > 0) {
            var body_start = header_end + 4
            var body_len = n - body_start
            var bi = 0
            while(bi < body_len) {
                body.append(buf[body_start + bi] as char)
                bi = bi + 1
            }
        }
    }

    var is_api = false
    if(path_len >= 4) {
        if(path_buf[0] == '/' as char && path_buf[1] == 'a' as char && path_buf[2] == 'p' as char && path_buf[3] == 'i' as char) {
            is_api = true
        }
    }

    if(is_api) {
        handle_api(client, srv, &raw path_buf[0], path_len, is_post, &raw body)
    } else {
        serve_index(client)
    }

    net::close_socket(client)
}

func handle_api(client : net::Socket, srv : *mut HttpServer, path : *char, path_len : int, is_post : bool, body : *string) {
    var resp_body = string("null")

    if(path_len == 15 && !is_post && starts_with(path, path_len, "/api/downloads")) {
        resp_body = download::dm_get_all_json(&raw mut srv.dm)
    } else if(path_len >= 16 && is_post && starts_with(path, path_len, "/api/downloads/new")) {
        var url_val = extract_json_string(body, "url")
        var name_val = extract_json_string(body, "filename")
        var folder_val = extract_json_string(body, "folder")
        if(url_val.size() > 0) {
            if(name_val.size() == 0) {
                name_val = url_to_filename(&raw url_val)
            }
            if(folder_val.size() == 0) {
                folder_val = string("~/Downloads")
            }
            var id = download::dm_add(&raw mut srv.dm, &url_val, &name_val, &folder_val)
            resp_body = string("{\"id\":")
            resp_body.append_integer(id)
            resp_body.append_view(",\"status\":\"queued\"}")
        } else {
            resp_body = string("{\"error\":\"URL is required\"}")
        }
    } else if(path_len >= 21 && is_post && starts_with(path, path_len, "/api/downloads/pause/")) {
        var id = extract_id_from_path(path, path_len, 21)
        download::dm_pause(&raw mut srv.dm, id)
        resp_body = string("{\"ok\":true}")
    } else if(path_len >= 22 && is_post && starts_with(path, path_len, "/api/downloads/resume/")) {
        var id = extract_id_from_path(path, path_len, 22)
        download::dm_resume(&raw mut srv.dm, id)
        resp_body = string("{\"ok\":true}")
    } else if(path_len >= 22 && is_post && starts_with(path, path_len, "/api/downloads/cancel/")) {
        var id = extract_id_from_path(path, path_len, 22)
        download::dm_cancel(&raw mut srv.dm, id)
        resp_body = string("{\"ok\":true}")
    }

    var resp = string("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: ")
    var len_str = int_to_str(resp_body.size() as int)
    resp.append_string(&len_str)
    resp.append_view("\r\nConnection: close\r\n\r\n")
    resp.append_string(&resp_body)
    net::send_all(client, resp.data(), resp.size() as int)
}

func serve_index(client : net::Socket) {
    var html = get_index_html()
    var resp = string("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: ")
    var len_str = int_to_str(html.size() as int)
    resp.append_string(&len_str)
    resp.append_view("\r\nConnection: close\r\n\r\n")
    resp.append_string(&html)
    net::send_all(client, resp.data(), resp.size() as int)
}

func find_body_start(buf : *char, len : int) : int {
    var i = 0
    while(i < len - 3) {
        if(buf[i] == '\r' && buf[i + 1] == '\n' && buf[i + 2] == '\r' && buf[i + 3] == '\n') {
            return i
        }
        i = i + 1
    }
    return -1
}

func starts_with(path : *char, path_len : int, prefix : *char) : bool {
    var i = 0
    var plen = 0
    while(prefix[plen] != '\0') { plen = plen + 1 }
    if(path_len < plen) { return false }
    while(i < plen) {
        if(path[i] != prefix[i]) { return false }
        i = i + 1
    }
    return true
}

func extract_id_from_path(path : *char, path_len : int, prefix_len : int) : i64 {
    var val : i64 = 0
    var i = prefix_len
    while(i < path_len && path[i] >= '0' && path[i] <= '9') {
        val = val * 10 + (path[i] - '0') as i64
        i = i + 1
    }
    return val
}

func extract_json_string(json : *string, key : *char) : string {
    var result = string()
    var needle = string("\"")
    var ki = 0
    while(key[ki] != '\0') {
        needle.append(key[ki] as char)
        ki = ki + 1
    }
    needle.append_view("\":\"")

    var found_at = -1
    var i = 0
    while(i < json.size() as int - needle.size() as int) {
        var match = true
        var j = 0
        while(j < needle.size() as int) {
            if(json.get(i as size_t + j as size_t) != needle.get(j as size_t)) { match = false; break }
            j = j + 1
        }
        if(match) { found_at = i + needle.size(); break }
        i = i + 1
    }

    if(found_at < 0) { return result }

    var pos = found_at
    while(pos < json.size() as int) {
        var c = json.get(pos as size_t)
        if(c == '"') { break }
        if(c == '\\' as char && pos + 1 < json.size() as int) {
            pos = pos + 1
            var next = json.get(pos as size_t)
            if(next == 'n') { result.append('\n') }
            else if(next == 't') { result.append('\t') }
            else if(next == '\\') { result.append('\\') }
            else { result.append(next) }
        } else {
            result.append(c)
        }
        pos = pos + 1
    }
    return result
}

func url_to_filename(url : *string) : string {
    var result = string()
    var last_slash = -1
    var i = 0
    while(i < url.size() as int) {
        if(url.get(i as size_t) == '/') { last_slash = i }
        i = i + 1
    }
    if(last_slash >= 0 && last_slash + 1 < url.size() as int) {
        var j = last_slash + 1
        while(j < url.size() as int) {
            result.append(url.get(j as size_t))
            j = j + 1
        }
    } else {
        result = string("download")
    }
    if(result.size() == 0) { result = string("download") }
    return result
}

func parse_i64_from_cstr(s : *char, len : int) : i64 {
    var val : i64 = 0
    var i = 0
    while(i < len && s[i] >= '0' && s[i] <= '9') {
        val = val * 10 + (s[i] - '0') as i64
        i = i + 1
    }
    return val
}

func int_to_str(val : int) : string {
    var s = string()
    if(val == 0) {
        s.append('0')
        return s
    }
    var tmp : [16]char
    var v = val
    var cnt = 0
    while(v > 0) {
        tmp[cnt] = (v % 10 + '0') as char
        v = v / 10
        cnt = cnt + 1
    }
    var i = cnt - 1
    while(i >= 0) {
        s.append(tmp[i])
        i = i - 1
    }
    return s
}

func get_index_html() : string {
    var h = string("<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'>")
    h.append_view("<meta name='viewport' content='width=device-width,initial-scale=1'>")
    h.append_view("<title>ChemicalDM</title><style>")
    h.append_view("*{margin:0;padding:0;box-sizing:border-box}")
    h.append_view(":root{--bg:#09090b;--bg-card:#18181b;--bg-hover:#27272a;--bg-sidebar:#0f0f12;")
    h.append_view("--fg:#fafafa;--fg-muted:#a1a1aa;--fg-dim:#52525b;--border:#27272a;")
    h.append_view("--primary:#3b82f6;--primary-hover:#2563eb;--success:#22c55e;")
    h.append_view("--warning:#eab308;--error:#ef4444;--info:#06b6d4;--accent:#8b5cf6;--radius:8px}")
    h.append_view("body{font-family:system-ui,-apple-system,sans-serif;background:var(--bg);color:var(--fg);")
    h.append_view("height:100vh;overflow:hidden;display:flex;flex-direction:column}")
    h.append_view(".nav-item{display:flex;align-items:center;gap:8px;padding:8px 12px;border-radius:var(--radius);")
    h.append_view("cursor:pointer;font-size:13px;color:var(--fg-muted);transition:background .15s}")
    h.append_view(".nav-item:hover{background:var(--bg-hover);color:var(--fg)}")
    h.append_view(".nav-item.active{background:var(--bg-hover);color:var(--fg);font-weight:500}")
    h.append_view(".nav-icon{width:16px;text-align:center;font-size:12px}")
    h.append_view(".nav-badge{margin-left:auto;background:var(--bg-hover);padding:1px 6px;border-radius:10px;font-size:11px;color:var(--fg-dim)}")
    h.append_view(".dl-item{background:var(--bg-card);border:1px solid var(--border);border-radius:var(--radius);")
    h.append_view("padding:12px 16px;margin-bottom:8px;cursor:pointer;transition:background .15s}")
    h.append_view(".dl-item:hover{background:var(--bg-hover)}")
    h.append_view(".dl-name{font-size:14px;font-weight:500;margin-bottom:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}")
    h.append_view(".dl-meta{font-size:12px;color:var(--fg-muted);display:flex;gap:12px;align-items:center}")
    h.append_view(".dl-progress{height:4px;background:var(--bg);border-radius:2px;margin-top:8px;overflow:hidden}")
    h.append_view(".dl-progress-bar{height:100%;border-radius:2px;transition:width .3s}")
    h.append_view(".status-active{color:var(--success)}.status-paused{color:var(--warning)}.status-failed{color:var(--error)}")
    h.append_view(".status-complete{color:var(--primary)}.status-queued{color:var(--fg-dim)}.status-error{color:var(--error)}")
    h.append_view("</style></head><body>")
    h.append_view("<div id='app' style='display:flex;height:100vh'>")
    build_sidebar(&raw h)
    build_main_area(&raw h)
    h.append_view("</div>")
    build_dialogs(&raw h)
    build_scripts(&raw h)
    h.append_view("</body></html>")
    return h
}

func build_sidebar(h : *string) {
    h.append_view("<aside style='width:220px;background:var(--bg-sidebar);border-right:1px solid var(--border);")
    h.append_view("display:flex;flex-direction:column;padding:16px 12px;gap:4px;flex-shrink:0'>")
    h.append_view("<div style='display:flex;align-items:center;gap:10px;padding:4px 8px;margin-bottom:16px'>")
    h.append_view("<div style='width:32px;height:32px;border-radius:8px;background:var(--primary);")
    h.append_view("display:flex;align-items:center;justify-content:center;font-size:16px;font-weight:700;color:#fff'>D</div>")
    h.append_view("<span style='font-size:15px;font-weight:600'>ChemicalDM</span></div>")
    h.append_view("<div id='nav-all' class='nav-item active' onclick=\"setCategory('all')\">")
    h.append_view("<span class='nav-icon'>&#9660;</span> All Downloads<span class='nav-badge' id='badge-all'>0</span></div>")
    h.append_view("<div id='nav-active' class='nav-item' onclick=\"setCategory('active')\">")
    h.append_view("<span class='nav-icon'>&#9654;</span> Active<span class='nav-badge' id='badge-active'>0</span></div>")
    h.append_view("<div id='nav-complete' class='nav-item' onclick=\"setCategory('complete')\">")
    h.append_view("<span class='nav-icon'>&#10003;</span> Complete<span class='nav-badge' id='badge-complete'>0</span></div>")
    h.append_view("<div id='nav-paused' class='nav-item' onclick=\"setCategory('paused')\">")
    h.append_view("<span class='nav-icon'>&#10074;&#10074;</span> Paused<span class='nav-badge' id='badge-paused'>0</span></div>")
    h.append_view("<div id='nav-failed' class='nav-item' onclick=\"setCategory('failed')\">")
    h.append_view("<span class='nav-icon'>&#10007;</span> Failed<span class='nav-badge' id='badge-failed'>0</span></div>")
    h.append_view("<div style='flex:1'></div>")
    h.append_view("<div class='nav-item' onclick=\"showSettings()\"><span class='nav-icon'>&#9881;</span> Settings</div>")
    h.append_view("</aside>")
}

func build_main_area(h : *string) {
    h.append_view("<main style='flex:1;display:flex;flex-direction:column;overflow:hidden'>")
    h.append_view("<div style='display:flex;align-items:center;gap:8px;padding:10px 16px;")
    h.append_view("border-bottom:1px solid var(--border);background:var(--bg-card)'>")
    h.append_view("<button onclick='showNewDownload()' style='background:var(--primary);color:#fff;border:none;")
    h.append_view("padding:6px 14px;border-radius:var(--radius);cursor:pointer;font-size:13px;font-weight:500'>+ New Download</button>")
    h.append_view("<div style='flex:1'></div>")
    h.append_view("<input id='search-input' type='text' placeholder='Search...' oninput='filterDownloads(this.value)' ")
    h.append_view("style='background:var(--bg);color:var(--fg);border:1px solid var(--border);padding:6px 12px;")
    h.append_view("border-radius:var(--radius);font-size:13px;width:220px;outline:none'>")
    h.append_view("</div>")
    h.append_view("<div id='download-list' style='flex:1;overflow-y:auto;padding:12px 16px'>")
    h.append_view("<div id='empty-state' style='display:flex;flex-direction:column;align-items:center;")
    h.append_view("justify-content:center;height:100%;color:var(--fg-dim)'>")
    h.append_view("<div style='font-size:48px;margin-bottom:16px'>&#8681;</div>")
    h.append_view("<div style='font-size:16px;margin-bottom:8px'>No downloads yet</div>")
    h.append_view("<div style='font-size:13px'>Click + New Download to get started</div>")
    h.append_view("</div></div>")
    h.append_view("</main>")
}

func build_dialogs(h : *string) {
    h.append_view("<div id='new-download-overlay' style='display:none;position:fixed;inset:0;background:rgba(0,0,0,0.6);")
    h.append_view("z-index:100;align-items:center;justify-content:center'>")
    h.append_view("<div style='background:var(--bg-card);border:1px solid var(--border);border-radius:12px;")
    h.append_view("padding:24px;width:480px;max-width:90vw'>")
    h.append_view("<h2 style='font-size:18px;margin-bottom:16px'>New Download</h2>")
    h.append_view("<label style='font-size:13px;color:var(--fg-muted);display:block;margin-bottom:4px'>URL</label>")
    h.append_view("<input id='dl-url' type='text' placeholder='https://example.com/file.zip' ")
    h.append_view("style='width:100%;background:var(--bg);color:var(--fg);border:1px solid var(--border);")
    h.append_view("padding:8px 12px;border-radius:var(--radius);font-size:14px;margin-bottom:12px;outline:none'>")
    h.append_view("<label style='font-size:13px;color:var(--fg-muted);display:block;margin-bottom:4px'>Save As</label>")
    h.append_view("<input id='dl-name' type='text' placeholder='file.zip (auto-detected from URL)' ")
    h.append_view("style='width:100%;background:var(--bg);color:var(--fg);border:1px solid var(--border);")
    h.append_view("padding:8px 12px;border-radius:var(--radius);font-size:14px;margin-bottom:12px;outline:none'>")
    h.append_view("<label style='font-size:13px;color:var(--fg-muted);display:block;margin-bottom:4px'>Save To</label>")
    h.append_view("<input id='dl-folder' type='text' value='~/Downloads' ")
    h.append_view("style='width:100%;background:var(--bg);color:var(--fg);border:1px solid var(--border);")
    h.append_view("padding:8px 12px;border-radius:var(--radius);font-size:14px;margin-bottom:16px;outline:none'>")
    h.append_view("<div style='display:flex;justify-content:flex-end;gap:8px'>")
    h.append_view("<button onclick='hideNewDownload()' style='background:var(--bg-hover);color:var(--fg);")
    h.append_view("border:1px solid var(--border);padding:8px 16px;border-radius:var(--radius);cursor:pointer;font-size:13px'>Cancel</button>")
    h.append_view("<button onclick='submitNewDownload()' style='background:var(--primary);color:#fff;border:none;")
    h.append_view("padding:8px 16px;border-radius:var(--radius);cursor:pointer;font-size:13px;font-weight:500'>Download</button>")
    h.append_view("</div></div></div>")

    h.append_view("<div id='settings-overlay' style='display:none;position:fixed;inset:0;background:rgba(0,0,0,0.6);")
    h.append_view("z-index:100;align-items:center;justify-content:center'>")
    h.append_view("<div style='background:var(--bg-card);border:1px solid var(--border);border-radius:12px;")
    h.append_view("padding:24px;width:460px;max-width:90vw'>")
    h.append_view("<h2 style='font-size:18px;margin-bottom:16px'>Settings</h2>")
    h.append_view("<label style='font-size:13px;color:var(--fg-muted);display:block;margin-bottom:4px'>Default Download Folder</label>")
    h.append_view("<input id='cfg-folder' type='text' value='~/Downloads' ")
    h.append_view("style='width:100%;background:var(--bg);color:var(--fg);border:1px solid var(--border);")
    h.append_view("padding:8px 12px;border-radius:var(--radius);font-size:14px;margin-bottom:12px;outline:none'>")
    h.append_view("<label style='font-size:13px;color:var(--fg-muted);display:block;margin-bottom:4px'>Max Parallel Downloads</label>")
    h.append_view("<input id='cfg-parallel' type='number' value='5' min='1' max='50' ")
    h.append_view("style='width:100%;background:var(--bg);color:var(--fg);border:1px solid var(--border);")
    h.append_view("padding:8px 12px;border-radius:var(--radius);font-size:14px;margin-bottom:16px;outline:none'>")
    h.append_view("<div style='display:flex;justify-content:flex-end;gap:8px'>")
    h.append_view("<button onclick='hideSettings()' style='background:var(--bg-hover);color:var(--fg);")
    h.append_view("border:1px solid var(--border);padding:8px 16px;border-radius:var(--radius);cursor:pointer;font-size:13px'>Cancel</button>")
    h.append_view("<button onclick='hideSettings()' style='background:var(--primary);color:#fff;border:none;")
    h.append_view("padding:8px 16px;border-radius:var(--radius);cursor:pointer;font-size:13px;font-weight:500'>Save</button>")
    h.append_view("</div></div></div>")
}

func build_scripts(h : *string) {
    h.append_view("<script>")
    h.append_view("var downloads=[];var currentCategory='all';var searchQuery='';")
    h.append_view("function setCategory(c){currentCategory=c;document.querySelectorAll('.nav-item').forEach(function(el){el.classList.remove('active')});")
    h.append_view("var nav=document.getElementById('nav-'+c);if(nav)nav.classList.add('active');renderDownloads()}")
    h.append_view("function filterDownloads(q){searchQuery=q.toLowerCase();renderDownloads()}")
    h.append_view("function showNewDownload(){document.getElementById('new-download-overlay').style.display='flex';document.getElementById('dl-url').focus()}")
    h.append_view("function hideNewDownload(){document.getElementById('new-download-overlay').style.display='none';")
    h.append_view("document.getElementById('dl-url').value='';document.getElementById('dl-name').value=''}")
    h.append_view("function showSettings(){document.getElementById('settings-overlay').style.display='flex'}")
    h.append_view("function hideSettings(){document.getElementById('settings-overlay').style.display='none'}")

    h.append_view("function submitNewDownload(){")
    h.append_view("var url=document.getElementById('dl-url').value.trim();")
    h.append_view("var name=document.getElementById('dl-name').value.trim();")
    h.append_view("var folder=document.getElementById('dl-folder').value.trim();")
    h.append_view("if(!url){return}")
    h.append_view("var body=JSON.stringify({url:url,filename:name,folder:folder});")
    h.append_view("fetch('/api/downloads/new',{method:'POST',headers:{'Content-Type':'application/json'},body:body})")
    h.append_view(".then(function(r){return r.json()}).then(function(d){")
    h.append_view("if(d.id){downloads.push({id:d.id,url:url,filename:name||url.split('/').pop()||'download',")
    h.append_view("folder:folder||'~/Downloads',status:'queued',progress:0,speed:0,total:0,downloaded:0,eta:'--:--'});")
    h.append_view("hideNewDownload();renderDownloads();updateBadges()}}).catch(function(){})}")

    h.append_view("function pauseDownload(id){")
    h.append_view("fetch('/api/downloads/pause/'+id,{method:'POST'}).then(function(){renderDownloads();updateBadges()}).catch(function(){})}")
    h.append_view("function resumeDownload(id){")
    h.append_view("fetch('/api/downloads/resume/'+id,{method:'POST'}).then(function(){renderDownloads();updateBadges()}).catch(function(){})}")
    h.append_view("function cancelDownload(id){")
    h.append_view("fetch('/api/downloads/cancel/'+id,{method:'POST'}).then(function(){")
    h.append_view("downloads=downloads.filter(function(x){return x.id!==id});renderDownloads();updateBadges()}).catch(function(){})}")

    h.append_view("function formatSize(b){if(!b||b===0)return '0 B';var u=['B','KB','MB','GB','TB'];var i=Math.floor(Math.log(b)/Math.log(1024));")
    h.append_view("return (b/Math.pow(1024,i)).toFixed(1)+' '+u[i]}")
    h.append_view("function formatSpeed(b){if(!b||b===0)return '--';return formatSize(b)+'/s'}")
    h.append_view("function statusClass(s){return 'status-'+s}")

    h.append_view("function renderDownloads(){")
    h.append_view("var list=document.getElementById('download-list');")
    h.append_view("var filtered=downloads.filter(function(d){")
    h.append_view("if(currentCategory==='active'&&d.status!=='active')return false;")
    h.append_view("if(currentCategory==='complete'&&d.status!=='complete')return false;")
    h.append_view("if(currentCategory==='paused'&&d.status!=='paused')return false;")
    h.append_view("if(currentCategory==='failed'&&d.status!=='failed'&&d.status!=='error')return false;")
    h.append_view("if(searchQuery&&d.filename.toLowerCase().indexOf(searchQuery)===-1&&d.url.toLowerCase().indexOf(searchQuery)===-1)return false;")
    h.append_view("return true});")
    h.append_view("if(filtered.length===0){list.innerHTML='<div style=\"display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;color:var(--fg-dim)\"><div style=\"font-size:48px;margin-bottom:16px\">&#8681;</div><div style=\"font-size:16px;margin-bottom:8px\">No downloads</div></div>';return}")
    h.append_view("var html='';filtered.forEach(function(d){var pct=d.progress||0;var barColor='var(--success)';")
    h.append_view("if(d.status==='paused')barColor='var(--warning)';if(d.status==='failed'||d.status==='error')barColor='var(--error)';")
    h.append_view("if(d.status==='complete')barColor='var(--primary)';if(d.status==='queued')barColor='var(--fg-dim)';")
    h.append_view("html+='<div class=\"dl-item\">';")
    h.append_view("html+='<div class=\"dl-name\">'+d.filename+'</div>';")
    h.append_view("html+='<div class=\"dl-meta\">';")
    h.append_view("html+='<span class=\"'+statusClass(d.status)+'\">'+d.status.charAt(0).toUpperCase()+d.status.slice(1)+'</span>';")
    h.append_view("if(d.total>0){html+='<span>'+formatSize(d.downloaded)+' / '+formatSize(d.total)+'</span>'}")
    h.append_view("if(d.speed>0){html+='<span>'+formatSpeed(d.speed)+'</span>'}")
    h.append_view("if(d.status==='active'||d.status==='paused'){html+='<span>'+d.eta+'</span>'}")
    h.append_view("if(d.status==='active'){html+='<span style=\"margin-left:auto;cursor:pointer\" onclick=\"event.stopPropagation();pauseDownload('+d.id+')\">&#10074;&#10074;</span>'}")
    h.append_view("if(d.status==='paused'){html+='<span style=\"margin-left:auto;cursor:pointer\" onclick=\"event.stopPropagation();resumeDownload('+d.id+')\">&#9654;</span>'}")
    h.append_view("if(d.status==='paused'||d.status==='failed'||d.status==='error'||d.status==='complete'){html+='<span style=\"cursor:pointer\" onclick=\"event.stopPropagation();cancelDownload('+d.id+')\">&#10005;</span>'}")
    h.append_view("html+='</div>';")
    h.append_view("html+='<div class=\"dl-progress\"><div class=\"dl-progress-bar\" style=\"width:'+pct+'%;background:'+barColor+'\"></div></div>';")
    h.append_view("html+='</div>'});list.innerHTML=html}")

    h.append_view("function updateBadges(){")
    h.append_view("var all=downloads.length;var active=downloads.filter(function(d){return d.status==='active'}).length;")
    h.append_view("var complete=downloads.filter(function(d){return d.status==='complete'}).length;")
    h.append_view("var paused=downloads.filter(function(d){return d.status==='paused'}).length;")
    h.append_view("var failed=downloads.filter(function(d){return d.status==='failed'||d.status==='error'}).length;")
    h.append_view("document.getElementById('badge-all').textContent=all;")
    h.append_view("document.getElementById('badge-active').textContent=active;")
    h.append_view("document.getElementById('badge-complete').textContent=complete;")
    h.append_view("document.getElementById('badge-paused').textContent=paused;")
    h.append_view("document.getElementById('badge-failed').textContent=failed}")

    h.append_view("function pollServer(){")
    h.append_view("fetch('/api/downloads').then(function(r){return r.json()}).then(function(data){")
    h.append_view("if(Array.isArray(data)){downloads=data}")
    h.append_view("renderDownloads();updateBadges()}).catch(function(){})}")
    h.append_view("setInterval(pollServer,1000);renderDownloads();updateBadges()")
    h.append_view("</script>")
}

}
