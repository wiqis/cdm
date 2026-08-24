// ChemicalDM — persistence. Stores the queue and settings near $HOME so a
// restart can resume paused and partially-downloaded tasks. The reader/writer
// here only needs to round-trip our own format; it is kept intentionally
// minimal and deterministic (no external json dependency).

public namespace cdm {

using std::string;
using std::string_view;
using std::vector;
using std::Option;

    public const CDM_STATE_FILE : *char = ".chemicaldm-state.json"

    // ---- minimal JSON writer ----

    func state_path() : string {
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
        var fn = string::make_no_len(CDM_STATE_FILE)
        path.append_string(&fn)
        return path
    }

    public func save_state(dir : string_view, dm : &DownloadManager) : bool {
        // Build the JSON document.
        var doc = string::make_no_len("{\"download_dir\":")
        var dir_s = json_string(dir)
        doc.append_string(&dir_s)
        doc.append_string(&string::make_no_len(",\"items\":["))
        for(var i = 0u; i < dm.items.size(); i++) {
            if(i > 0u) { doc.append(',') }
            var it = dm.items.get_ptr(i)
            doc.append('{')
            doc.append_string(&json_string(string_view::make_view(&it.id)))
            doc.append_string(&string::make_no_len(":"))
            doc.append_string(&json_string(string_view::make_view(&it.url)))
            doc.append('}')
        }
        doc.append_string(&string::make_no_len("]}"))

        var path = state_path()
        var f = fopen(path.data(), "wb")
        if(f == null) { return false }
        var wrote = fwrite(doc.data() as *mut u8, 1, doc.size(), f)
        fclose(f)
        return wrote == doc.size()
    }

    // ---- minimal JSON reader (subset: objects of string values) ----

    // Returns a vector of { key, value } pairs found in a top-level object.
    public func load_state() : Option<vector<std::pair<string, string>>> {
        var path = state_path()
        var f = fopen(path.data(), "rb")
        if(f == null) { return Option.None<vector<std::pair<string, string>>>() }

        // read whole file
        var content = string()
        unsafe var chunk : [4096u]u8
        while(true) {
            var n = fread(&raw mut chunk[0], 1, 4096u, f)
            if(n == 0u) { break }
            content.append_with_len(&raw mut chunk[0] as *char, n)
        }
        fclose(f)

        var pairs = vector<std::pair<string, string>>()
        var i : usize = 0
        // skip to first '{'
        while(i < content.size() && content.get(i) != '{') { i = i + 1u }
        i = i + 1u  // opening brace
        while(i < content.size() && content.get(i) != '}') {
            // skip whitespace and separators
            if(content.get(i) == '{' || content.get(i) == ',' || content.get(i) == ' ' || content.get(i) == '\n' || content.get(i) == '\r' || content.get(i) == '\t') {
                i = i + 1u
                continue
            }
            var key = parse_json_string(&content, &mut i)
            if(i >= content.size()) { break }
            // skip colon
            while(i < content.size() && content.get(i) != ':') { i = i + 1u }
            i = i + 1u
            if(i >= content.size()) { break }
            var c = content.get(i)
            if(c == '"') {
                var val = parse_json_string(&content, &mut i)
                pairs.push_back(std::pair<string, string>{ first : key, second : val })
            } else if(c == '{' || c == '[') {
                skip_json_value(&content, &mut i)
            } else if(c == '-' || (c >= '0' && c <= '9')) {
                var num = string()
                while(i < content.size() && content.get(i) != ',' && content.get(i) != '}') {
                    num.append(content.get(i))
                    i = i + 1u
                }
                pairs.push_back(std::pair<string, string>{ first : key, second : num })
            } else if(c == 't' || c == 'f' || c == 'n') {
                var w = string()
                while(i < content.size() && content.get(i) != ',' && content.get(i) != '}') {
                    w.append(content.get(i))
                    i = i + 1u
                }
                pairs.push_back(std::pair<string, string>{ first : key, second : w })
            }
        }
        return Option.Some<vector<std::pair<string, string>>>(pairs)
    }

    // Parse a double-quoted string starting at content[i]; advances i past the
    // closing quote. Returns the decoded value.
    func parse_json_string(content : &string, i : &mut usize) : string {
        // assume content.get(*i) == '"'
        var start = *i
        start = start + 1u
        var out = string()
        var p = start
        while(p < content.size()) {
            var c = content.get(p)
            if(c == '\\') {
                if(p + 1u < content.size()) {
                    var nxt = content.get(p + 1u)
                    if(nxt == 'n') { out.append('\n') }
                    else if(nxt == 'r') { out.append('\r') }
                    else if(nxt == 't') { out.append('\t') }
                    else if(nxt == '"') { out.append('"') }
                    else if(nxt == '\\') { out.append('\\') }
                    else { out.append(nxt) }
                    p = p + 2u
                    continue
                }
            } else if(c == '"') {
                *i = p + 1u
                return out
            } else {
                out.append(c)
            }
            p = p + 1u
        }
        *i = p
        return out
    }

    // Skip a JSON array or object body starting at content[*i] (char '{' or '[').
    func skip_json_value(content : &string, i : &mut usize) {
        var depth : int = 0
        var in_str = false
        while(*i < content.size()) {
            var c = content.get(*i)
            if(in_str) {
                if(c == '\\') { *i = *i + 2u; continue }
                if(c == '"') { in_str = false }
            } else {
                if(c == '"') { in_str = true }
                else if(c == '{' || c == '[') { depth = depth + 1 }
                else if(c == '}' || c == ']') {
                    depth = depth - 1
                    if(depth == 0) { *i = *i + 1u; return }
                }
            }
            *i = *i + 1u
        }
    }

} // end namespace cdm