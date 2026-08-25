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

// NOTE: Category classification (category_for_extension, categorize_path)
// lives in the APP (src/core/Categories.ch), not in cdmlib. Those tests are
// in the app suite: tests/segment_tests.ch and tests/format_tests.ch.

// NOTE: Formatters (format_bytes/format_state/...), json_escape and the
// settings save/load round-trip live in the APP (src/core/) — they are
// covered by the app suites: tests/format_tests.ch, tests/json_tests.ch and
// tests/settings_tests.ch. cdmlib only owns parsing/engine/queue behavior.
