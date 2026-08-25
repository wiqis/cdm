// ChemicalDM — unit tests for the newer engine features: duplicate-file
// renaming, priority scheduling, category routing and the edit/restart item
// operations. These are synchronous (no network) and exercise the manager
// queue logic directly.

using std::string;
using std::string_view;
using std::vector;
using std::Option;
using std::Result;

// Verify duplicate rename produces a non-colliding name.
@test
public func CDM_dup_rename(env : &mut TestEnv) {
    var base = string::make_no_len("/tmp/cdm-dup-test")
    fs::remove_dir_all_recursive(base.data())
    fs::create_dir_all(base.data())

    // Create an existing file "report.pdf" so the rename must find a new name.
    var existing = base.copy()
    existing.append_string(&string::make_no_len("/report.pdf"))
    var f = fopen(existing.data(), "w")
    if(f == null) { env.error("dup: cannot create existing file"); return }
    fclose(f)

    var dm = cdm::DownloadManager()
    dm.download_dir = base.copy()
    dm.duplicate_action = 0   // rename

    var item = cdm::DownloadItem(string(), string(), base.copy(), string::make_no_len("report.pdf"))
    var namev = string_view::make_no_len("report.pdf")
    cdm::resolve_duplicate_filename(&mut dm, base.data(), namev, &mut item)
    var got = item.filename.copy()
    var want = string::make_no_len("report (1).pdf")
    if(!got.equals(&want)) {
        env.error("dup: expected report (1).pdf, got ")
        env.error(got.data())
        fs::remove_dir_all_recursive(base.data())
        return
    }
    fs::remove_dir_all_recursive(base.data())
}

// Duplicate-overwrite keeps the original name.
@test
public func CDM_dup_overwrite(env : &mut TestEnv) {
    var base = string::make_no_len("/tmp/cdm-dup-overwrite")
    fs::remove_dir_all_recursive(base.data())
    fs::create_dir_all(base.data())
    var existing = base.copy()
    existing.append_string(&string::make_no_len("/report.pdf"))
    var f = fopen(existing.data(), "w")
    if(f == null) { env.error("dupow: cannot create file"); return }
    fclose(f)

    var dm = cdm::DownloadManager()
    dm.download_dir = base.copy()
    dm.duplicate_action = 1   // overwrite

    var item = cdm::DownloadItem(string(), string(), base.copy(), string::make_no_len("report.pdf"))
    var namev = string_view::make_no_len("report.pdf")
    cdm::resolve_duplicate_filename(&mut dm, base.data(), namev, &mut item)
    var want = string::make_no_len("report.pdf")
    if(!item.filename.equals(&want)) { env.error("dupow: name changed"); }
    fs::remove_dir_all_recursive(base.data())
}

// Priority: the lowest priority value must be started first.
@test
public func CDM_priority_order(env : &mut TestEnv) {
    var base = string::make_no_len("/tmp/cdm-prio-test")
    fs::remove_dir_all_recursive(base.data())
    fs::create_dir_all(base.data())

    var dm = cdm::DownloadManager()
    dm.download_dir = base.copy()
    dm.max_concurrent = 0   // prevent auto-start while we add items
    dm.max_segments = 1

    var u1 = string::make_no_len("https://127.0.0.1:9/a.bin")
    var u2 = string::make_no_len("https://127.0.0.1:9/b.bin")
    var u3 = string::make_no_len("https://127.0.0.1:9/c.bin")
    cdm::add_task_ex(&mut dm, string_view::make_view(&u1), string_view(), string_view(), 2, 0)
    var id2 = cdm::add_task_ex(&mut dm, string_view::make_view(&u2), string_view(), string_view(), 0, 0)
    cdm::add_task_ex(&mut dm, string_view::make_view(&u3), string_view(), string_view(), 1, 0)

    // With max_concurrent=1 the scheduler must pick the priority-0 item (id2)
    // first. Because the URLs are unroutable the worker may already be
    // DOWNLOADING or FAILED — the assertion is that id2 is the one attempted
    // (not left QUEUED) after start_pending.
    dm.max_concurrent = 1
    cdm::start_pending(&mut dm)
    var snap = cdm::snapshot(&mut dm)
    if(snap.size() != 3u) { env.error("prio: expected 3 items"); cdm::shutdown(&mut dm); return }
    var id2_attempted = false
    for(var i = 0u; i < snap.size(); i++) {
        var it = snap.get_ptr(i)
        if(it.id.equals(&id2)) {
            if(it.state != cdm::STATE_QUEUED && it.state != cdm::STATE_PAUSED && it.state != cdm::STATE_CANCELLED) {
                id2_attempted = true
            }
        }
    }
    if(!id2_attempted) {
        env.error("prio: priority-0 item was not the one started")
    }
    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(base.data())
}

// Destination resolution contract: with no dir_hint the library uses the
// manager's download_dir verbatim. Category routing is app policy — the
// library only stores the opaque category tag on the item.
@test
public func CDM_category_routing(env : &mut TestEnv) {
    var base = string::make_no_len("/tmp/cdm-cat-test")
    fs::remove_dir_all_recursive(base.data())
    fs::create_dir_all(base.data())

    var dm = cdm::DownloadManager()
    dm.download_dir = base.copy()

    var u = string::make_no_len("https://example.com/clip.mp4")
    var id = cdm::add_task_ex(&mut dm, string_view::make_view(&u), string_view(), string_view(), 0, 3)
    if(id.size() == 0u) { env.error("cat: add failed"); cdm::shutdown(&mut dm); fs::remove_dir_all_recursive(base.data()); return }

    var snap = cdm::snapshot(&mut dm)
    if(snap.size() == 0u) { env.error("cat: no item"); cdm::shutdown(&mut dm); fs::remove_dir_all_recursive(base.data()); return }
    var it = snap.get_ptr(0)
    var want = base.copy()
    if(!it.dir.equals(&want)) {
        env.error("cat: expected download_dir verbatim, got ")
        env.error(it.dir.data())
    }
    if(it.category != 3) { env.error("cat: category tag not stored"); return }
    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(base.data())
}

// edit_item updates the destination directory of a queued item.
@test
public func CDM_edit_item(env : &mut TestEnv) {
    var base = string::make_no_len("/tmp/cdm-edit-test")
    fs::remove_dir_all_recursive(base.data())
    fs::create_dir_all(base.data())

    var dm = cdm::DownloadManager()
    dm.download_dir = base.copy()
    dm.max_concurrent = 0   // don't auto-start

    var u = string::make_no_len("https://example.com/file.bin")
    var id = cdm::add_task_ex(&mut dm, string_view::make_view(&u), string_view(), string_view(), 0, 0)
    if(id.size() == 0u) { env.error("edit: add failed"); return }

    var newdir = string::make_no_len("/tmp/cdm-edit-test/nested")
    fs::create_dir_all(newdir.data())
    var dirv = string_view::make_view(&newdir)
    var ok = cdm::edit_item(&mut dm, &id, dirv, string_view(), 1, 0, 0, 0)
    if(!ok) { env.error("edit: edit_item returned false"); return }

    var snap = cdm::snapshot(&mut dm)
    if(snap.size() == 0u) { env.error("edit: no item"); return }
    var it = snap.get_ptr(0)
    var got = it.dir.copy()
    if(!got.equals(&newdir)) { env.error("edit: dir not updated"); return }
    if(it.priority != 1) { env.error("edit: priority not updated"); return }
    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(base.data())
}

// restart_task clears progress and re-queues.
@test
public func CDM_restart(env : &mut TestEnv) {
    var base = string::make_no_len("/tmp/cdm-restart-test")
    fs::remove_dir_all_recursive(base.data())
    fs::create_dir_all(base.data())

    var dm = cdm::DownloadManager()
    dm.download_dir = base.copy()
    dm.max_concurrent = 0

    var u = string::make_no_len("https://example.com/restart.bin")
    var id = cdm::add_task_ex(&mut dm, string_view::make_view(&u), string_view(), string_view(), 0, 0)
    if(id.size() == 0u) { env.error("restart: add failed"); return }

    // Simulate a completed item by marking it done + progress.
    var it = cdm::find_item_for_tests(&mut dm, &id)
    if(it == null) { env.error("restart: not found"); return }
    it.state = cdm::STATE_DONE
    it.downloaded_bytes = 500
    it.total_bytes = 500

    var ok = cdm::restart_task(&mut dm, &id)
    if(!ok) { env.error("restart: returned false"); return }
    var snap = cdm::snapshot(&mut dm)
    if(snap.size() == 0u) { env.error("restart: no item"); return }
    var it2 = snap.get_ptr(0)
    if(it2.state != cdm::STATE_QUEUED) { env.error("restart: not queued"); return }
    if(it2.downloaded_bytes != 0) { env.error("restart: progress not reset"); return }
    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(base.data())
}

// retry_task re-queues a failed item with a bumped retry count.
@test
public func CDM_retry(env : &mut TestEnv) {
    var base = string::make_no_len("/tmp/cdm-retry-test")
    fs::remove_dir_all_recursive(base.data())
    fs::create_dir_all(base.data())

    var dm = cdm::DownloadManager()
    dm.download_dir = base.copy()
    dm.max_concurrent = 0

    var u = string::make_no_len("https://example.com/retry.bin")
    var id = cdm::add_task_ex(&mut dm, string_view::make_view(&u), string_view(), string_view(), 0, 0)
    if(id.size() == 0u) { env.error("retry: add failed"); return }

    var it = cdm::find_item_for_tests(&mut dm, &id)
    if(it == null) { env.error("retry: not found"); return }
    it.state = cdm::STATE_FAILED
    it.error = string::make_no_len("boom")

    var ok = cdm::retry_task(&mut dm, &id)
    if(!ok) { env.error("retry: returned false"); return }
    var snap = cdm::snapshot(&mut dm)
    if(snap.size() == 0u) { env.error("retry: no item"); return }
    var it2 = snap.get_ptr(0)
    if(it2.state != cdm::STATE_QUEUED) { env.error("retry: not queued"); return }
    if(it2.error.size() != 0u) { env.error("retry: error not cleared"); return }
    cdm::shutdown(&mut dm)
    fs::remove_dir_all_recursive(base.data())
}

// display_filename applies the " (N)" suffix for duplicates.
@test
public func CDM_display_filename(env : &mut TestEnv) {
    var item = cdm::DownloadItem(string(), string(), string(), string::make_no_len("video.mp4"))
    item.duplicate_suffix = 2
    var d = item.display_filename()
    var want = string::make_no_len("video (2).mp4")
    if(!d.equals(&want)) {
        env.error("display: expected video (2).mp4, got ")
        env.error(d.data())
    }
    item.duplicate_suffix = 0
    var d2 = item.display_filename()
    if(!d2.equals(&string::make_no_len("video.mp4"))) { env.error("display: suffix 0 changed name") }
}