// ChemicalDM — download queue manager. Owns the item list (persistent record)
// and the live task runtimes (worker threads). All queue mutations happen
// under a single mutex; worker threads only touch their own TaskRuntime.

public namespace cdm {

using std::string;
using std::string_view;
using std::vector;
using std::ordered_map;
using std::mutex;

    public struct DownloadManager {
        var items_mutex : mutex
        var items : vector<DownloadItem>
        var runtimes : ordered_map<string, *mut TaskRuntime>
        var download_dir : string
        var max_concurrent : int
        var max_segments : int
        var min_segment_size : i64
        var speed_limit_kbps : i64
        var proxy_host : string
        var proxy_port : int
        var enable_resume : bool
        var allow_segments : bool
        var save_interval_millis : i64
        var last_save_millis : i64
        var duplicate_action : int
        var auto_resume_failed : bool
        var retry_policy : RetryPolicy
        // Path for periodic progress persistence (set by the app).
        var progress_file_path : string
        var user_agent : string
        var cookie_file : string
        var verify_ssl : bool
        var connect_timeout : int
        var max_download_size : i64
        var min_disk_space_mb : int
        var post_download_cmd : string
        var yt_quality : string
        var yt_format : string
        var yt_audio_only : bool
        var yt_max_playlist_items : int
        var referer_header : string
        var auth_header : string
        var force_ipv4 : bool
        var force_ipv6 : bool
        var filename_template : string
        var checksum : string
        var notifications_enabled : bool
        var language : string
        var max_history : int
        var theme : string
        // --- yt-dlp advanced ---
        var yt_output_template : string
        var yt_audio_format : string
        var yt_audio_quality : int
        var yt_recode_video : string
        var yt_merge_output_format : string
        var yt_write_subs : bool
        var yt_write_auto_subs : bool
        var yt_sub_langs : string
        var yt_embed_subs : bool
        var yt_convert_subs : string
        var yt_embed_metadata : bool
        var yt_embed_thumbnail : bool
        var yt_write_description : bool
        var yt_write_info_json : bool
        var yt_write_comments : bool
        var yt_restrict_filenames : bool
        var yt_trim_filenames : int
        var yt_no_overwrites : bool
        var yt_playlist_start : int
        var yt_playlist_end : int
        var yt_playlist_items : string
        var yt_proxy : string
        var yt_geo_bypass : bool
        var yt_geo_bypass_country : string
        var yt_extractor_retries : int
        var yt_socket_timeout : int
        var yt_username : string
        var yt_password : string
        var yt_netrc : bool
        var yt_exec_cmd : string
        var yt_ffmpeg_location : string
        var yt_remove_sponsorblock : bool
        var yt_sponsorblock_mark : string
        var yt_source_address : string
        var yt_legacy_server_connect : bool
        var yt_no_check_certificates : bool
        var ffmpeg_video_codec : string
        var ffmpeg_audio_codec : string
        var ffmpeg_audio_bitrate : string
        var bandwidth_limit_per : i64
        var auto_rename_duplicates : bool
        var move_completed_to : string
        var download_scheduler_enabled : bool
        var download_scheduler_start : string
        var download_scheduler_end : string
        var clipboard_monitor : bool

        @constructor func constructor() {
            var dir = expand_home(string_view::make_no_len(DEFAULT_DOWNLOAD_DIR))
            return DownloadManager {
                items_mutex = mutex(),
                items = vector<DownloadItem>(),
                runtimes = ordered_map<string, *mut TaskRuntime>(),
                download_dir = dir.copy(),
                max_concurrent = DEFAULT_MAX_CONCURRENT,
                max_segments = DEFAULT_MAX_SEGMENTS,
                min_segment_size = DEFAULT_MIN_SEGMENT_SIZE,
                speed_limit_kbps = 0,
                proxy_host = string(),
                proxy_port = 0,
                enable_resume = true,
                allow_segments = true,
                save_interval_millis = PROGRESS_SAVE_INTERVAL_MS,
                last_save_millis = 0,
                duplicate_action = 0,
                auto_resume_failed = false,
                retry_policy = RetryPolicy(),
                progress_file_path = string(),
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

        // Configure the global speed limit (KB/s; 0 disables).
        public func set_speed_limit_kbps(&mut self, kbps : i64) {
            self.speed_limit_kbps = kbps
        }

        // Destructor: tear down all worker threads before the members (mutex,
        // vectors) are destroyed. Without this, the still-joinable std::thread
        // inside each TaskRuntime would call std::terminate() on destruction.
        @delete
        func delete(&mut self) {
            cdm::shutdown(self)
        }

    }

    // Copy the live runtime progress into the persistent item record. Without
    // this, snapshots fall back to the (stale) item fields as soon as the
    // runtime is erased — interrupted downloads reported 0 bytes downloaded
    // and auto-resume restarted from scratch instead of from disk.
    func sync_runtime_progress(it : *mut DownloadItem, rt : *mut TaskRuntime) {
        rt.info_mutex.lock()
        it.downloaded_bytes = rt.progress.downloaded_bytes
        if(rt.progress.total_bytes > 0) { it.total_bytes = rt.progress.total_bytes }
        it.speed_bytes_per_sec = 0
        rt.info_mutex.unlock()
    }

    // Count of items currently in the DOWNLOADING state (proxies scheduler slots).
    // Must be called with items_mutex held.
    func count_active_locked(dm : &DownloadManager) : int {
        var n = 0
        for(var i = 0u; i < dm.items.size(); i++) {
            var it = dm.items.get_ptr(i)
            var rtpp = dm.runtimes.get_ptr(&it.id)
            if(rtpp != null) {
                var rt = *rtpp
                if(rt != null) {
                    var p = TaskProgress()
                    snapshot_progress_into(rt, &mut p)
                    if(p.state == STATE_DOWNLOADING) { n = n + 1 }
                }
            }
        }
        return n
    }

    func count_active(dm : &mut DownloadManager) : int {
        dm.items_mutex.lock()
        var n = count_active_locked(dm)
        dm.items_mutex.unlock()
        return n
    }

    // Look up an index by id, or return items.size(). Public so tests can inspect
// the underlying queue state directly.
public func find_item_index(dm : &DownloadManager, id : &string) : usize {
        for(var i = 0u; i < dm.items.size(); i++) {
            var it = dm.items.get_ptr(i)
            if(it.id.equals(id)) { return i }
        }
        return dm.items.size()
    }

    // Public helper for tests: locate an item by id and return a pointer into
    // the queue so its state can be simulated directly.
    public func find_item_for_tests(dm : &mut DownloadManager, id : &string) : *mut DownloadItem {
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { return null }
        return dm.items.get_ptr(idx)
    }

    // Find the (priority, queue position) of an item, used for scheduling.
    // Returns true when the item is queued for download.
    func pick_next_queued(dm : &DownloadManager) : bool {
        // helper unused (see start_pending); kept for symmetry
        return false
    }

    // Start queued items up to max_concurrent, honoring priority (lower value
    // first) and the original queue order as a tie-breaker.
    public func start_pending(dm : &mut DownloadManager) {
        // Periodic progress save for crash recovery.
        periodic_save_progress(dm)
        while(true) {
            dm.items_mutex.lock()
            var active = count_active_locked(dm)
            if(active >= dm.max_concurrent) { dm.items_mutex.unlock(); return }
            var best_idx : usize = dm.items.size()
            var best_prio : int = 0x7FFFFFFF
            for(var i = 0u; i < dm.items.size(); i++) {
                var it = dm.items.get_ptr(i)
                if(it.state != STATE_QUEUED) { continue }
                var rtpp = dm.runtimes.get_ptr(&it.id)
                if(rtpp != null) { continue }
                if(it.priority < best_prio) {
                    best_prio = it.priority
                    best_idx = i
                }
            }
            if(best_idx == dm.items.size()) { dm.items_mutex.unlock(); return }
            var it = dm.items.get_ptr(best_idx)

            var rt = new TaskRuntime(it.id.copy())
            if(rt == null) { dm.items_mutex.unlock(); return }

            // Per-item overrides fall back to the manager defaults.
            var per_segments = it.max_segments
            if(per_segments <= 0) { per_segments = dm.max_segments }
            var per_speed = it.speed_limit_kbps
            if(per_speed <= 0) { per_speed = dm.speed_limit_kbps }
            rt.speed_limit_kbps = per_speed
            rt.max_segments = per_segments
            rt.allow_segments = dm.allow_segments
            rt.enable_resume = dm.enable_resume
            rt.retry_policy.max_retries = dm.retry_policy.max_retries
            rt.retry_policy.delay_ms = dm.retry_policy.delay_ms
            rt.post_download_cmd = dm.post_download_cmd.copy()
            rt.user_agent = dm.user_agent.copy()
            rt.connect_timeout = dm.connect_timeout
            rt.referer_header = dm.referer_header.copy()
            rt.auth_header = dm.auth_header.copy()
            rt.force_ipv4 = dm.force_ipv4
            rt.force_ipv6 = dm.force_ipv6
            rt.filename_template = dm.filename_template.copy()
            rt.checksum = dm.checksum.copy()
            rt.manager = &raw mut dm

            dm.runtimes.insert(it.id.copy(), rt)
            it.state = STATE_DOWNLOADING
            var url_v = string_view::make_view(&it.url)
            var dir_v = string_view::make_view(&it.dir)
            var fname = it.display_filename()   // named temp: survives the call
            var fname_v = string_view::make_view(&fname)
            dm.items_mutex.unlock()
            if(start_task(rt, url_v, dir_v, fname_v)) {
                // Loop again to fill remaining slots.
            } else {
                dm.items_mutex.lock()
                dm.runtimes.erase(&it.id)
                delete rt
                dm.items_mutex.unlock()
                return
            }
        }
    }

    // Remove a runtime from the map under the lock and return it (caller takes
    // ownership). The caller MUST request_cancel/join/delete the runtime OUTSIDE
    // the lock, otherwise joining a worker that re-enters start_pending() would
    // deadlock on items_mutex. Erasing under the lock guarantees the scheduler's
    // count_active_locked()/snapshot() (which hold items_mutex while dereferencing
    // runtimes) can never touch a freed TaskRuntime.
    public func detach_runtime(dm : &mut DownloadManager, id : &string) : *mut TaskRuntime {
        dm.items_mutex.lock()
        var rtpp = dm.runtimes.get_ptr(id)
        var rt : *mut TaskRuntime = null
        if(rtpp != null && *rtpp != null) {
            rt = *rtpp
            dm.runtimes.erase(id)
        }
        dm.items_mutex.unlock()
        return rt
    }

    // Ask whether a file with this exact name already exists in the target
    // directory (used by the duplicate skip/rename policy).
    func output_exists(dm : &DownloadManager, dir : *char, filename : string_view) : bool {
        var p = string(dir)
        p.append('/')
        p.append_with_len(filename.data(), filename.size())
        return fs::exists(p.data())
    }

    // Generate a non-colliding file name in `dir` by appending " (N)" when the
    // base name already exists. Sets item.duplicate_suffix accordingly. Public
    // so the UI can preview names and tests can exercise it.
    public func resolve_duplicate_filename(dm : &DownloadManager, dir : *char, want_name : string_view, item : &mut DownloadItem) {
        if(dm.duplicate_action == 1) {
            // overwrite: reuse the name as-is
            item.duplicate_suffix = 0
            item.filename = sanitize_filename(want_name)
            return
        }
        if(!output_exists(dm, dir, want_name)) {
            item.duplicate_suffix = 0
            item.filename = sanitize_filename(want_name)
            return
        }
        if(dm.duplicate_action == 2) {
            // skip: keep the name; caller decides how to handle (drop or mark)
            item.duplicate_suffix = 0
            item.filename = sanitize_filename(want_name)
            return
        }
        // rename: find free "base (N).ext"
        var base = string()
        var ext = string()
        var view = want_name
        var dot = view.find_last(std::string_view("."))
        if(dot != std::NPOS && dot > 0) {
            base = string(view.data(), dot)
            ext = string(view.data() + dot, view.size() - dot)
        } else {
            base = string(view.data(), view.size())
        }
        var n = 1
        while(true) {
            var candidate = base
            var nstr = string()
            nstr.append_integer(n as bigint)
            candidate.append_view(" (")
            candidate.append_string(&nstr)
            candidate.append(')')
            candidate.append_string(&ext)
            if(!output_exists(dm, dir, string_view::make_view(&candidate))) {
                item.duplicate_suffix = n
                item.filename = candidate
                return
            }
            n = n + 1
        }
    }

    // Add a new URL to the queue with per-item options, using an explicit id.
    // When dir or filename are empty, sensible defaults (download_dir /
    // URL-derived name) are used. Returns the id of the new item, or empty
    // string when skipped (skip duplicate policy with an existing file). The
    // explicit id lets the app restore a previously persisted queue without
    // renumbering items (which would break resume bookkeeping).
    public func add_task_ex_id(dm : &mut DownloadManager, id : string_view,
                               url_str : string_view, dir_hint : string_view,
                               filename_hint : string_view, priority : int,
                               category : int) : string {
        var id_copy = string(id.data(), id.size())
        if(id_copy.empty()) {
            id_copy = uuid::v4().to_string()
        }
        var suggested = suggested_filename(url_str)
        if(filename_hint.size() > 0) {
            suggested = sanitize_filename(filename_hint)
        }

        // The caller resolves the destination directory (including any
        // category routing — that is app policy, not library policy).
        var resolved_dir = dm.download_dir.copy()
        if(dir_hint.size() > 0) {
            resolved_dir = string(dir_hint.data(), dir_hint.size())
        }
        // Normalize: a trailing separator would stack up ("dir//Sub").
        while(resolved_dir.size() > 1u && resolved_dir.get(resolved_dir.size() - 1u) == '/') {
            resolved_dir = resolved_dir.substring(0u, resolved_dir.size() - 1u)
        }

        // Ensure the destination directory exists before queueing.
        var mkres = fs::create_dir_all(resolved_dir.data())

        var item = DownloadItem(id_copy.copy(), string(url_str.data(), url_str.size()),
                                resolved_dir.copy(), suggested.copy())
        item.priority = priority
        item.category = category

        // Duplicate policy.
        var dup_dir_copy = resolved_dir.copy()
        resolve_duplicate_filename(dm, dup_dir_copy.data(), string_view::make_view(&suggested), &mut item)
        if(dm.duplicate_action == 2 && item.duplicate_suffix == 0 && output_exists(dm, dup_dir_copy.data(), string_view::make_view(&suggested))) {
            // skip duplicate entirely
            return string()
        }

        dm.items_mutex.lock()
        dm.items.push_back(item)
        dm.items_mutex.unlock()
        start_pending(dm)
        return id_copy
    }

    // Add a new URL to the queue with per-item options. When dir or filename
    // are empty, sensible defaults (download_dir / URL-derived name) are used.
    // Returns the id of the new item, or empty string when skipped (with the
    // skip duplicate policy and an existing file).
    public func add_task_ex(dm : &mut DownloadManager, url_str : string_view,
                            dir_hint : string_view, filename_hint : string_view,
                            priority : int, category : int) : string {
        var id = uuid::v4().to_string()
        return add_task_ex_id(dm, string_view::make_view(&id), url_str, dir_hint,
                              filename_hint, priority, category)
    }

    // Add a new URL to the queue using defaults (category 0 = none).
    public func add_task(dm : &mut DownloadManager, url_str : string_view) : string {
        return add_task_ex(dm, url_str, string_view(), string_view(), 0, 0)
    }

    // Create a "container" item that represents a YouTube playlist / single-video
    // job. It is a real DownloadItem (so it shows as a card in the queue) but it is
    // NOT schedulable: it is inserted with state DOWNLOADING so start_pending (which
    // only picks STATE_QUEUED) never spins up a worker for it. Its progress is driven
    // by the async yt-dlp poll (set_item_state_progress). Children of the container are
    // tagged with card_type=ITEM_TYPE_YT_CHILD + parent_id so the UI nests them.
    public func create_container_item(dm : &mut DownloadManager, card_type : int,
                                      url : string_view, dir : string_view,
                                      name : string_view) : string {
        var id = uuid::v4().to_string()
        var item = DownloadItem(id.copy(), string(url.data(), url.size()),
                                string(dir.data(), dir.size()), sanitize_filename(name))
        item.card_type = card_type
        item.state = STATE_DOWNLOADING
        dm.items_mutex.lock()
        dm.items.push_back(item)
        dm.items_mutex.unlock()
        return id
    }

    // Change a queued/paused item's destination/settings. Returns true when the
    // item was updated; running items are left untouched.
    public func edit_item(dm : &mut DownloadManager, id : &string,
                           dir : string_view, filename : string_view,
                           priority : int, max_segments : int,
                           speed_limit_kbps : i64, category : int) : bool {
        dm.items_mutex.lock()
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { dm.items_mutex.unlock(); return false }
        var it = dm.items.get_ptr(idx)
        var rtpp = dm.runtimes.get_ptr(&it.id)
        if(rtpp != null && *rtpp != null) {
            // A live runtime has its own path; edits apply on the next run.
            dm.items_mutex.unlock()
            return false
        }
        if(dir.size() > 0) {
            it.dir = string(dir.data(), dir.size())
            fs::create_dir_all(it.dir.data())
        }
        if(filename.size() > 0) {
            it.filename = sanitize_filename(filename)
        }
        it.priority = priority
        if(max_segments > 0) { it.max_segments = max_segments }
        it.speed_limit_kbps = speed_limit_kbps
        it.category = category
        dm.items_mutex.unlock()
        return true
    }

    // Tag an item with its card type and (optional) parent id. Used by the app
    // to mark playlist containers and their nested video/audio children. The
    // engine never touches these fields, so setting them once (under the lock)
    // is safe. Returns true when the item was found.
    public func set_item_card_type(dm : &mut DownloadManager, id : string_view,
                                   card_type : int, parent_id : string_view) : bool {
        dm.items_mutex.lock()
        var idx = find_item_index(dm, &string(id.data(), id.size()))
        if(idx == dm.items.size()) { dm.items_mutex.unlock(); return false }
        var it = dm.items.get_ptr(idx)
        it.card_type = card_type
        it.parent_id = string(parent_id.data(), parent_id.size())
        dm.items_mutex.unlock()
        return true
    }

    // Update a container item's lifecycle state and aggregate progress (used to
    // drive the playlist / single-YT card header from the async poll). Under lock.
    public func set_item_state_progress(dm : &mut DownloadManager, id : string_view,
                                        state : int, downloaded : i64, total : i64) : bool {
        dm.items_mutex.lock()
        var idx = find_item_index(dm, &string(id.data(), id.size()))
        if(idx == dm.items.size()) { dm.items_mutex.unlock(); return false }
        var it = dm.items.get_ptr(idx)
        it.state = state
        it.downloaded_bytes = downloaded
        it.total_bytes = total
        dm.items_mutex.unlock()
        return true
    }

    // Re-queue a failed or cancelled task for another attempt. Clears the error
    // and resets progress so the retry restarts cleanly.
    public func retry_task(dm : &mut DownloadManager, id : &string) : bool {
        dm.items_mutex.lock()
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { dm.items_mutex.unlock(); return false }
        var it = dm.items.get_ptr(idx)
        if(it.state == STATE_DONE) { dm.items_mutex.unlock(); return false }
        dm.items_mutex.unlock()
        // detach_runtime locks items_mutex internally; do it outside our lock.
        var rt = detach_runtime(dm, id)
        if(rt != null) {
            // Worker still attached (e.g. internal retry loop exhausted);
            // cancel it, wait for exit, clean up the runtime, then re-queue.
            request_cancel(rt)
            if(rt.running) { join_task(rt) }
            delete rt
        }
        dm.items_mutex.lock()
        idx = find_item_index(dm, id)
        if(idx != dm.items.size()) {
            var it2 = dm.items.get_ptr(idx)
            it2.state = STATE_QUEUED
            it2.error = string()
            // Preserve downloaded_bytes/total_bytes so the worker can resume
            // from the last written position on disk. Use restart_task to
            // truly start from scratch (it deletes partial files).
            it2.retry_count = it2.retry_count + 1
            it2.was_interrupted = false
        }
        dm.items_mutex.unlock()
        start_pending(dm)
        return true
    }

    // Change the URL of an existing download. Only allowed for non-running
    // items. Preserves progress so the worker resumes from disk with the new URL.
    public func change_url(dm : &mut DownloadManager, id : &string, new_url : string_view) : bool {
        dm.items_mutex.lock()
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { dm.items_mutex.unlock(); return false }
        var it = dm.items.get_ptr(idx)
        var rtpp = dm.runtimes.get_ptr(&it.id)
        if(rtpp != null && *rtpp != null) {
            dm.items_mutex.unlock()
            return false
        }
        it.url = string(new_url.data(), new_url.size())
        it.state = STATE_QUEUED
        it.error = string()
        // Preserve downloaded_bytes/total_bytes so the worker resumes from disk.
        // The new URL is likely a refreshed link for the same content.
        it.retry_count = 0
        it.was_interrupted = false
        dm.items_mutex.unlock()
        start_pending(dm)
        return true
    }

    // Restart a finished/failed/paused item from scratch: remove partial files,
    // reset progress, and re-queue.
    public func restart_task(dm : &mut DownloadManager, id : &string) : bool {
        dm.items_mutex.lock()
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { dm.items_mutex.unlock(); return false }
        var it = dm.items.get_ptr(idx)
        var del_dir = it.dir.copy()
        var del_name = it.filename.copy()
        dm.items_mutex.unlock()
        // detach_runtime locks items_mutex internally; do it outside our lock.
        var rt = detach_runtime(dm, id)
        if(rt != null) {
            request_cancel(rt)
            if(rt.running) { join_task(rt) }
            delete rt
        }
        // remove the existing file and any part files
        var path = string()
        path.append_string(&del_dir)
        path.append('/')
        path.append_string(&del_name)
        remove(path.data())
        var i : usize = 0
        while(i < MAX_PART_FILES) {
            var ps = string()
            ps.append_string(&del_dir)
            ps.append('/')
            ps.append_string(&del_name)
            var idxs = string()
            idxs.append_integer(i as bigint)
            ps.append('.')
            ps.append_string(&idxs)
            ps.append_view(".part")
            remove(ps.data())
            i += 1u
        }
        dm.items_mutex.lock()
        idx = find_item_index(dm, id)
        if(idx != dm.items.size()) {
            var it2 = dm.items.get_ptr(idx)
            it2.state = STATE_QUEUED
            it2.error = string()
            it2.downloaded_bytes = 0
            it2.total_bytes = 0
            it2.retry_count = 0
            it2.was_interrupted = false
        }
        dm.items_mutex.unlock()
        start_pending(dm)
        return true
    }

    // Pause a task. If it has not started yet it is simply marked paused.
    public func pause_task(dm : &mut DownloadManager, id : &string) {
        dm.items_mutex.lock()
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { dm.items_mutex.unlock(); return }
        var it = dm.items.get_ptr(idx)
        var rtpp = dm.runtimes.get_ptr(&it.id)
        if(rtpp != null && *rtpp != null) {
            request_pause(*rtpp)
            dm.items_mutex.unlock()
        } else {
            if(it.state == STATE_QUEUED) {
                it.state = STATE_PAUSED
            }
            dm.items_mutex.unlock()
        }
    }

    // Re-queue interrupted downloads (items that were downloading when the app
    // closed). Failed downloads are NOT auto-resumed — the user must manually
    // retry or resume them. Returns how many were re-queued.
    public func poll_auto_resume(dm : &mut DownloadManager) : int {
        var requeued = 0
        dm.items_mutex.lock()
        for(var i = 0u; i < dm.items.size(); i++) {
            var it = dm.items.get_ptr(i)
            // Resume items that were interrupted (app closed during download)
            // or items explicitly marked for auto-resume.
            var should_resume = false
            if(it.was_interrupted) {
                should_resume = true
            } else if(dm.auto_resume_failed && (it.state == STATE_FAILED || it.state == STATE_CANCELLED)) {
                if(dm.retry_policy.max_retries < 0 || it.retry_count < dm.retry_policy.max_retries) {
                    should_resume = true
                }
            }
            if(!should_resume) { continue }
            var rtpp = dm.runtimes.get_ptr(&it.id)
            if(rtpp != null && *rtpp != null) { continue }
            it.state = STATE_QUEUED
            it.error = string()
            it.was_interrupted = false
            // Preserve downloaded_bytes / total_bytes so the worker can
            // resume from the last written position on disk.
            it.retry_count = it.retry_count + 1
            requeued = requeued + 1
        }
        dm.items_mutex.unlock()
        start_pending(dm)
        return requeued
    }

    // Clear finished/cancelled items from the queue. Returns how many were
    // removed.
    public func clear_finished(dm : &mut DownloadManager) : int {
        var removed = 0
        dm.items_mutex.lock()
        var i : usize = 0
        while(i < dm.items.size()) {
            var it = dm.items.get_ptr(i)
            if(it.state == STATE_DONE || it.state == STATE_CANCELLED || it.state == STATE_FAILED) {
                var rtpp = dm.runtimes.get_ptr(&it.id)
                if(rtpp != null && *rtpp != null) { i = i + 1; continue }
                dm.items.erase(i)
                removed = removed + 1
            } else {
                i = i + 1
            }
        }
        dm.items_mutex.unlock()
        return removed
    }

    // Resume a paused or queued task.
    public func resume_task(dm : &mut DownloadManager, id : &string) {
        dm.items_mutex.lock()
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { dm.items_mutex.unlock(); return }
        var it = dm.items.get_ptr(idx)
        var rtpp = dm.runtimes.get_ptr(&it.id)
        if(rtpp != null && *rtpp != null) {
            resume_runtime(*rtpp)
            dm.items_mutex.unlock()
        } else {
            if(it.state == STATE_PAUSED || it.state == STATE_QUEUED) {
                it.state = STATE_QUEUED
            } else if(it.state == STATE_FAILED || it.state == STATE_CANCELLED) {
                // Resume a failed/cancelled download with existing progress.
                it.state = STATE_QUEUED
                it.error = string()
                it.was_interrupted = false
            }
            dm.items_mutex.unlock()
        }
        start_pending(dm)
    }

    // Cancel a running or queued task.
    public func cancel_task(dm : &mut DownloadManager, id : &string) {
        // detach_runtime locks items_mutex internally and removes the runtime
        // from the map; do it before taking the lock ourselves to avoid a
        // nested-lock deadlock.
        var rt = detach_runtime(dm, id)
        if(rt != null) {
            request_cancel(rt)
            if(rt.running) {
                join_task(rt)
            }
            dm.items_mutex.lock()
            var idx = find_item_index(dm, id)
            if(idx != dm.items.size()) {
                var it = dm.items.get_ptr(idx)
                // Preserve final progress on the item record before teardown.
                sync_runtime_progress(it, rt)
                it.state = STATE_CANCELLED
            }
            dm.items_mutex.unlock()
            delete rt
        } else {
            dm.items_mutex.lock()
            var idx = find_item_index(dm, id)
            if(idx != dm.items.size()) {
                var it = dm.items.get_ptr(idx)
                if(it.state != STATE_DONE && it.state != STATE_FAILED) {
                    it.state = STATE_CANCELLED
                }
            }
            dm.items_mutex.unlock()
        }
    }

    // Remove a task from the queue entirely (cancelling it if still active).
    // Optionally also deletes the downloaded file.
    public func remove_task(dm : &mut DownloadManager, id : &string) {
        remove_task_file(dm, id, false)
    }

    public func remove_task_file(dm : &mut DownloadManager, id : &string, delete_file : bool) {
        dm.items_mutex.lock()
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { dm.items_mutex.unlock(); return }
        var it = dm.items.get_ptr(idx)
        var del_path = string()
        var parts = vector<string>()
        if(delete_file) {
            del_path = it.local_path()
            var i : usize = 0
            while(i < MAX_PART_FILES) {
                var ps = string()
                ps.append_string(&it.dir)
                ps.append('/')
                ps.append_string(&it.filename)
                var idxs = string()
                idxs.append_integer(i as bigint)
                ps.append('.')
                ps.append_string(&idxs)
                ps.append_view(".part")
                parts.push_back(ps)
                i += 1u
            }
        }
        dm.items_mutex.unlock()
        if(delete_file) {
            remove(del_path.data())
            for(var k = 0u; k < parts.size(); k++) {
                remove(parts.get_ptr(k).data())
            }
        }
        cancel_task(dm, id)
        dm.items_mutex.lock()
        idx = find_item_index(dm, id)
        if(idx != dm.items.size()) { dm.items.erase(idx) }
        dm.items_mutex.unlock()
    }

    // Convenience wrapper: returns a new vector with all items (deep-copied
    // with live progress merged). Preferred over snapshot_into when a single
    // call-site snapshot is needed (e.g. tests).
    public func snapshot(dm : &mut DownloadManager) : vector<DownloadItem> {
        var out = vector<DownloadItem>()
        snapshot_into(dm, &mut out)
        return out
    }

    // Merge live progress into the item list and return an immutable snapshot.
    public func snapshot_into(dm : &mut DownloadManager, out : &mut vector<DownloadItem>) {
        out.clear()
        dm.items_mutex.lock()
        for(var i = 0u; i < dm.items.size(); i++) {
            var it = dm.items.get_ptr(i)
            var copy = DownloadItem(it.id.copy(), it.url.copy(), it.dir.copy(), it.filename.copy())
            copy.total_bytes = it.total_bytes
            copy.downloaded_bytes = it.downloaded_bytes
            copy.speed_bytes_per_sec = it.speed_bytes_per_sec
            copy.state = it.state
            copy.error = it.error.copy()
            copy.created_at = it.created_at
            copy.started_at = it.started_at
            copy.finished_at = it.finished_at
            copy.pause_requested = it.pause_requested
            copy.cancel_requested = it.cancel_requested
            copy.priority = it.priority
            copy.max_segments = it.max_segments
            copy.speed_limit_kbps = it.speed_limit_kbps
            copy.retry_count = it.retry_count
            copy.duplicate_suffix = it.duplicate_suffix
            copy.category = it.category
            copy.segments_json = it.segments_json.copy()
            copy.was_interrupted = it.was_interrupted
            copy.card_type = it.card_type
            copy.parent_id = it.parent_id.copy()
            var rtpp = dm.runtimes.get_ptr(&it.id)
            if(rtpp != null && *rtpp != null) {
                var p = TaskProgress()
                snapshot_progress_into(*rtpp, &mut p)
                copy.total_bytes = p.total_bytes
                copy.downloaded_bytes = p.downloaded_bytes
                copy.speed_bytes_per_sec = p.speed_bytes_per_sec
                copy.state = p.state
                copy.error = p.error.copy()
                copy.segments_json = snapshot_segments_json(*rtpp)
            }
            out.push_back(copy)
        }
        dm.items_mutex.unlock()
    }

    // ---- Periodic progress persistence (crash recovery) ----
    // Saves a compact progress.txt file every PROGRESS_SAVE_INTERVAL_MS so
    // that a crash/kill/SIGKILL leaves resumable state on disk. The file
    // is separate from queue.txt (the queue is only saved on clean shutdown).
    // Format: one tab-separated row per item: id\tdownloaded\ttotal\tinterrupted
    // Atomic: write to .tmp, fsync, rename over the old file.

    func periodic_save_progress(dm : &mut DownloadManager) {
        dm.items_mutex.lock()
        var now = now_millis()
        var elapsed = now - dm.last_save_millis
        var has_active = false
        for(var i = 0u; i < dm.items.size(); i++) {
            var it = dm.items.get_ptr(i)
            if(it.state == STATE_DOWNLOADING || it.state == STATE_QUEUED || it.state == STATE_PAUSED) {
                has_active = true
                break
            }
        }
        if(!has_active || elapsed < dm.save_interval_millis || dm.progress_file_path.empty()) {
            dm.items_mutex.unlock()
            return
        }
        dm.last_save_millis = now
        // Snapshot under the lock.
        var snap = vector<DownloadItem>()
        for(var i = 0u; i < dm.items.size(); i++) {
            var it = dm.items.get_ptr(i)
            var c = DownloadItem(it.id.copy(), it.url.copy(), it.dir.copy(), it.filename.copy())
            c.downloaded_bytes = it.downloaded_bytes
            c.total_bytes = it.total_bytes
            c.state = it.state
            c.was_interrupted = it.was_interrupted
            c.card_type = it.card_type
            // Merge live progress from runtime.
            var rtpp = dm.runtimes.get_ptr(&it.id)
            if(rtpp != null && *rtpp != null) {
                var p = TaskProgress()
                snapshot_progress_into(*rtpp, &mut p)
                c.downloaded_bytes = p.downloaded_bytes
                if(p.total_bytes > 0) { c.total_bytes = p.total_bytes }
                c.state = p.state
            }
            snap.push_back(c)
        }
        dm.items_mutex.unlock()

        // Build the progress file content.
        var out = string::make_no_len("#cdm-progress-v1\n")
        for(var i = 0u; i < snap.size(); i++) {
            var it = snap.get_ptr(i)
            if(it.card_type != ITEM_TYPE_NORMAL) { continue }
            if(it.state == STATE_DONE) { continue }
            out.append_string(&it.id)
            out.append('\t')
            out.append_integer(it.downloaded_bytes as bigint)
            out.append('\t')
            out.append_integer(it.total_bytes as bigint)
            out.append('\t')
            if(it.was_interrupted || it.state == STATE_DOWNLOADING || it.state == STATE_PAUSED) {
                out.append('1')
            } else {
                out.append('0')
            }
            out.append('\n')
        }

        // Atomic write: .tmp + fsync + rename.
        var tmp_path = dm.progress_file_path.copy()
        tmp_path.append_view(".tmp")
        var f = fopen(tmp_path.data(), "wb")
        if(f == null) { return }
        fwrite(out.data() as *mut u8, 1, out.size(), f)
        fflush(f)
        fclose(f)
        // rename is atomic on POSIX.
        rename(tmp_path.data(), dm.progress_file_path.data())

    }

    // Restore progress from a progress.txt file. Called by the app after
    // restore_queue to overlay the latest progress onto restored items.
    public func restore_progress(dm : &mut DownloadManager, path : string_view) : int {
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
            var start = pos
            while(pos < content.size() && content.get(pos) != '\n') {
                pos = pos + 1u
            }
            var end = pos
            if(pos < content.size()) { pos = pos + 1u }
            if(end <= start) { continue }
            var line = content.substring(start, end)
            if(!header_ok) {
                if(line.equals_view("#cdm-progress-v1")) { header_ok = true }
                continue
            }
            if(line.empty()) { continue }
            // Parse: id\tdownloaded\ttotal\tinterrupted
            var tab1 = line.find("\t")
            if(tab1 == std::NPOS) { continue }
            var id = line.substring(0u, tab1)
            var rest = line.substring(tab1 + 1u, line.size())
            var tab2 = rest.find("\t")
            if(tab2 == std::NPOS) { continue }
            var dl_str = rest.substring(0u, tab2)
            var rest2 = rest.substring(tab2 + 1u, rest.size())
            var tab3 = rest2.find("\t")
            var tot_str : string
            var int_str : string
            if(tab3 == std::NPOS) {
                tot_str = rest2
                int_str = string()
            } else {
                tot_str = rest2.substring(0u, tab3)
                int_str = rest2.substring(tab3 + 1u, rest2.size())
            }
            var downloaded = parse_i64_from_view(string_view::make_view(&dl_str))
            var total = parse_i64_from_view(string_view::make_view(&tot_str))
            var interrupted = int_str.equals_view("1")
            // Apply to the matching item.
            dm.items_mutex.lock()
            var idx = find_item_index(dm, &id)
            if(idx != dm.items.size()) {
                var it = dm.items.get_ptr(idx)
                if(downloaded > it.downloaded_bytes) { it.downloaded_bytes = downloaded }
                if(total > it.total_bytes) { it.total_bytes = total }
                if(interrupted && it.state != STATE_DONE) {
                    it.was_interrupted = true
                    it.state = STATE_FAILED
                    if(it.error.empty()) {
                        it.error = string::make_no_len("interrupted by shutdown")
                    }
                }
                restored = restored + 1
            }
            dm.items_mutex.unlock()
        }
        return restored
    }

    // Join and release every worker thread (called on shutdown). Mark any
    // items that were still downloading as interrupted so auto-resume can
    // pick them up on next launch.
    public func shutdown(dm : &mut DownloadManager) {
        // Loop until every runtime is gone. A worker finishing its download calls
        // start_pending() (under items_mutex) which may spawn a new worker, so we
        // must re-scan instead of assuming one pass covers everything.
        // Safety: cap iterations to avoid hanging if a worker is stuck.
        var max_iterations = 0
        while(max_iterations < 100) {
            max_iterations = max_iterations + 1
            dm.items_mutex.lock()
            var any_rt = dm.runtimes.size() > 0u
            dm.items_mutex.unlock()
            if(!any_rt) { break }
            // Snapshot the item ids under the lock, then process each by id so we
            // never hold a dangling pointer into dm.items across a blocking join.
            dm.items_mutex.lock()
            var ids = vector<string>()
            for(var i = 0u; i < dm.items.size(); i++) {
                ids.push_back(dm.items.get_ptr(i).id.copy())
            }
            dm.items_mutex.unlock()
            for(var j = 0u; j < ids.size(); j++) {
                var id = ids.get_ptr(j)
                // detach_runtime erases from the map and returns the runtime so the
                // scheduler (which holds items_mutex while dereferencing runtimes)
                // can never touch a freed TaskRuntime.
                var rt = detach_runtime(dm, &*id)
                if(rt != null) {
                    request_cancel(rt)
                    if(rt.running) {
                        join_task(rt)
                    }
                    // Preserve the final progress so a restart can resume from
                    // disk instead of starting over.
                    dm.items_mutex.lock()
                    var idx = find_item_index(dm, &*id)
                    if(idx != dm.items.size()) {
                        var it = dm.items.get_ptr(idx)
                        sync_runtime_progress(it, rt)
                        var rt_p = TaskProgress()
                        snapshot_progress_into(rt, &mut rt_p)
                        var rt_state = rt_p.state
                        if(it.state == STATE_DOWNLOADING || it.state == STATE_CANCELLED ||
                            rt_state == STATE_DOWNLOADING || rt_state == STATE_CANCELLED) {
                            it.state = STATE_FAILED
                            it.was_interrupted = true
                            it.error = string::make_no_len("interrupted by shutdown")
                        }
                    }
                    dm.items_mutex.unlock()
                    delete rt
                }
            }
        }
        // Final pass: mark any remaining downloading items as interrupted even
        // if their runtime couldn't be joined (stuck worker).
        dm.items_mutex.lock()
        for(var i = 0u; i < dm.items.size(); i++) {
            var it = dm.items.get_ptr(i)
            if(it.state == STATE_DOWNLOADING || it.state == STATE_QUEUED) {
                var rtpp = dm.runtimes.get_ptr(&it.id)
                if(rtpp == null || *rtpp == null) {
                    it.state = STATE_FAILED
                    it.was_interrupted = true
                    it.error = string::make_no_len("interrupted by shutdown")
                }
            }
        }
        dm.items_mutex.unlock()
    }

} // end namespace cdm