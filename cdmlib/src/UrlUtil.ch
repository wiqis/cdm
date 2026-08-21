// ChemicalDM — URL parsing and filename helpers.
// Thin, careful wrappers around http::URL so engine code never touches the
// parsing details directly.

public namespace cdm {

using std::string;
using std::string_view;
using std::Option;

    public struct UrlInfo {
        var scheme : string
        var host : string
        var port : uint
        var path : string      // bare path, no query/fragment
        var query : string

        @constructor func constructor() {
            return UrlInfo {
                scheme = string(),
                host = string(),
                port = 0u,
                path = string(),
                query = string()
            }
        }

        // Request-target for the HTTP request line (origin-form).
        public func request_target(&self) : string {
            var s = string()
            s.append_string(&self.path)
            if(self.query.size() > 0) {
                s.append('?')
                s.append_string(&self.query)
            }
            return s
        }

        // scheme + "://" + host (used by the UI for display).
        public func display(&self) : string {
            var s = string()
            s.append_string(&self.scheme)
            var sep = string::make_no_len("://")
            s.append_string(&sep)
            s.append_string(&self.host)
            return s
        }
    }

    public func parse_url(url_str : string_view) : Option<UrlInfo> {
        var opt = http::URL::parse(&url_str)
        if(opt is Option.Some) {
            var Some(u) = opt else unreachable
            var info = UrlInfo()
            info.scheme = u.scheme.copy()
            info.host = u.host.copy()
            info.port = u.port
            info.path = u.path.copy()
            info.query = u.query.copy()
            return Option.Some<UrlInfo>(info)
        }
        return Option.None<UrlInfo>()
    }

    // Strip directory components, query/hash remnants and control chars from a
    // file name so it is safe to write on any filesystem.
    public func sanitize_filename(name : string_view) : string {
        var s = string()
        for(var i = 0u; i < name.size(); i++) {
            var c = name.get(i)
            if(c == '/') {
                // Keep only the final path segment: reset accumulator.
                s = string()
            } else if(c == '\\' || c == '\0' || c == ':' || c == '*' || c == '?' || c == '"' || c == '<' || c == '>' || c == '|') {
                // skip unsafe characters
            } else {
                s.append(c)
            }
        }
        if(s.empty()) {
            s = string::make_no_len("download")
        }
        return s
    }

    // Derive a suggested filename from a URL's last path segment.
    public func suggested_filename(url_str : string_view) : string {
        var opt = parse_url(url_str)
        if(opt is Option.Some) {
            var Some(u) = opt else unreachable
            var pathv = string_view::make_view(&u.path)
            var text = pathv
            var idx = pathv.find_last("/")
            if(idx != std::NPOS && (idx + 1u) <= pathv.size()) {
                text = pathv.subview(idx + 1u, pathv.size())
            }
            var cleaned = sanitize_filename(text)
            return cleaned
        }
        return string::make_no_len("download")
    }

} // end namespace cdm