// ChemicalDM — JSON generation for API responses.
// Manual string building keeps the wire format fully under our control and
// avoids depending on the json library's emit details for hot paths.

public namespace cdm {

using std::string;
using std::string_view;
using std::vector;

    // Escape a string for use inside a JSON string literal.
    public func json_escape(s : string_view) : string {
        var out = string()

        var backslash_q = string::make_no_len("\\\"")
        var backslash_b = string::make_no_len("\\\\")
        var backslash_n = string::make_no_len("\\n")
        var backslash_r = string::make_no_len("\\r")
        var backslash_t = string::make_no_len("\\t")
        var u00 = string::make_no_len("\\u00")
        var hexdigits = string::make_no_len("0123456789abcdef")

        for(var i = 0u; i < s.size(); i++) {
            var c = s.get(i)
            if(c == '"') { out.append_string(&backslash_q) }
            else if(c == '\\') { out.append_string(&backslash_b) }
            else if(c == '\n') { out.append_string(&backslash_n) }
            else if(c == '\r') { out.append_string(&backslash_r) }
            else if(c == '\t') { out.append_string(&backslash_t) }
            else if(c < 0x20 as char) {
                // Four hex digits after "\u": e.g. 0x01 -> \u0001, 0x1F -> \u001F.
                var u = c as uint
                out.append_string(&u00)
                out.append(hexdigits.get(((u >> 4) & 0xF) as uint))
                out.append(hexdigits.get((u & 0xF) as uint))
            } else {
                out.append(c)
            }
        }
        return out
    }

    // Wrap a string in JSON quotes.
    public func json_string(s : string_view) : string {
        var out = string::make_no_len("\"")
        out.append_string(&json_escape(s))
        out.append('"')
        return out
    }

    public func json_i64(value : i64) : string {
        var s = string()
        s.append_integer(value as bigint)
        return s
    }

    public func json_int(value : int) : string {
        var s = string()
        s.append_integer(value as bigint)
        return s
    }

    // Append `"key":value` plus a comma separator unless it is the first pair.
    func json_kv(out : &mut string, key : string_view, value : &string, first : &mut bool) {
        if(!*first) { out.append(',') }
        *first = false
        out.append_string(&json_string(key))
        out.append(':')
        out.append_string(value)
    }

    // Append `"key":pre_serialized_json` — the value is already valid JSON.
    func json_kv_raw(out : &mut string, key : string_view, value : &string, first : &mut bool) {
        if(!*first) { out.append(',') }
        *first = false
        out.append_string(&json_string(key))
        out.append(':')
        out.append_string(value)
    }

    // Serialize one download item as a JSON object.
    public func item_to_json(item : &DownloadItem) : string {
        var id_s = json_string(string_view::make_view(&item.id))
        var url_s = json_string(string_view::make_view(&item.url))
        var filename_s = json_string(string_view::make_view(&item.filename))
        var dir_s = json_string(string_view::make_view(&item.dir))
        var state_name = format_state(item.state)
        var state_s = json_string(string_view::make_view(&state_name))
        var error_s = json_string(string_view::make_view(&item.error))
        var display = item.display_filename()
        var display_s = json_string(string_view::make_view(&display))

        var total_s = json_i64(item.total_bytes)
        var down_s = json_i64(item.downloaded_bytes)
        var speed_s = json_i64(item.speed_bytes_per_sec)
        var prio_s = json_int(item.priority)
        var seg_s = json_int(item.max_segments)
        var speed_lim_s = json_i64(item.speed_limit_kbps)
        var dup_s = json_int(item.duplicate_suffix)
        var cat_name = format_category(item.category)
        var cat_s = json_string(string_view::make_view(&cat_name))

        var percent = 0.0
        if(item.total_bytes > 0) { percent = (item.downloaded_bytes as double) * 100.0 / (item.total_bytes as double) }
        var percent_str = string()
        percent_str.append_double(percent, 1)
        var percent_s = json_string(string_view::make_view(&percent_str))

        var remaining = item.total_bytes - item.downloaded_bytes
        var eta_str = format_eta(remaining, item.speed_bytes_per_sec)
        var eta_s = json_string(string_view::make_view(&eta_str))

        var out = string()
        out.append('{')
        var first = true
        json_kv(&mut out, "id", &id_s, &mut first)
        json_kv(&mut out, "url", &url_s, &mut first)
        json_kv(&mut out, "filename", &filename_s, &mut first)
        json_kv(&mut out, "display_name", &display_s, &mut first)
        json_kv(&mut out, "dir", &dir_s, &mut first)
        json_kv(&mut out, "state", &state_s, &mut first)
        json_kv(&mut out, "error", &error_s, &mut first)
        json_kv(&mut out, "total_bytes", &total_s, &mut first)
        json_kv(&mut out, "downloaded_bytes", &down_s, &mut first)
        json_kv(&mut out, "speed_bytes_per_sec", &speed_s, &mut first)
        json_kv(&mut out, "priority", &prio_s, &mut first)
        json_kv(&mut out, "max_segments", &seg_s, &mut first)
        json_kv(&mut out, "speed_limit_kbps", &speed_lim_s, &mut first)
        json_kv(&mut out, "duplicate_suffix", &dup_s, &mut first)
        json_kv(&mut out, "category", &cat_s, &mut first)
        json_kv(&mut out, "percent", &percent_s, &mut first)
        json_kv(&mut out, "eta", &eta_s, &mut first)
        var type_s = json_int(item.card_type)
        json_kv(&mut out, "card_type", &type_s, &mut first)
        var parent_s = json_string(string_view::make_view(&item.parent_id))
        json_kv(&mut out, "parent_id", &parent_s, &mut first)
        var retry_s = json_int(item.retry_count)
        json_kv(&mut out, "retry_count", &retry_s, &mut first)
        var interrupted_s = if(item.was_interrupted) "true" else "false"
        var interrupted_sv = string::make_no_len(interrupted_s)
        json_kv(&mut out, "was_interrupted", &interrupted_sv, &mut first)
        if(!item.segments_json.empty()) {
            json_kv_raw(&mut out, "segments", &item.segments_json, &mut first)
        }
        out.append('}')
        return out
    }

    // Serialize the whole queue: { "items": [ ... ] }
    public func queue_to_json(downloads : &vector<DownloadItem>) : string {
        var out = string::make_no_len("{\"items\":[")
        for(var i = 0u; i < downloads.size(); i++) {
            if(i > 0u) { out.append(',') }
            out.append_string(&item_to_json(&*downloads.get_ptr(i)))
        }
        out.append_string(&string::make_no_len("]}"))
        return out
    }

    // Serialize app settings.
    public func settings_to_json(download_dir : string_view, max_concurrent : int) : string {
        var dir_s = json_string(download_dir)
        var max_s = json_int(max_concurrent)
        var out = string::make_no_len("{\"download_dir\":")
        out.append_string(&dir_s)
        out.append_string(&string::make_no_len(",\"max_concurrent\":"))
        out.append_string(&max_s)
        out.append('}')
        return out
    }

} // end namespace cdm