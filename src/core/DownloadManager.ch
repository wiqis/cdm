using std::string;

public namespace download {

public struct DownloadEntry {
    var id : i64
    var url : string
    var filename : string
    var folder : string
    var status : i64
    var total_bytes : i64
    var downloaded_bytes : i64
    var speed : i64
    var task_active : bool
}

public struct DownloadManager {
    var next_id : i64
    var entries : std::vector<DownloadEntry>
    var task_urls : std::vector<string>
    var task_filenames : std::vector<string>
    var task_folders : std::vector<string>
    var task_total : std::vector<i64>
    var task_downloaded : std::vector<i64>
    var task_speeds : std::vector<i64>
    var task_status : std::vector<i64>
    var task_error : std::vector<string>
}

public func dm_init() : DownloadManager {
    var dm = DownloadManager {
        next_id: 1,
        entries: std::vector<DownloadEntry>(),
        task_urls: std::vector<string>(),
        task_filenames: std::vector<string>(),
        task_folders: std::vector<string>(),
        task_total: std::vector<i64>(),
        task_downloaded: std::vector<i64>(),
        task_speeds: std::vector<i64>(),
        task_status: std::vector<i64>(),
        task_error: std::vector<string>()
    }
    return dm
}

public func dm_add(dm : *mut DownloadManager, url_str : &string, filename : &string, folder : &string) : i64 {
    var id = dm.next_id
    dm.next_id = dm.next_id + 1

    dm.task_urls.push_back(url_str.copy())
    dm.task_filenames.push_back(filename.copy())
    dm.task_folders.push_back(folder.copy())
    dm.task_total.push_back(0)
    dm.task_downloaded.push_back(0)
    dm.task_speeds.push_back(0)
    dm.task_status.push_back(0)
    dm.task_error.push_back(string())

    var entry = DownloadEntry {
        id: id,
        url: url_str.copy(),
        filename: filename.copy(),
        folder: folder.copy(),
        status: 0,
        total_bytes: 0,
        downloaded_bytes: 0,
        speed: 0,
        task_active: false
    }
    dm.entries.push_back(entry)

    start_task_bg(dm, dm.entries.size() - 1 as int)
    return id
}

public func dm_get_all_json(dm : *mut DownloadManager) : string {
    sync_tasks(dm)
    var json = string("[")
    var first = true
    var i = 0
    while(i < dm.entries.size() as int) {
        var e = dm.entries.get_ptr(i as size_t)
        if(!first) { json.append_view(",") }
        first = false
        json.append_view("{\"id\":")
        json.append_integer(e.id)
        json.append_view(",\"url\":\"")
        json.append_string(&e.url)
        json.append_view("\",\"filename\":\"")
        json.append_string(&e.filename)
        json.append_view("\",\"folder\":\"")
        json.append_string(&e.folder)
        json.append_view("\",\"status\":\"")
        var status_str = status_to_str(e.status)
        json.append_view(&status_str.to_view())
        json.append_view("\",\"total\":")
        json.append_integer(e.total_bytes)
        json.append_view(",\"downloaded\":")
        json.append_integer(e.downloaded_bytes)
        json.append_view(",\"speed\":")
        json.append_integer(e.speed)
        json.append_view(",\"progress\":")
        json.append_integer(calc_progress(e.total_bytes, e.downloaded_bytes))
        json.append_view(",\"eta\":\"")
        var eta_str = calc_eta(e.total_bytes, e.downloaded_bytes, e.speed)
        json.append_view(&eta_str.to_view())
        json.append_view("\"}")
        i = i + 1
    }
    json.append_view("]")
    return json
}

public func dm_pause(dm : *mut DownloadManager, id : i64) {
    var i = 0
    while(i < dm.entries.size() as int) {
        var e = dm.entries.get_ptr(i as size_t)
        if(e.id == id && e.status == 1) {
            e.status = 2
            e.task_active = false
        }
        i = i + 1
    }
}

public func dm_resume(dm : *mut DownloadManager, id : i64) {
    var i = 0
    while(i < dm.entries.size() as int) {
        var e = dm.entries.get_ptr(i as size_t)
        if(e.id == id && (e.status == 2 || e.status == 4)) {
            var idx = i
            e.status = 1
            e.task_active = true
            e.speed = 0
            dm.task_status.set(idx as size_t, 1)
            dm.task_downloaded.set(idx as size_t, 0)
            dm.task_speeds.set(idx as size_t, 0)
            start_task_bg(dm, idx)
        }
        i = i + 1
    }
}

public func dm_cancel(dm : *mut DownloadManager, id : i64) {
    var i = 0
    while(i < dm.entries.size() as int) {
        var e = dm.entries.get_ptr(i as size_t)
        if(e.id == id) {
            dm.entries.remove(i as size_t)
            dm.task_urls.remove(i as size_t)
            dm.task_filenames.remove(i as size_t)
            dm.task_folders.remove(i as size_t)
            dm.task_total.remove(i as size_t)
            dm.task_downloaded.remove(i as size_t)
            dm.task_speeds.remove(i as size_t)
            dm.task_status.remove(i as size_t)
            dm.task_error.remove(i as size_t)
            return
        }
        i = i + 1
    }
}

struct _TaskBgArgs {
    var dm_ptr : *mut DownloadManager
    var idx : int
}

func _task_bg_thread(arg : *mut void) : *void {
    var args = arg as *mut _TaskBgArgs
    var dm = args.dm_ptr
    var idx = args.idx

    var url_ptr = dm.task_urls.get_ptr(idx as size_t)
    var fname_ptr = dm.task_filenames.get_ptr(idx as size_t)
    var fpath_ptr = dm.task_folders.get_ptr(idx as size_t)

    var task = DownloadTask {
        id: dm.entries.get_ptr(idx as size_t).id,
        url: url_ptr.copy(),
        filename: fname_ptr.copy(),
        folder: fpath_ptr.copy(),
        total_bytes: 0,
        downloaded_bytes: 0,
        speed: 0,
        status_code: 1,
        error_msg: string()
    }

    do_download(&raw mut task, null as *mut bool)

    dm.task_status.set(idx as size_t, task.status_code)
    dm.task_downloaded.set(idx as size_t, task.downloaded_bytes)
    dm.task_total.set(idx as size_t, task.total_bytes)
    dm.task_speeds.set(idx as size_t, task.speed)
    dm.task_error.set(idx as size_t, task.error_msg.copy())

    var e = dm.entries.get_ptr(idx as size_t)
    e.status = task.status_code
    e.total_bytes = task.total_bytes
    e.downloaded_bytes = task.downloaded_bytes
    e.speed = task.speed
    e.task_active = false

    free(arg)
    return null as *void
}

func start_task_bg(dm : *mut DownloadManager, idx : int) {
    var args = malloc(sizeof(_TaskBgArgs) as size_t) as *mut _TaskBgArgs
    args.dm_ptr = dm
    args.idx = idx
    std::concurrent::spawn(_task_bg_thread, args as *mut void)
}

func sync_tasks(dm : *mut DownloadManager) {
    var i = 0
    while(i < dm.entries.size() as int) {
        var e = dm.entries.get_ptr(i as size_t)
        if(i < dm.task_status.size() as int) {
            e.status = dm.task_status.get(i as size_t)
            e.total_bytes = dm.task_total.get(i as size_t)
            e.downloaded_bytes = dm.task_downloaded.get(i as size_t)
            e.speed = dm.task_speeds.get(i as size_t)
        }
        i = i + 1
    }
}

func status_to_str(s : i64) : string {
    if(s == 0) { return string("queued") }
    if(s == 1) { return string("active") }
    if(s == 2) { return string("paused") }
    if(s == 3) { return string("complete") }
    if(s == 4) { return string("failed") }
    if(s == 5) { return string("error") }
    return string("unknown")
}

func calc_progress(total : i64, downloaded : i64) : i64 {
    if(total <= 0) { return 0 }
    return downloaded * 100 / total
}

func calc_eta(total : i64, downloaded : i64, speed : i64) : string {
    if(speed <= 0 || total <= downloaded) { return string("--:--") }
    var remaining = total - downloaded
    var secs = remaining / speed
    var mins = secs / 60
    var hrs = mins / 60
    mins = mins % 60
    secs = secs % 60
    var s = string()
    if(hrs > 0) {
        append_two_digit(&raw s, hrs)
        s.append(':')
    }
    append_two_digit(&raw s, mins)
    s.append(':')
    append_two_digit(&raw s, secs)
    return s
}

func append_two_digit(s : *string, val : i64) {
    var tens = val / 10
    var ones = val % 10
    s.append((tens + '0') as char)
    s.append((ones + '0') as char)
}

}
