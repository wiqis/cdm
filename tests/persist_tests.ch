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

// ---- Test: parse_i64_from_view only treats leading '-' as negative ----

@test
public func CDM_parse_i64_leading_minus_only(env : &mut TestEnv) {
    // Leading minus should work.
    var v1 = cdm::parse_i64_from_view(std::string_view::make_no_len("-42"))
    if(v1 != -42) {
        var msg = string::make_no_len("expected -42, got ")
        msg.append_integer(v1 as bigint)
        env.error(msg.data())
        return
    }
    // Mid-string minus should NOT flip the sign.
    var v2 = cdm::parse_i64_from_view(std::string_view::make_no_len("12-34"))
    if(v2 != 12) {
        var msg = string::make_no_len("expected 12 for '12-34', got ")
        msg.append_integer(v2 as bigint)
        env.error(msg.data())
        return
    }
    // Plain positive.
    var v3 = cdm::parse_i64_from_view(std::string_view::make_no_len("999"))
    if(v3 != 999) {
        var msg = string::make_no_len("expected 999, got ")
        msg.append_integer(v3 as bigint)
        env.error(msg.data())
        return
    }
    // Empty string.
    var v4 = cdm::parse_i64_from_view(std::string_view::make_no_len(""))
    if(v4 != 0) {
        var msg = string::make_no_len("expected 0 for empty, got ")
        msg.append_integer(v4 as bigint)
        env.error(msg.data())
        return
    }
    // Just minus.
    var v5 = cdm::parse_i64_from_view(std::string_view::make_no_len("-"))
    if(v5 != 0) {
        var msg = string::make_no_len("expected 0 for '-', got ")
        msg.append_integer(v5 as bigint)
        env.error(msg.data())
        return
    }
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

// ---- Test: change_url preserves progress for resume ----

@test
public func CDM_queue_change_url_preserves_progress(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("cu-prog"),
                        string_view::make_no_len("https://example.com/old.bin"),
                        string_view(), string_view(), 0, 0)
    var idx = cdm::find_item_index(&dm, &string::make_no_len("cu-prog"))
    dm.items.get_ptr(idx).downloaded_bytes = 50000
    dm.items.get_ptr(idx).total_bytes = 100000
    dm.items.get_ptr(idx).state = cdm::STATE_FAILED

    // Change URL — should preserve progress so worker resumes from disk.
    var ok = cdm::change_url(&mut dm, &string::make_no_len("cu-prog"),
                            string_view::make_no_len("https://example.com/new.bin"))
    if(!ok) { env.error("change_url should succeed"); return }

    var idx2 = cdm::find_item_index(&dm, &string::make_no_len("cu-prog"))
    var it = dm.items.get_ptr(idx2)
    if(!it.url.equals_view("https://example.com/new.bin")) { env.error("URL not updated"); return }
    if(it.state != cdm::STATE_QUEUED) { env.error("should be QUEUED"); return }
    if(it.downloaded_bytes != 50000) {
        var msg = string::make_no_len("expected 50000 downloaded after change_url, got ")
        msg.append_integer(it.downloaded_bytes as bigint)
        env.error(msg.data())
        return
    }
    if(it.total_bytes != 100000) {
        var msg = string::make_no_len("expected 100000 total after change_url, got ")
        msg.append_integer(it.total_bytes as bigint)
        env.error(msg.data())
        return
    }
    if(it.was_interrupted) { env.error("was_interrupted should be false after change_url"); return }
    if(it.retry_count != 0) { env.error("retry_count should reset to 0"); return }
}

// ---- Test: change_url then save/restore roundtrip preserves progress ----

@test
public func CDM_queue_change_url_save_roundtrip(env : &mut TestEnv) {
    var cfg_dir = setup_test_cfg()

    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("cu-rt"),
                        string_view::make_no_len("https://example.com/old2.bin"),
                        string_view(), string_view(), 0, 0)
    var idx = cdm::find_item_index(&dm, &string::make_no_len("cu-rt"))
    dm.items.get_ptr(idx).downloaded_bytes = 30000
    dm.items.get_ptr(idx).total_bytes = 80000
    dm.items.get_ptr(idx).state = cdm::STATE_FAILED

    // Change URL, save, restore.
    cdm::change_url(&mut dm, &string::make_no_len("cu-rt"),
                    string_view::make_no_len("https://example.com/refreshed.bin"))
    if(!cdm::save_queue(&mut dm)) { env.error("save_queue failed"); return }

    var dm2 = cdm::DownloadManager()
    dm2.max_concurrent = 0
    var restored = cdm::restore_queue(&mut dm2)
    if(restored != 1) {
        var msg = string::make_no_len("expected 1, got ")
        msg.append_integer(restored as bigint)
        env.error(msg.data())
        return
    }
    var idx2 = cdm::find_item_index(&dm2, &string::make_no_len("cu-rt"))
    var it = dm2.items.get_ptr(idx2)
    if(!it.url.equals_view("https://example.com/refreshed.bin")) { env.error("URL lost after roundtrip"); return }
    if(it.downloaded_bytes != 30000) {
        var msg = string::make_no_len("expected 30000, got ")
        msg.append_integer(it.downloaded_bytes as bigint)
        env.error(msg.data())
        return
    }
    if(it.total_bytes != 80000) {
        var msg = string::make_no_len("expected 80000, got ")
        msg.append_integer(it.total_bytes as bigint)
        env.error(msg.data())
        return
    }

    fs::remove_dir_all_recursive(cfg_dir.data())
}

// ---- Test: edit_item preserves category when current_cat is resolved ----
// This tests the Bridge pattern: resolve category from the item before calling
// edit_item (category=-1 means "no override").

@test
public func CDM_edit_item_preserves_category(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("edit-cat"),
                        string_view::make_no_len("https://example.com/edit.bin"),
                        string_view(), string_view(), 0, cdm::Category.Video as int)

    // Verify category was set.
    var idx = cdm::find_item_index(&dm, &string::make_no_len("edit-cat"))
    if(dm.items.get_ptr(idx).category != cdm::Category.Video as int) {
        env.error("initial category should be Video"); return
    }

    // Simulate the Bridge pattern: read current category, then call edit_item
    // with the resolved value (category >= 0 means override, < 0 means no change).
    var current_cat = 0
    dm.items_mutex.lock()
    var eidx = cdm::find_item_index(&dm, &string::make_no_len("edit-cat"))
    if(eidx < dm.items.size()) { current_cat = dm.items.get_ptr(eidx).category }
    dm.items_mutex.unlock()
    // cat_from_args = -1 (user did not send category in the edit request)
    var cat_from_args = -1
    var resolved_cat = if(cat_from_args >= 0) cat_from_args else current_cat

    var ok = cdm::edit_item(&mut dm, &string::make_no_len("edit-cat"),
                           string_view::make_no_len("/tmp/newdir"),
                           string_view(), 0, 0, 0, resolved_cat)
    if(!ok) { env.error("edit_item should succeed"); return }

    var idx2 = cdm::find_item_index(&dm, &string::make_no_len("edit-cat"))
    var it = dm.items.get_ptr(idx2)
    // Category should be preserved (not reset to 0).
    if(it.category != cdm::Category.Video as int) {
        var msg = string::make_no_len("category should be Video after edit, got ")
        msg.append_integer(it.category as bigint)
        env.error(msg.data())
        return
    }
    // Dir should be updated.
    if(!it.dir.equals_view("/tmp/newdir")) { env.error("dir should be updated"); return }
}

// ---- Test: edit_item overrides category when explicitly set ----

@test
public func CDM_edit_item_overrides_category(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("edit-ovr"),
                        string_view::make_no_len("https://example.com/edit2.bin"),
                        string_view(), string_view(), 0, cdm::Category.Video as int)

    // Override category to Music.
    var ok = cdm::edit_item(&mut dm, &string::make_no_len("edit-ovr"),
                           string_view(), string_view(), 0, 0, 0,
                           cdm::Category.Music as int)
    if(!ok) { env.error("edit_item should succeed"); return }

    var idx = cdm::find_item_index(&dm, &string::make_no_len("edit-ovr"))
    var it = dm.items.get_ptr(idx)
    if(it.category != cdm::Category.Music as int) {
        var msg = string::make_no_len("category should be Music, got ")
        msg.append_integer(it.category as bigint)
        env.error(msg.data())
        return
    }
}

// ---- Test: cancel_task cancels a queued item (no runtime) ----

@test
public func CDM_cancel_queued_item(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("cancel-q"),
                        string_view::make_no_len("https://example.com/cancel.bin"),
                        string_view(), string_view(), 0, 0)
    var idx = cdm::find_item_index(&dm, &string::make_no_len("cancel-q"))
    dm.items.get_ptr(idx).state = cdm::STATE_QUEUED

    cdm::cancel_task(&mut dm, &string::make_no_len("cancel-q"))
    var idx2 = cdm::find_item_index(&dm, &string::make_no_len("cancel-q"))
    var it = dm.items.get_ptr(idx2)
    if(it.state != cdm::STATE_CANCELLED) {
        var msg = string::make_no_len("expected CANCELLED, got ")
        msg.append_integer(it.state as bigint)
        env.error(msg.data())
        return
    }
}

// ---- Test: retry preserves category ----

@test
public func CDM_retry_preserves_category(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("retry-cat"),
                        string_view::make_no_len("https://example.com/retry.bin"),
                        string_view(), string_view(), 0, cdm::Category.Music as int)
    var idx = cdm::find_item_index(&dm, &string::make_no_len("retry-cat"))
    dm.items.get_ptr(idx).state = cdm::STATE_FAILED

    cdm::retry_task(&mut dm, &string::make_no_len("retry-cat"))
    var idx2 = cdm::find_item_index(&dm, &string::make_no_len("retry-cat"))
    var it = dm.items.get_ptr(idx2)
    if(it.category != cdm::Category.Music as int) {
        var msg = string::make_no_len("category should be Music after retry, got ")
        msg.append_integer(it.category as bigint)
        env.error(msg.data())
        return
    }
}

// ---- Test: resume preserves category ----

@test
public func CDM_resume_preserves_category(env : &mut TestEnv) {
    var dm = cdm::DownloadManager()
    dm.max_concurrent = 0
    cdm::add_task_ex_id(&mut dm, string_view::make_no_len("resume-cat"),
                        string_view::make_no_len("https://example.com/res.bin"),
                        string_view(), string_view(), 0, cdm::Category.Documents as int)
    var idx = cdm::find_item_index(&dm, &string::make_no_len("resume-cat"))
    dm.items.get_ptr(idx).state = cdm::STATE_FAILED
    dm.items.get_ptr(idx).downloaded_bytes = 1000
    dm.items.get_ptr(idx).total_bytes = 5000

    cdm::resume_task(&mut dm, &string::make_no_len("resume-cat"))
    var idx2 = cdm::find_item_index(&dm, &string::make_no_len("resume-cat"))
    var it = dm.items.get_ptr(idx2)
    if(it.category != cdm::Category.Documents as int) {
        var msg = string::make_no_len("category should be Documents after resume, got ")
        msg.append_integer(it.category as bigint)
        env.error(msg.data())
        return
    }
    // Progress should be preserved.
    if(it.downloaded_bytes != 1000) { env.error("downloaded progress lost"); return }
    if(it.total_bytes != 5000) { env.error("total progress lost"); return }
}

// ---- Test: save_yt_links creates atomic tmp files (no leftover .tmp) ----

// ---- Test: save_yt_links creates atomic tmp files (no leftover .tmp) ----

@test
public func CDM_persist_yt_links_atomic(env : &mut TestEnv) {
    var cfg_dir = setup_test_cfg()

    // All g_yt_links access needs unsafe (global pointer).
    var link_count : usize = 0
    var loaded_video_id = string()
    var loaded_url = string()
    var loaded_min_q : int = 0
    var loaded_max_q : int = 0
    var loaded_outdir = string()

    unsafe {
        if(cdm::g_yt_links == null) {
            var ptr = &raw mut cdm::g_yt_links
            *ptr = new std::vector<cdm::YtLinkRecord>()
        }
        cdm::g_yt_links.clear()

        // Add a test record.
        var rec = cdm::YtLinkRecord()
        rec.video_id = string::make_no_len("test-video-id")
        rec.audio_id = string::make_no_len("test-audio-id")
        rec.youtube_url = string::make_no_len("https://youtube.com/watch?v=test")
        rec.format = string::make_no_len("mp4")
        rec.mode = string::make_no_len("video")
        rec.audio_format = string::make_no_len("opus")
        rec.min_q = 720
        rec.max_q = 1080
        rec.output_dir = string::make_no_len("/tmp/yt_test")
        cdm::g_yt_links.push_back(rec)
    }

    // Ensure the settings directory exists (save_yt_links doesn't create it).
    var ypath = cdm::yt_links_file()
    var last_slash : usize = 0
    for(var i = 0u; i < ypath.size(); i++) {
        if(ypath.get(i) == '/') { last_slash = i }
    }
    if(last_slash > 0u) { fs::create_dir_all(ypath.substring(0u, last_slash).data()) }

    // Save — should be atomic (tmp + rename).
    cdm::save_yt_links()

    // The .tmp file should NOT exist after save.
    var tmppath = ypath.copy()
    tmppath.append_view(string_view::make_no_len(".tmp"))
    if(fs::exists(tmppath.data())) {
        env.error("yt_links.txt.tmp should not exist after atomic save")
        return
    }

    // The yt_links.txt should exist.
    if(!fs::exists(ypath.data())) {
        env.error("yt_links.txt should exist after save")
        return
    }

    // Verify content survives a load roundtrip.
    unsafe {
        cdm::g_yt_links.clear()
    }
    cdm::load_yt_links()
    unsafe {
        link_count = cdm::g_yt_links.size()
        if(link_count == 1u) {
            var loaded = cdm::g_yt_links.get_ptr(0)
            loaded_video_id = loaded.video_id.copy()
            loaded_url = loaded.youtube_url.copy()
            loaded_min_q = loaded.min_q
            loaded_max_q = loaded.max_q
            loaded_outdir = loaded.output_dir.copy()
        }
    }
    if(link_count != 1u) {
        var msg = string::make_no_len("expected 1 record after load, got ")
        msg.append_integer(link_count as bigint)
        env.error(msg.data())
        return
    }
    if(!loaded_video_id.equals_view("test-video-id")) { env.error("video_id mismatch"); return }
    if(!loaded_url.equals_view("https://youtube.com/watch?v=test")) { env.error("youtube_url mismatch"); return }
    if(loaded_min_q != 720) { env.error("min_q mismatch"); return }
    if(loaded_max_q != 1080) { env.error("max_q mismatch"); return }
    if(!loaded_outdir.equals_view("/tmp/yt_test")) { env.error("output_dir mismatch"); return }

    fs::remove_dir_all_recursive(cfg_dir.data())
}

// ---- Test: save_yt_links overwrites previous content ----

@test
public func CDM_persist_yt_links_overwrite(env : &mut TestEnv) {
    var cfg_dir = setup_test_cfg()

    var link_count2 : usize = 0
    var loaded_vid = string()

    unsafe {
        if(cdm::g_yt_links == null) {
            var ptr2 = &raw mut cdm::g_yt_links
            *ptr2 = new std::vector<cdm::YtLinkRecord>()
        }
        cdm::g_yt_links.clear()

        // Write 2 records.
        var rec1 = cdm::YtLinkRecord()
        rec1.video_id = string::make_no_len("vid-1")
        rec1.youtube_url = string::make_no_len("https://youtube.com/1")
        cdm::g_yt_links.push_back(rec1)
        var rec2 = cdm::YtLinkRecord()
        rec2.video_id = string::make_no_len("vid-2")
        rec2.youtube_url = string::make_no_len("https://youtube.com/2")
        cdm::g_yt_links.push_back(rec2)
    }
    // Ensure the settings directory exists.
    var ypath2 = cdm::yt_links_file()
    var ls2 : usize = 0
    for(var i2 = 0u; i2 < ypath2.size(); i2++) {
        if(ypath2.get(i2) == '/') { ls2 = i2 }
    }
    if(ls2 > 0u) { fs::create_dir_all(ypath2.substring(0u, ls2).data()) }
    cdm::save_yt_links()

    // Overwrite with 1 record.
    unsafe {
        cdm::g_yt_links.clear()
        var rec3 = cdm::YtLinkRecord()
        rec3.video_id = string::make_no_len("vid-3")
        rec3.youtube_url = string::make_no_len("https://youtube.com/3")
        cdm::g_yt_links.push_back(rec3)
    }
    cdm::save_yt_links()

    // Load — should have only 1 record.
    unsafe { cdm::g_yt_links.clear() }
    cdm::load_yt_links()
    unsafe {
        link_count2 = cdm::g_yt_links.size()
        if(link_count2 == 1u) {
            loaded_vid = cdm::g_yt_links.get_ptr(0).video_id.copy()
        }
    }
    if(link_count2 != 1u) {
        var msg = string::make_no_len("expected 1 record after overwrite, got ")
        msg.append_integer(link_count2 as bigint)
        env.error(msg.data())
        return
    }
    if(!loaded_vid.equals_view("vid-3")) { env.error("should be vid-3"); return }

    fs::remove_dir_all_recursive(cfg_dir.data())
}

// ---- Test: ensure_parent_dir creates nested directories ----

@test
public func CDM_engine_ensure_parent_dir(env : &mut TestEnv) {
    // Create a deeply nested path.
    var uuid_part = uuid::v4().to_string()
    var base = string::make_no_len("/tmp/cdm_ensure_dir_test_")
    base.append_string(&uuid_part)
    base.append_view(string_view::make_no_len("/a/b/c/d/file.bin"))

    // The directory doesn't exist yet.
    // ensure_parent_dir should create /a/b/c/d/.
    cdm::ensure_parent_dir(base.data())

    // Verify the parent directory was created.
    // Extract the parent: everything before the last '/'.
    var last_slash : usize = 0
    for(var i = 0u; i < base.size(); i++) {
        if(base.get(i) == '/') { last_slash = i }
    }
    var parent = base.substring(0u, last_slash)
    if(!fs::exists(parent.data())) {
        var msg = string::make_no_len("parent dir should exist: ")
        msg.append_string(&parent)
        env.error(msg.data())
        return
    }

    // The file itself should NOT exist yet (only the parent was created).
    if(fs::exists(base.data())) {
        env.error("file should not exist yet")
        return
    }

    // Clean up: remove /tmp/cdm_ensure_dir_test_<uuid>.
    var test_dir = string::make_no_len("/tmp/cdm_ensure_dir_test_")
    test_dir.append_string(&uuid_part)
    fs::remove_dir_all_recursive(test_dir.data())
}
