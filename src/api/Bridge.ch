// ChemicalDM — JS<->native bridge. Replaces the HTTP API layer: the webview
// page calls window.webview_bridge.call(method, argsJson) and receives a JSON
// result synchronously. No server, no ports, no fetch — the bridge is wired
// through WebKitGTK's script-dialog interception (webview::webview_bind).

public namespace cdm {

using std::string;
using std::string_view;
// json module types (JsonParser, ASTJsonHandler, JsonValue) are top-level.

    // Extract a single string field from a JSON object string { "key": "..." }.
    // Returns an empty string when the field is absent or the args are invalid.
    func json_field(args : string_view, key : string_view) : string {
        var parser = JsonParser(128, 4096)
        var ph = ASTJsonHandler.make()
        parser.parse(args.data(), args.size(), &mut ph)
        if(ph.root is JsonValue.Object) {
            var Object(map) = ph.root else unreachable
            var k = string(key.data(), key.size())
            var vp = map.get_ptr(&k)
            if(vp != null && vp is JsonValue.String) {
                var String(v) = *vp else unreachable
                return v.copy()
            }
        }
        return string()
    }

    func ok_json() : string {
        return string::make_no_len("{\"ok\":true}")
    }

    func err_json(msg : &string) : string {
        var out = string::make_no_len("{\"ok\":false,\"error\":")
        out.append_string(&json_string(string_view::make_view(msg)))
        out.append('}')
        return out
    }

    // Native dispatcher invoked by the webview bridge for every JS call.
    // method : "state" | "add" | "pause" | "resume" | "cancel" | "remove"
    // args   : {} for state, {"url":...} for add, {"id":...} otherwise.
    public func bridge_call(dm : *mut DownloadManager, method : string_view, args : string_view) : string {
        var m_state = string_view::make_no_len("state")
        var m_add = string_view::make_no_len("add")
        var m_pause = string_view::make_no_len("pause")
        var m_resume = string_view::make_no_len("resume")
        var m_cancel = string_view::make_no_len("cancel")
        var m_remove = string_view::make_no_len("remove")

        if(method.equals(&m_state)) {
            return state_json(&mut *dm, string_view::make_no_len(CDM_VERSION))
        }
        if(method.equals(&m_add)) {
            var url = json_field(args, string_view::make_no_len("url"))
            if(url.size() == 0u) {
                var msg = string::make_no_len("missing url parameter")
                return err_json(&msg)
            }
            var id = add_task(&mut *dm, string_view::make_view(&url))
            var out = string::make_no_len("{\"ok\":true,\"id\":")
            out.append_string(&json_string(string_view::make_view(&id)))
            out.append('}')
            return out
        }
        if(method.equals(&m_pause)) {
            var id = json_field(args, string_view::make_no_len("id"))
            if(id.size() > 0u) { pause_task(&mut *dm, &id) }
            return ok_json()
        }
        if(method.equals(&m_resume)) {
            var id = json_field(args, string_view::make_no_len("id"))
            if(id.size() > 0u) { resume_task(&mut *dm, &id) }
            return ok_json()
        }
        if(method.equals(&m_cancel)) {
            var id = json_field(args, string_view::make_no_len("id"))
            if(id.size() > 0u) { cancel_task(&mut *dm, &id) }
            return ok_json()
        }
        if(method.equals(&m_remove)) {
            var id = json_field(args, string_view::make_no_len("id"))
            if(id.size() > 0u) { remove_task(&mut *dm, &id) }
            return ok_json()
        }
        var msg = string::make_no_len("unknown method: ")
        var mjs = json_string(method)
        msg.append_string(&mjs)
        return err_json(&msg)
    }

} // end namespace cdm