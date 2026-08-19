using std::string;

public namespace url {

public struct Url {
    var scheme : string
    var host : string
    var port : int
    var path : string
    var valid : bool
}

public func parse(raw : std::string_view) : Url {
    var u = Url { scheme: string(), host: string(), port: 80, path: string(), valid: false }
    var data = string(raw)
    var s = data.data()
    var len = raw.size() as int
    if(len < 1) { return u }

    var pos = 0

    if(len >= 7 && s[0] == 'h' && s[1] == 't' && s[2] == 't' && s[3] == 'p' && s[4] == 's' && s[5] == ':' && s[6] == '/') {
        u.scheme = string("https")
        u.port = 443
        pos = 8
    } else if(len >= 7 && s[0] == 'h' && s[1] == 't' && s[2] == 't' && s[3] == 'p' && s[4] == ':' && s[5] == '/' && s[6] == '/') {
        u.scheme = string("http")
        u.port = 80
        pos = 7
    } else {
        return u
    }

    var host_start = pos
    var host_end = pos
    while(host_end < len && s[host_end] != ':' as char && s[host_end] != '/' as char) {
        host_end = host_end + 1
    }
    var i = host_start
    while(i < host_end) {
        u.host.append(s[i] as char)
        i = i + 1
    }

    if(host_end < len && s[host_end] == ':' as char) {
        host_end = host_end + 1
        var port_num = 0
        while(host_end < len && s[host_end] >= '0' as char && s[host_end] <= '9' as char) {
            port_num = port_num * 10 + (s[host_end] - '0') as int
            host_end = host_end + 1
        }
        if(port_num > 0) { u.port = port_num }
    }

    var path_start = host_end
    if(path_start < len && s[path_start] == '/' as char) {
        while(path_start < len) {
            u.path.append(s[path_start] as char)
            path_start = path_start + 1
        }
    } else {
        u.path.append('/')
    }

    if(u.host.size() > 0) { u.valid = true }
    return u
}

}
