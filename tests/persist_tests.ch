// ChemicalDM — tests for persistence reliability: queue state roundtrip,
// progress file crash recovery, and the interaction between queue.txt
// and progress.txt across simulated restarts.

using std::string;
using std::string_view;

// Helper: create an isolated config dir and set CDM_CONFIG_DIR.
func setup_test_cfg() : string {
    var cfg_dir = string::make_no_len("/tmp/cdm_persist_test_")
    cfg_dir.append_string(&uuid::v4().to_string())
    environment::set(string_view::make_no_len("CDM_CONFIG_DIR"), string_view::make_view(&cfg_dir))
    return cfg_dir
}

// ---- Test: item states survive save/restore roundtrip ----

@test
public func CDM_persist_state_queued_survives(env : &mut TestEnv) {
    var cfg_dir = setup_test_cfg()

    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("s-queued"),
                        string_view::make_no_len("https://example.com/a.bin"),
                        string_view(), string_view(), 0, 0)
    // Force state to QUEUED (it may already be, but be explicit).
    var idx = cdm::find_item_index(&dm, &string::make_no_len("s-queued"))
    dm.items.get_ptr(idx).state = cdm::STATE_QUEUED

    if(!cdm::save_queue(&mut dm)) { env.error("save_queue failed"); return }

    var dm2 = cdm::DownloadManager()
    dm2.max_concurrent = 0
    var restored = cdm::restore_queue(&mut dm2)
    if(restored != 1) { env.error("expected 1 restored"); return }

    var idx2 = cdm::find_item_index(&dm2, &string::make_no_len("s-queued"))
    if(idx2 == dm2.items.size()) { env.error("item not found"); return }
    var it = dm2.items.get_ptr(idx2)
    if(it.state != cdm::STATE_QUEUED) {
        var msg = string::make_no_len("expected QUEUED, got ")
        msg.append_integer(it.state as bigint)
        env.error(msg.data())
        return
    }

    fs::remove_dir_all_recursive(cfg_dir.data())
}

@test
public func CDM_persist_state_paused_survives(env : &mut TestEnv) {
    var cfg_dir = setup_test_cfg()

    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("s-paused"),
                        string_view::make_no_len("https://example.com/b.bin"),
                        string_view(), string_view(), 0, 0)
    var idx = cdm::find_item_index(&dm, &string::make_no_len("s-paused"))
    dm.items.get_ptr(idx).state = cdm::STATE_PAUSED
    dm.items.get_ptr(idx).downloaded_bytes = 5000
    dm.items.get_ptr(idx).total_bytes = 10000

    if(!cdm::save_queue(&mut dm)) { env.error("save_queue failed"); return }

    var dm2 = cdm::DownloadManager()
    dm2.max_concurrent = 0
    var restored = cdm::restore_queue(&mut dm2)
    if(restored != 1) { env.error("expected 1 restored"); return }

    var idx2 = cdm::find_item_index(&dm2, &string::make_no_len("s-paused"))
    var it = dm2.items.get_ptr(idx2)
    if(it.state != cdm::STATE_PAUSED) {
        var msg = string::make_no_len("expected PAUSED, got ")
        msg.append_integer(it.state as bigint)
        env.error(msg.data())
        return
    }
    if(it.downloaded_bytes != 5000) { env.error("progress lost"); return }
    if(it.total_bytes != 10000) { env.error("total lost"); return }
    // PAUSED item must NOT be auto-started by start_pending.
    // (start_pending only picks STATE_QUEUED.)
    var rtpp = dm2.runtimes.get_ptr(&it.id)
    if(rtpp != null && *rtpp != null) { env.error("PAUSED should not have a runtime"); return }

    fs::remove_dir_all_recursive(cfg_dir.data())
}

@test
public func CDM_persist_state_interrupted_survives(env : &mut TestEnv) {
    var cfg_dir = setup_test_cfg()

    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("s-interrupted"),
                        string_view::make_no_len("https://example.com/c.bin"),
                        string_view(), string_view(), 0, 0)
    var idx = cdm::find_item_index(&dm, &string::make_no_len("s-interrupted"))
    dm.items.get_ptr(idx).state = cdm::STATE_DOWNLOADING
    dm.items.get_ptr(idx).downloaded_bytes = 7000
    dm.items.get_ptr(idx).total_bytes = 20000
    dm.items.get_ptr(idx).was_interrupted = true

    if(!cdm::save_queue(&mut dm)) { env.error("save_queue failed"); return }

    var dm2 = cdm::DownloadManager()
    dm2.max_concurrent = 0
    var restored = cdm::restore_queue(&mut dm2)
    if(restored != 1) { env.error("expected 1 restored"); return }

    var idx2 = cdm::find_item_index(&dm2, &string::make_no_len("s-interrupted"))
    var it = dm2.items.get_ptr(idx2)
    if(!it.was_interrupted) { env.error("was_interrupted lost"); return }
    if(it.state != cdm::STATE_FAILED) { env.error("interrupted should be FAILED"); return }
    if(it.downloaded_bytes != 7000) { env.error("downloaded progress lost"); return }
    if(it.total_bytes != 20000) { env.error("total progress lost"); return }

    fs::remove_dir_all_recursive(cfg_dir.data())
}

// ---- Test: progress.txt roundtrip ----

@test
public func CDM_persist_progress_file_roundtrip(env : &mut TestEnv) {
    var cfg_dir = setup_test_cfg()

    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("p-prog1"),
                        string_view::make_no_len("https://example.com/x.bin"),
                        string_view(), string_view(), 0, 0)
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("p-prog2"),
                        string_view::make_no_len("https://example.com/y.bin"),
                        string_view(), string_view(), 0, 0)

    // Simulate partial progress.
    var idx1 = cdm::find_item_index(&dm, &string::make_no_len("p-prog1"))
    dm.items.get_ptr(idx1).downloaded_bytes = 3000
    dm.items.get_ptr(idx1).total_bytes = 10000
    dm.items.get_ptr(idx1).state = cdm::STATE_DOWNLOADING

    var idx2 = cdm::find_item_index(&dm, &string::make_no_len("p-prog2"))
    dm.items.get_ptr(idx2).downloaded_bytes = 8000
    dm.items.get_ptr(idx2).total_bytes = 8000
    dm.items.get_ptr(idx2).state = cdm::STATE_DONE

    // Save queue + progress.
    if(!cdm::save_queue(&mut dm)) { env.error("save_queue failed"); return }

    // Restore into a fresh manager (no progress overlay yet).
    var dm2 = cdm::DownloadManager()
    dm2.max_concurrent = 0
    var restored = cdm::restore_queue(&mut dm2)
    // DONE items are skipped by save_queue, so only 1 (DOWNLOADING) is saved.
    if(restored != 1) {
        var msg = string::make_no_len("expected 1 restored (DONE skipped), got ")
        msg.append_integer(restored as bigint)
        env.error(msg.data())
        return
    }

    // The DOWNLOADING item should have progress.
    var idx_p = cdm::find_item_index(&dm2, &string::make_no_len("p-prog1"))
    var it_p = dm2.items.get_ptr(idx_p)
    if(it_p.downloaded_bytes != 3000) {
        var msg = string::make_no_len("expected 3000, got ")
        msg.append_integer(it_p.downloaded_bytes as bigint)
        env.error(msg.data())
        return
    }
    if(it_p.total_bytes != 10000) { env.error("total mismatch"); return }

    fs::remove_dir_all_recursive(cfg_dir.data())
}

// ---- Test: progress.txt overlay updates stale queue data ----

@test
public func CDM_persist_progress_overlay(env : &mut TestEnv) {
    var cfg_dir = setup_test_cfg()

    // Simulate: queue.txt has an item with 0 progress (initial state),
    // but progress.txt has updated progress from a crash.
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("ov-item"),
                        string_view::make_no_len("https://example.com/z.bin"),
                        string_view(), string_view(), 0, 0)
    // Set progress to 0 (as if it was just queued).
    var idx = cdm::find_item_index(&dm, &string::make_no_len("ov-item"))
    dm.items.get_ptr(idx).downloaded_bytes = 0
    dm.items.get_ptr(idx).total_bytes = 0

    if(!cdm::save_queue(&mut dm)) { env.error("save_queue failed"); return }

    // Now manually write a progress.txt with higher progress.
    var ppath = cdm::progress_file()
    var pout = string::make_no_len("#cdm-progress-v1\n")
    pout.append_view("ov-item")
    pout.append('\t')
    pout.append_view("15000")
    pout.append('\t')
    pout.append_view("50000")
    pout.append('\t')
    pout.append_view("1")
    pout.append('\n')
    var pf = fopen(ppath.data(), "wb")
    if(pf == null) { env.error("cannot write progress.txt"); return }
    fwrite(pout.data() as *mut u8, 1, pout.size(), pf)
    fclose(pf)

    // Restore queue, then overlay progress.
    var dm2 = cdm::DownloadManager()
    dm2.max_concurrent = 0
    var restored = cdm::restore_queue(&mut dm2)
    if(restored != 1) { env.error("expected 1 restored"); return }

    var progress_restored = cdm::restore_progress(&mut dm2, string_view::make_view(&ppath))
    if(progress_restored != 1) { env.error("expected 1 progress restored"); return }

    var idx2 = cdm::find_item_index(&dm2, &string::make_no_len("ov-item"))
    var it = dm2.items.get_ptr(idx2)
    if(it.downloaded_bytes != 15000) {
        var msg = string::make_no_len("overlay downloaded: expected 15000, got ")
        msg.append_integer(it.downloaded_bytes as bigint)
        env.error(msg.data())
        return
    }
    if(it.total_bytes != 50000) { env.error("overlay total mismatch"); return }
    if(!it.was_interrupted) { env.error("overlay should set was_interrupted"); return }
    if(it.state != cdm::STATE_FAILED) { env.error("overlay should set FAILED"); return }

    fs::remove_dir_all_recursive(cfg_dir.data())
}

// ---- Test: DONE items are not saved to queue.txt ----

@test
public func CDM_persist_done_items_skipped(env : &mut TestEnv) {
    var cfg_dir = setup_test_cfg()

    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("done-skip"),
                        string_view::make_no_len("https://example.com/d.bin"),
                        string_view(), string_view(), 0, 0)
    var idx = cdm::find_item_index(&dm, &string::make_no_len("done-skip"))
    dm.items.get_ptr(idx).state = cdm::STATE_DONE

    if(!cdm::save_queue(&mut dm)) { env.error("save_queue failed"); return }

    var dm2 = cdm::DownloadManager()
    dm2.max_concurrent = 0
    var restored = cdm::restore_queue(&mut dm2)
    if(restored != 0) {
        var msg = string::make_no_len("DONE items should not be restored, got ")
        msg.append_integer(restored as bigint)
        env.error(msg.data())
        return
    }

    fs::remove_dir_all_recursive(cfg_dir.data())
}

// ---- Test: multiple items with mixed states ----

@test
public func CDM_persist_mixed_states(env : &mut TestEnv) {
    var cfg_dir = setup_test_cfg()

    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    // Item 1: QUEUED with progress
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("mix-q"),
                        string_view::make_no_len("https://example.com/q.bin"),
                        string_view(), string_view(), 0, 0)
    var iq = cdm::find_item_index(&dm, &string::make_no_len("mix-q"))
    dm.items.get_ptr(iq).state = cdm::STATE_QUEUED
    dm.items.get_ptr(iq).downloaded_bytes = 100
    dm.items.get_ptr(iq).total_bytes = 500

    // Item 2: PAUSED with progress
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("mix-p"),
                        string_view::make_no_len("https://example.com/p.bin"),
                        string_view(), string_view(), 0, 0)
    var ip = cdm::find_item_index(&dm, &string::make_no_len("mix-p"))
    dm.items.get_ptr(ip).state = cdm::STATE_PAUSED
    dm.items.get_ptr(ip).downloaded_bytes = 200
    dm.items.get_ptr(ip).total_bytes = 800

    // Item 3: DONE (should be skipped)
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("mix-d"),
                        string_view::make_no_len("https://example.com/d.bin"),
                        string_view(), string_view(), 0, 0)
    var id = cdm::find_item_index(&dm, &string::make_no_len("mix-d"))
    dm.items.get_ptr(id).state = cdm::STATE_DONE

    if(!cdm::save_queue(&mut dm)) { env.error("save_queue failed"); return }

    var dm2 = cdm::DownloadManager()
    dm2.max_concurrent = 0
    var restored = cdm::restore_queue(&mut dm2)
    if(restored != 2) {
        var msg = string::make_no_len("expected 2 restored (DONE skipped), got ")
        msg.append_integer(restored as bigint)
        env.error(msg.data())
        return
    }

    // Verify QUEUED item.
    var rq = cdm::find_item_index(&dm2, &string::make_no_len("mix-q"))
    var tq = dm2.items.get_ptr(rq)
    if(tq.state != cdm::STATE_QUEUED) { env.error("mix-q should be QUEUED"); return }
    if(tq.downloaded_bytes != 100) { env.error("mix-q progress"); return }

    // Verify PAUSED item (not auto-started).
    var rp = cdm::find_item_index(&dm2, &string::make_no_len("mix-p"))
    var tp = dm2.items.get_ptr(rp)
    if(tp.state != cdm::STATE_PAUSED) {
        var msg = string::make_no_len("mix-p should be PAUSED, got ")
        msg.append_integer(tp.state as bigint)
        env.error(msg.data())
        return
    }
    if(tp.downloaded_bytes != 200) { env.error("mix-p progress"); return }
    // PAUSED must not have a runtime.
    var rtpp = dm2.runtimes.get_ptr(&tp.id)
    if(rtpp != null && *rtpp != null) { env.error("PAUSED should not have runtime"); return }

    fs::remove_dir_all_recursive(cfg_dir.data())
}

// ---- Test: v1 format backward compatibility ----

@test
public func CDM_persist_v1_backward_compat(env : &mut TestEnv) {
    var cfg_dir = setup_test_cfg()

    // Manually write a v1-format queue.txt (no progress/state fields).
    // Ensure the config directory exists by saving then overwriting.
    var dummy = cdm::DownloadManager()
    dummy.max_concurrent = 0
    if(!cdm::save_queue(&mut dummy)) { env.error("pre-save failed"); return }
    var qpath = cdm::queue_file()
    var qout = string::make_no_len("#cdm-queue-v1\n")
    qout.append_view("https://example.com/v1.bin")
    qout.append('\t')
    qout.append_view("v1-id")
    qout.append('\t')
    qout.append_view("/tmp/v1dir")
    qout.append('\t')
    qout.append_view("2")
    qout.append('\n')
    var qf = fopen(qpath.data(), "wb")
    if(qf == null) { env.error("cannot write queue.txt"); return }
    fwrite(qout.data() as *mut u8, 1, qout.size(), qf)
    fclose(qf)

    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    var restored = cdm::restore_queue(&mut dm)
    if(restored != 1) {
        var msg = string::make_no_len("v1 compat: expected 1, got ")
        msg.append_integer(restored as bigint)
        env.error(msg.data())
        return
    }
    var idx = cdm::find_item_index(&dm, &string::make_no_len("v1-id"))
    var it = dm.items.get_ptr(idx)
    if(!it.dir.equals_view("/tmp/v1dir")) { env.error("v1 dir"); return }
    if(it.category != 2) { env.error("v1 category"); return }
    // v1 rows have no state field — default to QUEUED.
    if(it.state != cdm::STATE_QUEUED) { env.error("v1 default state should be QUEUED"); return }

    fs::remove_dir_all_recursive(cfg_dir.data())
}

// ---- Test: queue.txt integrity not affected by progress file writes ----

@test
public func CDM_persist_progress_does_not_corrupt_queue(env : &mut TestEnv) {
    var cfg_dir = setup_test_cfg()

    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("integ-item"),
                        string_view::make_no_len("https://example.com/integ.bin"),
                        string_view(), string_view(), 0, 0)
    if(!cdm::save_queue(&mut dm)) { env.error("save_queue failed"); return }

    // Read the queue.txt content.
    var qpath = cdm::queue_file()
    var qf = fopen(qpath.data(), "rb")
    if(qf == null) { env.error("cannot read queue.txt"); return }
    var qcontent = string()
    var chunk : [4096u]u8
    while(true) {
        var n = fread(&raw mut chunk[0], 1, 4096u, qf)
        if(n == 0u) { break }
        qcontent.append_with_len(&raw mut chunk[0] as *char, n)
    }
    fclose(qf)

    // Write a progress file.
    var ppath = cdm::progress_file()
    var pout = string::make_no_len("#cdm-progress-v1\ninteg-item\t500\t1000\t1\n")
    var pf = fopen(ppath.data(), "wb")
    if(pf == null) { env.error("cannot write progress.txt"); return }
    fwrite(pout.data() as *mut u8, 1, pout.size(), pf)
    fclose(pf)

    // Re-read queue.txt — it must be unchanged.
    var qf2 = fopen(qpath.data(), "rb")
    if(qf2 == null) { env.error("queue.txt disappeared"); return }
    var qcontent2 = string()
    while(true) {
        var n = fread(&raw mut chunk[0], 1, 4096u, qf2)
        if(n == 0u) { break }
        qcontent2.append_with_len(&raw mut chunk[0] as *char, n)
    }
    fclose(qf2)

    if(!qcontent.equals(&qcontent2)) { env.error("queue.txt changed after progress write"); return }

    fs::remove_dir_all_recursive(cfg_dir.data())
}

// ---- Test: retry_task preserves progress for resume ----

@test
public func CDM_persist_retry_preserves_progress(env : &mut TestEnv) {
    var cfg_dir = setup_test_cfg()

    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("retry-prog"),
                        string_view::make_no_len("https://example.com/rp.bin"),
                        string_view(), string_view(), 0, 0)
    var idx = cdm::find_item_index(&dm, &string::make_no_len("retry-prog"))
    dm.items.get_ptr(idx).state = cdm::STATE_FAILED
    dm.items.get_ptr(idx).downloaded_bytes = 15000
    dm.items.get_ptr(idx).total_bytes = 50000
    dm.items.get_ptr(idx).was_interrupted = true

    // Retry should preserve downloaded/total bytes.
    var ok = cdm::retry_task(&mut dm, &string::make_no_len("retry-prog"))
    if(!ok) { env.error("retry_task returned false"); return }

    var idx2 = cdm::find_item_index(&dm, &string::make_no_len("retry-prog"))
    if(idx2 == dm.items.size()) { env.error("item not found after retry"); return }
    var it = dm.items.get_ptr(idx2)
    if(it.state != cdm::STATE_QUEUED) {
        var msg = string::make_no_len("expected QUEUED after retry, got ")
        msg.append_integer(it.state as bigint)
        env.error(msg.data())
        return
    }
    if(it.downloaded_bytes != 15000) {
        var msg = string::make_no_len("expected 15000 downloaded after retry, got ")
        msg.append_integer(it.downloaded_bytes as bigint)
        env.error(msg.data())
        return
    }
    if(it.total_bytes != 50000) {
        var msg = string::make_no_len("expected 50000 total after retry, got ")
        msg.append_integer(it.total_bytes as bigint)
        env.error(msg.data())
        return
    }
    if(it.was_interrupted) { env.error("was_interrupted should be false after retry"); return }
    if(it.retry_count != 1) {
        var msg = string::make_no_len("expected retry_count=1, got ")
        msg.append_integer(it.retry_count as bigint)
        env.error(msg.data())
        return
    }

    fs::remove_dir_all_recursive(cfg_dir.data())
}

// ---- Test: save_queue creates atomic tmp files (no leftover .tmp) ----

@test
public func CDM_persist_save_queue_atomic(env : &mut TestEnv) {
    var cfg_dir = setup_test_cfg()

    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("atomic-item"),
                        string_view::make_no_len("https://example.com/a.bin"),
                        string_view(), string_view(), 0, 0)
    var idx = cdm::find_item_index(&dm, &string::make_no_len("atomic-item"))
    dm.items.get_ptr(idx).state = cdm::STATE_DOWNLOADING
    dm.items.get_ptr(idx).downloaded_bytes = 500
    dm.items.get_ptr(idx).total_bytes = 1000

    if(!cdm::save_queue(&mut dm)) { env.error("save_queue failed"); return }

    // After save, the .tmp file should NOT exist (rename completed).
    var tmppath = cdm::queue_file()
    tmppath.append_view(".tmp")
    if(fs::exists(tmppath.data())) {
        env.error("queue.txt.tmp should not exist after atomic save")
        return
    }

    // The queue.txt should exist and contain the item.
    var qpath = cdm::queue_file()
    if(!fs::exists(qpath.data())) {
        env.error("queue.txt should exist after save")
        return
    }

    // Verify item survived the roundtrip.
    var dm2 = cdm::DownloadManager()
    dm2.max_concurrent = 0
    var restored = cdm::restore_queue(&mut dm2)
    if(restored != 1) {
        var msg = string::make_no_len("expected 1 restored, got ")
        msg.append_integer(restored as bigint)
        env.error(msg.data())
        return
    }
    var idx2 = cdm::find_item_index(&dm2, &string::make_no_len("atomic-item"))
    var it = dm2.items.get_ptr(idx2)
    if(it.downloaded_bytes != 500) {
        var msg = string::make_no_len("expected 500 downloaded, got ")
        msg.append_integer(it.downloaded_bytes as bigint)
        env.error(msg.data())
        return
    }
    if(it.total_bytes != 1000) {
        var msg = string::make_no_len("expected 1000 total, got ")
        msg.append_integer(it.total_bytes as bigint)
        env.error(msg.data())
        return
    }

    fs::remove_dir_all_recursive(cfg_dir.data())
}

// ---- Test: retry then save roundtrip preserves progress ----

@test
public func CDM_persist_retry_save_roundtrip(env : &mut TestEnv) {
    var cfg_dir = setup_test_cfg()

    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("rr-item"),
                        string_view::make_no_len("https://example.com/rr.bin"),
                        string_view(), string_view(), 0, 0)
    var idx = cdm::find_item_index(&dm, &string::make_no_len("rr-item"))
    dm.items.get_ptr(idx).state = cdm::STATE_FAILED
    dm.items.get_ptr(idx).downloaded_bytes = 25000
    dm.items.get_ptr(idx).total_bytes = 100000

    // Retry (preserves progress), then save queue.
    cdm::retry_task(&mut dm, &string::make_no_len("rr-item"))
    if(!cdm::save_queue(&mut dm)) { env.error("save_queue failed"); return }

    // Restore into a fresh manager.
    var dm2 = cdm::DownloadManager()
    dm2.max_concurrent = 0
    var restored = cdm::restore_queue(&mut dm2)
    if(restored != 1) {
        var msg = string::make_no_len("expected 1, got ")
        msg.append_integer(restored as bigint)
        env.error(msg.data())
        return
    }
    var idx2 = cdm::find_item_index(&dm2, &string::make_no_len("rr-item"))
    var it = dm2.items.get_ptr(idx2)
    if(it.downloaded_bytes != 25000) {
        var msg = string::make_no_len("expected 25000, got ")
        msg.append_integer(it.downloaded_bytes as bigint)
        env.error(msg.data())
        return
    }
    if(it.total_bytes != 100000) {
        var msg = string::make_no_len("expected 100000, got ")
        msg.append_integer(it.total_bytes as bigint)
        env.error(msg.data())
        return
    }

    fs::remove_dir_all_recursive(cfg_dir.data())
}
