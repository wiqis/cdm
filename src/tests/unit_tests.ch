// ChemicalDM — unit tests for the pure parsing/formatting helpers.
//
// These are synchronous, no-network tests: they exercise the string, URL,
// content-length/range, content-disposition, JSON and formatter logic used by
// the engine. They run under the `@test` harness (`--test` on the CLI, or via
// the build.lab test runner).

using std::string;
using std::string_view;
using std::Option;
using std::Result;

// Ensure two strings are equal; report through the test env.
func cdm_expect_eq(env : &mut TestEnv, label : *char, got : &string, want : &string) {
    if(!got.equals(want)) {
        env.error("cdm unit: ")
        env.error(label)
        env.error(" got=")
        env.error(got.data())
        env.error(" want=")
        env.error(want.data())
    }
}

func cdm_expect_true(env : &mut TestEnv, label : *char, ok : bool) {
    if(!ok) {
        env.error("cdm unit: ")
        env.error(label)
        env.error(" failed")
    }
}

// ─── Content-Length parsing ───────────────────────────────────────────

@test
public func CDM_cl_parse_basic(env : &mut TestEnv) {
    var a = string::make_no_len("1024")
    if(cdm::parse_content_length(&a) != 1024) { env.error("parse_content_length(1024)"); return }
    var b = string::make_no_len("0")
    if(cdm::parse_content_length(&b) != 0) { env.error("parse_content_length(0)"); return }
    var empty = string()
    if(cdm::parse_content_length(&empty) != -1) { env.error("parse_content_length(empty)"); return }
    var junk = string::make_no_len("abc")
    if(cdm::parse_content_length(&junk) != -1) { env.error("parse_content_length(junk)"); return }
    var neg = string::make_no_len("-5")
    if(cdm::parse_content_length(&neg) != -1) { env.error("parse_content_length(-5)"); return }
}

@test
public func CDM_cl_parse_embedded(env : &mut TestEnv) {
    var s = string::make_no_len("   12345")
    if(cdm::parse_content_length(&s) != 12345) { env.error("parse_content_length embedded 12345"); return }
    var big = string::make_no_len("999999999999")
    if(cdm::parse_content_length(&big) != 999999999999) { env.error("parse_content_length big"); return }
}

// ─── Content-Range total parsing ─────────────────────────────────────

@test
public func CDM_cr_parse(env : &mut TestEnv) {
    var a = string::make_no_len("bytes 0-99/1000")
    if(cdm::parse_content_range_total(&a) != 1000) { env.error("cr total 1000"); return }
    var wild = string::make_no_len("bytes 0-9/*")
    if(cdm::parse_content_range_total(&wild) != -1) { env.error("cr wild should be -1"); return }
    var no_slash = string::make_no_len("bytes 0-99")
    if(cdm::parse_content_range_total(&no_slash) != -1) { env.error("cr no slash"); return }
    var multi = string::make_no_len("bytes 0-499/5000")
    if(cdm::parse_content_range_total(&multi) != 5000) { env.error("cr total 5000"); return }
}

// ─── Suggested filename from URL ──────────────────────────────────────

@test
public func CDM_suggested_filename(env : &mut TestEnv) {
    var want = string::make_no_len("file.zip")
    var got = cdm::suggested_filename(string_view::make_no_len("https://example.com/dir/file.zip?x=1"))
    cdm_expect_eq(env, "suggested simple", &got, &want)

    var want2 = string::make_no_len("download")
    var got2 = cdm::suggested_filename(string_view::make_no_len("https://example.com/"))
    cdm_expect_eq(env, "suggested empty", &got2, &want2)

    var want3 = string::make_no_len("report")
    var got3 = cdm::suggested_filename(string_view::make_no_len("https://example.com/a/b/c/report"))
    cdm_expect_eq(env, "suggested noext", &got3, &want3)
}

// ─── sanitize_filename ────────────────────────────────────────────────

@test
public func CDM_sanitize_filename(env : &mut TestEnv) {
    // sanitize keeps only the last path segment and strips unsafe characters.
    var want = string::make_no_len("b")
    var got = cdm::sanitize_filename(string_view::make_no_len("a/b\\?*:|\"<>"))
    cdm_expect_eq(env, "sanitize unsafe", &got, &want)

    var want_dir = string::make_no_len("final.txt")
    var got_dir = cdm::sanitize_filename(string_view::make_no_len("dir1/dir2/final.txt"))
    cdm_expect_eq(env, "sanitize path", &got_dir, &want_dir)
}

// ─── Content-Disposition filename ────────────────────────────────────

@test
public func CDM_cd_parse(env : &mut TestEnv) {
    var a = string::make_no_len("attachment; filename=\"data.bin\"")
    var oa = cdm::parse_content_disposition_name(&a)
    if(oa is Option.None) { env.error("cd(a) none"); return }
    var Some(x) = oa else unreachable
    var want = string::make_no_len("data.bin")
    cdm_expect_eq(env, "cd quoted", &x, &want)

    var b = string::make_no_len("inline; filename=report.pdf")
    var ob = cdm::parse_content_disposition_name(&b)
    if(ob is Option.None) { env.error("cd(b) none"); return }
    var Some(y) = ob else unreachable
    var want2 = string::make_no_len("report.pdf")
    cdm_expect_eq(env, "cd unquoted", &y, &want2)
}

// ─── Category classification ──────────────────────────────────────────

@test
public func CDM_categories(env : &mut TestEnv) {
    var video = cdm::category_for_extension(string_view::make_no_len("mp4"))
    cdm_expect_true(env, "mp4 is video", video == cdm::Category.Video)

    var music = cdm::category_for_extension(string_view::make_no_len("MP3"))
    cdm_expect_true(env, "mp3 is music", music == cdm::Category.Music)

    var doc = cdm::category_for_extension(string_view::make_no_len("pdf"))
    cdm_expect_true(env, "pdf is doc", doc == cdm::Category.Documents)

    var zip = cdm::category_for_extension(string_view::make_no_len("zip"))
    cdm_expect_true(env, "zip is compressed", zip == cdm::Category.Compressed)

    var other = cdm::category_for_extension(string_view::make_no_len("xyz123"))
    cdm_expect_true(env, "unknown is other", other == cdm::Category.Other)

    var catpath = cdm::categorize_path(string_view::make_no_len("/dl"), string_view::make_no_len("movie.mp4"))
    var want = string::make_no_len("/dl/Video")
    cdm_expect_eq(env, "categorize path", &catpath, &want)
}

// ─── Formatters ───────────────────────────────────────────────────────

@test
public func CDM_formatters(env : &mut TestEnv) {
    var kb = cdm::format_bytes(1024)
    var want_kb = string::make_no_len("1.0 KB")
    cdm_expect_eq(env, "format 1KB", &kb, &want_kb)

    var mb = cdm::format_bytes(1536 * 1024)
    var want_mb = string::make_no_len("1.5 MB")
    cdm_expect_eq(env, "format 1.5MB", &mb, &want_mb)

    var st = cdm::format_state(cdm::STATE_DONE)
    var want_st = string::make_no_len("Done")
    cdm_expect_eq(env, "state done", &st, &want_st)
}

// ─── JSON escaping ────────────────────────────────────────────────────

@test
public func CDM_json_escape(env : &mut TestEnv) {
    var want = string::make_no_len("a\\\"b\\\\c")
    var got = cdm::json_escape(string_view::make_no_len("a\"b\\c"))
    cdm_expect_eq(env, "json escape", &got, &want)
}

// ─── CLI parsing ──────────────────────────────────────────────────────

@test
public func CDM_cli_parse(env : &mut TestEnv) {
    var opts = cdm::CliOptions()
    var arg0 = string::make_no_len("cdm")
    var arg1 = string::make_no_len("https://a.com/f.bin")
    var arg2 = string::make_no_len("--dir")
    var arg3 = string::make_no_len("/tmp/out")

    var argv : [4]*char
    argv[0] = arg0.data()
    argv[1] = arg1.data()
    argv[2] = arg2.data()
    argv[3] = arg3.data()

    var err = cdm::parse_cli(4, &raw mut argv[0], &mut opts)
    if(err != null) {
        env.error("cli parse returned error")
        return
    }
    if(opts.urls.size() != 1u) { env.error("cli urls size"); return }
    var got_url = opts.urls.get_ref(0).copy()
    cdm_expect_eq(env, "cli url", &got_url, &arg1)
    cdm_expect_eq(env, "cli dir", &opts.download_dir, &arg3)
}

// ─── URL parsing / filename edge cases ───────────────────────────────

@test
public func CDM_url_query_stripped(env : &mut TestEnv) {
    // The suggested filename must come from the last path segment only,
    // ignoring the query string and any fragment.
    var want = string::make_no_len("file.zip")
    var got = cdm::suggested_filename(string_view::make_no_len("https://cdn.example.com/dl/file.zip?token=abc&sig=xyz#frag"))
    cdm_expect_eq(env, "query stripped", &got, &want)
}

@test
public func CDM_url_no_path(env : &mut TestEnv) {
    var got = cdm::suggested_filename(string_view::make_no_len("https://example.com"))
    var want = string::make_no_len("download")
    cdm_expect_eq(env, "no path", &got, &want)
}

// ─── JSON escaping edge cases ────────────────────────────────────────

@test
public func CDM_json_escape_controls(env : &mut TestEnv) {
    // Control characters below 0x20 must be escaped as \u00XX.
    var input = string::make_no_len("a")
    input.append(1 as char)   // SOH
    input.append('b')
    var out = cdm::json_escape(string_view::make_view(&input))
    var want = string::make_no_len("a\\u0001b")
    cdm_expect_eq(env, "control escaped", &out, &want)

    var n = string::make_no_len("line1\nline2\ttab")
    var out2 = cdm::json_escape(string_view::make_view(&n))
    var want2 = string::make_no_len("line1\\nline2\\ttab")
    cdm_expect_eq(env, "newline/tab escaped", &out2, &want2)
}

// ─── fs::create_dir_all with absolute nested paths ─────────────────────
// Regression: normalize_path used to drop the leading '/' for absolute
// paths, so create_dir_all("/tmp/x") created a *relative* "x" under the
// process CWD instead of /tmp/x.
@test
public func CDM_fs_create_dir_all_absolute(env : &mut TestEnv) {
    var base = string::make_no_len("/tmp/cdm-mkdir-test")
    fs::remove_dir_all_recursive(base.data())

    var nested = base.copy()
    nested.append_string(&string::make_no_len("/a/b/c"))
    var r = fs::create_dir_all(nested.data())
    if(r is Result.Err) {
        env.error("fs::create_dir_all returned error")
        return
    }
    if(!fs::exists(nested.data())) {
        env.error("fs::create_dir_all did not create the absolute nested path")
        return
    }
    // Verify it is writable.
    var probe = nested.copy()
    probe.append_string(&string::make_no_len("/probe.txt"))
    var f = fopen(probe.data(), "w")
    if(f == null) {
        env.error("cannot write into created dir")
        return
    }
    fclose(f)
    fs::remove_dir_all_recursive(base.data())
}

// ─── Settings save/load round-trip ───────────────────────────────────
// save_settings/load_settings write to $CDM_CONFIG_DIR/config.txt (or
// $HOME/.chemicaldm). These tests isolate the config dir via the
// CDM_CONFIG_DIR env override so the user's real config is never touched.
@test
public func CDM_settings_roundtrip(env : &mut TestEnv) {
    var test_cfg = string::make_no_len("/tmp/cdm-settings-test")
    fs::remove_dir_all_recursive(test_cfg.data())
    fs::create_dir_all(test_cfg.data())

    // Isolate the config dir for the duration of this test.
    var env_set = environment::set(string_view::make_no_len("CDM_CONFIG_DIR"), string_view::make_view(&test_cfg))

    var s = cdm::CdmSettings()
    s.download_dir = string::make_no_len("/tmp/dl")
    s.max_concurrent = 5
    s.max_segments = 8
    s.speed_limit_kbps = 512
    s.enable_resume = false
    s.allow_segments = true
    s.proxy_host = string::make_no_len("proxy.local")
    s.proxy_port = 8080
    if(!cdm::save_settings(&s)) {
        env.error("save_settings returned false")
        fs::remove_dir_all_recursive(test_cfg.data())
        return
    }

    var loaded = cdm::CdmSettings()
    if(!cdm::load_settings(&raw mut loaded)) {
        env.error("load_settings returned false")
        fs::remove_dir_all_recursive(test_cfg.data())
        return
    }

    var d_want = string::make_no_len("/tmp/dl")
    var p_want = string::make_no_len("proxy.local")
    cdm_expect_eq(env, "settings dir", &loaded.download_dir, &d_want)
    cdm_expect_eq(env, "settings proxy", &loaded.proxy_host, &p_want)
    if(loaded.max_concurrent != 5) { env.error("settings concurrent"); return }
    if(loaded.max_segments != 8) { env.error("settings segments"); return }
    if(loaded.speed_limit_kbps != 512) { env.error("settings speed"); return }
    if(loaded.enable_resume != false) { env.error("settings resume"); return }
    if(loaded.proxy_port != 8080) { env.error("settings proxy port"); return }

    environment::unset(string_view::make_no_len("CDM_CONFIG_DIR"))
    fs::remove_dir_all_recursive(test_cfg.data())
}
