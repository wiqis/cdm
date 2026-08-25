// ChemicalDM — tests for settings persistence and expand_home logic.

using std::string;
using std::string_view;

@test
public func CDM_expand_home(env : &mut TestEnv) {
    // ~ is expanded to $HOME.
    var e1 = cdm::expand_home(string_view::make_no_len("~/Downloads"))
    if(e1.size() <= 1) { env.error("expand_home should expand ~"); return }
    if(e1.get(0) == '~') { env.error("~ should not remain"); return }

    // Non-tilde path is returned as-is.
    var e2 = cdm::expand_home(string_view::make_no_len("/tmp/out"))
    if(!e2.equals_view("/tmp/out")) { env.error("non-tilde unchanged"); return }

    // Empty path.
    var e3 = cdm::expand_home(string_view::make_no_len(""))
    if(!e3.empty()) { env.error("empty -> empty"); return }

    // Just ~.
    var e4 = cdm::expand_home(string_view::make_no_len("~"))
    if(e4.size() <= 1) { env.error("just ~ should expand"); return }
    if(e4.get(0) == '~') { env.error("~ should not remain"); return }
}

@test
public func CDM_parse_bool(env : &mut TestEnv) {
    var t = string::make_no_len("true")
    if(!cdm::parse_bool(&t)) { env.error("true"); return }

    var f = string::make_no_len("false")
    if(cdm::parse_bool(&f)) { env.error("false"); return }

    var one = string::make_no_len("1")
    if(!cdm::parse_bool(&one)) { env.error("1"); return }

    var zero = string::make_no_len("0")
    if(cdm::parse_bool(&zero)) { env.error("0"); return }

    var yes = string::make_no_len("yes")
    if(!cdm::parse_bool(&yes)) { env.error("yes"); return }

    var no = string::make_no_len("no")
    if(cdm::parse_bool(&no)) { env.error("no"); return }

    var garbage = string::make_no_len("abc")
    if(cdm::parse_bool(&garbage)) { env.error("garbage"); return }
}

@test
public func CDM_parse_int_opt(env : &mut TestEnv) {
    var p1 = string::make_no_len("123")
    var v1 = cdm::parse_int_opt(p1.data())
    if(v1 != 123) { env.error("123"); return }

    var p2 = string::make_no_len("0")
    var v2 = cdm::parse_int_opt(p2.data())
    if(v2 != 0) { env.error("0"); return }

    var p3 = string::make_no_len("-1")
    var v3 = cdm::parse_int_opt(p3.data())
    if(v3 != -1) { env.error("-1"); return }

    var p4 = string::make_no_len("abc")
    var v4 = cdm::parse_int_opt(p4.data())
    if(v4 != -1) { env.error("non-number"); return }

    var p5 = string::make_no_len("12.5")
    var v5 = cdm::parse_int_opt(p5.data())
    if(v5 != -1) { env.error("decimal"); return }

    var p6 = string::make_no_len("")
    var v6 = cdm::parse_int_opt(p6.data())
    if(v6 != -1) { env.error("empty"); return }
}

@test
public func CDM_retry_policy_default(env : &mut TestEnv) {
    var rp = cdm::RetryPolicy()
    if(rp.max_retries != cdm::DEFAULT_MAX_RETRIES) { env.error("default max_retries"); return }
    if(rp.delay_ms != cdm::DEFAULT_RETRY_DELAY_MS) { env.error("default delay_ms"); return }
    // should_retry with default policy (3 retries): attempt 0..3 should be true.
    if(!rp.should_retry(0)) { env.error("attempt 0"); return }
    if(!rp.should_retry(3)) { env.error("attempt 3"); return }
    if(rp.should_retry(4)) { env.error("attempt 4 should not retry"); return }
}

@test
public func CDM_retry_policy_infinite(env : &mut TestEnv) {
    var rp = cdm::RetryPolicy()
    rp.max_retries = -1
    // Infinite retries: always returns true.
    if(!rp.should_retry(0)) { env.error("inf attempt 0"); return }
    if(!rp.should_retry(100)) { env.error("inf attempt 100"); return }
    if(!rp.should_retry(999999)) { env.error("inf attempt 999999"); return }
}

@test
public func CDM_retry_policy_zero(env : &mut TestEnv) {
    var rp = cdm::RetryPolicy()
    rp.max_retries = 0
    // 0 retries: only attempt 0 should pass.
    if(!rp.should_retry(0)) { env.error("zero attempt 0"); return }
    if(rp.should_retry(1)) { env.error("zero attempt 1"); return }
}

@test
public func CDM_settings_persistence(env : &mut TestEnv) {
    // Create a settings, serialize, parse back.
    var s = cdm::CdmSettings()
    s.download_dir = string::make_no_len("/tmp/test_cdm")
    s.max_concurrent = 5
    s.max_segments = 8
    s.speed_limit_kbps = 500
    s.enable_resume = false
    s.allow_segments = false
    s.use_categories = true
    s.duplicate_action = 1
    s.auto_resume_failed = true
    s.max_retries = 7
    s.retry_delay_ms = 2000

    var serialized = cdm::save_settings_to_string(&s)
    // Verify key fields are present.
    if(serialized.find("downloadFolder") == std::NPOS) { env.error("missing downloadFolder"); return }
    if(serialized.find("parallelDownloads") == std::NPOS) { env.error("missing parallelDownloads"); return }
    if(serialized.find("maxRetries") == std::NPOS) { env.error("missing maxRetries"); return }
    if(serialized.find("retryDelayMs") == std::NPOS) { env.error("missing retryDelayMs"); return }

    // Parse back.
    var parsed = cdm::parse_settings_string(string_view::make_view(&serialized))
    if(parsed.max_concurrent != 5) { env.error("parsed max_concurrent"); return }
    if(parsed.max_segments != 8) { env.error("parsed max_segments"); return }
    if(parsed.speed_limit_kbps != 500) { env.error("parsed speed_limit_kbps"); return }
    if(parsed.enable_resume) { env.error("parsed enable_resume should be false"); return }
    if(parsed.allow_segments) { env.error("parsed allow_segments should be false"); return }
    if(!parsed.use_categories) { env.error("parsed use_categories should be true"); return }
    if(parsed.duplicate_action != 1) { env.error("parsed duplicate_action"); return }
    if(!parsed.auto_resume_failed) { env.error("parsed auto_resume_failed"); return }
    if(parsed.max_retries != 7) { env.error("parsed max_retries"); return }
    if(parsed.retry_delay_ms != 2000) { env.error("parsed retry_delay_ms"); return }
}

@test
public func CDM_settings_disk_roundtrip(env : &mut TestEnv) {
    // Isolate the config directory so the test doesn't touch the user's home.
    var cfg_dir = string::make_no_len("/tmp/cdm_cfg_test_")
    cfg_dir.append_string(&uuid::v4().to_string())
    var set_res = environment::set(string_view::make_no_len("CDM_CONFIG_DIR"), string_view::make_view(&cfg_dir))
    if(set_res is std::Result.Err) { env.error("cannot set CDM_CONFIG_DIR"); return }

    var s = cdm::CdmSettings()
    s.download_dir = string::make_no_len("/home/me/Downloads")
    s.max_concurrent = 6
    s.max_segments = 9
    s.speed_limit_kbps = 750
    s.enable_resume = false
    s.allow_segments = false
    s.use_categories = true
    s.duplicate_action = 2
    s.auto_resume_failed = true
    s.max_retries = 11
    s.retry_delay_ms = 1500

    if(!cdm::save_settings(&s)) { env.error("save_settings failed"); return }

    // A fresh struct should be populated from disk.
    var loaded = cdm::CdmSettings()
    if(!cdm::load_settings(&raw mut loaded)) { env.error("load_settings failed"); return }
    if(loaded.max_concurrent != 6) { env.error("disk max_concurrent"); return }
    if(loaded.max_segments != 9) { env.error("disk max_segments"); return }
    if(loaded.speed_limit_kbps != 750) { env.error("disk speed_limit_kbps"); return }
    if(loaded.enable_resume) { env.error("disk enable_resume"); return }
    if(loaded.allow_segments) { env.error("disk allow_segments"); return }
    if(!loaded.use_categories) { env.error("disk use_categories"); return }
    if(loaded.duplicate_action != 2) { env.error("disk duplicate_action"); return }
    if(!loaded.auto_resume_failed) { env.error("disk auto_resume_failed"); return }
    if(loaded.max_retries != 11) { env.error("disk max_retries"); return }
    if(loaded.retry_delay_ms != 1500) { env.error("disk retry_delay_ms"); return }

    // Clean up the test config directory.
    fs::remove_dir_all_recursive(cfg_dir.data())
}
