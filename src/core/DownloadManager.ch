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

        @constructor func constructor() {
            var dir = string::make_no_len(DEFAULT_DOWNLOAD_DIR)
            return DownloadManager {
                items_mutex = mutex(),
                items = vector<DownloadItem>(),
                runtimes = ordered_map<string, *mut TaskRuntime>(),
                download_dir = dir,
                max_concurrent = DEFAULT_MAX_CONCURRENT
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

    // Look up an index by id, or return items.size().
    func find_item_index(dm : &DownloadManager, id : &string) : usize {
        for(var i = 0u; i < dm.items.size(); i++) {
            var it = dm.items.get_ptr(i)
            if(it.id.equals(id)) { return i }
        }
        return dm.items.size()
    }

    // Start queued items up to max_concurrent.
    public func start_pending(dm : &mut DownloadManager) {
        var active = count_active(dm)
        for(var i = 0u; i < dm.items.size(); i++) {
            if(active >= dm.max_concurrent) { return }
            var it = dm.items.get_ptr(i)
            if(it.state != STATE_QUEUED) { continue }
            var rtpp = dm.runtimes.get_ptr(&it.id)
            if(rtpp != null) { continue }

            var id_copy = it.id.copy()
            var rt = new TaskRuntime(id_copy)
            if(rt == null) { continue }

            dm.runtimes.insert(it.id.copy(), rt)
            var url_v = string_view::make_view(&it.url)
            var dir_v = string_view::make_view(&it.dir)
            var fname_v = string_view::make_view(&it.filename)
            if(start_task(rt, url_v, dir_v, fname_v)) {
                it.state = STATE_DOWNLOADING
                active = active + 1
            } else {
                dm.runtimes.erase(&it.id)
                delete rt
            }
        }
    }

    // Add a new URL to the queue.
    public func add_task(dm : &mut DownloadManager, url_str : string_view) : string {
        var suggested = suggested_filename(url_str)
        var id = uuid::v4().to_string()

        var item = DownloadItem(id.copy(), string(url_str.data(), url_str.size()),
                                dm.download_dir.copy(), suggested)

        dm.items.push_back(item)
        start_pending(dm)
        return id
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
    public func remove_task(dm : &mut DownloadManager, id : &string) {
        var idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { return }
        cancel_task(dm, id)
        idx = find_item_index(dm, id)
        if(idx == dm.items.size()) { return }
        var it = dm.items.get_ptr(idx)
        // vector erase by swap-and-pop is O(1); order is not user-visible.
        dm.items.erase(idx)
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

    // Join and release every worker thread (called on shutdown or --selftest).
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
                delete rt
            }
        }
        dm.runtimes = ordered_map<string, *mut TaskRuntime>()
    }

} // end namespace cdm