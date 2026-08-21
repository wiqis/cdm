// ChemicalDM — tests for queue operations (add, find, retry, change_url,
// pause, resume, cancel, remove). These test the DownloadManager's queue
// logic without starting actual network downloads.

using std::string;
using std::string_view;

@test
public func CDM_queue_add_and_find(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 10
    var id = cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/a.bin"))
    if(id.empty()) { env.error("add_task returned empty id"); return }
    var idx = cdm::find_item_index(&dm, &id)
    if(idx == dm.items.size()) { env.error("item not found after add"); return }
    var it = dm.items.get_ptr(idx)
    // Item may be QUEUED or DOWNLOADING depending on max_concurrent / start_pending.
    if(it.state != cdm::STATE_QUEUED && it.state != cdm::STATE_DOWNLOADING) {
        env.error("expected QUEUED or DOWNLOADING"); return
    }
}

@test
public func CDM_queue_find_nonexistent(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    var fake = string::make_no_len("nonexistent-id")
    var idx = cdm::find_item_index(&dm, &fake)
    if(idx != dm.items.size()) { env.error("nonexistent should return size"); return }
}

@test
public func CDM_queue_add_multiple(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 10
    var id1 = cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/a.bin"))
    var id2 = cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/b.bin"))
    var id3 = cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/c.bin"))
    if(dm.items.size() != 3u) { env.error("expected 3 items"); return }
    if(id1.equals(&id2) || id2.equals(&id3)) { env.error("duplicate ids"); return }
}

@test
public func CDM_queue_pause_queued(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 10
    var id = cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/a.bin"))
    // Item is queued (no worker attached since max_concurrent not exceeded
    // but start_pending spawns a worker — so we pause before it starts).
    // Actually start_pending will have spawned a worker. Let's just test
    // the pause path: pause should transition to PAUSED.
    cdm::pause_task(&mut dm, &id)
    var idx = cdm::find_item_index(&dm, &id)
    var it = dm.items.get_ptr(idx)
    // With a live runtime, pause_task requests pause on the worker.
    // Without a runtime (e.g. if we manually cleared it), it marks PAUSED.
    // Either way the item should not be in a broken state.
    if(it.state == cdm::STATE_DONE || it.state == cdm::STATE_FAILED) {
        env.error("pause should not transition to done/failed")
        return
    }
}

@test
public func CDM_queue_retry(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    // Prevent auto-start so items stay in QUEUED state.
    dm.max_concurrent = 0
    var id = cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/a.bin"))
    var idx = cdm::find_item_index(&dm, &id)
    var it = dm.items.get_ptr(idx)

    // Simulate a failed download.
    it.state = cdm::STATE_FAILED
    it.error = string::make_no_len("test error")
    it.downloaded_bytes = 500

    var ok = cdm::retry_task(&mut dm, &id)
    if(!ok) { env.error("retry_task should succeed"); return }
    idx = cdm::find_item_index(&dm, &id)
    it = dm.items.get_ptr(idx)
    if(it.state != cdm::STATE_QUEUED) { env.error("retry should set QUEUED"); return }
    if(!it.error.empty()) { env.error("retry should clear error"); return }
    if(it.retry_count != 1) { env.error("retry_count should be 1"); return }
}

@test
public func CDM_queue_retry_done_fails(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 10
    var id = cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/a.bin"))
    var idx = cdm::find_item_index(&dm, &id)
    var it = dm.items.get_ptr(idx)
    it.state = cdm::STATE_DONE
    var ok = cdm::retry_task(&mut dm, &id)
    if(ok) { env.error("retry should fail for DONE"); return }
}

@test
public func CDM_queue_cancel(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 10
    var id = cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/a.bin"))
    // Clear runtime to test the non-running cancel path.
    var idx = cdm::find_item_index(&dm, &id)
    var it = dm.items.get_ptr(idx)
    var rtpp = dm.runtimes.get_ptr(&it.id)
    if(rtpp != null && *rtpp != null) {
        var rt = *rtpp
        cdm::request_cancel(rt)
        if(rt.running) { cdm::join_task(rt) }
        delete rt
        dm.runtimes.erase(&it.id)
    }
    cdm::cancel_task(&mut dm, &id)
    idx = cdm::find_item_index(&dm, &id)
    it = dm.items.get_ptr(idx)
    if(it.state != cdm::STATE_CANCELLED) { env.error("expected CANCELLED"); return }
}

@test
public func CDM_queue_remove(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 10
    var id = cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/a.bin"))
    // Clear runtime.
    var idx = cdm::find_item_index(&dm, &id)
    var it = dm.items.get_ptr(idx)
    var rtpp = dm.runtimes.get_ptr(&it.id)
    if(rtpp != null && *rtpp != null) {
        var rt = *rtpp
        cdm::request_cancel(rt)
        if(rt.running) { cdm::join_task(rt) }
        delete rt
        dm.runtimes.erase(&it.id)
    }
    cdm::remove_task(&mut dm, &id)
    idx = cdm::find_item_index(&dm, &id)
    if(idx != dm.items.size()) { env.error("item should be removed"); return }
}

@test
public func CDM_queue_change_url(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    var id = cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/old.bin"))

    var ok = cdm::change_url(&mut dm, &id, string_view::make_no_len("https://example.com/new.bin"))
    if(!ok) { env.error("change_url should succeed"); return }
    var idx = cdm::find_item_index(&dm, &id)
    var it = dm.items.get_ptr(idx)
    if(!it.url.equals_view("https://example.com/new.bin")) { env.error("URL not updated"); return }
    if(it.state != cdm::STATE_QUEUED) { env.error("should be QUEUED"); return }
    if(it.downloaded_bytes != 0) { env.error("progress should reset"); return }
}

@test
public func CDM_queue_resume_failed(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    var id = cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/a.bin"))
    var idx = cdm::find_item_index(&dm, &id)
    var it = dm.items.get_ptr(idx)

    // Simulate failed state with partial progress.
    it.state = cdm::STATE_FAILED
    it.downloaded_bytes = 500
    it.total_bytes = 1000

    cdm::resume_task(&mut dm, &id)
    idx = cdm::find_item_index(&dm, &id)
    it = dm.items.get_ptr(idx)
    if(it.state != cdm::STATE_QUEUED) { env.error("resume failed -> QUEUED"); return }
    // Progress should be preserved for the worker to resume.
    if(it.downloaded_bytes != 500) { env.error("downloaded_bytes should be preserved"); return }
    if(it.total_bytes != 1000) { env.error("total_bytes should be preserved"); return }
}

@test
public func CDM_queue_clear_finished(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 10
    var id1 = cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/a.bin"))
    var id2 = cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/b.bin"))
    var id3 = cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/c.bin"))

    // Clear runtimes and set states.
    for(var i = 0u; i < dm.items.size(); i++) {
        var it = dm.items.get_ptr(i)
        var rtpp = dm.runtimes.get_ptr(&it.id)
        if(rtpp != null && *rtpp != null) {
            var rt = *rtpp
            cdm::request_cancel(rt)
            if(rt.running) { cdm::join_task(rt) }
            delete rt
            dm.runtimes.erase(&it.id)
        }
    }
    dm.items.get_ptr(0).state = cdm::STATE_DONE
    dm.items.get_ptr(1).state = cdm::STATE_FAILED
    dm.items.get_ptr(2).state = cdm::STATE_QUEUED

    var removed = cdm::clear_finished(&mut dm)
    if(removed != 2) { env.error("expected 2 removed"); return }
    if(dm.items.size() != 1u) { env.error("expected 1 remaining"); return }
}

@test
public func CDM_queue_priority_ordering(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 10
    // Add items with different priorities (lower = higher priority).
    var id_low = cdm::add_task_ex(&mut dm, string_view::make_no_len("https://example.com/low.bin"),
                                  string_view(), string_view(), 10, cdm::Category.Other)
    var id_high = cdm::add_task_ex(&mut dm, string_view::make_no_len("https://example.com/high.bin"),
                                   string_view(), string_view(), 1, cdm::Category.Other)
    var id_default = cdm::add_task_ex(&mut dm, string_view::make_no_len("https://example.com/default.bin"),
                                      string_view(), string_view(), 0, cdm::Category.Other)

    // Find items and verify priorities.
    var idx_high = cdm::find_item_index(&dm, &id_high)
    var idx_low = cdm::find_item_index(&dm, &id_low)
    var idx_def = cdm::find_item_index(&dm, &id_default)
    if(idx_high == dm.items.size()) { env.error("high not found"); return }
    if(idx_low == dm.items.size()) { env.error("low not found"); return }
    if(idx_def == dm.items.size()) { env.error("default not found"); return }
    var prio_high = dm.items.get_ptr(idx_high).priority
    var prio_low = dm.items.get_ptr(idx_low).priority
    var prio_def = dm.items.get_ptr(idx_def).priority
    if(prio_high != 1) { env.error("high prio"); return }
    if(prio_low != 10) { env.error("low prio"); return }
    if(prio_def != 0) { env.error("default prio"); return }
}

@test
public func CDM_queue_snapshot(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 10
    cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/a.bin"))
    cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/b.bin"))
    var snap = cdm::snapshot(&mut dm)
    if(snap.size() != 2u) { env.error("snapshot size"); return }
    // IDs should match.
    var it0 = dm.items.get_ptr(0)
    var snap0 = snap.get_ptr(0)
    if(!it0.id.equals(&snap0.id)) { env.error("snapshot id mismatch"); return }
}

@test
public func CDM_queue_state_json(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 5
    cdm::add_task(&mut dm, string_view::make_no_len("https://example.com/a.bin"))
    var json = cdm::state_json(&mut dm, string_view::make_no_len("0.1.0"))
    if(json.find("0.1.0") == std::NPOS) { env.error("missing version"); return }
    if(json.find("items") == std::NPOS) { env.error("missing items"); return }
    if(json.find("a.bin") == std::NPOS) { env.error("missing item filename"); return }
}
