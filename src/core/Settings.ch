// ChemicalDM — settings & persistence.
//
// Persists the user-configurable settings and the download queue to
// $HOME/.chemicaldm/ so a restart resumes interrupted downloads. The format is
// a simple line-based `key:value` config for settings plus a JSON document for
// the queue (matching the wire format used by the state bridge).

public namespace cdm {

using std::string;
using std::string_view;
using std::vector;
using std::Option;
using std::pair;
using std::ordered_map;

    public struct CdmSettings {
        var download_dir : string
        var max_concurrent : int
        var max_segments : int
        var min_segment_size : i64
        var speed_limit_kbps : i64
        var enable_resume : bool
        var allow_segments : bool
        var proxy_host : string
        var proxy_port : int
        var categories : vector<string>
        var category_dirs : ordered_map<string, string>
        var auto_start : bool
        var quiet : bool

        @constructor func constructor() {
            return CdmSettings {
                download_dir = string::make_no_len(DEFAULT_DOWNLOAD_DIR),
                max_concurrent = DEFAULT_MAX_CONCURRENT,
                max_segments = DEFAULT_MAX_SEGMENTS,
                min_segment_size = DEFAULT_MIN_SEGMENT_SIZE,
                speed_limit_kbps = 0,
                enable_resume = true,
                allow_segments = true,
                proxy_host = string(),
                proxy_port = 0,
                categories = vector<string>(),
                category_dirs = ordered_map<string, string>(),
                auto_start = false,
                quiet = false
            }
        }
    }

func settings_dir() : string {
    // Allow isolating the config directory (used by tests). When unset, the
    // standard $HOME/.chemicaldm location is used.
    var cfg_env = std::get_env(string_view::make_no_len("CDM_CONFIG_DIR"))
    if(cfg_env is Option.Some) {
        var Some(cd) = cfg_env else unreachable
        return cd.copy()
    }
    var home = string()
    var opt = std::get_env(string_view::make_no_len("HOME"))
    if(opt is Option.Some) {
        var Some(h) = opt else unreachable
        home = h.copy()
    } else {
        home = string::make_no_len(".")
    }
    var path = home.copy()
    path.append('/')
    var fn = string::make_no_len(".chemicaldm")
    path.append_string(&fn)
    return path
}

    func settings_file() : string {
        var dir = settings_dir()
        var path = dir.copy()
        path.append('/')
        var fn = string::make_no_len("config.txt")
        path.append_string(&fn)
        return path
    }

    // Save settings to disk. Returns true on success.
    public func save_settings(s : &CdmSettings) : bool {
        var dir = settings_dir()
        var mk = fs::create_dir_all(dir.data())
        // Result is not actionable here.

        var path = settings_file()
        var f = fopen(path.data(), "wb")
        if(f == null) { return false }

        var out = string()
        out.append_view("downloadFolder:")
        out.append_string(&s.download_dir)
        out.append_view("\n")
        out.append_view("parallelDownloads:")
        out.append_integer(s.max_concurrent as bigint)
        out.append_view("\n")
        out.append_view("maxSegments:")
        out.append_integer(s.max_segments as bigint)
        out.append_view("\n")
        out.append_view("minSegmentSize:")
        out.append_integer(s.min_segment_size as bigint)
        out.append_view("\n")
        out.append_view("speedLimit:")
        out.append_integer(s.speed_limit_kbps as bigint)
        out.append_view("\n")
        out.append_view("enableResume:")
        if(s.enable_resume) { out.append_view("true\n") } else { out.append_view("false\n") }
        out.append_view("allowSegments:")
        if(s.allow_segments) { out.append_view("true\n") } else { out.append_view("false\n") }
        out.append_view("proxyHost:")
        out.append_string(&s.proxy_host)
        out.append_view("\n")
        out.append_view("proxyPort:")
        out.append_integer(s.proxy_port as bigint)
        out.append_view("\n")
        out.append_view("autoStart:")
        if(s.auto_start) { out.append_view("true\n") } else { out.append_view("false\n") }
        out.append_view("quiet:")
        if(s.quiet) { out.append_view("true\n") } else { out.append_view("false\n") }

        var wrote = fwrite(out.data() as *mut u8, 1, out.size(), f)
        fclose(f)
        return wrote == out.size()
    }

    func read_line(content : &string, pos : &mut usize) : string {
        var start = *pos
        while(*pos < content.size() && content.get(*pos) != '\n') {
            *pos = *pos + 1u
        }
        var end = *pos
        if(end > start && end > 0u && content.get(end - 1u) == '\r') { end = end - 1u }
        if(*pos < content.size()) { *pos = *pos + 1u }  // skip newline
        return content.substring(start, end)
    }

    func parse_bool(s : &string) : bool {
        return s.equals_view("true") || s.equals_view("1") || s.equals_view("yes")
    }

    // Load settings from disk. Returns false when no settings exist yet.
    public func load_settings(out : *mut CdmSettings) : bool {
        var path = settings_file()
        var f = fopen(path.data(), "rb")
        if(f == null) { return false }

        var content = string()
        var chunk : [4096u]u8
        while(true) {
            var n = fread(&raw mut chunk[0], 1, 4096u, f)
            if(n == 0u) { break }
            content.append_with_len(&raw mut chunk[0] as *char, n)
        }
        fclose(f)

        var pos : usize = 0
        while(pos < content.size()) {
            var line = read_line(&content, &mut pos)
            if(line.empty() || line.get(0) == '#') { continue }
            var colon = line.find_last(std::string_view::make_no_len(":"))
            if(colon == std::NPOS) { continue }
            var key = line.substring(0u, colon)
            var val = line.substring(colon + 1u, line.size())

            var kh = fnv1_hash_view(string_view::make_view(&key))
            if(kh == comptime_fnv1_hash("downloadFolder")) { out.download_dir = val.copy() }
            else if(kh == comptime_fnv1_hash("parallelDownloads")) {
                var n = cli_parse_int(val.data())
                if(n > 0) { out.max_concurrent = n }
            }
            else if(kh == comptime_fnv1_hash("maxSegments")) {
                var n = cli_parse_int(val.data())
                if(n > 0) { out.max_segments = n }
            }
            else if(kh == comptime_fnv1_hash("minSegmentSize")) {
                var n = cli_parse_int(val.data())
                if(n > 0) { out.min_segment_size = n as i64 }
            }
            else if(kh == comptime_fnv1_hash("speedLimit")) {
                var n = cli_parse_int(val.data())
                if(n > 0) { out.speed_limit_kbps = n as i64 }
            }
            else if(kh == comptime_fnv1_hash("enableResume")) { out.enable_resume = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("allowSegments")) { out.allow_segments = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("proxyHost")) { out.proxy_host = val.copy() }
            else if(kh == comptime_fnv1_hash("proxyPort")) {
                var n = cli_parse_int(val.data())
                if(n >= 0) { out.proxy_port = n }
            }
            else if(kh == comptime_fnv1_hash("autoStart")) { out.auto_start = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("quiet")) { out.quiet = parse_bool(&val) }
        }
        return true
    }

    // Queue file format: one line per entry, `url<TAB>id<TAB>dir`. Versioned
    // header line `#cdm-queue-v1`. Simple, robust, and independent of the JSON
    // reader (which only handles flat objects).
    const QUEUE_HEADER : *char = "#cdm-queue-v1"
    const QUEUE_SEP : char = '\t'

    func queue_file() : string {
        var path = settings_dir()
        path.append('/')
        var fn = string::make_no_len("queue.txt")
        path.append_string(&fn)
        return path
    }

    // Load a previously saved queue and re-queue its incomplete items into the
    // manager. Returns how many items were restored.
    func restore_queue(dm : &mut DownloadManager) : int {
        var path = queue_file()
        var f = fopen(path.data(), "rb")
        if(f == null) { return 0 }
        var content = string()
        var chunk : [8192u]u8
        while(true) {
            var n = fread(&raw mut chunk[0], 1, 8192u, f)
            if(n == 0u) { break }
            content.append_with_len(&raw mut chunk[0] as *char, n)
        }
        fclose(f)

        var restored = 0
        var pos : usize = 0
        var header_ok = false
        while(pos < content.size()) {
            var line = read_line(&content, &mut pos)
            if(!header_ok) {
                if(line.equals_view(std::string_view::make_no_len(QUEUE_HEADER))) { header_ok = true }
                continue
            }
            if(line.empty()) { continue }
            // split on tab
            var tab = line.find(std::string_view::make_no_len("\t"))
            if(tab == std::NPOS) { continue }
            var url = line.substring(0u, tab)
            if(url.empty()) { continue }
            var id = add_task(dm, string_view::make_view(&url))
            if(id.size() > 0u) { restored = restored + 1 }
        }
        return restored
    }

    // Save the queue to disk. Does not block the engine.
    public func save_queue(dm : &DownloadManager) : bool {
        var dir = settings_dir()
        var mk = fs::create_dir_all(dir.data())
        var path = queue_file()

        var out = string::make_no_len(QUEUE_HEADER)
        out.append('\n')
        for(var i = 0u; i < dm.items.size(); i++) {
            var it = dm.items.get_ptr(i)
            out.append_string(&it.url)
            out.append(QUEUE_SEP)
            out.append_string(&it.id)
            out.append(QUEUE_SEP)
            out.append_string(&it.dir)
            out.append('\n')
        }

        var f = fopen(path.data(), "wb")
        if(f == null) { return false }
        var wrote = fwrite(out.data() as *mut u8, 1, out.size(), f)
        fclose(f)
        return wrote == out.size()
    }

} // end namespace cdm