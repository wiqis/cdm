using std::string;

public namespace download {

public struct DownloadTask {
    var id : i64
    var url : string
    var filename : string
    var folder : string
    var total_bytes : i64
    var downloaded_bytes : i64
    var speed : i64
    var status_code : i64
    var error_msg : string
}

func download_thread_func(ctx : *mut void) : *void {
    var task = ctx as *mut DownloadTask
    do_download(task, null as *mut bool)
    return null as *void
}

public func start_download_async(task : *mut DownloadTask) {
    task.status_code = 1
    std::concurrent::spawn(download_thread_func, task as *mut void)
}

public func do_download(task : *mut DownloadTask, cancel_flag : *mut bool) {
    var url_copy = task.url.copy()
    var u = url::parse(url_copy.to_view())
    if(!u.valid) {
        task.status_code = 5
        task.error_msg = string("Invalid URL")
        return
    }

    var host_cstr : [256]char
    var i = 0
    while(i < u.host.size() && i < 255) {
        host_cstr[i] = u.host.get(i as size_t)
        i = i + 1
    }
    host_cstr[i] = '\0'

    var sock = net::dial(&raw host_cstr[0], u.port as uint)
    if(sock == 0 as net::Socket) {
        task.status_code = 4
        task.error_msg = string("Connection failed")
        return
    }

    var head_req = string("HEAD ")
    head_req.append_string(&u.path)
    head_req.append_view(" HTTP/1.1\r\nHost: ")
    head_req.append_string(&u.host)
    head_req.append_view("\r\nConnection: close\r\n\r\n")
    net::send_all(sock, head_req.data(), head_req.size() as int)

    var head_buf : [8192]u8
    var head_len = net::recv_all(sock, &raw mut head_buf[0], 8191 as size_t)
    net::close_socket(sock)

    if(head_len <= 0) {
        task.status_code = 4
        task.error_msg = string("No response")
        return
    }
    head_buf[head_len] = 0 as u8

    var content_length : i64 = -1
    var accept_ranges = false
    parse_response_headers(&raw mut head_buf[0] as *mut char, head_len, &raw mut content_length, &raw mut accept_ranges)

    if(content_length > 0) {
        task.total_bytes = content_length
    }

    sock = net::dial(&raw host_cstr[0], u.port as uint)
    if(sock == 0 as net::Socket) {
        task.status_code = 4
        task.error_msg = string("Reconnection failed")
        return
    }

    var get_req = string("GET ")
    get_req.append_string(&u.path)
    get_req.append_view(" HTTP/1.1\r\nHost: ")
    get_req.append_string(&u.host)
    get_req.append_view("\r\nConnection: close\r\n\r\n")
    net::send_all(sock, get_req.data(), get_req.size() as int)

    var resp_buf_size : size_t = 131072 as size_t
    var resp_buf = malloc(resp_buf_size) as *mut u8
    if(resp_buf == null as *mut u8) {
        task.status_code = 5
        task.error_msg = string("Out of memory")
        net::close_socket(sock)
        return
    }

    var first_read = net::recv_all(sock, resp_buf, resp_buf_size)
    if(first_read <= 0) {
        task.status_code = 4
        task.error_msg = string("No data received")
        free(resp_buf as *mut void)
        net::close_socket(sock)
        return
    }

    var header_end = find_header_end(resp_buf as *mut char, first_read)
    if(header_end < 0) {
        task.status_code = 4
        task.error_msg = string("Invalid HTTP response")
        free(resp_buf as *mut void)
        net::close_socket(sock)
        return
    }

    var status_code = parse_status_code(resp_buf as *mut char, first_read)
    if(status_code < 200 || status_code >= 300) {
        task.status_code = 4
        var err = string("HTTP error: ")
        var code_str = int_to_str(status_code)
        err.append_string(&code_str)
        task.error_msg = err
        free(resp_buf as *mut void)
        net::close_socket(sock)
        return
    }

    var body_start = header_end + 4
    var body_in_first = first_read - body_start

    var file_path = task.folder.copy()
    file_path.append_view("/")
    file_path.append_string(&task.filename)

    var file_cstr : [512]char
    var fi = 0
    while(fi < file_path.size() && fi < 511) {
        file_cstr[fi] = file_path.get(fi as size_t)
        fi = fi + 1
    }
    file_cstr[fi] = '\0'

    var fp = fopen(&raw file_cstr[0], "wb")
    if(fp == null as *mut FILE) {
        task.status_code = 5
        task.error_msg = string("Cannot create file")
        free(resp_buf as *mut void)
        net::close_socket(sock)
        return
    }

    if(body_in_first > 0) {
        var body_offset = resp_buf + body_start as size_t
        fwrite(body_offset as *void, 1 as size_t, body_in_first as size_t, fp)
        task.downloaded_bytes = task.downloaded_bytes + body_in_first as i64
    }

    var last_speed_clock = clock()
    var last_speed_bytes : i64 = task.downloaded_bytes

    while(true) {
        if(cancel_flag != null as *mut bool) {
            if(*cancel_flag) { break }
        }

        var n = net::recv_all(sock, resp_buf, resp_buf_size)
        if(n <= 0) { break }

        fwrite(resp_buf as *void, 1 as size_t, n as size_t, fp)
        task.downloaded_bytes = task.downloaded_bytes + n as i64

        var now_clock = clock()
        var elapsed : i64 = (now_clock - last_speed_clock) as i64
        if(elapsed > 500) {
            var bytes_since = task.downloaded_bytes - last_speed_bytes
            if(elapsed > 0) {
                task.speed = (bytes_since * 1000) / elapsed
            }
            last_speed_clock = now_clock
            last_speed_bytes = task.downloaded_bytes
        }
    }

    fflush(fp)
    fclose(fp)
    free(resp_buf as *mut void)
    net::close_socket(sock)

    if(cancel_flag != null as *mut bool && *cancel_flag) {
        task.status_code = 2
        task.speed = 0
    } else {
        task.status_code = 3
        task.speed = 0
    }
}

func parse_response_headers(buf : *mut char, len : int, content_length : *mut i64, accept_ranges : *mut bool) {
    var pos = 0
    while(pos < len - 1) {
        if(buf[pos] == '\r' && buf[pos + 1] == '\n') { break }
        pos = pos + 1
    }

    var line_start = 0
    while(line_start < pos) {
        var line_end = line_start
        while(line_end < pos && buf[line_end] != '\r') { line_end = line_end + 1 }

        if(line_end - line_start == 14) {
            var match_cl = true
            var cl_header = "Content-Length"
            var ci = 0
            while(ci < 14) {
                if(buf[line_start + ci] != cl_header[ci]) { match_cl = false; break }
                ci = ci + 1
            }
            if(match_cl && line_end + 1 < pos && buf[line_end] == ':') {
                var vs = line_start + 15
                while(vs < line_end && buf[vs] == ' ') { vs = vs + 1 }
                var val : i64 = 0
                while(vs < line_end && buf[vs] >= '0' && buf[vs] <= '9') {
                    val = val * 10 + (buf[vs] - '0') as i64
                    vs = vs + 1
                }
                *content_length = val
            }
        }

        if(line_end - line_start >= 13) {
            var match_ar = true
            var ar_header = "Accept-Ranges"
            var ai = 0
            while(ai < 13) {
                if(buf[line_start + ai] != ar_header[ai]) { match_ar = false; break }
                ai = ai + 1
            }
            if(match_ar) { *accept_ranges = true }
        }

        line_start = line_end + 2
    }
}

func parse_status_code(buf : *mut char, len : int) : int {
    var i = 0
    while(i < len && buf[i] != ' ') { i = i + 1 }
    if(i + 3 < len) {
        i = i + 1
        return (buf[i] - '0') as int * 100 + (buf[i + 1] - '0') as int * 10 + (buf[i + 2] - '0') as int
    }
    return 0
}

func find_header_end(buf : *mut char, len : int) : int {
    var i = 0
    while(i < len - 3) {
        if(buf[i] == '\r' && buf[i + 1] == '\n' && buf[i + 2] == '\r' && buf[i + 3] == '\n') {
            return i
        }
        i = i + 1
    }
    return -1
}

func int_to_str(val : int) : string {
    var s = string()
    if(val == 0) {
        s.append('0')
        return s
    }
    var is_neg = false
    var v = val
    if(v < 0) { is_neg = true; v = -v }
    var tmp : [16]char
    var cnt = 0
    while(v > 0) {
        tmp[cnt] = (v % 10 + '0') as char
        v = v / 10
        cnt = cnt + 1
    }
    if(is_neg) { s.append('-') }
    var idx = cnt - 1
    while(idx >= 0) {
        s.append(tmp[idx])
        idx = idx - 1
    }
    return s
}

}
