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
        var user_agent : string
        var cookie_file : string
        var verify_ssl : bool
        var connect_timeout : int
        var max_download_size : i64          // 0 = unlimited
        var min_disk_space_mb : int          // 0 = unchecked
        var post_download_cmd : string
        var yt_quality : string              // e.g. "best", "worst", "720", "1080"
        var yt_format : string               // e.g. "video+audio", "bestvideo", "bestaudio"
        var yt_audio_only : bool
        var yt_max_playlist_items : int      // 0 = unlimited
        var referer_header : string
        var auth_header : string
        var force_ipv4 : bool
        var force_ipv6 : bool
        var filename_template : string       // e.g. "{title}.{ext}"
        var checksum : string                // e.g. "md5:abc123" or "sha256:..."
        var notifications_enabled : bool     // desktop notifications on completion/error
        var language : string                // UI language code (empty = auto)
        var max_history : int                // max completed downloads to keep in history (0 = unlimited)
        var theme : string                   // "auto", "light", "dark"
        // --- yt-dlp advanced ---
        var yt_output_template : string      // output filename template for yt-dlp
        var yt_audio_format : string         // audio extraction format: mp3, aac, flac, opus, vorbis
        var yt_audio_quality : int           // audio quality: 0=best, 10=worst (VBR)
        var yt_recode_video : string         // recode video to: avi, flv, mkv, mp4, webm
        var yt_merge_output_format : string  // merge format: mp4, mkv, webm, avi
        var yt_write_subs : bool             // download subtitles
        var yt_write_auto_subs : bool        // download auto-generated subtitles
        var yt_sub_langs : string            // subtitle languages: en,ja,es,etc
        var yt_embed_subs : bool             // embed subtitles in video
        var yt_convert_subs : string         // convert subs to: srt, vtt, ass, etc
        var yt_embed_metadata : bool         // embed metadata in video file
        var yt_embed_thumbnail : bool        // embed thumbnail as cover art
        var yt_write_description : bool      // write .description file
        var yt_write_info_json : bool        // write .info.json file
        var yt_write_comments : bool         // download video comments
        var yt_restrict_filenames : bool     // restrict to ASCII filenames
        var yt_trim_filenames : int          // max filename length (0 = unlimited)
        var yt_no_overwrites : bool          // don't overwrite existing files
        var yt_playlist_start : int          // playlist start index (1-based)
        var yt_playlist_end : int            // playlist end index (0 = all)
        var yt_playlist_items : string       // specific items: "1,2,5-10"
        var yt_proxy : string               // proxy: socks5://host:port
        var yt_geo_bypass : bool             // geo-restriction bypass
        var yt_geo_bypass_country : string   // country code for bypass
        var yt_extractor_retries : int       // extractor retry count
        var yt_socket_timeout : int          // socket timeout in seconds
        var yt_username : string             // YouTube username
        var yt_password : string             // YouTube password
        var yt_netrc : bool                  // use .netrc for authentication
        var yt_exec_cmd : string             // execute command after download
        var yt_ffmpeg_location : string      // custom ffmpeg path
        var yt_remove_sponsorblock : bool    // remove sponsor segments
        var yt_sponsorblock_mark : string    // mark sponsor segments (colors)
        // --- network advanced ---
        var yt_source_address : string       // source IP for yt-dlp
        var yt_legacy_server_connect : bool  // legacy SSL connections
        var yt_no_check_certificates : bool  // skip SSL verification for yt-dlp
        // --- ffmpeg post-processing ---
        var ffmpeg_video_codec : string      // h264, h265, vp9, av1
        var ffmpeg_audio_codec : string      // aac, mp3, opus
        var ffmpeg_audio_bitrate : string    // e.g. "192K", "320K"
        // --- download management ---
        var bandwidth_limit_per : i64        // per-download speed limit KB/s (0=unlimited)
        var auto_rename_duplicates : bool    // auto-rename when duplicate exists
        var move_completed_to : string       // move completed files to this folder
        var download_scheduler_enabled : bool // schedule downloads
        var download_scheduler_start : string // start time HH:MM
        var download_scheduler_end : string  // end time HH:MM
        var clipboard_monitor : bool         // auto-detect URLs from clipboard

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
                temporary_folder = string(),
                user_agent = string(),
                cookie_file = string(),
                verify_ssl = true,
                connect_timeout = SOCKET_TIMEOUT_SECS,
                max_download_size = 0,
                min_disk_space_mb = 0,
                post_download_cmd = string(),
                yt_quality = string(),
                yt_format = string(),
                yt_audio_only = false,
                yt_max_playlist_items = 0,
                referer_header = string(),
                auth_header = string(),
                force_ipv4 = false,
                force_ipv6 = false,
                filename_template = string(),
                checksum = string(),
                notifications_enabled = true,
                language = string(),
                max_history = 1000,
                theme = string::make_no_len("auto"),
                yt_output_template = string(),
                yt_audio_format = string(),
                yt_audio_quality = 0,
                yt_recode_video = string(),
                yt_merge_output_format = string::make_no_len("mp4"),
                yt_write_subs = false,
                yt_write_auto_subs = false,
                yt_sub_langs = string::make_no_len("en"),
                yt_embed_subs = false,
                yt_convert_subs = string(),
                yt_embed_metadata = true,
                yt_embed_thumbnail = false,
                yt_write_description = false,
                yt_write_info_json = false,
                yt_write_comments = false,
                yt_restrict_filenames = false,
                yt_trim_filenames = 0,
                yt_no_overwrites = true,
                yt_playlist_start = 0,
                yt_playlist_end = 0,
                yt_playlist_items = string(),
                yt_proxy = string(),
                yt_geo_bypass = false,
                yt_geo_bypass_country = string(),
                yt_extractor_retries = 3,
                yt_socket_timeout = 30,
                yt_username = string(),
                yt_password = string(),
                yt_netrc = false,
                yt_exec_cmd = string(),
                yt_ffmpeg_location = string(),
                yt_remove_sponsorblock = false,
                yt_sponsorblock_mark = string(),
                yt_source_address = string(),
                yt_legacy_server_connect = false,
                yt_no_check_certificates = false,
                ffmpeg_video_codec = string(),
                ffmpeg_audio_codec = string(),
                ffmpeg_audio_bitrate = string(),
                bandwidth_limit_per = 0,
                auto_rename_duplicates = false,
                move_completed_to = string(),
                download_scheduler_enabled = false,
                download_scheduler_start = string(),
                download_scheduler_end = string(),
                clipboard_monitor = false
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
            else if(kh == comptime_fnv1_hash("userAgent")) { out.user_agent = val.copy() }
            else if(kh == comptime_fnv1_hash("cookieFile")) { out.cookie_file = val.copy() }
            else if(kh == comptime_fnv1_hash("verifySsl")) { out.verify_ssl = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("connectTimeout")) {
                var n = parse_int_opt(val.data())
                if(n > 0) { out.connect_timeout = n }
            }
            else if(kh == comptime_fnv1_hash("maxDownloadSize")) {
                var n = parse_i64_from_view(string_view::make_view(&val))
                if(n >= 0) { out.max_download_size = n }
            }
            else if(kh == comptime_fnv1_hash("minDiskSpaceMb")) {
                var n = parse_int_opt(val.data())
                if(n >= 0) { out.min_disk_space_mb = n }
            }
            else if(kh == comptime_fnv1_hash("postDownloadCmd")) { out.post_download_cmd = val.copy() }
            else if(kh == comptime_fnv1_hash("ytQuality")) { out.yt_quality = val.copy() }
            else if(kh == comptime_fnv1_hash("ytFormat")) { out.yt_format = val.copy() }
            else if(kh == comptime_fnv1_hash("ytAudioOnly")) { out.yt_audio_only = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytMaxPlaylistItems")) {
                var n = parse_int_opt(val.data())
                if(n >= 0) { out.yt_max_playlist_items = n }
            }
            else if(kh == comptime_fnv1_hash("refererHeader")) { out.referer_header = val.copy() }
            else if(kh == comptime_fnv1_hash("authHeader")) { out.auth_header = val.copy() }
            else if(kh == comptime_fnv1_hash("forceIpv4")) { out.force_ipv4 = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("forceIpv6")) { out.force_ipv6 = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("filenameTemplate")) { out.filename_template = val.copy() }
            else if(kh == comptime_fnv1_hash("checksum")) { out.checksum = val.copy() }
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
        dm.user_agent = s.user_agent.copy()
        dm.cookie_file = s.cookie_file.copy()
        dm.verify_ssl = s.verify_ssl
        dm.connect_timeout = s.connect_timeout
        dm.max_download_size = s.max_download_size
        dm.min_disk_space_mb = s.min_disk_space_mb
        dm.post_download_cmd = s.post_download_cmd.copy()
        dm.yt_quality = s.yt_quality.copy()
        dm.yt_format = s.yt_format.copy()
        dm.yt_audio_only = s.yt_audio_only
        dm.yt_max_playlist_items = s.yt_max_playlist_items
        dm.referer_header = s.referer_header.copy()
        dm.auth_header = s.auth_header.copy()
        dm.force_ipv4 = s.force_ipv4
        dm.force_ipv6 = s.force_ipv6
        dm.filename_template = s.filename_template.copy()
        dm.checksum = s.checksum.copy()
        dm.notifications_enabled = s.notifications_enabled
        dm.language = s.language.copy()
        dm.max_history = s.max_history
        dm.theme = s.theme.copy()
        dm.yt_output_template = s.yt_output_template.copy()
        dm.yt_audio_format = s.yt_audio_format.copy()
        dm.yt_audio_quality = s.yt_audio_quality
        dm.yt_recode_video = s.yt_recode_video.copy()
        dm.yt_merge_output_format = s.yt_merge_output_format.copy()
        dm.yt_write_subs = s.yt_write_subs
        dm.yt_write_auto_subs = s.yt_write_auto_subs
        dm.yt_sub_langs = s.yt_sub_langs.copy()
        dm.yt_embed_subs = s.yt_embed_subs
        dm.yt_convert_subs = s.yt_convert_subs.copy()
        dm.yt_embed_metadata = s.yt_embed_metadata
        dm.yt_embed_thumbnail = s.yt_embed_thumbnail
        dm.yt_write_description = s.yt_write_description
        dm.yt_write_info_json = s.yt_write_info_json
        dm.yt_write_comments = s.yt_write_comments
        dm.yt_restrict_filenames = s.yt_restrict_filenames
        dm.yt_trim_filenames = s.yt_trim_filenames
        dm.yt_no_overwrites = s.yt_no_overwrites
        dm.yt_playlist_start = s.yt_playlist_start
        dm.yt_playlist_end = s.yt_playlist_end
        dm.yt_playlist_items = s.yt_playlist_items.copy()
        dm.yt_proxy = s.yt_proxy.copy()
        dm.yt_geo_bypass = s.yt_geo_bypass
        dm.yt_geo_bypass_country = s.yt_geo_bypass_country.copy()
        dm.yt_extractor_retries = s.yt_extractor_retries
        dm.yt_socket_timeout = s.yt_socket_timeout
        dm.yt_username = s.yt_username.copy()
        dm.yt_password = s.yt_password.copy()
        dm.yt_netrc = s.yt_netrc
        dm.yt_exec_cmd = s.yt_exec_cmd.copy()
        dm.yt_ffmpeg_location = s.yt_ffmpeg_location.copy()
        dm.yt_remove_sponsorblock = s.yt_remove_sponsorblock
        dm.yt_sponsorblock_mark = s.yt_sponsorblock_mark.copy()
        dm.yt_source_address = s.yt_source_address.copy()
        dm.yt_legacy_server_connect = s.yt_legacy_server_connect
        dm.yt_no_check_certificates = s.yt_no_check_certificates
        dm.ffmpeg_video_codec = s.ffmpeg_video_codec.copy()
        dm.ffmpeg_audio_codec = s.ffmpeg_audio_codec.copy()
        dm.ffmpeg_audio_bitrate = s.ffmpeg_audio_bitrate.copy()
        dm.bandwidth_limit_per = s.bandwidth_limit_per
        dm.auto_rename_duplicates = s.auto_rename_duplicates
        dm.move_completed_to = s.move_completed_to.copy()
        dm.download_scheduler_enabled = s.download_scheduler_enabled
        dm.download_scheduler_start = s.download_scheduler_start.copy()
        dm.download_scheduler_end = s.download_scheduler_end.copy()
        dm.clipboard_monitor = s.clipboard_monitor
        if(s.download_dir.size() > 0) {
            dm.download_dir = s.download_dir.copy()
        }
        // HTTP options are now passed through TaskRuntime, not globals.
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
        if(s.user_agent.size() > 0) {
            out.append_view("userAgent:")
            out.append_string(&s.user_agent)
            out.append_view("\n")
        }
        if(s.cookie_file.size() > 0) {
            out.append_view("cookieFile:")
            out.append_string(&s.cookie_file)
            out.append_view("\n")
        }
        out.append_view("verifySsl:")
        if(s.verify_ssl) { out.append_view("true\n") } else { out.append_view("false\n") }
        out.append_view("connectTimeout:")
        out.append_integer(s.connect_timeout as bigint)
        out.append_view("\n")
        if(s.max_download_size > 0) {
            out.append_view("maxDownloadSize:")
            out.append_integer(s.max_download_size as bigint)
            out.append_view("\n")
        }
        if(s.min_disk_space_mb > 0) {
            out.append_view("minDiskSpaceMb:")
            out.append_integer(s.min_disk_space_mb as bigint)
            out.append_view("\n")
        }
        if(s.post_download_cmd.size() > 0) {
            out.append_view("postDownloadCmd:")
            out.append_string(&s.post_download_cmd)
            out.append_view("\n")
        }
        if(s.yt_quality.size() > 0) {
            out.append_view("ytQuality:")
            out.append_string(&s.yt_quality)
            out.append_view("\n")
        }
        if(s.yt_format.size() > 0) {
            out.append_view("ytFormat:")
            out.append_string(&s.yt_format)
            out.append_view("\n")
        }
        out.append_view("ytAudioOnly:")
        if(s.yt_audio_only) { out.append_view("true\n") } else { out.append_view("false\n") }
        if(s.yt_max_playlist_items > 0) {
            out.append_view("ytMaxPlaylistItems:")
            out.append_integer(s.yt_max_playlist_items as bigint)
            out.append_view("\n")
        }
        if(s.referer_header.size() > 0) {
            out.append_view("refererHeader:")
            out.append_string(&s.referer_header)
            out.append_view("\n")
        }
        if(s.auth_header.size() > 0) {
            out.append_view("authHeader:")
            out.append_string(&s.auth_header)
            out.append_view("\n")
        }
        out.append_view("forceIpv4:")
        if(s.force_ipv4) { out.append_view("true\n") } else { out.append_view("false\n") }
        out.append_view("forceIpv6:")
        if(s.force_ipv6) { out.append_view("true\n") } else { out.append_view("false\n") }
        if(s.filename_template.size() > 0) {
            out.append_view("filenameTemplate:")
            out.append_string(&s.filename_template)
            out.append_view("\n")
        }
        if(s.checksum.size() > 0) {
            out.append_view("checksum:")
            out.append_string(&s.checksum)
            out.append_view("\n")
        }
        out.append_view("notificationsEnabled:")
        if(s.notifications_enabled) { out.append_view("true\n") } else { out.append_view("false\n") }
        if(s.language.size() > 0) {
            out.append_view("language:")
            out.append_string(&s.language)
            out.append_view("\n")
        }
        out.append_view("maxHistory:")
        out.append_integer(s.max_history as bigint)
        out.append_view("\n")
        if(s.theme.size() > 0) {
            out.append_view("theme:")
            out.append_string(&s.theme)
            out.append_view("\n")
        }
        // yt-dlp advanced settings
        if(s.yt_output_template.size() > 0) { out.append_view("ytOutputTemplate:"); out.append_string(&s.yt_output_template); out.append_view("\n") }
        if(s.yt_audio_format.size() > 0) { out.append_view("ytAudioFormat:"); out.append_string(&s.yt_audio_format); out.append_view("\n") }
        if(s.yt_audio_quality > 0) { out.append_view("ytAudioQuality:"); out.append_integer(s.yt_audio_quality as bigint); out.append_view("\n") }
        if(s.yt_recode_video.size() > 0) { out.append_view("ytRecodeVideo:"); out.append_string(&s.yt_recode_video); out.append_view("\n") }
        if(s.yt_merge_output_format.size() > 0) { out.append_view("ytMergeOutputFormat:"); out.append_string(&s.yt_merge_output_format); out.append_view("\n") }
        if(s.yt_write_subs) { out.append_view("ytWriteSubs:true\n") }
        if(s.yt_write_auto_subs) { out.append_view("ytWriteAutoSubs:true\n") }
        if(s.yt_sub_langs.size() > 0) { out.append_view("ytSubLangs:"); out.append_string(&s.yt_sub_langs); out.append_view("\n") }
        if(s.yt_embed_subs) { out.append_view("ytEmbedSubs:true\n") }
        if(s.yt_convert_subs.size() > 0) { out.append_view("ytConvertSubs:"); out.append_string(&s.yt_convert_subs); out.append_view("\n") }
        if(s.yt_embed_metadata) { out.append_view("ytEmbedMetadata:true\n") }
        if(s.yt_embed_thumbnail) { out.append_view("ytEmbedThumbnail:true\n") }
        if(s.yt_write_description) { out.append_view("ytWriteDescription:true\n") }
        if(s.yt_write_info_json) { out.append_view("ytWriteInfoJson:true\n") }
        if(s.yt_write_comments) { out.append_view("ytWriteComments:true\n") }
        if(s.yt_restrict_filenames) { out.append_view("ytRestrictFilenames:true\n") }
        if(s.yt_trim_filenames > 0) { out.append_view("ytTrimFilenames:"); out.append_integer(s.yt_trim_filenames as bigint); out.append_view("\n") }
        if(!s.yt_no_overwrites) { out.append_view("ytNoOverwrites:false\n") }
        if(s.yt_playlist_start > 0) { out.append_view("ytPlaylistStart:"); out.append_integer(s.yt_playlist_start as bigint); out.append_view("\n") }
        if(s.yt_playlist_end > 0) { out.append_view("ytPlaylistEnd:"); out.append_integer(s.yt_playlist_end as bigint); out.append_view("\n") }
        if(s.yt_playlist_items.size() > 0) { out.append_view("ytPlaylistItems:"); out.append_string(&s.yt_playlist_items); out.append_view("\n") }
        if(s.yt_proxy.size() > 0) { out.append_view("ytProxy:"); out.append_string(&s.yt_proxy); out.append_view("\n") }
        if(s.yt_geo_bypass) { out.append_view("ytGeoBypass:true\n") }
        if(s.yt_geo_bypass_country.size() > 0) { out.append_view("ytGeoBypassCountry:"); out.append_string(&s.yt_geo_bypass_country); out.append_view("\n") }
        if(s.yt_extractor_retries != 3) { out.append_view("ytExtractorRetries:"); out.append_integer(s.yt_extractor_retries as bigint); out.append_view("\n") }
        if(s.yt_socket_timeout != 30) { out.append_view("ytSocketTimeout:"); out.append_integer(s.yt_socket_timeout as bigint); out.append_view("\n") }
        if(s.yt_username.size() > 0) { out.append_view("ytUsername:"); out.append_string(&s.yt_username); out.append_view("\n") }
        if(s.yt_password.size() > 0) { out.append_view("ytPassword:"); out.append_string(&s.yt_password); out.append_view("\n") }
        if(s.yt_netrc) { out.append_view("ytNetrc:true\n") }
        if(s.yt_exec_cmd.size() > 0) { out.append_view("ytExecCmd:"); out.append_string(&s.yt_exec_cmd); out.append_view("\n") }
        if(s.yt_ffmpeg_location.size() > 0) { out.append_view("ytFfmpegLocation:"); out.append_string(&s.yt_ffmpeg_location); out.append_view("\n") }
        if(s.yt_remove_sponsorblock) { out.append_view("ytRemoveSponsorblock:true\n") }
        if(s.yt_sponsorblock_mark.size() > 0) { out.append_view("ytSponsorblockMark:"); out.append_string(&s.yt_sponsorblock_mark); out.append_view("\n") }
        if(s.yt_source_address.size() > 0) { out.append_view("ytSourceAddress:"); out.append_string(&s.yt_source_address); out.append_view("\n") }
        if(s.yt_legacy_server_connect) { out.append_view("ytLegacyServerConnect:true\n") }
        if(s.yt_no_check_certificates) { out.append_view("ytNoCheckCertificates:true\n") }
        if(s.ffmpeg_video_codec.size() > 0) { out.append_view("ffmpegVideoCodec:"); out.append_string(&s.ffmpeg_video_codec); out.append_view("\n") }
        if(s.ffmpeg_audio_codec.size() > 0) { out.append_view("ffmpegAudioCodec:"); out.append_string(&s.ffmpeg_audio_codec); out.append_view("\n") }
        if(s.ffmpeg_audio_bitrate.size() > 0) { out.append_view("ffmpegAudioBitrate:"); out.append_string(&s.ffmpeg_audio_bitrate); out.append_view("\n") }
        if(s.bandwidth_limit_per > 0) { out.append_view("bandwidthLimitPer:"); out.append_integer(s.bandwidth_limit_per); out.append_view("\n") }
        if(s.auto_rename_duplicates) { out.append_view("autoRenameDuplicates:true\n") }
        if(s.move_completed_to.size() > 0) { out.append_view("moveCompletedTo:"); out.append_string(&s.move_completed_to); out.append_view("\n") }
        if(s.clipboard_monitor) { out.append_view("clipboardMonitor:true\n") }
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
            else if(kh == comptime_fnv1_hash("userAgent")) { s.user_agent = val.copy() }
            else if(kh == comptime_fnv1_hash("cookieFile")) { s.cookie_file = val.copy() }
            else if(kh == comptime_fnv1_hash("verifySsl")) { s.verify_ssl = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("connectTimeout")) {
                var n = parse_int_opt(val.data())
                if(n > 0) { s.connect_timeout = n }
            }
            else if(kh == comptime_fnv1_hash("maxDownloadSize")) {
                var n = parse_i64_from_view(string_view::make_view(&val))
                if(n >= 0) { s.max_download_size = n }
            }
            else if(kh == comptime_fnv1_hash("minDiskSpaceMb")) {
                var n = parse_int_opt(val.data())
                if(n >= 0) { s.min_disk_space_mb = n }
            }
            else if(kh == comptime_fnv1_hash("postDownloadCmd")) { s.post_download_cmd = val.copy() }
            else if(kh == comptime_fnv1_hash("ytQuality")) { s.yt_quality = val.copy() }
            else if(kh == comptime_fnv1_hash("ytFormat")) { s.yt_format = val.copy() }
            else if(kh == comptime_fnv1_hash("ytAudioOnly")) { s.yt_audio_only = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytMaxPlaylistItems")) {
                var n = parse_int_opt(val.data())
                if(n >= 0) { s.yt_max_playlist_items = n }
            }
            else if(kh == comptime_fnv1_hash("refererHeader")) { s.referer_header = val.copy() }
            else if(kh == comptime_fnv1_hash("authHeader")) { s.auth_header = val.copy() }
            else if(kh == comptime_fnv1_hash("forceIpv4")) { s.force_ipv4 = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("forceIpv6")) { s.force_ipv6 = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("filenameTemplate")) { s.filename_template = val.copy() }
            else if(kh == comptime_fnv1_hash("checksum")) { s.checksum = val.copy() }
            else if(kh == comptime_fnv1_hash("notificationsEnabled")) { s.notifications_enabled = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("language")) { s.language = val.copy() }
            else if(kh == comptime_fnv1_hash("maxHistory")) {
                var n = parse_int_opt(val.data())
                if(n >= 0) { s.max_history = n }
            }
            else if(kh == comptime_fnv1_hash("theme")) { s.theme = val.copy() }
            // yt-dlp advanced
            else if(kh == comptime_fnv1_hash("ytOutputTemplate")) { s.yt_output_template = val.copy() }
            else if(kh == comptime_fnv1_hash("ytAudioFormat")) { s.yt_audio_format = val.copy() }
            else if(kh == comptime_fnv1_hash("ytAudioQuality")) { var n = parse_int_opt(val.data()); if(n >= 0) { s.yt_audio_quality = n } }
            else if(kh == comptime_fnv1_hash("ytRecodeVideo")) { s.yt_recode_video = val.copy() }
            else if(kh == comptime_fnv1_hash("ytMergeOutputFormat")) { s.yt_merge_output_format = val.copy() }
            else if(kh == comptime_fnv1_hash("ytWriteSubs")) { s.yt_write_subs = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytWriteAutoSubs")) { s.yt_write_auto_subs = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytSubLangs")) { s.yt_sub_langs = val.copy() }
            else if(kh == comptime_fnv1_hash("ytEmbedSubs")) { s.yt_embed_subs = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytConvertSubs")) { s.yt_convert_subs = val.copy() }
            else if(kh == comptime_fnv1_hash("ytEmbedMetadata")) { s.yt_embed_metadata = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytEmbedThumbnail")) { s.yt_embed_thumbnail = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytWriteDescription")) { s.yt_write_description = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytWriteInfoJson")) { s.yt_write_info_json = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytWriteComments")) { s.yt_write_comments = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytRestrictFilenames")) { s.yt_restrict_filenames = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytTrimFilenames")) { var n = parse_int_opt(val.data()); if(n >= 0) { s.yt_trim_filenames = n } }
            else if(kh == comptime_fnv1_hash("ytNoOverwrites")) { s.yt_no_overwrites = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytPlaylistStart")) { var n = parse_int_opt(val.data()); if(n >= 0) { s.yt_playlist_start = n } }
            else if(kh == comptime_fnv1_hash("ytPlaylistEnd")) { var n = parse_int_opt(val.data()); if(n >= 0) { s.yt_playlist_end = n } }
            else if(kh == comptime_fnv1_hash("ytPlaylistItems")) { s.yt_playlist_items = val.copy() }
            else if(kh == comptime_fnv1_hash("ytProxy")) { s.yt_proxy = val.copy() }
            else if(kh == comptime_fnv1_hash("ytGeoBypass")) { s.yt_geo_bypass = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytGeoBypassCountry")) { s.yt_geo_bypass_country = val.copy() }
            else if(kh == comptime_fnv1_hash("ytExtractorRetries")) { var n = parse_int_opt(val.data()); if(n >= 0) { s.yt_extractor_retries = n } }
            else if(kh == comptime_fnv1_hash("ytSocketTimeout")) { var n = parse_int_opt(val.data()); if(n >= 0) { s.yt_socket_timeout = n } }
            else if(kh == comptime_fnv1_hash("ytUsername")) { s.yt_username = val.copy() }
            else if(kh == comptime_fnv1_hash("ytPassword")) { s.yt_password = val.copy() }
            else if(kh == comptime_fnv1_hash("ytNetrc")) { s.yt_netrc = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytExecCmd")) { s.yt_exec_cmd = val.copy() }
            else if(kh == comptime_fnv1_hash("ytFfmpegLocation")) { s.yt_ffmpeg_location = val.copy() }
            else if(kh == comptime_fnv1_hash("ytRemoveSponsorblock")) { s.yt_remove_sponsorblock = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytSponsorblockMark")) { s.yt_sponsorblock_mark = val.copy() }
            else if(kh == comptime_fnv1_hash("ytSourceAddress")) { s.yt_source_address = val.copy() }
            else if(kh == comptime_fnv1_hash("ytLegacyServerConnect")) { s.yt_legacy_server_connect = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ytNoCheckCertificates")) { s.yt_no_check_certificates = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("ffmpegVideoCodec")) { s.ffmpeg_video_codec = val.copy() }
            else if(kh == comptime_fnv1_hash("ffmpegAudioCodec")) { s.ffmpeg_audio_codec = val.copy() }
            else if(kh == comptime_fnv1_hash("ffmpegAudioBitrate")) { s.ffmpeg_audio_bitrate = val.copy() }
            else if(kh == comptime_fnv1_hash("bandwidthLimitPer")) { var n = parse_i64_from_view(string_view::make_view(&val)); if(n >= 0) { s.bandwidth_limit_per = n } }
            else if(kh == comptime_fnv1_hash("autoRenameDuplicates")) { s.auto_rename_duplicates = parse_bool(&val) }
            else if(kh == comptime_fnv1_hash("moveCompletedTo")) { s.move_completed_to = val.copy() }
            else if(kh == comptime_fnv1_hash("clipboardMonitor")) { s.clipboard_monitor = parse_bool(&val) }
        }
        return s
    }

    // Parse a JSON settings export and populate a CdmSettings. Returns true on success.
    // Uses a simple key-value JSON parser (handles flat objects only).
    // Helper: read a JSON string value (after opening quote) into a string.
    func read_json_string(s : &string_view, i : &mut usize) : string {
        var out = string()
        while(*i < s.size() && s.get(*i) != '"') {
            if(s.get(*i) == '\\' && *i + 1 < s.size()) { *i = *i + 1 }  // skip escaped char
            out.append(s.get(*i))
            *i = *i + 1
        }
        if(*i < s.size()) { *i = *i + 1 }  // skip closing quote
        return out
    }

    // Parse a JSON settings export and populate a CdmSettings. Returns true on success.
    // Uses a simple key-value JSON parser (handles flat objects only).
    public func parse_settings_json(data : *u8, len : usize, out : &mut CdmSettings) : bool {
        var s = string_view(data as *char, len)
        // Simple JSON parser: extract "key": value pairs
        var i : usize = 0
        while(i < s.size()) {
            // Skip to next '"'
            while(i < s.size() && s.get(i) != '"') { i = i + 1 }
            if(i >= s.size()) { break }
            i = i + 1  // skip opening quote
            var key = read_json_string(&s, &mut i)
            // Skip to ':'
            while(i < s.size() && s.get(i) != ':') { i = i + 1 }
            if(i >= s.size()) { break }
            i = i + 1  // skip ':'
            // Skip whitespace
            while(i < s.size() && (s.get(i) == ' ' || s.get(i) == '\t' || s.get(i) == '\n' || s.get(i) == '\r')) { i = i + 1 }
            if(i >= s.size()) { break }
            // Parse value
            var val = string()
            var val_is_bool = false
            var val_bool = false
            var val_is_num = false
            var val_num : i64 = 0
            if(s.get(i) == '"') {
                i = i + 1  // skip opening quote
                val = read_json_string(&s, &mut i)
            } else if(s.get(i) == 't' || s.get(i) == 'f') {
                val_is_bool = true
                if(s.get(i) == 't') { val_bool = true; i = i + 4 }  // true
                else { val_bool = false; i = i + 5 }  // false
            } else if(s.get(i) == '-' || (s.get(i) >= '0' && s.get(i) <= '9')) {
                val_is_num = true
                var neg = false
                if(s.get(i) == '-') { neg = true; i = i + 1 }
                var n : i64 = 0
                while(i < s.size() && s.get(i) >= '0' && s.get(i) <= '9') {
                    n = n * 10 + (s.get(i) as i64 - '0' as i64)
                    i = i + 1
                }
                if(neg) { n = -n }
                val_num = n
            } else {
                while(i < s.size() && s.get(i) != ',' && s.get(i) != '}') { i = i + 1 }
                continue
            }
            // Apply to settings by key
            var kh = fnv1_hash_view(string_view::make_view(&key))
            if(kh == comptime_fnv1_hash("download_dir") || kh == comptime_fnv1_hash("downloadFolder")) { out.download_dir = val.copy() }
            else if(kh == comptime_fnv1_hash("max_concurrent") || kh == comptime_fnv1_hash("parallelDownloads")) { if(val_is_num) { out.max_concurrent = val_num as int } }
            else if(kh == comptime_fnv1_hash("max_segments") || kh == comptime_fnv1_hash("maxSegments")) { if(val_is_num) { out.max_segments = val_num as int } }
            else if(kh == comptime_fnv1_hash("speed_limit_kbps") || kh == comptime_fnv1_hash("speedLimit")) { if(val_is_num) { out.speed_limit_kbps = val_num } }
            else if(kh == comptime_fnv1_hash("enable_resume")) { if(val_is_bool) { out.enable_resume = val_bool } }
            else if(kh == comptime_fnv1_hash("allow_segments")) { if(val_is_bool) { out.allow_segments = val_bool } }
            else if(kh == comptime_fnv1_hash("duplicate_action") || kh == comptime_fnv1_hash("duplicateAction")) { if(val_is_num) { out.duplicate_action = val_num as int } }
            else if(kh == comptime_fnv1_hash("auto_resume_failed")) { if(val_is_bool) { out.auto_resume_failed = val_bool } }
            else if(kh == comptime_fnv1_hash("max_retries") || kh == comptime_fnv1_hash("maxRetries")) { if(val_is_num) { out.max_retries = val_num as int } }
            else if(kh == comptime_fnv1_hash("retry_delay_ms") || kh == comptime_fnv1_hash("retryDelayMs")) { if(val_is_num) { out.retry_delay_ms = val_num } }
            else if(kh == comptime_fnv1_hash("user_agent") || kh == comptime_fnv1_hash("userAgent")) { out.user_agent = val.copy() }
            else if(kh == comptime_fnv1_hash("cookie_file") || kh == comptime_fnv1_hash("cookieFile")) { out.cookie_file = val.copy() }
            else if(kh == comptime_fnv1_hash("verify_ssl") || kh == comptime_fnv1_hash("verifySsl")) { if(val_is_bool) { out.verify_ssl = val_bool } }
            else if(kh == comptime_fnv1_hash("connect_timeout") || kh == comptime_fnv1_hash("connectTimeout")) { if(val_is_num) { out.connect_timeout = val_num as int } }
            else if(kh == comptime_fnv1_hash("max_download_size") || kh == comptime_fnv1_hash("maxDownloadSize")) { if(val_is_num) { out.max_download_size = val_num } }
            else if(kh == comptime_fnv1_hash("min_disk_space_mb") || kh == comptime_fnv1_hash("minDiskSpaceMb")) { if(val_is_num) { out.min_disk_space_mb = val_num as int } }
            else if(kh == comptime_fnv1_hash("post_download_cmd") || kh == comptime_fnv1_hash("postDownloadCmd")) { out.post_download_cmd = val.copy() }
            else if(kh == comptime_fnv1_hash("yt_quality") || kh == comptime_fnv1_hash("ytQuality")) { out.yt_quality = val.copy() }
            else if(kh == comptime_fnv1_hash("yt_format") || kh == comptime_fnv1_hash("ytFormat")) { out.yt_format = val.copy() }
            else if(kh == comptime_fnv1_hash("yt_audio_only") || kh == comptime_fnv1_hash("ytAudioOnly")) { if(val_is_bool) { out.yt_audio_only = val_bool } }
            else if(kh == comptime_fnv1_hash("yt_max_playlist_items") || kh == comptime_fnv1_hash("ytMaxPlaylistItems")) { if(val_is_num) { out.yt_max_playlist_items = val_num as int } }
            else if(kh == comptime_fnv1_hash("referer_header") || kh == comptime_fnv1_hash("refererHeader")) { out.referer_header = val.copy() }
            else if(kh == comptime_fnv1_hash("auth_header") || kh == comptime_fnv1_hash("authHeader")) { out.auth_header = val.copy() }
            else if(kh == comptime_fnv1_hash("force_ipv4") || kh == comptime_fnv1_hash("forceIpv4")) { if(val_is_bool) { out.force_ipv4 = val_bool } }
            else if(kh == comptime_fnv1_hash("force_ipv6") || kh == comptime_fnv1_hash("forceIpv6")) { if(val_is_bool) { out.force_ipv6 = val_bool } }
            else if(kh == comptime_fnv1_hash("filename_template") || kh == comptime_fnv1_hash("filenameTemplate")) { out.filename_template = val.copy() }
            else if(kh == comptime_fnv1_hash("checksum")) { out.checksum = val.copy() }
            else if(kh == comptime_fnv1_hash("notifications_enabled") || kh == comptime_fnv1_hash("notificationsEnabled")) { if(val_is_bool) { out.notifications_enabled = val_bool } }
            else if(kh == comptime_fnv1_hash("language")) { out.language = val.copy() }
            else if(kh == comptime_fnv1_hash("max_history") || kh == comptime_fnv1_hash("maxHistory")) { if(val_is_num) { out.max_history = val_num as int } }
            else if(kh == comptime_fnv1_hash("theme")) { out.theme = val.copy() }
            // Skip to next comma
            while(i < s.size() && s.get(i) != ',') { i = i + 1 }
            if(i < s.size()) { i = i + 1 }  // skip comma
        }
        return true
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
    // manager, preserving the original id, destination directory, category,
    // progress, and state so resume works correctly across restarts.
    // Does NOT call start_pending (the caller must do that once after all items
    // are restored, so workers don't start before progress is applied).
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
            // Fields are tab-separated: url \t id \t dir \t [category] \t [downloaded] \t [total] \t [interrupted] \t [state]
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
            var saved_state : i64 = STATE_QUEUED as i64
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
                        // v2+ row: ... \t downloaded \t total \t interrupted \t [state]
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
                                var rest6 = rest5.substring(tab6 + 1u, rest5.size())
                                var tab7 = rest6.find(std::string_view::make_no_len("\t"))
                                if(tab7 != std::NPOS) {
                                    var int_s = rest6.substring(0u, tab7)
                                    was_interrupted = int_s.equals_view("1")
                                    var state_s = rest6.substring(tab7 + 1u, rest6.size())
                                    saved_state = parse_i64(string_view::make_view(&state_s))
                                } else {
                                    var int_s = rest6
                                    was_interrupted = int_s.equals_view("1")
                                }
                            } else {
                                total = parse_i64(string_view::make_view(&rest5))
                            }
                        } else {
                            downloaded = parse_i64(string_view::make_view(&rest4))
                        }
                    }
                }
            }
            // Insert the item directly (bypass add_task_ex_id to avoid
            // triggering start_pending before all progress is applied).
            var id_copy = id.copy()
            if(id_copy.empty()) {
                id_copy = uuid::v4().to_string()
            }
            var resolved_dir = dm.download_dir.copy()
            if(dir.size() > 0) {
                resolved_dir = dir.copy()
            }
            var suggested = suggested_filename(string_view::make_view(&url))
            var item = DownloadItem(id_copy.copy(), string(url.data(), url.size()),
                                    resolved_dir.copy(), suggested.copy())
            item.category = category as int
            // Apply saved progress and state.
            item.downloaded_bytes = downloaded
            item.total_bytes = total
            item.was_interrupted = was_interrupted
            item.state = saved_state as int
            if(was_interrupted && item.state != STATE_DONE && item.state != STATE_FAILED) {
                item.state = STATE_FAILED
                item.error = string::make_no_len("interrupted by shutdown")
            }
            dm.items_mutex.lock()
            dm.items.push_back(item)
            dm.items_mutex.unlock()
            restored = restored + 1
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
            if(c == '-' && !started) { neg = true }
            else if(c >= '0' && c <= '9') {
                val = val * 10 + (c as i64 - '0' as i64)
                started = true
            } else if(started) {
                break
            }
        }
        if(!started) { return 0 }
        if(neg) { val = -val }
        return val
    }

    // Save the queue to disk. Does not block the engine.
    // Format (tab-separated, one row per item):
    //   url \t id \t dir \t category \t downloaded \t total \t was_interrupted \t state
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
            out.append(QUEUE_SEP)
            out.append_integer(it.state as bigint)
            out.append('\n')
        }

        // Atomic write: write to .tmp then rename so a crash during write
        // never corrupts the queue file.
        var tmp_path = path.copy()
        tmp_path.append_view(".tmp")
        var f = fopen(tmp_path.data(), "wb")
        if(f == null) { return false }
        var wrote = fwrite(out.data() as *mut u8, 1, out.size(), f)
        fflush(f)
        fclose(f)
        rename(tmp_path.data(), path.data())

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