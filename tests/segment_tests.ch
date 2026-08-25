// ChemicalDM — tests for segment computation, URL parsing, category helpers,
// and sanitize/suggest filename logic. Pure-logic functions, no I/O.

using std::string;
using std::string_view;

@test
public func CDM_segment_count(env : &mut TestEnv) {
    // Too small for any segments.
    var c1 = cdm::compute_segment_count(100, 4, 256 * 1024)
    if(c1 != 0) { env.error("expected 0 for tiny file"); return }

    // Unknown size.
    var c2 = cdm::compute_segment_count(-1, 4, 256 * 1024)
    if(c2 != 0) { env.error("expected 0 for unknown size"); return }

    // max_segments=1 → no segmentation.
    var c3 = cdm::compute_segment_count(100000000, 1, 256 * 1024)
    if(c3 != 0) { env.error("expected 0 for max_segments=1"); return }

    // Large file, 4 segments, min_size=256KB -> should get 4.
    var c4 = cdm::compute_segment_count(100000000, 4, 256 * 1024)
    if(c4 != 4) { env.error("expected 4 segments"); return }

    // File just under 4*min_size → falls back to fewer.
    // 500KB / 4 = 125KB < 256KB → n = 500K/256K = 1 (too few) → 0
    var c5 = cdm::compute_segment_count(500 * 1024, 4, 256 * 1024)
    if(c5 != 0) { env.error("expected 0 for undersized file"); return }

    // File = 2*min_size → exactly 2 segments.
    var c6 = cdm::compute_segment_count(512 * 1024, 4, 256 * 1024)
    if(c6 != 2) { env.error("expected 2 segments for 2x min"); return }
}

@test
public func CDM_build_segments(env : &mut TestEnv) {
    var segs = cdm::build_segments(string_view::make_no_len("test.bin"), 4, 1000000, string_view::make_no_len("/tmp"))
    if(segs.size() != 4u) { env.error("expected 4 segments"); return }
    // First segment starts at 0.
    var s0 = segs.get_ptr(0)
    if(s0.start != 0) { env.error("seg0 start != 0"); return }
    // Last segment ends at total-1.
    var s3 = segs.get_ptr(3)
    if(s3.end != 999999) { env.error("seg3 end != 999999"); return }
    // Segments are contiguous: s[i+1].start == s[i].end + 1.
    for(var i = 0u; i + 1 < segs.size(); i++) {
        var cur = segs.get_ptr(i)
        var nxt = segs.get_ptr(i + 1)
        if(nxt.start != cur.end + 1) { env.error("segments not contiguous"); return }
    }
    // Count=0 returns empty.
    var segs2 = cdm::build_segments(string_view::make_no_len("x"), 0, 1000, string_view::make_no_len("."))
    if(segs2.size() != 0u) { env.error("count=0 should be empty"); return }
}

@test
public func CDM_app_sanitize_filename(env : &mut TestEnv) {
    var s1 = cdm::sanitize_filename(string_view::make_no_len("hello world.txt"))
    if(!s1.equals_view("hello world.txt")) { env.error("simple name"); return }

    // Path separators are stripped to basename.
    var s2 = cdm::sanitize_filename(string_view::make_no_len("/home/user/file.tar.gz"))
    if(!s2.equals_view("file.tar.gz")) { env.error("path stripping"); return }

    // Unsafe chars removed.
    var s3 = cdm::sanitize_filename(string_view::make_no_len("a*b?c"))
    if(!s3.equals_view("abc")) { env.error("unsafe chars"); return }

    // Empty → "download".
    var s4 = cdm::sanitize_filename(string_view::make_no_len(""))
    if(!s4.equals_view("download")) { env.error("empty -> download"); return }

    // All unsafe → "download".
    var s5 = cdm::sanitize_filename(string_view::make_no_len(":///"))
    if(!s5.equals_view("download")) { env.error("all unsafe -> download"); return }
}

@test
public func CDM_app_suggested_filename(env : &mut TestEnv) {
    var s1 = cdm::suggested_filename(string_view::make_no_len("https://example.com/files/doc.pdf"))
    if(!s1.equals_view("doc.pdf")) { env.error("simple URL filename"); return }

    var s2 = cdm::suggested_filename(string_view::make_no_len("https://cdn.test.io/path/to/video.mp4?token=abc"))
    if(!s2.equals_view("video.mp4")) { env.error("URL with query"); return }

    // No path → "download".
    var s3 = cdm::suggested_filename(string_view::make_no_len("https://example.com"))
    if(!s3.equals_view("download")) { env.error("no path -> download"); return }
}

@test
public func CDM_extension_of(env : &mut TestEnv) {
    var e1 = cdm::extension_of(string_view::make_no_len("file.tar.gz"))
    if(!e1.equals_view("gz")) { env.error("double ext"); return }

    var e2 = cdm::extension_of(string_view::make_no_len("noext"))
    if(!e2.empty()) { env.error("no ext should be empty"); return }

    var e3 = cdm::extension_of(string_view::make_no_len("UPPER.PDF"))
    if(!e3.equals_view("pdf")) { env.error("case normalization"); return }
}

@test
public func CDM_category_for_extension(env : &mut TestEnv) {
    if(cdm::category_for_extension(string_view::make_no_len("pdf")) != cdm::Category.Documents) { env.error("pdf should be Documents"); return }
    if(cdm::category_for_extension(string_view::make_no_len("mp4")) != cdm::Category.Video) { env.error("mp4 should be Video"); return }
    if(cdm::category_for_extension(string_view::make_no_len("mp3")) != cdm::Category.Music) { env.error("mp3 should be Music"); return }
    if(cdm::category_for_extension(string_view::make_no_len("zip")) != cdm::Category.Compressed) { env.error("zip should be Compressed"); return }
    if(cdm::category_for_extension(string_view::make_no_len("exe")) != cdm::Category.Programs) { env.error("exe should be Programs"); return }
    if(cdm::category_for_extension(string_view::make_no_len("xyz")) != cdm::Category.Other) { env.error("unknown should be Other"); return }
    // Case-insensitive.
    if(cdm::category_for_extension(string_view::make_no_len("PDF")) != cdm::Category.Documents) { env.error("PDF upper"); return }
}

// categorize_path maps a filename to root + category subfolder (moved from
// cdmlib unit tests — this is app-side routing logic).
@test
public func CDM_categorize_path(env : &mut TestEnv) {
    var got = cdm::categorize_path(string_view::make_no_len("/dl"), string_view::make_no_len("movie.mp4"))
    var want = string::make_no_len("/dl/Video")
    if(!got.equals(&want)) { env.error("categorize path mp4"); return }

    var got2 = cdm::categorize_path(string_view::make_no_len("/dl"), string_view::make_no_len("notes.txt"))
    var want2 = string::make_no_len("/dl/Documents")
    if(!got2.equals(&want2)) { env.error("categorize path txt"); return }

    // Unknown extension stays in the root (Other has no subfolder).
    var got3 = cdm::categorize_path(string_view::make_no_len("/dl"), string_view::make_no_len("blob.xyz123"))
    var want3 = string::make_no_len("/dl")
    if(!got3.equals(&want3)) { env.error("categorize path other"); return }
}

@test
public func CDM_category_from_name(env : &mut TestEnv) {
    if(cdm::category_from_name(string_view::make_no_len("Video")) != cdm::Category.Video) { env.error("Video"); return }
    if(cdm::category_from_name(string_view::make_no_len("video")) != cdm::Category.Video) { env.error("video lower"); return }
    if(cdm::category_from_name(string_view::make_no_len("DOCUMENTS")) != cdm::Category.Documents) { env.error("DOCUMENTS upper"); return }
    if(cdm::category_from_name(string_view::make_no_len("Programs")) != cdm::Category.Programs) { env.error("Programs"); return }
    if(cdm::category_from_name(string_view::make_no_len("Music")) != cdm::Category.Music) { env.error("Music"); return }
    if(cdm::category_from_name(string_view::make_no_len("Compressed")) != cdm::Category.Compressed) { env.error("Compressed"); return }
    // Empty / unknown => Other.
    if(cdm::category_from_name(string_view::make_no_len("")) != cdm::Category.Other) { env.error("empty -> Other"); return }
    if(cdm::category_from_name(string_view::make_no_len("Nonsense")) != cdm::Category.Other) { env.error("unknown -> Other"); return }
}

@test
public func CDM_category_dir(env : &mut TestEnv) {
    if(!cdm::category_dir(cdm::Category.Video).equals_view("Video")) { env.error("Video dir"); return }
    if(!cdm::category_dir(cdm::Category.Other).equals_view("")) { env.error("Other dir empty"); return }
}

@test
public func CDM_parse_content_length(env : &mut TestEnv) {
    var cl1 = string::make_no_len("12345")
    if(cdm::parse_content_length(&cl1) != 12345) { env.error("simple number"); return }

    var cl2 = string::make_no_len("")
    if(cdm::parse_content_length(&cl2) != -1) { env.error("empty -> -1"); return }

    var cl3 = string::make_no_len("0")
    if(cdm::parse_content_length(&cl3) != 0) { env.error("zero"); return }

    var cl4 = string::make_no_len("abc")
    if(cdm::parse_content_length(&cl4) != -1) { env.error("non-number"); return }

    // Negative numbers return -1 (invalid).
    var cl5 = string::make_no_len("-1")
    if(cdm::parse_content_length(&cl5) != -1) { env.error("negative -> -1"); return }
}

@test
public func CDM_parse_content_range_total(env : &mut TestEnv) {
    // Standard Content-Range header.
    var cr1 = string::make_no_len("bytes 0-999/5000")
    if(cdm::parse_content_range_total(&cr1) != 5000) { env.error("standard"); return }

    // Unknown total.
    var cr2 = string::make_no_len("bytes 0-999/*")
    if(cdm::parse_content_range_total(&cr2) != -1) { env.error("unknown total"); return }

    // No slash.
    var cr3 = string::make_no_len("bytes 0-999")
    if(cdm::parse_content_range_total(&cr3) != -1) { env.error("no slash"); return }

    // Just a number after slash.
    var cr4 = string::make_no_len("/99999")
    if(cdm::parse_content_range_total(&cr4) != 99999) { env.error("just total"); return }

    // Empty.
    var cr5 = string::make_no_len("")
    if(cdm::parse_content_range_total(&cr5) != -1) { env.error("empty"); return }
}
