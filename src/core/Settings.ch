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
        var use_categories : bool
        var duplicate_action : int        // 0 = rename, 1 = overwrite, 2 = skip
        var network_timeout : int         // seconds
        var auto_resume_failed : bool
        var max_retries : int
        var retry_delay_ms : i64
        var temporary_folder : string

        @constructor func constructor() {
            return CdmSettings {
                download_dir = expand_home(string_view::make_no_len(DEFAULT_DOWNLOAD_DIR)),
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
                quiet = false,
                use_categories = true,
                duplicate_action = 0,
                network_timeout = SOCKET_TIMEOUT_SECS,
                auto_resume_failed = false,
                max_retries = DEFAULT_MAX_RETRIES,
                retry_delay_ms = DEFAULT_RETRY_DELAY_MS,
                temporary_folder = string()
            }
        }

        // The default sub-folder used for a category when the user has not
        // overridden it. Other category = "" (no sub folder => download root).
        public func category_folder(&self, c : Category) : string {
            var key = category_key(c)
            var cached = string()
            if(self.category_dirs.find(&key, &mut cached)) {
                return cached
            }
            return category_default_dir(c)
        }

        // Resolve the destination directory for a download. When categories are
        // enabled and the category has a folder, returns download_dir + folder.
        public func category_dir_for(&self, c : Category, filename : string_view) : string {
            if(!self.use_categories) { return self.download_dir.copy() }
            var sub = self.category_folder(c)
            if(sub.empty()) { return self.download_dir.copy() }
            var out = self.download_dir.copy()
            out.append('/')
            out.append_string(&sub)
            return out
        }
    }

    // Stable key used for per-category directory override persistence.
    func category_key(c : Category) : string {
        if(c == Category.Documents) { return string::make_no_len("documents") }
        if(c == Category.Programs) { return string::make_no_len("programs") }
        if(c == Category.Video) { return string::make_no_len("video") }
        if(c == Category.Music) { return string::make_no_len("music") }
        if(c == Category.Compressed) { return string::make_no_len("compressed") }
        return string::make_no_len("other")
    }

    func category_default_dir(c : Category) : string {
        if(c == Category.Documents) { return string::make_no_len(CATEGORY_DOCS_DIR) }
        if(c == Category.Programs) { return string::make_no_len(CATEGORY_PROGRAMS_DIR) }
        if(c == Category.Video) { return string::make_no_len(CATEGORY_VIDEO_DIR) }
        if(c == Category.Music) { return string::make_no_len(CATEGORY_MUSIC_DIR) }
        if(c == Category.Compressed) { return string::make_no_len(CATEGORY_COMPRESSED_DIR) }
        return string()
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
        out.append_view("useCategories:")
        if(s.use_categories) { out.append_view("true\n") } else { out.append_view("false\n") }
        out.append_view("duplicateAction:")
        out.append_integer(s.duplicate_action as bigint)
        out.append_view("\n")
        out.append_view("networkTimeout:")
        out.append_integer(s.network_timeout as bigint)
        out.append_view("\n")
        out.append_view("autoResumeFailed:")
        if(s.auto_resume_failed) { out.append_view("true\n") } else { out.append_view("false\n") }
        out.append_view("maxRetries:")
        out.append_integer(s.max_retries as bigint)
        out.append_view("\n")
        out.append_view("retryDelayMs:")
        out.append_integer(s.retry_delay_ms as bigint)
        out.append_view("\n")
        out.append_view("temporaryFolder:")
        out.append_string(&s.temporary_folder)
        out.append_view("\n")
        // Per-category folder overrides: categoryDocuments:<dir> etc.
        var doc_v = category_folder_for_write(s, Category.Documents)
        out.append_view("categoryDocuments:")
        out.append_string(&doc_v)
        out.append_view("\n")
        var mus_v = category_folder_for_write(s, Category.Music)
        out.append_view("categoryMusic:")
        out.append_string(&mus_v)
        out.append_view("\n")
        var vid_v = category_folder_for_write(s, Category.Video)
        out.append_view("categoryVideos:")
        out.append_string(&vid_v)
        out.append_view("\n")
        var pro_v = category_folder_for_write(s, Category.Programs)
        out.append_view("categoryPrograms:")
        out.append_string(&pro_v)
        out.append_view("\n")
        var cmp_v = category_folder_for_write(s, Category.Compressed)
        out.append_view("categoryCompressed:")
        out.append_string(&cmp_v)
        out.append_view("\n")

        var wrote = fwrite(out.data() as *mut u8, 1, out.size(), f)
        fclose(f)
        return wrote == out.size()
    }

    // Return the override for a category, or an empty string when the category
    // still uses its built-in default (so the writer can persist only diffs).
    func category_folder_for_write(s : &CdmSettings, c : Category) : string {
        var key = category_key(c)
        var cached = string()
        if(s.category_dirs.find(&key, &mut cached)) {
            return cached
        }
        return string()
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

    public func parse_bool(s : &string) : bool {
        return s.equals_view("true") || s.equals_view("1") || s.equals_view("yes")
    }

    // Parse a non-negative integer from a C string. Returns -1 on failure.
    public func parse_int_opt(s : *char) : int {
        var p = s
        var val = 0
        var started = false
        while(*p != 0) {
            if(*p >= '0' && *p <= '9') {
                val = val * 10 + (*p as int - '0' as int)
                started = true
            } else {
                return -1
            }
            p = p + 1
        }
        if(!started) { return -1 }
        return val
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
            if(kh == comptime_fnv1_hash("downloadFolder")) { out.download_dir = expand_home(string_view::make_view(&val)) }
            else if(kh == comptime_fnv1_hash("parallelDownloads")) {
                var n = parse_int_opt(val.data())
                if(n > 0) { out.max_concurrent = n }
            }
            else if(kh == comptime_fnv1_hash("maxSegments")) {
                var n = parse_int_opt(val.data())
                if(n > 0) { out.max_segments = n }
            }
            else if(kh == comptime_fnv1_hash("minSegmentSize")) {
                var n = parse_int_opt(val.data())
                if(n > 0) { out.min_segment_size = n as i64 }
            }
            else if(kh == comptime_fnv1_hash("speedLimit")) {
                var n = parse_int_opt(val.data())
                if(n > 0) { out.speed_limit_kbps = n as i64 }
            }
            else if(kh == comptime_fnv1_hash("enableResume")) { out.enable_resume = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("allowSegments")) { out.allow_segments = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("proxyHost")) { out.proxy_host = val.copy() }
            else if(kh == comptime_fnv1_hash("proxyPort")) {
                var n = parse_int_opt(val.data())
                if(n >= 0) { out.proxy_port = n }
            }
            else if(kh == comptime_fnv1_hash("autoStart")) { out.auto_start = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("quiet")) { out.quiet = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("useCategories")) { out.use_categories = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("duplicateAction")) {
                var n = parse_int_opt(val.data())
                if(n >= 0) { out.duplicate_action = n }
            }
            else if(kh == comptime_fnv1_hash("networkTimeout")) {
                var n = parse_int_opt(val.data())
                if(n > 0) { out.network_timeout = n }
            }
            else if(kh == comptime_fnv1_hash("autoResumeFailed")) { out.auto_resume_failed = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("maxRetries")) {
                var n = parse_int_opt(val.data())
                if(n >= -1) { out.max_retries = n }
            }
            else if(kh == comptime_fnv1_hash("retryDelayMs")) {
                var n = parse_int_opt(val.data())
                if(n >= 0) { out.retry_delay_ms = n as i64 }
            }
            else if(kh == comptime_fnv1_hash("temporaryFolder")) { out.temporary_folder = val.copy() }
            else if(kh == comptime_fnv1_hash("categoryDocuments")) {
                out.category_dirs.insert(string::make_no_len("documents"), val.copy())
            }
            else if(kh == comptime_fnv1_hash("categoryMusic")) {
                out.category_dirs.insert(string::make_no_len("music"), val.copy())
            }
            else if(kh == comptime_fnv1_hash("categoryVideos")) {
                out.category_dirs.insert(string::make_no_len("video"), val.copy())
            }
            else if(kh == comptime_fnv1_hash("categoryPrograms")) {
                out.category_dirs.insert(string::make_no_len("programs"), val.copy())
            }
            else if(kh == comptime_fnv1_hash("categoryCompressed")) {
                out.category_dirs.insert(string::make_no_len("compressed"), val.copy())
            }
        }
        return true
    }

    // Apply persisted settings to a DownloadManager. The library no longer
    // handles settings — the app bridges CdmSettings → DownloadManager fields.
    public func apply_settings_to_dm(dm : &mut DownloadManager, s : &CdmSettings) {
        dm.max_concurrent = s.max_concurrent
        dm.max_segments = s.max_segments
        dm.min_segment_size = s.min_segment_size
        dm.speed_limit_kbps = s.speed_limit_kbps
        dm.enable_resume = s.enable_resume
        dm.allow_segments = s.allow_segments
        dm.proxy_host = s.proxy_host.copy()
        dm.proxy_port = s.proxy_port
        dm.duplicate_action = s.duplicate_action
        dm.auto_resume_failed = s.auto_resume_failed
        dm.retry_policy.max_retries = s.max_retries
        dm.retry_policy.delay_ms = s.retry_delay_ms
        if(s.download_dir.size() > 0) {
            dm.download_dir = s.download_dir.copy()
        }
    }

    // In-memory serialization (no filesystem I/O). Used by tests to verify
    // round-trip correctness without touching disk.
    public func save_settings_to_string(s : &CdmSettings) : string {
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
        out.append_view("speedLimit:")
        out.append_integer(s.speed_limit_kbps as bigint)
        out.append_view("\n")
        out.append_view("enableResume:")
        if(s.enable_resume) { out.append_view("true\n") } else { out.append_view("false\n") }
        out.append_view("allowSegments:")
        if(s.allow_segments) { out.append_view("true\n") } else { out.append_view("false\n") }
        out.append_view("useCategories:")
        if(s.use_categories) { out.append_view("true\n") } else { out.append_view("false\n") }
        out.append_view("duplicateAction:")
        out.append_integer(s.duplicate_action as bigint)
        out.append_view("\n")
        out.append_view("autoResumeFailed:")
        if(s.auto_resume_failed) { out.append_view("true\n") } else { out.append_view("false\n") }
        out.append_view("maxRetries:")
        out.append_integer(s.max_retries as bigint)
        out.append_view("\n")
        out.append_view("retryDelayMs:")
        out.append_integer(s.retry_delay_ms as bigint)
        out.append_view("\n")
        return out
    }

    // In-memory parser: populate a CdmSettings from the serialized string
    // produced by save_settings_to_string. No filesystem I/O.
    public func parse_settings_string(content : string_view) : CdmSettings {
        var s = CdmSettings()
        // Copy to a string so we can use read_line (which needs &string).
        var buf = string()
        buf.append_view(&content)
        var pos : usize = 0
        while(pos < buf.size()) {
            var line = read_line(&buf, &mut pos)
            if(line.empty() || line.get(0) == '#') { continue }
            var colon = line.find_last(std::string_view::make_no_len(":"))
            if(colon == std::NPOS) { continue }
            var key = line.substring(0u, colon)
            var val = line.substring(colon + 1u, line.size())
            var kh = fnv1_hash_view(string_view::make_view(&key))
            if(kh == comptime_fnv1_hash("downloadFolder")) { s.download_dir = expand_home(string_view::make_view(&val)) }
            else if(kh == comptime_fnv1_hash("parallelDownloads")) {
                var n = parse_int_opt(val.data())
                if(n > 0) { s.max_concurrent = n }
            }
            else if(kh == comptime_fnv1_hash("maxSegments")) {
                var n = parse_int_opt(val.data())
                if(n > 0) { s.max_segments = n }
            }
            else if(kh == comptime_fnv1_hash("speedLimit")) {
                var n = parse_int_opt(val.data())
                if(n >= 0) { s.speed_limit_kbps = n as i64 }
            }
            else if(kh == comptime_fnv1_hash("enableResume")) { s.enable_resume = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("allowSegments")) { s.allow_segments = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("useCategories")) { s.use_categories = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("duplicateAction")) {
                var n = parse_int_opt(val.data())
                if(n >= 0) { s.duplicate_action = n }
            }
            else if(kh == comptime_fnv1_hash("autoResumeFailed")) { s.auto_resume_failed = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("maxRetries")) {
                var n = parse_int_opt(val.data())
                if(n >= -1) { s.max_retries = n }
            }
            else if(kh == comptime_fnv1_hash("retryDelayMs")) {
                var n = parse_int_opt(val.data())
                if(n >= 0) { s.retry_delay_ms = n as i64 }
            }
        }
        return s
    }

    // Queue file format: one line per entry, `url<TAB>id<TAB>dir`. Versioned
    // header line `#cdm-queue-v1`. Simple, robust, and independent of the JSON
    // reader (which only handles flat objects).
    const QUEUE_HEADER : *char = "#cdm-queue-v1"
    const QUEUE_SEP : char = '\t'

    public func queue_file() : string {
        var path = settings_dir()
        path.append('/')
        var fn = string::make_no_len("queue.txt")
        path.append_string(&fn)
        return path
    }

    // Path for periodic progress persistence (crash recovery).
    public func progress_file() : string {
        var path = settings_dir()
        path.append('/')
        var fn = string::make_no_len("progress.txt")
        path.append_string(&fn)
        return path
    }

    // Load a previously saved queue and re-queue its incomplete items into the
    // manager, preserving the original id, destination directory and category
    // tag so resume bookkeeping (and any category routing) survives a restart.
    // Returns how many items were restored.
    public func restore_queue(dm : &mut DownloadManager) : int {
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
            // Fields are tab-separated: url \t id \t dir \t [category] \t [downloaded] \t [total] \t [interrupted]
            var tab1 = line.find(std::string_view::make_no_len("\t"))
            if(tab1 == std::NPOS) { continue }
            var url = line.substring(0u, tab1)
            if(url.empty()) { continue }
            var rest = line.substring(tab1 + 1u, line.size())

            var id = string()
            var dir = string()
            var category = 0
            var downloaded : i64 = 0
            var total : i64 = 0
            var was_interrupted = false
            var tab2 = rest.find(std::string_view::make_no_len("\t"))
            if(tab2 == std::NPOS) {
                // Legacy 2-field row: url \t id  (dir defaults to manager root).
                id = rest
            } else {
                id = rest.substring(0u, tab2)
                var rest2 = rest.substring(tab2 + 1u, rest.size())
                var tab3 = rest2.find(std::string_view::make_no_len("\t"))
                if(tab3 == std::NPOS) {
                    dir = rest2
                } else {
                    dir = rest2.substring(0u, tab3)
                    var rest3 = rest2.substring(tab3 + 1u, rest2.size())
                    var tab4 = rest3.find(std::string_view::make_no_len("\t"))
                    if(tab4 == std::NPOS) {
                        // v1 row: url \t id \t dir \t category
                        var cat_n = parse_int_opt(rest3.data())
                        if(cat_n >= 0) { category = cat_n }
                    } else {
                        // v2 row: ... \t downloaded \t total \t interrupted
                        var cat_n = parse_int_opt(rest3.substring(0u, tab4).data())
                        if(cat_n >= 0) { category = cat_n }
                        var rest4 = rest3.substring(tab4 + 1u, rest3.size())
                        var tab5 = rest4.find(std::string_view::make_no_len("\t"))
                        if(tab5 != std::NPOS) {
                            var dl_str = rest4.substring(0u, tab5)
                            downloaded = parse_i64(string_view::make_view(&dl_str))
                            var rest5 = rest4.substring(tab5 + 1u, rest4.size())
                            var tab6 = rest5.find(std::string_view::make_no_len("\t"))
                            if(tab6 != std::NPOS) {
                                var tot_str = rest5.substring(0u, tab6)
                                total = parse_i64(string_view::make_view(&tot_str))
                                var int_s = rest5.substring(tab6 + 1u, rest5.size())
                                was_interrupted = int_s.equals_view("1")
                            } else {
                                total = parse_i64(string_view::make_view(&rest5))
                            }
                        } else {
                            downloaded = parse_i64(string_view::make_view(&rest4))
                        }
                    }
                }
            }
            var id_view = string_view::make_view(&id)
            var dir_view = string_view::make_view(&dir)
            var rid = add_task_ex_id(dm, id_view, string_view::make_view(&url),
                                    dir_view, string_view(), 0, category)
            if(rid.size() > 0u) {
                restored = restored + 1
                // Restore progress and interrupt state so the engine can resume
                // from the last written position on disk instead of starting over.
                if(downloaded > 0 || total > 0 || was_interrupted) {
                    dm.items_mutex.lock()
                    var idx = find_item_index(dm, &rid)
                    if(idx != dm.items.size()) {
                        var it = dm.items.get_ptr(idx)
                        it.downloaded_bytes = downloaded
                        it.total_bytes = total
                        it.was_interrupted = was_interrupted
                        // Mark as failed/interrupted so poll_auto_resume can re-queue it.
                        if(was_interrupted) {
                            it.state = STATE_FAILED
                            it.error = string::make_no_len("interrupted by shutdown")
                        }
                    }
                    dm.items_mutex.unlock()
                }
            }
        }
        return restored
    }

    // Parse an i64 from a string view. Returns 0 on failure.
    func parse_i64(s : string_view) : i64 {
        var val : i64 = 0
        var neg = false
        var started = false
        for(var i = 0u; i < s.size(); i++) {
            var c = s.get(i)
            if(c == '-') { neg = true }
            else if(c >= '0' && c <= '9') {
                val = val * 10 + (c as i64 - '0' as i64)
                started = true
            }
        }
        if(!started) { return 0 }
        if(neg) { val = -val }
        return val
    }

    // Save the queue to disk. Does not block the engine.
    // Format (tab-separated, one row per item):
    //   url \t id \t dir \t category \t downloaded \t total \t was_interrupted
    // Rows for DONE/CANCELLED items are skipped (nothing to resume).
    public func save_queue(dm : &mut DownloadManager) : bool {
        var dir = settings_dir()
        var mk = fs::create_dir_all(dir.data())
        var path = queue_file()

        // Read through snapshot() so we never touch dm.items concurrently with
        // the download/playlist threads (which mutate it under items_mutex).
        var items = vector<DownloadItem>()
        snapshot_into(dm, &mut items)
        var out = string::make_no_len(QUEUE_HEADER)
        out.append('\n')
        for(var i = 0u; i < items.size(); i++) {
            var it = items.get_ptr(i)
            // Only persist real downloads. Playlist containers and their nested
            // video/audio children are driven by yt-dlp and are not resumable as
            // standalone DM tasks across restarts.
            if(it.card_type != ITEM_TYPE_NORMAL) { continue }
            // Skip items that are already finished — nothing to resume.
            if(it.state == STATE_DONE) { continue }
            out.append_string(&it.url)
            out.append(QUEUE_SEP)
            out.append_string(&it.id)
            out.append(QUEUE_SEP)
            out.append_string(&it.dir)
            out.append(QUEUE_SEP)
            out.append_integer(it.category as bigint)
            out.append(QUEUE_SEP)
            out.append_integer(it.downloaded_bytes as bigint)
            out.append(QUEUE_SEP)
            out.append_integer(it.total_bytes as bigint)
            out.append(QUEUE_SEP)
            if(it.was_interrupted) { out.append('1') } else { out.append('0') }
            out.append('\n')
        }

        var f = fopen(path.data(), "wb")
        if(f == null) { return false }
        var wrote = fwrite(out.data() as *mut u8, 1, out.size(), f)
        fclose(f)

        // Also write progress.txt on clean shutdown so crash recovery has
        // a fresh baseline. Atomic write.
        var ppath = progress_file()
        var pout = string::make_no_len("#cdm-progress-v1\n")
        for(var i = 0u; i < items.size(); i++) {
            var it = items.get_ptr(i)
            if(it.card_type != ITEM_TYPE_NORMAL) { continue }
            if(it.state == STATE_DONE) { continue }
            pout.append_string(&it.id)
            pout.append('\t')
            pout.append_integer(it.downloaded_bytes as bigint)
            pout.append('\t')
            pout.append_integer(it.total_bytes as bigint)
            pout.append('\t')
            if(it.was_interrupted) { pout.append('1') } else { pout.append('0') }
            pout.append('\n')
        }
        var ptmp = ppath.copy()
        ptmp.append_view(".tmp")
        var pf = fopen(ptmp.data(), "wb")
        if(pf != null) {
            fwrite(pout.data() as *mut u8, 1, pout.size(), pf)
            fflush(pf)
            fclose(pf)
            rename(ptmp.data(), ppath.data())
        }

        return wrote == out.size()
    }

} // end namespace cdm