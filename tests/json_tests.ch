// ChemicalDM — tests for JSON serialization helpers.

using std::string;
using std::string_view;

@test
public func CDM_app_json_escape(env : &mut TestEnv) {
    // Plain string.
    var e1 = cdm::json_escape(string_view::make_no_len("hello"))
    if(!e1.equals_view("hello")) { env.error("plain"); return }

    // Quotes escaped.
    var e2 = cdm::json_escape(string_view::make_no_len("a\"b"))
    if(!e2.equals_view("a\\\"b")) { env.error("quotes"); return }

    // Backslash escaped.
    var e3 = cdm::json_escape(string_view::make_no_len("a\\b"))
    if(!e3.equals_view("a\\\\b")) { env.error("backslash"); return }

    // Newline escaped.
    var e4 = cdm::json_escape(string_view::make_no_len("a\nb"))
    if(!e4.equals_view("a\\nb")) { env.error("newline"); return }

    // Tab escaped.
    var e5 = cdm::json_escape(string_view::make_no_len("a\tb"))
    if(!e5.equals_view("a\\tb")) { env.error("tab"); return }

    // Control char → \u0001.
    var e6 = cdm::json_escape(string_view::make_no_len("\x01"))
    if(!e6.equals_view("\\u0001")) { env.error("control char"); return }

    // Empty string.
    var e7 = cdm::json_escape(string_view::make_no_len(""))
    if(!e7.empty()) { env.error("empty"); return }
}

@test
public func CDM_json_string(env : &mut TestEnv) {
    var s1 = cdm::json_string(string_view::make_no_len("hello"))
    if(!s1.equals_view("\"hello\"")) { env.error("basic"); return }

    var s2 = cdm::json_string(string_view::make_no_len("a\"b"))
    if(!s2.equals_view("\"a\\\"b\"")) { env.error("escaped quotes"); return }

    var s3 = cdm::json_string(string_view::make_no_len(""))
    if(!s3.equals_view("\"\"")) { env.error("empty"); return }
}

@test
public func CDM_json_i64(env : &mut TestEnv) {
    var j1 = cdm::json_i64(0)
    if(!j1.equals_view("0")) { env.error("zero"); return }

    var j2 = cdm::json_i64(-1)
    if(!j2.equals_view("-1")) { env.error("negative"); return }

    var j3 = cdm::json_i64(123456789)
    if(!j3.equals_view("123456789")) { env.error("large"); return }
}

@test
public func CDM_json_int(env : &mut TestEnv) {
    var j1 = cdm::json_int(42)
    if(!j1.equals_view("42")) { env.error("42"); return }

    var j2 = cdm::json_int(-5)
    if(!j2.equals_view("-5")) { env.error("-5"); return }
}

@test
public func CDM_item_to_json(env : &mut TestEnv) {
    var item = cdm::DownloadItem(string::make_no_len("id-1"),
                                 string::make_no_len("https://example.com/file.zip"),
                                 string::make_no_len("/tmp"),
                                 string::make_no_len("file.zip"))
    item.total_bytes = 1024
    item.downloaded_bytes = 512
    item.state = cdm::STATE_DOWNLOADING
    item.priority = 1
    item.category = cdm::Category.Compressed as int

    var json = cdm::item_to_json(&item)
    // Check key fields are present.
    if(json.find("id-1") == std::NPOS) { env.error("missing id"); return }
    if(json.find("file.zip") == std::NPOS) { env.error("missing filename"); return }
    if(json.find("Downloading") == std::NPOS) { env.error("missing state"); return }
    if(json.find("Compressed") == std::NPOS) { env.error("missing category"); return }
    if(json.find("was_interrupted") == std::NPOS) { env.error("missing was_interrupted"); return }
    if(json.find("retry_count") == std::NPOS) { env.error("missing retry_count"); return }
    // Percent = 512*100/1024 = 50.0
    if(json.find("50.0") == std::NPOS) { env.error("missing percent"); return }
}

@test
public func CDM_item_to_json_done(env : &mut TestEnv) {
    var item = cdm::DownloadItem(string::make_no_len("id-2"),
                                 string::make_no_len("https://example.com/doc.pdf"),
                                 string::make_no_len("/tmp"),
                                 string::make_no_len("doc.pdf"))
    item.total_bytes = 2048
    item.downloaded_bytes = 2048
    item.state = cdm::STATE_DONE
    item.was_interrupted = false
    item.retry_count = 0

    var json = cdm::item_to_json(&item)
    if(json.find("Done") == std::NPOS) { env.error("missing Done state"); return }
    if(json.find("100.0") == std::NPOS) { env.error("missing 100%"); return }
    if(json.find("false") == std::NPOS) { env.error("missing false for was_interrupted"); return }
}
