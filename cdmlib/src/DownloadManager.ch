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
        var use_categories : bool
        var duplicate_action : int
        var auto_resume_failed : bool
        var retry_policy : RetryPolicy

        @constructor func constructor() {
            var dir = expand_home(string_view::make_no_len(DEFAULT_DOWNLOAD_DIR))
            return DownloadManager {
                items_mutex = mutex(),
                items = vector<DownloadItem>(),
                runtimes = ordered_map<string, *mut TaskRuntime>(),
                download_dir = dir,
                max_concurrent = DEFAULT_MAX_CONCURRENT,
                max_segments = DEFAULT_MAX_SEGMENTS,
                min_segment_size = DEFAULT_MIN_SEGMENT_SIZE,
                speed_limit_kbps = 0,
                proxy_host = string(),
                proxy_port = 0,
                enable_resume = true,
                allow_segments = true,
                save_interval_millis = 2000,
                last_save_millis = 0,
                use_categories = false,
                duplicate_action = 0,
                auto_resume_failed = false,
                retry_policy = RetryPolicy()
            }
        }

        // Configure the global speed limit (KB/s; 0 disables).
        public func set_speed_limit_kbps(&mut self, kbps : i64) {
            self.speed_limit_kbps = kbps
        }

        // Apply persisted settings (other than the download dir).
        public func apply_settings(&mut self, s : &CdmSettings) {
            self.max_concurrent = s.max_concurrent
            self.max_segments = s.max_segments
            self.min_segment_size = s.min_segment_size
            self.speed_limit_kbps = s.speed_limit_kbps
            self.enable_resume = s.enable_resume
            self.allow_segments = s.allow_segments
            self.proxy_host = s.proxy_host.copy()
            self.proxy_port = s.proxy_port
            self.use_categories = s.use_categories
            self.duplicate_action = s.duplicate_action
            self.auto_resume_failed = s.auto_resume_failed
            self.retry_policy.max_retries = s.max_retries
            self.retry_policy.delay_ms = s.retry_delay_ms
            if(s.download_dir.size() > 0) {
                self.download_dir = s.download_dir.copy()
            }
        }
    }

    // Count of items currently in the DOWNLOADING state (proxies scheduler slots).
    func count_active(dm : &DownloadManager) : int {
        var n = 0
        for(var i = 0u; i < dm.items.size(); i++) {
            var it = dm.items.get_ptr(i)
            var rtpp = dm.runtimes.get_ptr(&it.id)
            if(rtpp != null) {
                var rt = *rtpp
                if(rt != null) {
                    var p = snapshot_progress(rt)
                    if(p.state == STATE_DOWNLOADING) { n = n + 1 }
                }
            }
        }
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
        var active = count_active(dm)
        var started_any = true
        while(started_any) {
            if(active >= dm.max_concurrent) { return }
            started_any = false
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
            if(best_idx == dm.items.size()) { return }
            var it = dm.items.get_ptr(best_idx)

            var id_copy = it.id.copy()
            var rt = new TaskRuntime(id_copy)
            if(rt == null) { return }

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

            dm.runtimes.insert(it.id.copy(), rt)
            var url_v = string_view::make_view(&it.url)
            var dir_v = string_view::make_view(&it.dir)
            var fname = it.display_filename()   // named temp: survives the call
            var fname_v = string_view::make_view(&fname)
            if(start_task(rt, url_v, dir_v, fname_v)) {
                it.state = STATE_DOWNLOADING
                active = active + 1
                started_any = true
            } else {
                dm.runtimes.erase(&it.id)
                delete rt
                return
            }
        }
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

    // Add a new URL to the queue with per-item options. When dir or filename
    // are empty, sensible defaults (download_dir / URL-derived name) are used.
    // Returns the id of the new item, or empty string when skipped (with the
    // skip duplicate policy and an existing file).
    public func add_task_ex(dm : &mut DownloadManager, url_str : string_view,
                            dir_hint : string_view, filename_hint : string_view,
                            priority : int, category : Category) : string {
var id = uuid::v4().to_string()
        // Resolve the file name first so category routing is based on the
        // name actually used (the URL-derived guess, or the caller's override).
        var suggested = suggested_filename(url_str)
        if(filename_hint.size() > 0) {
            suggested = sanitize_filename(filename_hint)
        }

        var resolved_dir = dm.download_dir.copy()
        if(dir_hint.size() > 0) {
            resolved_dir = string(dir_hint.data(), dir_hint.size())
        } else if(dm.use_categories) {
            var cat = category
            if(cat == Category.Other) {
                var ext = extension_of(string_view::make_view(&suggested))
                cat = category_for_extension(string_view::make_view(&ext))
            }
            resolved_dir = category_dir_for_dirs(dm, cat, string_view::make_view(&suggested))
        }

        // Ensure the destination directory exists before queueing.
        var mkres = fs::create_dir_all(resolved_dir.data())

        var item = DownloadItem(id.copy(), string(url_str.data(), url_str.size()),
                                resolved_dir.copy(), suggested.copy())
        item.priority = priority
        item.category = category as int
        if(dm.use_categories && dir_hint.size() == 0u) {
            // Reflect the resolved category (e.g. an mp4 became Video) so the
            // UI and persistence store the category actually used.
            var rdir_ext = extension_of(string_view::make_view(&item.filename))
            var resolved_cat = category_for_extension(string_view::make_view(&rdir_ext))
            if(resolved_cat != Category.Other) { item.category = resolved_cat as int }
        }

        // Duplicate policy.
        var dup_dir_copy = resolved_dir.copy()
        resolve_duplicate_filename(dm, dup_dir_copy.data(), string_view::make_view(&suggested), &mut item)
        if(dm.duplicate_action == 2 && item.duplicate_suffix == 0 && output_exists(dm, dup_dir_copy.data(), string_view::make_view(&suggested))) {
            // skip duplicate entirely
            return string()
        }

        dm.items.push_back(item)
        start_pending(dm)
        return id
    }

    // Add a new URL to the queue using defaults (kept for compatibility).
    public func add_task(dm : &mut DownloadManager, url_str : string_view) : string {
        return add_task_ex(dm, url_str, string_view(), string_view(), 0, Category.Other)
    }

    // Change a queued/paused item's destination/settings. Returns true when the
    // item was updated; running items are left untouched.
    public func edit_item(dm : &mut DownloadManager, id : &string,
                          dir : string_view, filename : string_view,
                          priority : int, max_segments : int,
                          speed_limit_kbps : i64, category : Category) : bool {
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { return false }
        var it = dm.items.get_ptr(idx)
        var rtpp = dm.runtimes.get_ptr(&it.id)
        if(rtpp != null && *rtpp != null) {
            // A live runtime has its own path; edits apply on the next run.
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
        if(category != Category.Other) { it.category = category as int }
        return true
    }

    // Re-queue a failed or cancelled task for another attempt. Clears the error
    // and resets progress so the retry restarts cleanly.
    public func retry_task(dm : &mut DownloadManager, id : &string) : bool {
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { return false }
        var it = dm.items.get_ptr(idx)
        if(it.state == STATE_DONE) { return false }
        var rtpp = dm.runtimes.get_ptr(&it.id)
        if(rtpp != null && *rtpp != null) {
            // Worker still attached (e.g. internal retry loop exhausted);
            // cancel it, wait for exit, clean up the runtime, then re-queue.
            var rt = *rtpp
            request_cancel(rt)
            if(rt.running) { join_task(rt) }
            delete rt
            dm.runtimes.erase(&it.id)
        }
        it.state = STATE_QUEUED
        it.error = string()
        it.downloaded_bytes = 0
        it.total_bytes = 0
        it.retry_count = it.retry_count + 1
        it.was_interrupted = false
        start_pending(dm)
        return true
    }

    // Change the URL of an existing download. Only allowed for non-running
    // items. Clears progress so the download restarts with the new URL.
    public func change_url(dm : &mut DownloadManager, id : &string, new_url : string_view) : bool {
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { return false }
        var it = dm.items.get_ptr(idx)
        var rtpp = dm.runtimes.get_ptr(&it.id)
        if(rtpp != null && *rtpp != null) {
            return false
        }
        it.url = string(new_url.data(), new_url.size())
        it.state = STATE_QUEUED
        it.error = string()
        it.downloaded_bytes = 0
        it.total_bytes = 0
        it.retry_count = 0
        it.was_interrupted = false
        start_pending(dm)
        return true
    }

    // Restart a finished/failed/paused item from scratch: remove partial files,
    // reset progress, and re-queue.
    public func restart_task(dm : &mut DownloadManager, id : &string) : bool {
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { return false }
        var it = dm.items.get_ptr(idx)
        var rtpp = dm.runtimes.get_ptr(&it.id)
        if(rtpp != null && *rtpp != null) {
            var rt = *rtpp
            request_cancel(rt)
            if(rt.running) { join_task(rt) }
            delete rt
            dm.runtimes.erase(&it.id)
        }
        // remove the existing file and any part files
        var path = it.local_path()
        remove(path.data())
        var i : usize = 0
        while(i < 64) {
            var ps = string()
            ps.append_string(&it.dir)
            ps.append('/')
            ps.append_string(&it.filename)
            var idxs = string()
            idxs.append_integer(i as bigint)
            ps.append('.')
            ps.append_string(&idxs)
            ps.append_view(".part")
            remove(ps.data())
            i += 1
        }
        it.state = STATE_QUEUED
        it.error = string()
        it.downloaded_bytes = 0
        it.total_bytes = 0
        it.retry_count = 0
        start_pending(dm)
        return true
    }

    // Pause a task. If it has not started yet it is simply marked paused.
    public func pause_task(dm : &mut DownloadManager, id : &string) {
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { return }
        var it = dm.items.get_ptr(idx)
        var rtpp = dm.runtimes.get_ptr(&it.id)
        if(rtpp != null && *rtpp != null) {
            request_pause(*rtpp)
        } else if(it.state == STATE_QUEUED) {
            it.state = STATE_PAUSED
        }
    }

    // Re-queue interrupted downloads (items that were downloading when the app
    // closed). Failed downloads are NOT auto-resumed — the user must manually
    // retry or resume them. Returns how many were re-queued.
    public func poll_auto_resume(dm : &mut DownloadManager) : int {
        var requeued = 0
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
        start_pending(dm)
        return requeued
    }

    // Clear finished/cancelled items from the queue. Returns how many were
    // removed.
    public func clear_finished(dm : &mut DownloadManager) : int {
        var removed = 0
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
        return removed
    }

    // Resume a paused or queued task.
    public func resume_task(dm : &mut DownloadManager, id : &string) {
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { return }
        var it = dm.items.get_ptr(idx)
        var rtpp = dm.runtimes.get_ptr(&it.id)
        if(rtpp != null && *rtpp != null) {
            resume_runtime(*rtpp)
        } else if(it.state == STATE_PAUSED || it.state == STATE_QUEUED) {
            it.state = STATE_QUEUED
        } else if(it.state == STATE_FAILED || it.state == STATE_CANCELLED) {
            // Resume a failed/cancelled download with existing progress.
            it.state = STATE_QUEUED
            it.error = string()
            it.was_interrupted = false
        }
        start_pending(dm)
    }

    // Cancel a running or queued task.
    public func cancel_task(dm : &mut DownloadManager, id : &string) {
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { return }
        var it = dm.items.get_ptr(idx)

        var rtpp = dm.runtimes.get_ptr(&it.id)
        if(rtpp != null && *rtpp != null) {
            var rt = *rtpp
            request_cancel(rt)
            if(rt.running) {
                join_task(rt)
            }
            delete rt
            dm.runtimes.erase(&it.id)
            it.state = STATE_CANCELLED
        } else if(it.state != STATE_DONE && it.state != STATE_FAILED) {
            it.state = STATE_CANCELLED
        }
    }

    // Remove a task from the queue entirely (cancelling it if still active).
    // Optionally also deletes the downloaded file.
    public func remove_task(dm : &mut DownloadManager, id : &string) {
        remove_task_file(dm, id, false)
    }

    public func remove_task_file(dm : &mut DownloadManager, id : &string, delete_file : bool) {
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { return }
        var it = dm.items.get_ptr(idx)
        if(delete_file) {
            var path = it.local_path()
            remove(path.data())
            var i : usize = 0
            while(i < 64) {
                var ps = string()
                ps.append_string(&it.dir)
                ps.append('/')
                ps.append_string(&it.filename)
                var idxs = string()
                idxs.append_integer(i as bigint)
                ps.append('.')
                ps.append_string(&idxs)
                ps.append_view(".part")
                remove(ps.data())
                i += 1
            }
        }
        cancel_task(dm, id)
        idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { return }
        dm.items.erase(idx)
    }

    // Copy a target directory path computed from an explicit category.
    func category_dir_for_dirs(dm : &DownloadManager, cat : Category, filename : string_view) : string {
        // Build the categorized path directly (library-internal version of
        // Settings.category_dir_for that doesn't require a settings object).
        var sub = category_dir(cat)
        var out = dm.download_dir.copy()
        if(sub.size() > 0) {
            out.append('/')
            out.append_string(&sub)
        }
        return out
    }

    // Merge live progress into the item list and return an immutable snapshot.
    public func snapshot(dm : &mut DownloadManager) : vector<DownloadItem> {
        var out = vector<DownloadItem>()
        for(var i = 0u; i < dm.items.size(); i++) {
            var it = dm.items.get_ptr(i)
            var copy = it.copy()
            var rtpp = dm.runtimes.get_ptr(&it.id)
            if(rtpp != null && *rtpp != null) {
                var p = snapshot_progress(*rtpp)
                copy.total_bytes = p.total_bytes
                copy.downloaded_bytes = p.downloaded_bytes
                copy.speed_bytes_per_sec = p.speed_bytes_per_sec
                copy.state = p.state
                copy.error = p.error.copy()
                copy.segments_json = snapshot_segments_json(*rtpp)
            }
            out.push_back(copy)
        }
        return out
    }

    // Serve-side JSON document of the whole queue + settings.
    public func state_json(dm : &mut DownloadManager, version : string_view) : string {
        var dir_copy = dm.download_dir.copy()
        var out = string::make_no_len("{\"download_dir\":")
        out.append_string(&json_string(string_view::make_view(&dir_copy)))
        out.append_string(&string::make_no_len(",\"max_concurrent\":"))
        out.append_integer(dm.max_concurrent as bigint)
        out.append_string(&string::make_no_len(",\"version\":"))
        out.append_string(&json_string(version))
        out.append_string(&string::make_no_len(",\"items\":["))
        var snap = snapshot(dm)
        for(var i = 0u; i < snap.size(); i++) {
            if(i > 0u) { out.append(',') }
            var it = snap.get_ptr(i)
            out.append_string(&item_to_json(&*it))
        }
        out.append_string(&string::make_no_len("]}"))
        return out
    }

    // Join and release every worker thread (called on shutdown). Mark any
    // items that were still downloading as interrupted so auto-resume can
    // pick them up on next launch.
    public func shutdown(dm : &mut DownloadManager) {
        for(var i = 0u; i < dm.items.size(); i++) {
            var it = dm.items.get_ptr(i)
            var rtpp = dm.runtimes.get_ptr(&it.id)
            if(rtpp != null && *rtpp != null) {
                var rt = *rtpp
                request_cancel(rt)
                if(rt.running) {
                    join_task(rt)
                }
                // Mark as interrupted so auto-resume can restart it later.
                if(it.state == STATE_DOWNLOADING) {
                    it.state = STATE_FAILED
                    it.was_interrupted = true
                    var msg = string::make_no_len("interrupted by shutdown")
                    it.error = msg
                }
                delete rt
            }
        }
        dm.runtimes = ordered_map<string, *mut TaskRuntime>()
    }

} // end namespace cdm