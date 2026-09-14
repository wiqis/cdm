// ChemicalDM — JS<->native bridge. Replaces the HTTP API layer: the webview
// page calls window.webview_bridge.call(method, argsJson) and receives a JSON
// result synchronously. No server, no ports, no fetch — the bridge is wired
// through WebKitGTK's script-dialog interception (webview::webview_bind).

public namespace cdm {

using std::string;
using std::string_view;
using std::Option;
using std::Result;
using std::vector;
// json module types (JsonParser, ASTJsonHandler, JsonValue) are top-level.

    // Build the full queue state as a JSON document for the UI.
    // Moved from DownloadManager (library no longer handles serialization).
    func state_json(dm : &mut DownloadManager, version : string_view) : string {
        var dir_copy = dm.download_dir.copy()
        var out = string::make_no_len("{\"download_dir\":")
        out.append_string(&json_string(string_view::make_view(&dir_copy)))
        out.append_string(&string::make_no_len(",\"max_concurrent\":"))
        out.append_integer(dm.max_concurrent as bigint)
        out.append_string(&string::make_no_len(",\"version\":"))
        out.append_string(&json_string(version))
        out.append_string(&string::make_no_len(",\"items\":["))
        var snap = vector<DownloadItem>()
        snapshot_into(dm, &mut snap)
        for(var i = 0u; i < snap.size(); i++) {
            if(i > 0u) { out.append(',') }
            var it = snap.get_ptr(i)
            out.append_string(&item_to_json(&*it))
        }
        out.append_string(&string::make_no_len("]}"))
        return out
    }

    // Resolve the args from the webview bridge into a JSON object string.
    // The bridge JS wraps every call body in a params array:
    //   {id, method, params: [body]}
    // so `args` arrives as ["{...}"] or [{...}] (array wrapping).
    // This helper extracts the first array element (when it's a string)
    // and re-parses it, or returns the original args if already an object.
    func resolve_bridge_args(args : string_view) : string {
        var parser = JsonParser(128, 4096)
        var ph = ASTJsonHandler.make()
        parser.parse(args.data(), args.size(), &mut ph)
        // If already a JSON object, return as-is.
        if(ph.root is JsonValue.Object) {
            return string(args.data(), args.size())
        }
        // If an array, extract element 0 (the stringified body).
        if(ph.root is JsonValue.Array) {
            var Array(arr) = ph.root else unreachable
            if(arr.size() > 0) {
                var elem = arr.get_ptr(0)
                if(elem is JsonValue.String) {
                    var String(s) = *elem else unreachable
                    return s.copy()
                }
                // Element is an object (not stringified) — serialize back.
                if(elem is JsonValue.Object) {
                    // Fall through and return original; caller will handle.
                }
            }
        }
        return string(args.data(), args.size())
    }

    // Extract a single string field from a JSON object string { "key": "..." }.
    // Returns an empty string when the field is absent or the args are invalid.
    func json_field(args : string_view, key : string_view) : string {
        var resolved = resolve_bridge_args(args)
        var rview = string_view::make_view(&resolved)
        var parser = JsonParser(128, 4096)
        var ph = ASTJsonHandler.make()
        parser.parse(rview.data(), rview.size(), &mut ph)
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
        var resolved = resolve_bridge_args(args)
        var rview = string_view::make_view(&resolved)
        var parser = JsonParser(128, 4096)
        var ph = ASTJsonHandler.make()
        parser.parse(rview.data(), rview.size(), &mut ph)
        if(ph.root is JsonValue.Object) {
            var Object(map) = ph.root else unreachable
            var k = string(key.data(), key.size())
            var vp = map.get_ptr(&k)
            if(vp != null) {
                if(vp is JsonValue.Number) {
                    var Number(n) = *vp else unreachable
                    var v : i64 = 0
                    var started = false
                    var negative = false
                    for(var i = 0u; i < n.size(); i++) {
                        var c = n.get(i)
                        if(c >= '0' && c <= '9') {
                            v = v * 10 + (c as i64 - '0' as i64)
                            started = true
                        } else if(c == '-' && !started) {
                            negative = true
                        } else {
                            // decimal point or exponent: stop
                            break
                        }
                    }
                    if(started) { if(negative) { return (0 - v) as int } else { return v as int } }
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
        var resolved = resolve_bridge_args(args)
        var rview = string_view::make_view(&resolved)
        var parser = JsonParser(128, 4096)
        var ph = ASTJsonHandler.make()
        parser.parse(rview.data(), rview.size(), &mut ph)
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

    // Convenience: build err_json from a C-style string literal.
    func err_msg(msg : *char) : string {
        var s = string(msg)
        return err_json(&s)
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
        out.append_string(&string::make_no_len(",\"duplicate_action\":"))
        out.append_integer(dm.duplicate_action as bigint)
        out.append_string(&string::make_no_len(",\"auto_resume_failed\":"))
        if(dm.auto_resume_failed) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"max_retries\":"))
        out.append_integer(dm.retry_policy.max_retries as bigint)
        out.append_string(&string::make_no_len(",\"retry_delay_ms\":"))
        out.append_integer(dm.retry_policy.delay_ms as bigint)
        out.append_string(&string::make_no_len(",\"user_agent\": "))
        var ua_s = json_string(string_view::make_view(&dm.user_agent))
        out.append_string(&ua_s)
        out.append_string(&string::make_no_len(",\"cookie_file\": "))
        var ck_s = json_string(string_view::make_view(&dm.cookie_file))
        out.append_string(&ck_s)
        out.append_string(&string::make_no_len(",\"verify_ssl\": "))
        if(dm.verify_ssl) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"connect_timeout\": "))
        out.append_integer(dm.connect_timeout as bigint)
        out.append_string(&string::make_no_len(",\"max_download_size\": "))
        out.append_integer(dm.max_download_size as bigint)
        out.append_string(&string::make_no_len(",\"min_disk_space_mb\": "))
        out.append_integer(dm.min_disk_space_mb as bigint)
        out.append_string(&string::make_no_len(",\"post_download_cmd\": "))
        var pdc_s = json_string(string_view::make_view(&dm.post_download_cmd))
        out.append_string(&pdc_s)
        out.append_string(&string::make_no_len(",\"yt_quality\": "))
        var yq_s = json_string(string_view::make_view(&dm.yt_quality))
        out.append_string(&yq_s)
        out.append_string(&string::make_no_len(",\"yt_format\": "))
        var yf_s = json_string(string_view::make_view(&dm.yt_format))
        out.append_string(&yf_s)
        out.append_string(&string::make_no_len(",\"yt_audio_only\": "))
        if(dm.yt_audio_only) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"yt_max_playlist_items\": "))
        out.append_integer(dm.yt_max_playlist_items as bigint)
        out.append_string(&string::make_no_len(",\"referer_header\": "))
        var ref_s = json_string(string_view::make_view(&dm.referer_header))
        out.append_string(&ref_s)
        out.append_string(&string::make_no_len(",\"auth_header\": "))
        var auth_s = json_string(string_view::make_view(&dm.auth_header))
        out.append_string(&auth_s)
        out.append_string(&string::make_no_len(",\"force_ipv4\": "))
        if(dm.force_ipv4) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"force_ipv6\": "))
        if(dm.force_ipv6) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"filename_template\": "))
        var ft_s = json_string(string_view::make_view(&dm.filename_template))
        out.append_string(&ft_s)
        out.append_string(&string::make_no_len(",\"checksum\": "))
        var cs_s = json_string(string_view::make_view(&dm.checksum))
        out.append_string(&cs_s)
        out.append_string(&string::make_no_len(",\"notifications_enabled\": "))
        if(dm.notifications_enabled) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"language\": "))
        var lang_s = json_string(string_view::make_view(&dm.language))
        out.append_string(&lang_s)
        out.append_string(&string::make_no_len(",\"max_history\": "))
        out.append_integer(dm.max_history as bigint)
        out.append_string(&string::make_no_len(",\"theme\": "))
        var th_s = json_string(string_view::make_view(&dm.theme))
        out.append_string(&th_s)
        // yt-dlp advanced
        out.append_string(&string::make_no_len(",\"yt_output_template\":")); var yt_out_s = json_string(string_view::make_view(&dm.yt_output_template)); out.append_string(&yt_out_s)
        out.append_string(&string::make_no_len(",\"yt_audio_format\":")); var yt_af_s = json_string(string_view::make_view(&dm.yt_audio_format)); out.append_string(&yt_af_s)
        out.append_string(&string::make_no_len(",\"yt_audio_quality\":")); out.append_integer(dm.yt_audio_quality as bigint)
        out.append_string(&string::make_no_len(",\"yt_recode_video\":")); var yt_rv_s = json_string(string_view::make_view(&dm.yt_recode_video)); out.append_string(&yt_rv_s)
        out.append_string(&string::make_no_len(",\"yt_merge_output_format\":")); var yt_mof_s = json_string(string_view::make_view(&dm.yt_merge_output_format)); out.append_string(&yt_mof_s)
        out.append_string(&string::make_no_len(",\"yt_write_subs\":")); if(dm.yt_write_subs) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"yt_write_auto_subs\":")); if(dm.yt_write_auto_subs) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"yt_sub_langs\":")); var yt_sl_s = json_string(string_view::make_view(&dm.yt_sub_langs)); out.append_string(&yt_sl_s)
        out.append_string(&string::make_no_len(",\"yt_embed_subs\":")); if(dm.yt_embed_subs) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"yt_convert_subs\":")); var yt_cs_s = json_string(string_view::make_view(&dm.yt_convert_subs)); out.append_string(&yt_cs_s)
        out.append_string(&string::make_no_len(",\"yt_embed_metadata\":")); if(dm.yt_embed_metadata) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"yt_embed_thumbnail\":")); if(dm.yt_embed_thumbnail) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"yt_write_description\":")); if(dm.yt_write_description) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"yt_write_info_json\":")); if(dm.yt_write_info_json) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"yt_restrict_filenames\":")); if(dm.yt_restrict_filenames) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"yt_trim_filenames\":")); out.append_integer(dm.yt_trim_filenames as bigint)
        out.append_string(&string::make_no_len(",\"yt_no_overwrites\":")); if(dm.yt_no_overwrites) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"yt_playlist_start\":")); out.append_integer(dm.yt_playlist_start as bigint)
        out.append_string(&string::make_no_len(",\"yt_playlist_end\":")); out.append_integer(dm.yt_playlist_end as bigint)
        out.append_string(&string::make_no_len(",\"yt_proxy\":")); var yt_px_s = json_string(string_view::make_view(&dm.yt_proxy)); out.append_string(&yt_px_s)
        out.append_string(&string::make_no_len(",\"yt_geo_bypass\":")); if(dm.yt_geo_bypass) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"yt_geo_bypass_country\":")); var yt_gc_s = json_string(string_view::make_view(&dm.yt_geo_bypass_country)); out.append_string(&yt_gc_s)
        out.append_string(&string::make_no_len(",\"yt_extractor_retries\":")); out.append_integer(dm.yt_extractor_retries as bigint)
        out.append_string(&string::make_no_len(",\"yt_socket_timeout\":")); out.append_integer(dm.yt_socket_timeout as bigint)
        out.append_string(&string::make_no_len(",\"yt_exec_cmd\":")); var yt_ec_s = json_string(string_view::make_view(&dm.yt_exec_cmd)); out.append_string(&yt_ec_s)
        out.append_string(&string::make_no_len(",\"yt_ffmpeg_location\":")); var yt_fl_s = json_string(string_view::make_view(&dm.yt_ffmpeg_location)); out.append_string(&yt_fl_s)
        out.append_string(&string::make_no_len(",\"yt_remove_sponsorblock\":")); if(dm.yt_remove_sponsorblock) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"yt_source_address\":")); var yt_sa_s = json_string(string_view::make_view(&dm.yt_source_address)); out.append_string(&yt_sa_s)
        out.append_string(&string::make_no_len(",\"yt_legacy_server_connect\":")); if(dm.yt_legacy_server_connect) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"yt_no_check_certificates\":")); if(dm.yt_no_check_certificates) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"ffmpeg_video_codec\":")); var ff_vc_s = json_string(string_view::make_view(&dm.ffmpeg_video_codec)); out.append_string(&ff_vc_s)
        out.append_string(&string::make_no_len(",\"ffmpeg_audio_codec\":")); var ff_ac_s = json_string(string_view::make_view(&dm.ffmpeg_audio_codec)); out.append_string(&ff_ac_s)
        out.append_string(&string::make_no_len(",\"ffmpeg_audio_bitrate\":")); var ff_ab_s = json_string(string_view::make_view(&dm.ffmpeg_audio_bitrate)); out.append_string(&ff_ab_s)
        out.append_string(&string::make_no_len(",\"bandwidth_limit_per\":")); out.append_integer(dm.bandwidth_limit_per)
        out.append_string(&string::make_no_len(",\"auto_rename_duplicates\":")); if(dm.auto_rename_duplicates) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"move_completed_to\":")); var mct_s = json_string(string_view::make_view(&dm.move_completed_to)); out.append_string(&mct_s)
        out.append_string(&string::make_no_len(",\"clipboard_monitor\":")); if(dm.clipboard_monitor) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"proxy_host\":")); var prx_h_s = json_string(string_view::make_view(&dm.proxy_host)); out.append_string(&prx_h_s)
        out.append_string(&string::make_no_len(",\"proxy_port\":")); out.append_integer(dm.proxy_port as bigint)
        out.append_string(&string::make_no_len(",\"yt_write_comments\":")); if(dm.yt_write_comments) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
        out.append_string(&string::make_no_len(",\"yt_playlist_items\":")); var yt_pi_s = json_string(string_view::make_view(&dm.yt_playlist_items)); out.append_string(&yt_pi_s)
        out.append_string(&string::make_no_len(",\"yt_sponsorblock_mark\":")); var yt_sbm_s = json_string(string_view::make_view(&dm.yt_sponsorblock_mark)); out.append_string(&yt_sbm_s)
        out.append_string(&string::make_no_len(",\"use_categories\":")); if(dm.use_categories) { out.append_string(&string::make_no_len("true")) } else { out.append_string(&string::make_no_len("false")) }
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
            // Reject malformed URLs before queueing so users get immediate,
            // meaningful feedback instead of a download that fails later.
            var url_err = validate_url(string_view::make_view(&url))
            if(!url_err.is_ok()) {
                return err_json(&url_err.message)
            }
            var dir = json_field(args, string_view::make_no_len("dir"))
            var fname = json_field(args, string_view::make_no_len("filename"))
            var prio = json_int_field(args, string_view::make_no_len("priority"), 0)
            var cat_str = json_field(args, string_view::make_no_len("category"))

            // Category routing: resolve the category → directory here in the app,
            // then pass the resolved directory to the library. The numeric tag is
            // stored opaquely on the item so the UI can display/filter it.
            var resolved_dir = dir.copy()
            var cat_tag = 0
            if(resolved_dir.size() == 0u) {
                var cat = Category.Other
                if(cat_str.equals(&string::make_no_len("Documents"))) { cat = Category.Documents }
                else if(cat_str.equals(&string::make_no_len("Programs"))) { cat = Category.Programs }
                else if(cat_str.equals(&string::make_no_len("Video"))) { cat = Category.Video }
                else if(cat_str.equals(&string::make_no_len("Music"))) { cat = Category.Music }
                else if(cat_str.equals(&string::make_no_len("Compressed"))) { cat = Category.Compressed }
            if(cat != Category.Other) {
                cat_tag = cat as int
                var sub = category_dir(cat)
                resolved_dir = dm.download_dir.copy()
                if(sub.size() > 0) {
                    // avoid stacking separators when the root already ends in '/'
                    if(resolved_dir.size() > 0 && resolved_dir.get(resolved_dir.size() - 1u) != '/') {
                        resolved_dir.append('/')
                    }
                    resolved_dir.append_string(&sub)
                }
            }
            }
            var dirv = string_view::make_view(&resolved_dir)
            var fnamev = string_view::make_view(&fname)
            var id = add_task_ex(&mut *dm, string_view::make_view(&url), dirv, fnamev, prio, cat_tag)
            if(id.size() == 0u) {
                var msg = string::make_no_len("duplicate download skipped")
                return err_json(&msg)
            }
            // Apply per-task speed limit if provided.
            var sl = json_int_field(args, string_view::make_no_len("speed_limit_kbps"), 0)
            if(sl > 0) {
                dm.items_mutex.lock()
                var idx = find_item_index(&*dm, &id)
                if(idx < dm.items.size()) {
                    dm.items.get_ptr(idx).speed_limit_kbps = sl as i64
                }
                dm.items_mutex.unlock()
            }
            var out = string::make_no_len("{\"ok\":true,\"id\":")
            out.append_string(&json_string(string_view::make_view(&id)))
            out.append('}')
            return out
        }
        if(method.equals(&m_pause)) {
            var id = json_field(args, string_view::make_no_len("id"))
            if(id.size() == 0u) { return err_msg("missing id parameter") }
            pause_task(&mut *dm, &id)
            return ok_json()
        }
        if(method.equals(&m_resume)) {
            var id = json_field(args, string_view::make_no_len("id"))
            if(id.size() == 0u) { return err_msg("missing id parameter") }
            resume_task(&mut *dm, &id)
            return ok_json()
        }
        if(method.equals(&m_cancel)) {
            var id = json_field(args, string_view::make_no_len("id"))
            if(id.size() == 0u) { return err_msg("missing id parameter") }
            cancel_task(&mut *dm, &id)
            return ok_json()
        }
        if(method.equals(&m_remove)) {
            var id = json_field(args, string_view::make_no_len("id"))
            if(id.size() == 0u) { return err_msg("missing id parameter") }
            remove_task(&mut *dm, &id)
            return ok_json()
        }
        if(method.equals(&m_remove_file)) {
            var id = json_field(args, string_view::make_no_len("id"))
            if(id.size() == 0u) { return err_msg("missing id parameter") }
            remove_task_file(&mut *dm, &id, true)
            return ok_json()
        }
        if(method.equals(&m_retry)) {
            var id = json_field(args, string_view::make_no_len("id"))
            if(id.size() == 0u) {
                return err_msg("missing id parameter")
            }
            var ok = retry_task(&mut *dm, &id)
            if(!ok) {
                return err_msg("cannot retry: item not found or already done")
            }
            return ok_json()
        }
        if(method.equals(&m_restart)) {
            var id = json_field(args, string_view::make_no_len("id"))
            if(id.size() == 0u) {
                return err_msg("missing id parameter")
            }
            var ok = restart_task(&mut *dm, &id)
            if(!ok) {
                return err_msg("cannot restart: item not found or still running")
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
            var sl = json_int_field(args, string_view::make_no_len("speed_limit_kbps"), 0)
            var cat = json_int_field(args, string_view::make_no_len("category"), -1)
            var dirv = string_view::make_view(&dir)
            var fnamev = string_view::make_view(&fname)
            // Read current category from the item so edit doesn't reset it.
            var current_cat = 0
            dm.items_mutex.lock()
            var eidx = find_item_index(&*dm, &id)
            if(eidx < dm.items.size()) { current_cat = dm.items.get_ptr(eidx).category }
            dm.items_mutex.unlock()
            var ok = edit_item(&mut *dm, &id, dirv, fnamev, prio, segs, sl as i64, if(cat >= 0) cat else current_cat)
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
            var url_val = validate_url(string_view::make_view(&new_url))
            if(!url_val.is_ok()) { return err_json(&url_val.message) }
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
            // Build a CdmSettings from JSON args, validate, then apply + persist.
            var settings = CdmSettings()
            // Core fields.
            var dl = json_field(args, string_view::make_no_len("download_dir"))
            if(dl.size() > 0u) { settings.download_dir = dl.copy() }
            settings.max_concurrent = json_int_field(args, string_view::make_no_len("max_concurrent"), dm.max_concurrent)
            settings.max_segments = json_int_field(args, string_view::make_no_len("max_segments"), dm.max_segments)
            settings.speed_limit_kbps = json_int_field(args, string_view::make_no_len("speed_limit_kbps"), dm.speed_limit_kbps as int) as i64
            settings.duplicate_action = json_int_field(args, string_view::make_no_len("duplicate_action"), dm.duplicate_action)
            settings.enable_resume = json_bool_field(args, string_view::make_no_len("enable_resume"), dm.enable_resume)
            settings.allow_segments = json_bool_field(args, string_view::make_no_len("allow_segments"), dm.allow_segments)
            settings.auto_resume_failed = json_bool_field(args, string_view::make_no_len("auto_resume_failed"), dm.auto_resume_failed)
            settings.max_retries = json_int_field(args, string_view::make_no_len("max_retries"), dm.retry_policy.max_retries)
            settings.retry_delay_ms = json_int_field(args, string_view::make_no_len("retry_delay_ms"), dm.retry_policy.delay_ms as int) as i64
            // HTTP / network.
            var ua = json_field(args, string_view::make_no_len("user_agent"))
            if(ua.size() > 0) { settings.user_agent = ua.copy() }
            var ck = json_field(args, string_view::make_no_len("cookie_file"))
            if(ck.size() > 0) { settings.cookie_file = ck.copy() }
            settings.verify_ssl = json_bool_field(args, string_view::make_no_len("verify_ssl"), dm.verify_ssl)
            settings.connect_timeout = json_int_field(args, string_view::make_no_len("connect_timeout"), dm.connect_timeout)
            settings.max_download_size = json_int_field(args, string_view::make_no_len("max_download_size"), dm.max_download_size as int) as i64
            settings.min_disk_space_mb = json_int_field(args, string_view::make_no_len("min_disk_space_mb"), dm.min_disk_space_mb)
            var postcmd = json_field(args, string_view::make_no_len("post_download_cmd"))
            if(postcmd.size() > 0) { settings.post_download_cmd = postcmd.copy() }
            var ref = json_field(args, string_view::make_no_len("referer_header"))
            if(ref.size() > 0) { settings.referer_header = ref.copy() }
            var auth = json_field(args, string_view::make_no_len("auth_header"))
            if(auth.size() > 0) { settings.auth_header = auth.copy() }
            settings.force_ipv4 = json_bool_field(args, string_view::make_no_len("force_ipv4"), dm.force_ipv4)
            settings.force_ipv6 = json_bool_field(args, string_view::make_no_len("force_ipv6"), dm.force_ipv6)
            var ftemp = json_field(args, string_view::make_no_len("filename_template"))
            if(ftemp.size() > 0) { settings.filename_template = ftemp.copy() }
            var csum = json_field(args, string_view::make_no_len("checksum"))
            if(csum.size() > 0) { settings.checksum = csum.copy() }
            settings.notifications_enabled = json_bool_field(args, string_view::make_no_len("notifications_enabled"), dm.notifications_enabled)
            var lang = json_field(args, string_view::make_no_len("language"))
            if(lang.size() > 0) { settings.language = lang.copy() }
            settings.max_history = json_int_field(args, string_view::make_no_len("max_history"), dm.max_history)
            var th = json_field(args, string_view::make_no_len("theme"))
            if(th.size() > 0) { settings.theme = th.copy() }
            var prxh = json_field(args, string_view::make_no_len("proxy_host"))
            if(prxh.size() > 0) { settings.proxy_host = prxh.copy() }
            settings.proxy_port = json_int_field(args, string_view::make_no_len("proxy_port"), dm.proxy_port)
            // YouTube basic.
            var yq = json_field(args, string_view::make_no_len("yt_quality"))
            if(yq.size() > 0) { settings.yt_quality = yq.copy() }
            var yf = json_field(args, string_view::make_no_len("yt_format"))
            if(yf.size() > 0) { settings.yt_format = yf.copy() }
            settings.yt_audio_only = json_bool_field(args, string_view::make_no_len("yt_audio_only"), dm.yt_audio_only)
            settings.yt_max_playlist_items = json_int_field(args, string_view::make_no_len("yt_max_playlist_items"), dm.yt_max_playlist_items)
            // YouTube advanced.
            var yt_out_tpl = json_field(args, string_view::make_no_len("yt_output_template"))
            if(yt_out_tpl.size() > 0) { settings.yt_output_template = yt_out_tpl.copy() }
            var yt_aud_fmt = json_field(args, string_view::make_no_len("yt_audio_format"))
            if(yt_aud_fmt.size() > 0) { settings.yt_audio_format = yt_aud_fmt.copy() }
            settings.yt_audio_quality = json_int_field(args, string_view::make_no_len("yt_audio_quality"), dm.yt_audio_quality)
            var yt_rv = json_field(args, string_view::make_no_len("yt_recode_video"))
            if(yt_rv.size() > 0) { settings.yt_recode_video = yt_rv.copy() }
            var yt_mof = json_field(args, string_view::make_no_len("yt_merge_output_format"))
            if(yt_mof.size() > 0) { settings.yt_merge_output_format = yt_mof.copy() }
            settings.yt_write_subs = json_bool_field(args, string_view::make_no_len("yt_write_subs"), dm.yt_write_subs)
            settings.yt_write_auto_subs = json_bool_field(args, string_view::make_no_len("yt_write_auto_subs"), dm.yt_write_auto_subs)
            var yt_sl = json_field(args, string_view::make_no_len("yt_sub_langs"))
            if(yt_sl.size() > 0) { settings.yt_sub_langs = yt_sl.copy() }
            settings.yt_embed_subs = json_bool_field(args, string_view::make_no_len("yt_embed_subs"), dm.yt_embed_subs)
            var yt_cs = json_field(args, string_view::make_no_len("yt_convert_subs"))
            if(yt_cs.size() > 0) { settings.yt_convert_subs = yt_cs.copy() }
            settings.yt_embed_metadata = json_bool_field(args, string_view::make_no_len("yt_embed_metadata"), dm.yt_embed_metadata)
            settings.yt_embed_thumbnail = json_bool_field(args, string_view::make_no_len("yt_embed_thumbnail"), dm.yt_embed_thumbnail)
            settings.yt_write_description = json_bool_field(args, string_view::make_no_len("yt_write_description"), dm.yt_write_description)
            settings.yt_write_info_json = json_bool_field(args, string_view::make_no_len("yt_write_info_json"), dm.yt_write_info_json)
            settings.yt_write_comments = json_bool_field(args, string_view::make_no_len("yt_write_comments"), dm.yt_write_comments)
            settings.yt_restrict_filenames = json_bool_field(args, string_view::make_no_len("yt_restrict_filenames"), dm.yt_restrict_filenames)
            settings.yt_trim_filenames = json_int_field(args, string_view::make_no_len("yt_trim_filenames"), dm.yt_trim_filenames)
            settings.yt_no_overwrites = json_bool_field(args, string_view::make_no_len("yt_no_overwrites"), dm.yt_no_overwrites)
            settings.yt_playlist_start = json_int_field(args, string_view::make_no_len("yt_playlist_start"), dm.yt_playlist_start)
            settings.yt_playlist_end = json_int_field(args, string_view::make_no_len("yt_playlist_end"), dm.yt_playlist_end)
            var yt_pi = json_field(args, string_view::make_no_len("yt_playlist_items"))
            if(yt_pi.size() > 0) { settings.yt_playlist_items = yt_pi.copy() }
            var yt_px = json_field(args, string_view::make_no_len("yt_proxy"))
            if(yt_px.size() > 0) { settings.yt_proxy = yt_px.copy() }
            settings.yt_geo_bypass = json_bool_field(args, string_view::make_no_len("yt_geo_bypass"), dm.yt_geo_bypass)
            var yt_gbc = json_field(args, string_view::make_no_len("yt_geo_bypass_country"))
            if(yt_gbc.size() > 0) { settings.yt_geo_bypass_country = yt_gbc.copy() }
            settings.yt_extractor_retries = json_int_field(args, string_view::make_no_len("yt_extractor_retries"), dm.yt_extractor_retries)
            settings.yt_socket_timeout = json_int_field(args, string_view::make_no_len("yt_socket_timeout"), dm.yt_socket_timeout)
            var yt_ec = json_field(args, string_view::make_no_len("yt_exec_cmd"))
            if(yt_ec.size() > 0) { settings.yt_exec_cmd = yt_ec.copy() }
            var yt_fl = json_field(args, string_view::make_no_len("yt_ffmpeg_location"))
            if(yt_fl.size() > 0) { settings.yt_ffmpeg_location = yt_fl.copy() }
            settings.yt_remove_sponsorblock = json_bool_field(args, string_view::make_no_len("yt_remove_sponsorblock"), dm.yt_remove_sponsorblock)
            var yt_sbm = json_field(args, string_view::make_no_len("yt_sponsorblock_mark"))
            if(yt_sbm.size() > 0) { settings.yt_sponsorblock_mark = yt_sbm.copy() }
            var yt_sa = json_field(args, string_view::make_no_len("yt_source_address"))
            if(yt_sa.size() > 0) { settings.yt_source_address = yt_sa.copy() }
            settings.yt_legacy_server_connect = json_bool_field(args, string_view::make_no_len("yt_legacy_server_connect"), dm.yt_legacy_server_connect)
            settings.yt_no_check_certificates = json_bool_field(args, string_view::make_no_len("yt_no_check_certificates"), dm.yt_no_check_certificates)
            // FFmpeg.
            var ff_vc = json_field(args, string_view::make_no_len("ffmpeg_video_codec"))
            if(ff_vc.size() > 0) { settings.ffmpeg_video_codec = ff_vc.copy() }
            var ff_ac = json_field(args, string_view::make_no_len("ffmpeg_audio_codec"))
            if(ff_ac.size() > 0) { settings.ffmpeg_audio_codec = ff_ac.copy() }
            var ff_ab = json_field(args, string_view::make_no_len("ffmpeg_audio_bitrate"))
            if(ff_ab.size() > 0) { settings.ffmpeg_audio_bitrate = ff_ab.copy() }
            // Misc.
            settings.bandwidth_limit_per = json_int_field(args, string_view::make_no_len("bandwidth_limit_per"), dm.bandwidth_limit_per as int) as i64
            settings.auto_rename_duplicates = json_bool_field(args, string_view::make_no_len("auto_rename_duplicates"), dm.auto_rename_duplicates)
            var mct = json_field(args, string_view::make_no_len("move_completed_to"))
            if(mct.size() > 0) { settings.move_completed_to = mct.copy() }
            settings.clipboard_monitor = json_bool_field(args, string_view::make_no_len("clipboard_monitor"), dm.clipboard_monitor)
            settings.use_categories = json_bool_field(args, string_view::make_no_len("use_categories"), dm.use_categories)
            // Validate core fields before applying.
            var cv = validate_max_concurrent(settings.max_concurrent)
            if(!cv.is_ok()) { return err_json(&cv.message) }
            var sv = validate_max_segments(settings.max_segments)
            if(!sv.is_ok()) { return err_json(&sv.message) }
            var slv = validate_speed_limit(settings.speed_limit_kbps)
            if(!slv.is_ok()) { return err_json(&slv.message) }
            var dv = validate_duplicate_action(settings.duplicate_action)
            if(!dv.is_ok()) { return err_json(&dv.message) }
            var rv = validate_max_retries(settings.max_retries)
            if(!rv.is_ok()) { return err_json(&rv.message) }
            var rlv = validate_retry_delay(settings.retry_delay_ms)
            if(!rlv.is_ok()) { return err_json(&rlv.message) }
            if(settings.download_dir.size() > 0u) {
                var dv2 = validate_directory(string_view::make_view(&settings.download_dir))
                if(!dv2.is_ok()) { return err_json(&dv2.message) }
            }
            if(settings.move_completed_to.size() > 0u) {
                var mv = validate_directory(string_view::make_view(&settings.move_completed_to))
                if(!mv.is_ok()) { return err_json(&mv.message) }
            }
            // Force IPv4 and IPv6 are mutually exclusive.
            if(settings.force_ipv4 && settings.force_ipv6) {
                var msg = string::make_no_len("force_ipv4 and force_ipv6 cannot both be true")
                return err_json(&msg)
            }
            // Bounds checks for timeout/space settings.
            if(settings.connect_timeout < 1) {
                var msg = string::make_no_len("connect_timeout must be at least 1 second")
                return err_json(&msg)
            }
            if(settings.min_disk_space_mb < 0) {
                var msg = string::make_no_len("min_disk_space_mb must be non-negative")
                return err_json(&msg)
            }
            // Apply to the live manager and persist for next launch.
            apply_settings_to_dm(&mut *dm, &settings)
            save_settings(&settings)
            return ok_json()
        }
        var m_settings_export = string_view::make_no_len("settings_export")
        if(method.equals(&m_settings_export)) {
            var file_path = json_field(args, string_view::make_no_len("path"))
            if(file_path.size() == 0u) {
                var msg = string::make_no_len("missing path")
                return err_json(&msg)
            }
            var json_out = settings_json(&mut *dm)
            var f = fopen(file_path.data(), "w")
            if(f == null) {
                var msg = string::make_no_len("cannot write to ")
                msg.append_string(&file_path)
                return err_json(&msg)
            }
            fwrite(json_out.data() as *mut u8, 1, json_out.size(), f)
            fflush(f)
            fclose(f)
            return ok_json()
        }
        var m_settings_import = string_view::make_no_len("settings_import")
        if(method.equals(&m_settings_import)) {
            var file_path = json_field(args, string_view::make_no_len("path"))
            if(file_path.size() == 0u) {
                var msg = string::make_no_len("missing path")
                return err_json(&msg)
            }
            var f = fopen(file_path.data(), "rb")
            if(f == null) {
                var msg = string::make_no_len("cannot read ")
                msg.append_string(&file_path)
                return err_json(&msg)
            }
            fseek(f, 0, 2)
            var fsize = ftell(f)
            fseek(f, 0, 0)
            var buf = string()
            var chunk : [4096u]u8
            while(fsize > 0) {
                var to_read = fsize
                if(to_read > 4096) { to_read = 4096 }
                var n = fread(&raw mut chunk[0], 1, to_read as usize, f)
                if(n == 0u) { break }
                buf.append_with_len(&raw mut chunk[0] as *char, n)
                fsize = fsize - n as i64
            }
            fclose(f)
            // Parse as JSON and apply each field to dm.
            var settings = CdmSettings()
            var jres = parse_settings_json(buf.data() as *u8, buf.size(), &mut settings)
            if(!jres) {
                var msg = string::make_no_len("invalid settings JSON")
                return err_json(&msg)
            }
            apply_settings_to_dm(&mut *dm, &settings)
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
            if(!fs::exists(path.data())) {
                var msg = string::make_no_len("file not found: ")
                msg.append_string(&path)
                return err_json(&msg)
            }
            var cmd_args = vector<string>()
            cmd_args.push_back(string::make_no_len("xdg-open"))
            cmd_args.push_back(path.copy())
            var cfg = process::ProcessConfig.default()
            cfg.args = cmd_args
            cfg.capture_stdout = false
            cfg.capture_stderr = false
            process::execute(cfg)
            return ok_json()
        }
        var m_show_folder = string_view::make_no_len("show_in_folder")
        if(method.equals(&m_show_folder)) {
            var path = json_field(args, string_view::make_no_len("path"))
            if(path.size() == 0u) {
                var msg = string::make_no_len("missing path")
                return err_json(&msg)
            }
            // Ensure the directory exists before trying to open it.
            if(!fs::exists(path.data())) {
                // Try the parent directory (strip trailing component).
                var last_slash = std::NPOS
                for(var si = 0u; si < path.size(); si++) {
                    if(path.get(si) == '/') { last_slash = si }
                }
                if(last_slash != std::NPOS && last_slash > 0u) {
                    path = path.substring(0u, last_slash)
                }
            }
            // Verify the final path exists before launching the file manager.
            if(!fs::exists(path.data())) {
                var msg = string::make_no_len("directory does not exist: ")
                msg.append_string(&path)
                return err_json(&msg)
            }
            var cmd_args = vector<string>()
            cmd_args.push_back(string::make_no_len("xdg-open"))
            cmd_args.push_back(path.copy())
            var cfg = process::ProcessConfig.default()
            cfg.args = cmd_args
            cfg.capture_stdout = false
            cfg.capture_stderr = false
            process::execute(cfg)
            return ok_json()
        }
        var m_browse_folder = string_view::make_no_len("browse_folder")
        if(method.equals(&m_browse_folder)) {
            var title_ptr = string_view::make_no_len("Select Download Folder").data()
            var selected = webview::webview_browse_folder(title_ptr)
            if(selected.size() == 0u) {
                var msg = string::make_no_len("no folder selected")
                return err_json(&msg)
            }
            var out = string::make_no_len("{\"ok\":true,\"path\":")
            out.append_string(&json_string(string_view::make_view(&selected)))
            out.append('}')
            return out
        }
        // ---- YouTube / yt-dlp methods ----
        var m_yt_status = string_view::make_no_len("yt_status")
        if(method.equals(&m_yt_status)) {
            return check_tools_status_json(&mut *dm)
        }
        var m_yt_install = string_view::make_no_len("yt_install")
        if(method.equals(&m_yt_install)) {
            var tool = json_field(args, string_view::make_no_len("tool"))
            fprintf(stderr, "[CDM-BRIDGE] yt_install called\n")
            var err = string()
            if(tool.equals_view(string_view::make_no_len("yt-dlp"))) {
                err = ytdlp_download_async(&mut *dm)
            } else if(tool.equals_view(string_view::make_no_len("ffmpeg"))) {
                err = ffmpeg_download_async(&mut *dm)
            } else {
                var msg = string::make_no_len("unknown tool: ")
                msg.append_string(&tool)
                return err_json(&msg)
            }
            if(err.size() > 0) {
                fprintf(stderr, "[CDM-BRIDGE] yt_install FAILED\n")
                return err_json(&err)
            }
            fprintf(stderr, "[CDM-BRIDGE] yt_install OK\n")
            return ok_json()
        }
        // ---- YouTube / yt-dlp methods ----
        // yt_info: starts async info fetch in a background thread (non-blocking).
        var m_yt_info = string_view::make_no_len("yt_info")
        if(method.equals(&m_yt_info)) {
            var url = json_field(args, string_view::make_no_len("url"))
            if(url.size() == 0u) {
                var msg = string::make_no_len("missing url")
                return err_json(&msg)
            }
            // Validate URL.
            var url_err = validate_url(string_view::make_view(&url))
            if(!url_err.is_ok()) {
                return err_json(&url_err.message)
            }
            // Start async fetch in a background thread.
            var start_err = start_async_info(string_view::make_view(&url))
            if(start_err.size() > 0u) {
                fprintf(stderr, "[CDM-BRIDGE] yt_info start failed: %s\n", start_err.data())
                return err_json(&start_err)
            }
            fprintf(stderr, "[CDM-BRIDGE] yt_info started ok\n")
            return ok_json()
        }
        // yt_info_poll: poll for async info fetch completion.
        var m_yt_info_poll = string_view::make_no_len("yt_info_poll")
        if(method.equals(&m_yt_info_poll)) {
            return poll_async_info()
        }
        // yt_info_get: retrieve the stored info JSON (called after poll reports done).
        var m_yt_info_get = string_view::make_no_len("yt_info_get")
        if(method.equals(&m_yt_info_get)) {
            fprintf(stderr, "[CDM-BRIDGE] yt_info_get called\n")
            return get_async_info()
        }
        // debug_log: JS-side diagnostics routed to stderr (so they show in the
        // terminal that launched the app, where the user watches native logs).
        var m_debug_log = string_view::make_no_len("debug_log")
        if(method.equals(&m_debug_log)) {
            var msg = json_field(args, string_view::make_no_len("msg"))
            fprintf(stderr, "[CDM-JS-LOG] %s\n", msg.data())
            return ok_json()
        }
        // yt_download: starts async download in a background thread (non-blocking).
        var m_yt_download = string_view::make_no_len("yt_download")
        if(method.equals(&m_yt_download)) {
            var url = json_field(args, string_view::make_no_len("url"))
            if(url.size() == 0u) {
                var msg = string::make_no_len("missing url")
                return err_json(&msg)
            }
            var format = json_field(args, string_view::make_no_len("format"))
            var dir = json_field(args, string_view::make_no_len("dir"))
            var mode = json_field(args, string_view::make_no_len("mode"))
            var audio_fmt = json_field(args, string_view::make_no_len("audio_format"))
            var min_q = json_int_field(args, string_view::make_no_len("min_quality"), 0)
            var max_q = json_int_field(args, string_view::make_no_len("max_quality"), 0)
            var auto_merge = json_bool_field(args, string_view::make_no_len("auto_merge"), true)
            var del_sep = json_bool_field(args, string_view::make_no_len("delete_separate"), true)
            // Check tools are available.
            if(!ytdlp_is_available()) {
                var msg = string::make_no_len("yt-dlp is not installed. Use yt_install to set it up.")
                return err_json(&msg)
            }
            // Resolve output directory.
            var output_dir = dm.download_dir.copy()
            if(dir.size() > 0) {
                output_dir = dir.copy()
            }
            fs::create_dir_all(output_dir.data())
            // Start async download in background thread.
            var start_err = start_async_download(
                string_view::make_view(&url),
                string_view::make_view(&format),
                string_view::make_view(&mode),
                string_view::make_view(&audio_fmt),
                min_q, max_q,
                string_view::make_view(&output_dir),
                dm
            )
            // Set merge preferences after start (they're read by merge monitor).
            if(start_err.size() == 0u) {
                g_async_dl.mu.lock()
                g_async_dl.auto_merge = auto_merge
                g_async_dl.delete_separate = del_sep
                g_async_dl.mu.unlock()
            }
            if(start_err.size() > 0u) {
                return err_json(&start_err)
            }
            return ok_json()
        }
        // yt_download_poll: poll for async download progress.
        var m_yt_download_poll = string_view::make_no_len("yt_download_poll")
        if(method.equals(&m_yt_download_poll)) {
            return poll_async_download()
        }
        // yt_download_playlist: starts async playlist download.
        var m_yt_download_playlist = string_view::make_no_len("yt_download_playlist")
        if(method.equals(&m_yt_download_playlist)) {
            var url = json_field(args, string_view::make_no_len("url"))
            if(url.size() == 0u) {
                var msg = string::make_no_len("missing url")
                return err_json(&msg)
            }
            var format = json_field(args, string_view::make_no_len("format"))
            var dir = json_field(args, string_view::make_no_len("dir"))
            var mode = json_field(args, string_view::make_no_len("mode"))
            var audio_fmt = json_field(args, string_view::make_no_len("audio_format"))
            var min_q = json_int_field(args, string_view::make_no_len("min_quality"), 0)
            var max_q = json_int_field(args, string_view::make_no_len("max_quality"), 0)
            var max_retries = json_int_field(args, string_view::make_no_len("max_retries"), 0)
            if(!ytdlp_is_available()) {
                var msg = string::make_no_len("yt-dlp is not installed")
                return err_json(&msg)
            }
            var output_dir = dm.download_dir.copy()
            if(dir.size() > 0) {
                output_dir = dir.copy()
            }
            fs::create_dir_all(output_dir.data())
            // Start async playlist download.
            var start_err = start_async_playlist_download(
                string_view::make_view(&url),
                string_view::make_view(&format),
                string_view::make_view(&mode),
                string_view::make_view(&audio_fmt),
                string_view::make_view(&output_dir),
                min_q, max_q, max_retries,
                dm
            )
            if(start_err.size() > 0u) {
                return err_json(&start_err)
            }
            return ok_json()
        }
        // yt_download_playlist_poll: poll for async playlist download progress.
        var m_yt_download_playlist_poll = string_view::make_no_len("yt_download_playlist_poll")
        if(method.equals(&m_yt_download_playlist_poll)) {
            return poll_async_playlist_download()
        }
        // yt_download_playlist_retry: retry a single failed playlist item by index.
        var m_yt_download_playlist_retry = string_view::make_no_len("yt_download_playlist_retry")
        if(method.equals(&m_yt_download_playlist_retry)) {
            var idx = json_int_field(args, string_view::make_no_len("index"), -1)
            var rerr = retry_playlist_item(idx)
            if(rerr.size() > 0u) { return err_json(&rerr) }
            return ok_json()
        }
        // yt_download_playlist_open: open a finished playlist item's merged file.
        var m_yt_download_playlist_open = string_view::make_no_len("yt_download_playlist_open")
        if(method.equals(&m_yt_download_playlist_open)) {
            var idx = json_int_field(args, string_view::make_no_len("index"), -1)
            var path = playlist_item_output_path(idx)
            if(path.size() == 0u) { return err_json(&string::make_no_len("no such item")) }
            var cmd_args = vector<string>()
            cmd_args.push_back(string::make_no_len("xdg-open"))
            cmd_args.push_back(path.copy())
            var ocfg = process::ProcessConfig.default()
            ocfg.args = cmd_args
            ocfg.capture_stdout = false
            ocfg.capture_stderr = false
            process::execute(ocfg)
            return ok_json()
        }
        // yt_cancel: cancel any active async YouTube operation.
        var m_yt_cancel = string_view::make_no_len("yt_cancel")
        if(method.equals(&m_yt_cancel)) {
            cancel_async_info()
            cancel_async_download()
            cancel_async_playlist_download()
            return ok_json()
        }
        var msg = string::make_no_len("unknown method: ")
        var mjs = json_string(method)
        msg.append_string(&mjs)
        return err_json(&msg)
    }

} // end namespace cdm