// ChemicalDM — JS<->native bridge. Replaces the HTTP API layer: the webview
// page calls window.webview_bridge.call(method, argsJson) and receives a JSON
// result synchronously. No server, no ports, no fetch — the bridge is wired
// through WebKitGTK's script-dialog interception (webview::webview_bind).

public namespace cdm {

using std::string;
using std::string_view;
using std::Option;
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

    // Extract an integer field; returns `def` when absent or not numeric.
    func json_int_field(args : string_view, key : string_view, def : int) : int {
        var parser = JsonParser(128, 4096)
        var ph = ASTJsonHandler.make()
        parser.parse(args.data(), args.size(), &mut ph)
        if(ph.root is JsonValue.Object) {
            var Object(map) = ph.root else unreachable
            var k = string(key.data(), key.size())
            var vp = map.get_ptr(&k)
            if(vp != null) {
                if(vp is JsonValue.Number) {
                    var Number(n) = *vp else unreachable
                    var v : i64 = 0
                    var started = false
                    for(var i = 0u; i < n.size(); i++) {
                        var c = n.get(i)
                        if(c >= '0' && c <= '9') {
                            v = v * 10 + (c as i64 - '0' as i64)
                            started = true
                        } else if(c == '-') {
                            // ignore sign for simplicity (numeric config fields)
                        } else {
                            // decimal point or exponent: stop
                            break
                        }
                    }
                    if(started) { return v as int }
                }
                if(vp is JsonValue.Bool) {
                    var Bool(b) = *vp else unreachable
                    return if(b) 1 else 0
                }
            }
        }
        return def
    }

    // Extract a boolean field; returns `def` when absent.
    func json_bool_field(args : string_view, key : string_view, def : bool) : bool {
        var parser = JsonParser(128, 4096)
        var ph = ASTJsonHandler.make()
        parser.parse(args.data(), args.size(), &mut ph)
        if(ph.root is JsonValue.Object) {
            var Object(map) = ph.root else unreachable
            var k = string(key.data(), key.size())
            var vp = map.get_ptr(&k)
            if(vp != null) {
                if(vp is JsonValue.Bool) {
                    var Bool(b) = *vp else unreachable
                    return b
                }
                if(vp is JsonValue.Number) {
                    var Number(n) = *vp else unreachable
                    return n.equals_view("1") || n.equals_view("true")
                }
            }
        }
        return def
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

    // Serialize the current settings for the UI.
    func settings_json(dm : &DownloadManager) : string {
        var out = string::make_no_len("{\"download_dir\":")
        var dir_s = json_string(string_view::make_view(&dm.download_dir))
        out.append_string(&dir_s)
        out.append_string(&string::make_no_len(",\"max_concurrent\":"))
        out.append_integer(dm.max_concurrent as bigint)
        out.append_string(&string::make_no_len(",\"max_segments\":"))
        out.append_integer(dm.max_segments as bigint)
        out.append_string(&string::make_no_len(",\"speed_limit_kbps\":"))
        out.append_integer(dm.speed_limit_kbps as bigint)
        out.append_string(&string::make_no_len(",\"enable_resume\":"))
        if(dm.enable_resume) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"allow_segments\":"))
        if(dm.allow_segments) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"use_categories\":"))
        if(dm.use_categories) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"duplicate_action\":"))
        out.append_integer(dm.duplicate_action as bigint)
        out.append_string(&string::make_no_len(",\"auto_resume_failed\":"))
        if(dm.auto_resume_failed) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"max_retries\":"))
        out.append_integer(dm.max_retries as bigint)
        out.append_string(&string::make_no_len(",\"retry_delay_ms\":"))
        out.append_integer(dm.retry_delay_ms as bigint)
        out.append('}')
        return out
    }

    // Native dispatcher invoked by the webview bridge for every JS call.
    // method : "state" | "add" | "pause" | "resume" | "cancel" | "remove"
    //        | "remove_file" | "retry" | "restart" | "edit" | "settings_get"
    // args   : {} for state, {"url":...} for add, {"id":...} otherwise.
    public func bridge_call(dm : *mut DownloadManager, method : string_view, args : string_view) : string {
        var m_state = string_view::make_no_len("state")
        var m_add = string_view::make_no_len("add")
        var m_pause = string_view::make_no_len("pause")
        var m_resume = string_view::make_no_len("resume")
        var m_cancel = string_view::make_no_len("cancel")
        var m_remove = string_view::make_no_len("remove")
        var m_remove_file = string_view::make_no_len("remove_file")
        var m_retry = string_view::make_no_len("retry")
        var m_restart = string_view::make_no_len("restart")
        var m_edit = string_view::make_no_len("edit")
        var m_settings_get = string_view::make_no_len("settings_get")
        var m_settings_set = string_view::make_no_len("settings_set")

        if(method.equals(&m_state)) {
            return state_json(&mut *dm, string_view::make_no_len(CDM_VERSION))
        }
        if(method.equals(&m_add)) {
            var url = json_field(args, string_view::make_no_len("url"))
            if(url.size() == 0u) {
                var msg = string::make_no_len("missing url parameter")
                return err_json(&msg)
            }
            var dir = json_field(args, string_view::make_no_len("dir"))
            var fname = json_field(args, string_view::make_no_len("filename"))
            var prio = json_int_field(args, string_view::make_no_len("priority"), 0)
            var cat_str = json_field(args, string_view::make_no_len("category"))
            var cat = Category.Other
            if(cat_str.equals(&string::make_no_len("Documents"))) { cat = Category.Documents }
            else if(cat_str.equals(&string::make_no_len("Programs"))) { cat = Category.Programs }
            else if(cat_str.equals(&string::make_no_len("Video"))) { cat = Category.Video }
            else if(cat_str.equals(&string::make_no_len("Music"))) { cat = Category.Music }
            else if(cat_str.equals(&string::make_no_len("Compressed"))) { cat = Category.Compressed }
            var dirv = string_view::make_view(&dir)
            var fnamev = string_view::make_view(&fname)
            var id = add_task_ex(&mut *dm, string_view::make_view(&url), dirv, fnamev, prio, cat)
            if(id.size() == 0u) {
                var msg = string::make_no_len("duplicate download skipped")
                return err_json(&msg)
            }
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
        if(method.equals(&m_remove_file)) {
            var id = json_field(args, string_view::make_no_len("id"))
            if(id.size() > 0u) { remove_task_file(&mut *dm, &id, true) }
            return ok_json()
        }
        if(method.equals(&m_retry)) {
            var id = json_field(args, string_view::make_no_len("id"))
            if(id.size() > 0u) {
                var ok = retry_task(&mut *dm, &id)
                if(!ok) {
                    var msg = string::make_no_len("cannot retry item")
                    return err_json(&msg)
                }
            }
            return ok_json()
        }
        if(method.equals(&m_restart)) {
            var id = json_field(args, string_view::make_no_len("id"))
            if(id.size() > 0u) {
                var ok = restart_task(&mut *dm, &id)
                if(!ok) {
                    var msg = string::make_no_len("cannot restart item")
                    return err_json(&msg)
                }
            }
            return ok_json()
        }
        if(method.equals(&m_edit)) {
            var id = json_field(args, string_view::make_no_len("id"))
            if(id.size() == 0u) {
                var msg = string::make_no_len("missing id")
                return err_json(&msg)
            }
            var dir = json_field(args, string_view::make_no_len("dir"))
            var fname = json_field(args, string_view::make_no_len("filename"))
            var prio = json_int_field(args, string_view::make_no_len("priority"), 0)
            var segs = json_int_field(args, string_view::make_no_len("max_segments"), 0)
            var dirv = string_view::make_view(&dir)
            var fnamev = string_view::make_view(&fname)
            var ok = edit_item(&mut *dm, &id, dirv, fnamev, prio, segs, 0, Category.Other)
            if(!ok) {
                var msg = string::make_no_len("cannot edit running item")
                return err_json(&msg)
            }
            return ok_json()
        }
        var m_change_url = string_view::make_no_len("change_url")
        if(method.equals(&m_change_url)) {
            var id = json_field(args, string_view::make_no_len("id"))
            var new_url = json_field(args, string_view::make_no_len("url"))
            if(id.size() == 0u || new_url.size() == 0u) {
                var msg = string::make_no_len("missing id or url")
                return err_json(&msg)
            }
            var ok = change_url(&mut *dm, &id, string_view::make_view(&new_url))
            if(!ok) {
                var msg = string::make_no_len("cannot change url (item may be running)")
                return err_json(&msg)
            }
            return ok_json()
        }
        if(method.equals(&m_settings_get)) {
            return settings_json(&mut *dm)
        }
        if(method.equals(&m_settings_set)) {
            var dl = json_field(args, string_view::make_no_len("download_dir"))
            var conc = json_int_field(args, string_view::make_no_len("max_concurrent"), dm.max_concurrent)
            var seats = json_int_field(args, string_view::make_no_len("max_segments"), dm.max_segments)
            var speed = json_int_field(args, string_view::make_no_len("speed_limit_kbps"), dm.speed_limit_kbps as int)
            var dupact = json_int_field(args, string_view::make_no_len("duplicate_action"), dm.duplicate_action)
            var en_resume = json_bool_field(args, string_view::make_no_len("enable_resume"), dm.enable_resume)
            var al_segs = json_bool_field(args, string_view::make_no_len("allow_segments"), dm.allow_segments)
            var use_cats = json_bool_field(args, string_view::make_no_len("use_categories"), dm.use_categories)
            var auto_res = json_bool_field(args, string_view::make_no_len("auto_resume_failed"), dm.auto_resume_failed)
            var retries = json_int_field(args, string_view::make_no_len("max_retries"), dm.max_retries)
            var delay = json_int_field(args, string_view::make_no_len("retry_delay_ms"), dm.retry_delay_ms as int)
            if(dl.size() > 0u) {
                dm.download_dir = dl.copy()
            }
            if(conc > 0) { dm.max_concurrent = conc }
            if(seats > 0) { dm.max_segments = seats }
            dm.speed_limit_kbps = speed as i64
            dm.duplicate_action = dupact
            dm.enable_resume = en_resume
            dm.allow_segments = al_segs
            dm.use_categories = use_cats
            dm.auto_resume_failed = auto_res
            dm.max_retries = retries
            if(delay >= 0) { dm.retry_delay_ms = delay as i64 }
            // Persist the settings for next launch.
            var settings = CdmSettings()
            settings.download_dir = dm.download_dir.copy()
            settings.max_concurrent = dm.max_concurrent
            settings.max_segments = dm.max_segments
            settings.speed_limit_kbps = dm.speed_limit_kbps
            settings.duplicate_action = dm.duplicate_action
            settings.enable_resume = dm.enable_resume
            settings.allow_segments = dm.allow_segments
            settings.use_categories = dm.use_categories
            settings.auto_resume_failed = dm.auto_resume_failed
            settings.max_retries = dm.max_retries
            settings.retry_delay_ms = dm.retry_delay_ms
            save_settings(&settings)
            return ok_json()
        }
        var m_open_file = string_view::make_no_len("open_file")
        if(method.equals(&m_open_file)) {
            var path = json_field(args, string_view::make_no_len("path"))
            if(path.size() == 0u) {
                var msg = string::make_no_len("missing path")
                return err_json(&msg)
            }
            var cmd = string::make_no_len("xdg-open \"")
            cmd.append_string(&path)
            cmd.append('"')
            popen(cmd.data(), "r")
            return ok_json()
        }
        var m_show_folder = string_view::make_no_len("show_in_folder")
        if(method.equals(&m_show_folder)) {
            var path = json_field(args, string_view::make_no_len("path"))
            if(path.size() == 0u) {
                var msg = string::make_no_len("missing path")
                return err_json(&msg)
            }
            var cmd = string::make_no_len("xdg-open \"")
            cmd.append_string(&path)
            cmd.append('"')
            popen(cmd.data(), "r")
            return ok_json()
        }
        var msg = string::make_no_len("unknown method: ")
        var mjs = json_string(method)
        msg.append_string(&mjs)
        return err_json(&msg)
    }

} // end namespace cdm