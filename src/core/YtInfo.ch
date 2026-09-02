// ChemicalDM — YouTube video and playlist metadata.
//
// Extracts video info and playlist entries using yt-dlp --dump-json.
// The structs are intentionally simple PODs (no nested allocations)
// so they can be serialized to JSON for the bridge without heavy deps.

public namespace cdm {

using std::string;
using std::string_view;
using std::vector;
using std::Result;
using std::Option;
using std::ordered_map;

    // ---- Format info (one entry from yt-dlp's formats array) ----

    public struct YtFormat {
        var format_id : string
        var ext : string
        var height : int
        var width : int
        var tbr : double           // total bitrate kbps
        var vcodec : string        // "none" if audio-only
        var acodec : string        // "none" if video-only
        var fps : int
        var format_note : string
        var filesize : i64
        var filesize_approx : i64
        var protocol : string      // yt-dlp protocol (https, https_dash, m3u8, http_hls, ...)

        @constructor func constructor() {
            return YtFormat {
                format_id = string(),
                ext = string(),
                height = 0,
                width = 0,
                tbr = 0.0,
                vcodec = string(),
                acodec = string(),
                fps = 0,
                format_note = string(),
                filesize = 0,
                filesize_approx = 0,
                protocol = string()
            }
        }

        public func copy(&self) : YtFormat {
            var c = YtFormat()
            c.format_id = self.format_id.copy()
            c.ext = self.ext.copy()
            c.height = self.height
            c.width = self.width
            c.tbr = self.tbr
            c.vcodec = self.vcodec.copy()
            c.acodec = self.acodec.copy()
            c.fps = self.fps
            c.format_note = self.format_note.copy()
            c.filesize = self.filesize
            c.filesize_approx = self.filesize_approx
            c.protocol = self.protocol.copy()
            return c
        }

        public func has_video(&self) : bool {
            return !self.vcodec.equals_view(string_view::make_no_len("none"))
        }

        public func has_audio(&self) : bool {
            return !self.acodec.equals_view(string_view::make_no_len("none"))
        }

        public func is_combined(&self) : bool {
            return self.has_video() && self.has_audio()
        }

        public func is_video_only(&self) : bool {
            return self.has_video() && !self.has_audio()
        }

        public func is_audio_only(&self) : bool {
            return !self.has_video() && self.has_audio()
        }

        // Human-readable label for the UI.
        public func quality_label(&self) : string {
            var out = string()
            if(self.is_audio_only()) {
                out.append_view(string_view::make_no_len("Audio "))
                out.append_string(&self.ext)
                return out
            }
            if(self.height > 0) {
                var h = string()
                h.append_integer(self.height as bigint)
                out.append_string(&h)
                out.append_view(string_view::make_no_len("p"))
            }
            if(self.fps > 30) {
                out.append(' ')
                var f = string()
                f.append_integer(self.fps as bigint)
                out.append_string(&f)
                out.append_view(string_view::make_no_len("fps"))
            }
            if(self.is_video_only()) {
                out.append_view(string_view::make_no_len(" [no audio]"))
            }
            if(self.format_note.size() > 0) {
                out.append(' ')
                out.append_string(&self.format_note)
            }
            out.append_view(string_view::make_no_len(" • "))
            out.append_string(&self.ext)
            return out
        }

        public func to_json(&self) : string {
            var out = string::make_no_len("{\"format_id\":")
            out.append_string(&json_string(string_view::make_view(&self.format_id)))
            out.append_string(&string::make_no_len(",\"ext\":"))
            out.append_string(&json_string(string_view::make_view(&self.ext)))
            out.append_string(&string::make_no_len(",\"height\":"))
            var hs = string()
            hs.append_integer(self.height as bigint)
            out.append_string(&hs)
            out.append_string(&string::make_no_len(",\"width\":"))
            var ws = string()
            ws.append_integer(self.width as bigint)
            out.append_string(&ws)
            out.append_string(&string::make_no_len(",\"tbr\":"))
            var tbrs = string()
            tbrs.append_double(self.tbr, 1)
            out.append_string(&tbrs)
            out.append_string(&string::make_no_len(",\"vcodec\":"))
            out.append_string(&json_string(string_view::make_view(&self.vcodec)))
            out.append_string(&string::make_no_len(",\"acodec\":"))
            out.append_string(&json_string(string_view::make_view(&self.acodec)))
            out.append_string(&string::make_no_len(",\"fps\":"))
            var fps_s = string()
            fps_s.append_integer(self.fps as bigint)
            out.append_string(&fps_s)
            out.append_string(&string::make_no_len(",\"format_note\":"))
            out.append_string(&json_string(string_view::make_view(&self.format_note)))
            out.append_string(&string::make_no_len(",\"label\":"))
            var label = self.quality_label()
            out.append_string(&json_string(string_view::make_view(&label)))
            out.append_string(&string::make_no_len(",\"is_combined\":"))
            if(self.is_combined()) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
            out.append_string(&string::make_no_len(",\"is_video_only\":"))
            if(self.is_video_only()) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
            out.append_string(&string::make_no_len(",\"is_audio_only\":"))
            if(self.is_audio_only()) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
            out.append_string(&string::make_no_len(",\"protocol\":"))
            out.append_string(&json_string(string_view::make_view(&self.protocol)))
            out.append('}')
            return out
        }
    }

    // ---- Video info ----

    public struct YtVideoInfo {
        var id : string
        var title : string
        var duration : i64          // seconds
        var thumbnail : string
        var webpage_url : string
        var formats : vector<YtFormat>
        var is_playlist : bool
        var playlist_id : string
        var playlist_title : string

        @constructor func constructor() {
            return YtVideoInfo {
                id = string(),
                title = string(),
                duration = 0,
                thumbnail = string(),
                webpage_url = string(),
                formats = vector<YtFormat>(),
                is_playlist = false,
                playlist_id = string(),
                playlist_title = string()
            }
        }

        public func duration_str(&self) : string {
            return format_duration_seconds(self.duration)
        }

        // Best combined format (has both video and audio, highest resolution).
        public func best_combined(&self) : Option<YtFormat> {
            var best : Option<YtFormat> = Option.None<YtFormat>()
            var best_height = -1
            for(var i = 0u; i < self.formats.size(); i++) {
                var f = self.formats.get_ptr(i)
                if(f.is_combined() && f.height > best_height) {
                    best_height = f.height
                    best = Option.Some<YtFormat>(f.copy())
                }
            }
            return best
        }

        // Best video-only format.
        public func best_video_only(&self) : Option<YtFormat> {
            var best : Option<YtFormat> = Option.None<YtFormat>()
            var best_height = -1
            for(var i = 0u; i < self.formats.size(); i++) {
                var f = self.formats.get_ptr(i)
                if(f.is_video_only() && f.height > best_height) {
                    best_height = f.height
                    best = Option.Some<YtFormat>(f.copy())
                }
            }
            return best
        }

        // Best audio-only format.
        public func best_audio_only(&self) : Option<YtFormat> {
            var best : Option<YtFormat> = Option.None<YtFormat>()
            var best_tbr = -1.0
            for(var i = 0u; i < self.formats.size(); i++) {
                var f = self.formats.get_ptr(i)
                if(f.is_audio_only() && f.tbr > best_tbr) {
                    best_tbr = f.tbr
                    best = Option.Some<YtFormat>(f.copy())
                }
            }
            return best
        }

        public func to_json(&self) : string {
            var out = string::make_no_len("{\"id\":")
            out.append_string(&json_string(string_view::make_view(&self.id)))
            out.append_string(&string::make_no_len(",\"title\":"))
            out.append_string(&json_string(string_view::make_view(&self.title)))
            out.append_string(&string::make_no_len(",\"duration\":"))
            var ds = string()
            ds.append_integer(self.duration as bigint)
            out.append_string(&ds)
            out.append_string(&string::make_no_len(",\"duration_str\":"))
            out.append_string(&json_string(string_view::make_view(self.duration_str())))
            out.append_string(&string::make_no_len(",\"thumbnail\":"))
            out.append_string(&json_string(string_view::make_view(&self.thumbnail)))
            out.append_string(&string::make_no_len(",\"webpage_url\":"))
            out.append_string(&json_string(string_view::make_view(&self.webpage_url)))
            out.append_string(&string::make_no_len(",\"is_playlist\":"))
            if(self.is_playlist) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
            // Formats array.
            out.append_string(&string::make_no_len(",\"formats\":["))
            for(var i = 0u; i < self.formats.size(); i++) {
                if(i > 0u) { out.append(',') }
                out.append_string(&self.formats.get_ptr(i).to_json())
            }
            out.append_string(&string::make_no_len("]"))
            out.append('}')
            return out
        }
    }

    // ---- Playlist entry ----

    public struct YtPlaylistEntry {
        var id : string
        var title : string
        var url : string
        var duration : i64
        var index : int

        @constructor func constructor() {
            return YtPlaylistEntry {
                id = string(),
                title = string(),
                url = string(),
                duration = 0,
                index = 0
            }
        }

        public func duration_str(&self) : string {
            if(self.duration <= 0) { return string() }
            return format_duration_seconds(self.duration)
        }

        public func to_json(&self) : string {
            var out = string::make_no_len("{\"id\":")
            out.append_string(&json_string(string_view::make_view(&self.id)))
            out.append_string(&string::make_no_len(",\"title\":"))
            out.append_string(&json_string(string_view::make_view(&self.title)))
            out.append_string(&string::make_no_len(",\"url\":"))
            out.append_string(&json_string(string_view::make_view(&self.url)))
            out.append_string(&string::make_no_len(",\"duration\":"))
            var ds = string()
            ds.append_integer(self.duration as bigint)
            out.append_string(&ds)
            out.append_string(&string::make_no_len(",\"duration_str\":"))
            out.append_string(&json_string(string_view::make_view(self.duration_str())))
            out.append_string(&string::make_no_len(",\"index\":"))
            var is = string()
            is.append_integer(self.index as bigint)
            out.append_string(&is)
            out.append('}')
            return out
        }
    }

    // ---- Playlist info ----

    public struct YtPlaylistInfo {
        var id : string
        var title : string
        var entries : vector<YtPlaylistEntry>
        var webpage_url : string
        var is_playlist : bool

        @constructor func constructor() {
            return YtPlaylistInfo {
                id = string(),
                title = string(),
                entries = vector<YtPlaylistEntry>(),
                webpage_url = string(),
                is_playlist = false
            }
        }

        public func entry_count(&self) : int {
            return self.entries.size() as int
        }

        public func to_json(&self) : string {
            var out = string::make_no_len("{\"id\":")
            out.append_string(&json_string(string_view::make_view(&self.id)))
            out.append_string(&string::make_no_len(",\"title\":"))
            out.append_string(&json_string(string_view::make_view(&self.title)))
            out.append_string(&string::make_no_len(",\"is_playlist\":"))
            if(self.is_playlist) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
            out.append_string(&string::make_no_len(",\"entry_count\":"))
            var cs = string()
            cs.append_integer(self.entry_count() as bigint)
            out.append_string(&cs)
            out.append_string(&string::make_no_len(",\"webpage_url\":"))
            out.append_string(&json_string(string_view::make_view(&self.webpage_url)))
            out.append_string(&string::make_no_len(",\"entries\":["))
            for(var i = 0u; i < self.entries.size(); i++) {
                if(i > 0u) { out.append(',') }
                out.append_string(&self.entries.get_ptr(i).to_json())
            }
            out.append_string(&string::make_no_len("]}"))
            return out
        }
    }

    // ---- Duration formatting ----

    public func format_duration_seconds(secs : i64) : string {
        if(secs <= 0) { return string() }
        var h = secs / 3600
        var m = (secs % 3600) / 60
        var s = secs % 60
        var out = string()
        if(h > 0) {
            out.append_integer(h as bigint)
            out.append(':')
        }
        if(m < 10 && h > 0) { out.append('0') }
        out.append_integer(m as bigint)
        out.append(':')
        if(s < 10) { out.append('0') }
        out.append_integer(s as bigint)
        return out
    }

    // ---- Info extraction (runs yt-dlp) ----

    // Extract info for a single video URL. Blocks until done.
    public func yt_extract_video_info(url : string_view) : Result<YtVideoInfo, string> {
        var path = ytdlp_resolved_path()
        var args = vector<string>()
        args.push_back(path.copy())
        args.push_back(string::make_no_len("--dump-json"))
        args.push_back(string::make_no_len("--no-warnings"))
        args.push_back(string::make_no_len("--no-playlist"))
        args.push_back(string(url.data(), url.size()))
        var cfg = make_exec_cfg(args)
        var res = process::execute(cfg)
        if(res is Result.Err) {
            var Err(e) = res else unreachable
            return Result.Err<YtVideoInfo, string>(e.message())
        }
        var Ok(pr) = res else unreachable
        if(!pr.success) {
            var err_out = string()
            for(var i = 0u; i < pr.output.stderr_data.size(); i++) {
                err_out.append(pr.output.stderr_data.get(i) as char)
            }
            if(err_out.empty()) {
                err_out = string::make_no_len("yt-dlp exited with error")
            }
            return Result.Err<YtVideoInfo, string>(err_out)
        }
        // Parse stdout JSON.
        var stdout_str = string()
        for(var i = 0u; i < pr.output.stdout_data.size(); i++) {
            stdout_str.append(pr.output.stdout_data.get(i) as char)
        }
        var info = parse_video_json(string_view::make_view(&stdout_str))
        return Result.Ok<YtVideoInfo, string>(info)
    }

    // Extract info for a playlist URL. flat=true for fast enumeration.
    public func yt_extract_playlist_info(url : string_view, flat : bool) : Result<YtPlaylistInfo, string> {
        var path = ytdlp_resolved_path()
        var args = vector<string>()
        args.push_back(path.copy())
        args.push_back(string::make_no_len("--dump-json"))
        args.push_back(string::make_no_len("--no-warnings"))
        if(flat) {
            args.push_back(string::make_no_len("--flat-playlist"))
        }
        args.push_back(string(url.data(), url.size()))
        var cfg = make_exec_cfg(args)
        var res = process::execute(cfg)
        if(res is Result.Err) {
            var Err(e) = res else unreachable
            return Result.Err<YtPlaylistInfo, string>(e.message())
        }
        var Ok(pr) = res else unreachable
        if(!pr.success) {
            var err_out = string()
            for(var i = 0u; i < pr.output.stderr_data.size(); i++) {
                err_out.append(pr.output.stderr_data.get(i) as char)
            }
            return Result.Err<YtPlaylistInfo, string>(err_out)
        }
        var stdout_str = string()
        for(var i = 0u; i < pr.output.stdout_data.size(); i++) {
            stdout_str.append(pr.output.stdout_data.get(i) as char)
        }
        var info = parse_playlist_json(string_view::make_view(&stdout_str))
        return Result.Ok<YtPlaylistInfo, string>(info)
    }

    // ---- JSON parsing helpers (using the json module) ----

    // Parse a single video JSON object into YtVideoInfo.
    public func parse_video_json(json_str : string_view) : YtVideoInfo {
        var info = YtVideoInfo()
        var parser = JsonParser(256, 1048576)
        var ph = ASTJsonHandler.make()
        parser.parse(json_str.data(), json_str.size(), &mut ph)

        if(ph.root is JsonValue.Object) {
            var Object(map) = ph.root else unreachable
            // Extract simple fields.
            info.id = json_get_string_field(&map, "id")
            info.title = json_get_string_field(&map, "title")
            info.thumbnail = json_get_string_field(&map, "thumbnail")
            info.webpage_url = json_get_string_field(&map, "webpage_url")
            info.duration = json_get_int_field(&map, "duration")

            // Playlist fields (if this is a playlist entry).
            info.playlist_id = json_get_string_field(&map, "playlist_id")
            info.playlist_title = json_get_string_field(&map, "playlist")
            if(info.playlist_id.size() > 0) {
                info.is_playlist = true
            }

            // Parse formats array.
            var formats_key = string("formats")
            var formats_vp = map.get_ptr(&formats_key)
            if(formats_vp != null && formats_vp is JsonValue.Array) {
                var Array(arr) = *formats_vp else unreachable
                for(var i = 0u; i < arr.size(); i++) {
                    var elem = arr.get_ptr(i)
                    if(elem != null && elem is JsonValue.Object) {
                        var Object(fmt_map) = *elem else unreachable
                        var fmt = YtFormat()
                        fmt.format_id = json_get_string_field(&fmt_map, "format_id")
                        fmt.ext = json_get_string_field(&fmt_map, "ext")
                        fmt.vcodec = json_get_string_field(&fmt_map, "vcodec")
                        fmt.acodec = json_get_string_field(&fmt_map, "acodec")
                        fmt.protocol = json_get_string_field(&fmt_map, "protocol")
                        fmt.format_note = json_get_string_field(&fmt_map, "format_note")
                        fmt.height = json_get_int_field(&fmt_map, "height") as int
                        fmt.width = json_get_int_field(&fmt_map, "width") as int
                        fmt.fps = json_get_int_field(&fmt_map, "fps") as int
                        fmt.filesize = json_get_i64_field(&fmt_map, "filesize")
                        fmt.filesize_approx = json_get_i64_field(&fmt_map, "filesize_approx")
                        fmt.tbr = json_get_double_field(&fmt_map, "tbr")
                        info.formats.push_back(fmt)
                    }
                }
            }
        }
        return info
    }

    // Parse playlist JSON (may be one JSON object with entries array,
    // or NDJSON — one JSON per line).
    public     func parse_playlist_json(json_str : string_view) : YtPlaylistInfo {
        var info = YtPlaylistInfo()
        info.is_playlist = true

        // Try NDJSON first (yt-dlp --flat-playlist --dump-json emits one
        // JSON object per line). Each line is a simplified entry.
        var ndjson_entries = vector<YtPlaylistEntry>()
        var ndjson_id = string()
        var ndjson_title = string()
        var ndjson_url = string()
        var pos : usize = 0
        var line_num = 0
        while(pos < json_str.size()) {
            var line_start = pos
            while(pos < json_str.size() && json_str.get(pos) != '\n') {
                pos = pos + 1u
            }
            var line_end = pos
            if(pos < json_str.size()) { pos = pos + 1u }  // skip \n
            if(line_end <= line_start) { continue }
            var trimmed_start = line_start
            while(trimmed_start < line_end && (json_str.get(trimmed_start) == ' ' || json_str.get(trimmed_start) == '\t' || json_str.get(trimmed_start) == '\r')) {
                trimmed_start = trimmed_start + 1u
            }
            if(trimmed_start >= line_end) { continue }
            if(json_str.get(trimmed_start) != '{') { continue }

            var line_parser = JsonParser(128, 1048576)
            var line_ph = ASTJsonHandler.make()
            line_parser.parse(json_str.data() + trimmed_start, line_end - trimmed_start, &mut line_ph)

            if(line_ph.root is JsonValue.Object) {
                var Object(line_map) = line_ph.root else unreachable
                var entry = parse_playlist_entry_copy(&line_map)
                line_num = line_num + 1
                entry.index = line_num
                ndjson_entries.push_back(entry)
                // First line may carry playlist-level metadata.
                if(ndjson_id.empty()) {
                    ndjson_id = json_get_string_field(&line_map, "playlist_id")
                    ndjson_title = json_get_string_field(&line_map, "playlist")
                    ndjson_url = json_get_string_field(&line_map, "webpage_url")
                }
            }
        }

        if(ndjson_entries.size() > 0u) {
            info.entries = ndjson_entries
            info.id = ndjson_id.copy()
            info.title = ndjson_title.copy()
            info.webpage_url = ndjson_url.copy()
            if(info.title.empty()) { info.title = string::make_no_len("Playlist") }
            return info
        }

        // Fall back to a single JSON object (with or without "entries").
        var parser = JsonParser(256, 1048576)
        var ph = ASTJsonHandler.make()
        parser.parse(json_str.data(), json_str.size(), &mut ph)

        if(ph.root is JsonValue.Object) {
            var Object(map) = ph.root else unreachable
            info.id = json_get_string_field(&map, "id")
            info.title = json_get_string_field(&map, "title")
            info.webpage_url = json_get_string_field(&map, "webpage_url")

            // Check for entries array.
            var entries_key = string("entries")
            var entries_vp = map.get_ptr(&entries_key)
            if(entries_vp != null && entries_vp is JsonValue.Array) {
                var Array(arr) = *entries_vp else unreachable
                for(var i = 0u; i < arr.size(); i++) {
                    var elem = arr.get_ptr(i)
                    if(elem != null && elem is JsonValue.Object) {
                        var Object(entry_map) = *elem else unreachable
                        var entry = parse_playlist_entry_copy(&entry_map)
                        entry.index = (i as int) + 1
                        info.entries.push_back(entry)
                    }
                }
                return info
            }
            // Single-video response used as playlist — treat as 1 entry.
            var entry = YtPlaylistEntry()
            entry.id = info.id.copy()
            entry.title = info.title.copy()
            entry.url = info.webpage_url.copy()
            entry.duration = json_get_int_field(&map, "duration")
            entry.index = 1
            info.entries.push_back(entry)
            return info
        }

        // If we still don't have a title, try to derive from URL.
        if(info.title.empty()) {
            info.title = string::make_no_len("Playlist")
        }
        return info
    }

    // Parse playlist entry from a pointer to the Object map (avoids move).
    func parse_playlist_entry_copy(m : &ordered_map<string, JsonValue>) : YtPlaylistEntry {
        var entry = YtPlaylistEntry()
        entry.id = json_get_string_field(m, "id")
        entry.title = json_get_string_field(m, "title")
        if(entry.title.empty()) {
            entry.title = string::make_no_len("Unknown")
        }
        entry.url = json_get_string_field(m, "webpage_url")
        if(entry.url.empty()) {
            if(entry.id.size() > 0) {
                entry.url = string::make_no_len("https://youtube.com/watch?v=")
                entry.url.append_string(&entry.id)
            }
        }
        entry.duration = json_get_int_field(m, "duration")
        return entry
    }

    func parse_playlist_entry(val : JsonValue) : YtPlaylistEntry {
        var entry = YtPlaylistEntry()
        if(val is JsonValue.Object) {
            var Object(m) = val else unreachable
            entry.id = json_get_string_field(&m, "id")
            entry.title = json_get_string_field(&m, "title")
            if(entry.title.empty()) {
                entry.title = string::make_no_len("Unknown")
            }
            entry.url = json_get_string_field(&m, "webpage_url")
            if(entry.url.empty()) {
                // Construct URL from id.
                if(entry.id.size() > 0) {
                    entry.url = string::make_no_len("https://youtube.com/watch?v=")
                    entry.url.append_string(&entry.id)
                }
            }
            entry.duration = json_get_int_field(&m, "duration")
        }
        return entry
    }

    // ---- JSON field extraction helpers using the json library ----
    // Use map.get() (returns value copy) instead of get_ptr() to avoid
    // dereferencing pointers to destructible structs.

    func json_get_string_field(m : &ordered_map<string, JsonValue>, key : *char) : string {
        var k = string(key)
        var vp = m.get_ptr(&k)
        if(vp != null && vp is JsonValue.String) {
            var String(v) = *vp else unreachable
            return v.copy()
        }
        return string()
    }

    func json_get_int_field(m : &ordered_map<string, JsonValue>, key : *char) : i64 {
        var k = string(key)
        var vp = m.get_ptr(&k)
        if(vp != null && vp is JsonValue.Number) {
            var Number(n) = *vp else unreachable
            return parse_i64_str(string_view::make_view(&n))
        }
        return 0
    }

    func json_get_i64_field(m : &ordered_map<string, JsonValue>, key : *char) : i64 {
        return json_get_int_field(m, key)
    }

    func json_get_double_field(m : &ordered_map<string, JsonValue>, key : *char) : double {
        var k = string(key)
        var vp = m.get_ptr(&k)
        if(vp != null && vp is JsonValue.Number) {
            var Number(n) = *vp else unreachable
            // Parse the number string as double.
            var val = 0.0
            var div = 1.0
            var in_decimal = false
            for(var i = 0u; i < n.size(); i++) {
                var c = n.get(i)
                if(c == '.') {
                    in_decimal = true
                } else if(c >= '0' && c <= '9') {
                    var digit = (c as double) - ('0' as double)
                    if(in_decimal) {
                        div = div * 10.0
                        val = val + digit / div
                    } else {
                        val = val * 10.0 + digit
                    }
                }
            }
            return val
        }
        return 0.0
    }

    func parse_i64_str(s : string_view) : i64 {
        var val : i64 = 0
        var neg = false
        for(var i = 0u; i < s.size(); i++) {
            var c = s.get(i)
            if(c == '-') { neg = true }
            else if(c >= '0' && c <= '9') {
                val = val * 10 + (c as i64 - '0' as i64)
            }
        }
        if(neg) { val = -val }
        return val
    }

} // end namespace cdm
