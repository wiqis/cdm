// ChemicalDM — tests for YouTube download features: tool status, progress
// parsing, URL detection, format metadata, playlist detection, duration
// formatting, and validation.

using std::string;
using std::string_view;

// ---- Tool status tests ----

@test
public func CDM_yt_tool_info_json(env : &mut TestEnv) {
    var info = cdm::ToolInfo(string::make_no_len("yt-dlp"))
    info.status = cdm::ToolStatus.Installed
    info.version = string::make_no_len("2024.01.01")
    info.path = string::make_no_len("/usr/bin/yt-dlp")
    var json = info.to_json()
    if(json.find("yt-dlp") == std::NPOS) { env.error("missing name"); return }
    if(json.find("installed") == std::NPOS) { env.error("missing status"); return }
    if(json.find("2024.01.01") == std::NPOS) { env.error("missing version"); return }
}

@test
public func CDM_yt_tool_info_not_installed(env : &mut TestEnv) {
    var info = cdm::ToolInfo(string::make_no_len("ffmpeg"))
    if(info.is_available()) { env.error("should not be available"); return }
    if(info.status != cdm::ToolStatus.NotInstalled) { env.error("status should be NotInstalled"); return }
}

@test
public func CDM_yt_tools_status_json(env : &mut TestEnv) {
    var status = cdm::ToolsStatus()
    var json = status.to_json()
    if(json.find("yt_dlp") == std::NPOS) { env.error("missing yt_dlp"); return }
    if(json.find("ffmpeg") == std::NPOS) { env.error("missing ffmpeg"); return }
    if(json.find("both_ready") == std::NPOS) { env.error("missing both_ready"); return }
}

// ---- URL detection tests ----

@test
public func CDM_yt_is_youtube_url(env : &mut TestEnv) {
    if(!cdm::is_youtube_url(string_view::make_no_len("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))) { env.error("youtube.com URL"); return }
    if(!cdm::is_youtube_url(string_view::make_no_len("https://youtu.be/dQw4w9WgXcQ"))) { env.error("youtu.be URL"); return }
    if(!cdm::is_youtube_url(string_view::make_no_len("HTTP://YOUTUBE.COM/watch?v=abc"))) { env.error("case insensitive"); return }
    if(cdm::is_youtube_url(string_view::make_no_len("https://example.com/video.mp4"))) { env.error("non-youtube URL"); return }
    if(cdm::is_youtube_url(string_view::make_no_len("not a url"))) { env.error("plain text"); return }
}

@test
public func CDM_yt_is_playlist_url(env : &mut TestEnv) {
    if(!cdm::is_youtube_playlist_url(string_view::make_no_len("https://youtube.com/playlist?list=PLxxxxxx"))) { env.error("playlist URL with list="); return }
    if(!cdm::is_youtube_playlist_url(string_view::make_no_len("https://youtube.com/watch?v=abc&list=PLyyyy"))) { env.error("video URL with list param"); return }
    if(!cdm::is_youtube_playlist_url(string_view::make_no_len("https://youtube.com/playlist?list=PLzzz"))) { env.error("playlist path"); return }
    if(cdm::is_youtube_playlist_url(string_view::make_no_len("https://youtube.com/watch?v=abc"))) { env.error("single video URL"); return }
    if(cdm::is_youtube_playlist_url(string_view::make_no_len("https://example.com/video.mp4"))) { env.error("non-youtube URL"); return }
}

// ---- Duration formatting tests ----

@test
public func CDM_yt_format_duration(env : &mut TestEnv) {
    var d1 = cdm::format_duration_seconds(0)
    if(!d1.empty()) { env.error("0 seconds should be empty"); return }

    var d2 = cdm::format_duration_seconds(45)
    if(!d2.equals_view("0:45")) { env.error("45s -> 0:45"); return }

    var d3 = cdm::format_duration_seconds(125)
    if(!d3.equals_view("2:05")) { env.error("125s -> 2:05"); return }

    var d4 = cdm::format_duration_seconds(3661)
    if(!d4.equals_view("1:01:01")) { env.error("3661s -> 1:01:01"); return }

    var d5 = cdm::format_duration_seconds(60)
    if(!d5.equals_view("1:00")) { env.error("60s -> 1:00"); return }

    var d6 = cdm::format_duration_seconds(3600)
    if(!d6.equals_view("1:00:00")) { env.error("3600s -> 1:00:00"); return }
}

// ---- Progress parsing tests ----

@test
public func CDM_yt_parse_progress_percentage(env : &mut TestEnv) {
    var line = string::make_no_len("[download]  45.2% of  156.72MiB at  2.34MiB/s ETA 00:27")
    var update = cdm::parse_yt_progress(string_view::make_view(&line))
    if(!update.has_progress) { env.error("should have progress"); return }
    // 45.2% parsed
    if(update.progress < 45.0 || update.progress > 46.0) {
        var ps = string()
        ps.append_double(update.progress, 1)
        env.error("progress should be ~45.2, got: ")
        env.error(ps.data())
        return
    }
}

@test
public func CDM_yt_parse_progress_speed(env : &mut TestEnv) {
    var line = string::make_no_len("[download] 12.5% of 50.00MiB at 1.50MiB/s ETA 00:30")
    var update = cdm::parse_yt_progress(string_view::make_view(&line))
    if(!update.has_progress) { env.error("should have progress"); return }
    if(update.speed.size() == 0) { env.error("should have speed"); return }
    var eta = string(update.eta.data(), update.eta.size())
    if(eta.size() == 0) { env.error("should have eta"); return }
}

@test
public func CDM_yt_parse_progress_eta(env : &mut TestEnv) {
    var line = string::make_no_len("[download]  80.0% of  200.00MiB at  3.00MiB/s ETA 00:10")
    var update = cdm::parse_yt_progress(string_view::make_view(&line))
    if(update.eta.size() == 0) { env.error("should have ETA"); return }
}

@test
public func CDM_yt_parse_progress_complete(env : &mut TestEnv) {
    var line = string::make_no_len("[download] 100% of  100.00MiB in 00:30")
    var update = cdm::parse_yt_progress(string_view::make_view(&line))
    if(!update.has_progress) { env.error("should have progress"); return }
    if(update.progress < 99.0) { env.error("progress should be ~100"); return }
}

@test
public func CDM_yt_parse_progress_merger(env : &mut TestEnv) {
    var line = string::make_no_len("[Merger] Merging formats into \"video_title.mp4\"")
    var update = cdm::parse_yt_progress(string_view::make_view(&line))
    if(!update.is_merge) { env.error("should be merge"); return }
}

@test
public func CDM_yt_parse_progress_non_progress_line(env : &mut TestEnv) {
    var line = string::make_no_len("[youtube] Extracting URL: https://youtube.com/watch?v=abc")
    var update = cdm::parse_yt_progress(string_view::make_view(&line))
    if(update.has_progress) { env.error("non-progress line should not have progress"); return }
    if(update.status.size() == 0) { env.error("status should be set"); return }
}

// ---- Format struct tests ----

@test
public func CDM_yt_format_struct(env : &mut TestEnv) {
    var fmt = cdm::YtFormat()
    fmt.format_id = string::make_no_len("248")
    fmt.ext = string::make_no_len("webm")
    fmt.height = 1080
    fmt.width = 1920
    fmt.vcodec = string::make_no_len("vp9")
    fmt.acodec = string::make_no_len("none")
    fmt.fps = 60

    if(!fmt.has_video()) { env.error("should have video"); return }
    if(fmt.has_audio()) { env.error("should not have audio"); return }
    if(!fmt.is_video_only()) { env.error("should be video only"); return }
    if(fmt.is_combined()) { env.error("should not be combined"); return }
    if(fmt.is_audio_only()) { env.error("should not be audio only"); return }

    var label = fmt.quality_label()
    if(label.find("1080p") == std::NPOS) { env.error("should contain 1080p"); return }
    if(label.find("60fps") == std::NPOS) { env.error("should contain 60fps"); return }
    if(label.find("[no audio]") == std::NPOS) { env.error("should contain [no audio]"); return }
}

@test
public func CDM_yt_format_combined(env : &mut TestEnv) {
    var fmt = cdm::YtFormat()
    fmt.format_id = string::make_no_len("18")
    fmt.ext = string::make_no_len("mp4")
    fmt.height = 360
    fmt.vcodec = string::make_no_len("avc1")
    fmt.acodec = string::make_no_len("mp4a")

    if(!fmt.is_combined()) { env.error("should be combined"); return }
    if(fmt.is_video_only()) { env.error("should not be video only"); return }
    if(fmt.is_audio_only()) { env.error("should not be audio only"); return }
}

@test
public func CDM_yt_format_audio_only(env : &mut TestEnv) {
    var fmt = cdm::YtFormat()
    fmt.format_id = string::make_no_len("140")
    fmt.ext = string::make_no_len("m4a")
    fmt.vcodec = string::make_no_len("none")
    fmt.acodec = string::make_no_len("mp4a")
    fmt.tbr = 128.0

    if(fmt.has_video()) { env.error("should not have video"); return }
    if(!fmt.has_audio()) { env.error("should should have audio"); return }
    if(!fmt.is_audio_only()) { env.error("should be audio only"); return }

    var label = fmt.quality_label()
    if(label.find("Audio") == std::NPOS) { env.error("should contain Audio"); return }
}

@test
public func CDM_yt_format_json(env : &mut TestEnv) {
    var fmt = cdm::YtFormat()
    fmt.format_id = string::make_no_len("248")
    fmt.ext = string::make_no_len("webm")
    fmt.height = 720
    fmt.vcodec = string::make_no_len("vp9")
    fmt.acodec = string::make_no_len("none")
    var json = fmt.to_json()
    if(json.find("248") == std::NPOS) { env.error("missing format_id"); return }
    if(json.find("720") == std::NPOS) { env.error("missing height"); return }
    if(json.find("is_video_only") == std::NPOS) { env.error("missing is_video_only"); return }
}

// ---- Video info tests ----

@test
public func CDM_yt_video_info_struct(env : &mut TestEnv) {
    var info = cdm::YtVideoInfo()
    info.id = string::make_no_len("dQw4w9WgXcQ")
    info.title = string::make_no_len("Never Gonna Give You Up")
    info.duration = 212

    if(info.id.size() == 0) { env.error("id should be set"); return }
    if(info.title.size() == 0) { env.error("title should be set"); return }

    var ds = info.duration_str()
    if(ds.size() == 0) { env.error("duration_str should not be empty"); return }
    // 212 seconds = 3:32
    if(!ds.equals_view("3:32")) { env.error("duration should be 3:32"); return }
}

@test
public func CDM_yt_video_info_best_combined(env : &mut TestEnv) {
    var info = cdm::YtVideoInfo()
    // Add a combined format.
    var fmt1 = cdm::YtFormat()
    fmt1.format_id = string::make_no_len("18")
    fmt1.height = 360
    fmt1.vcodec = string::make_no_len("avc1")
    fmt1.acodec = string::make_no_len("mp4a")
    info.formats.push_back(fmt1)
    // Add a video-only format.
    var fmt2 = cdm::YtFormat()
    fmt2.format_id = string::make_no_len("137")
    fmt2.height = 1080
    fmt2.vcodec = string::make_no_len("avc1")
    fmt2.acodec = string::make_no_len("none")
    info.formats.push_back(fmt2)
    // Add a better combined format.
    var fmt3 = cdm::YtFormat()
    fmt3.format_id = string::make_no_len("22")
    fmt3.height = 720
    fmt3.vcodec = string::make_no_len("avc1")
    fmt3.acodec = string::make_no_len("mp4a")
    info.formats.push_back(fmt3)

    var best = info.best_combined()
    if(best is std::Option.None) { env.error("should have best combined"); return }
    var Some(b) = best else unreachable
    // Should pick the 720p combined over 360p.
    if(b.height != 720) { env.error("best combined should be 720p"); return }
}

@test
public func CDM_yt_video_info_best_video_only(env : &mut TestEnv) {
    var info = cdm::YtVideoInfo()
    var fmt1 = cdm::YtFormat()
    fmt1.format_id = string::make_no_len("136")
    fmt1.height = 720
    fmt1.vcodec = string::make_no_len("avc1")
    fmt1.acodec = string::make_no_len("none")
    info.formats.push_back(fmt1)
    var fmt2 = cdm::YtFormat()
    fmt2.format_id = string::make_no_len("137")
    fmt2.height = 1080
    fmt2.vcodec = string::make_no_len("avc1")
    fmt2.acodec = string::make_no_len("none")
    info.formats.push_back(fmt2)

    var best = info.best_video_only()
    if(best is std::Option.None) { env.error("should have best video only"); return }
    var Some(b) = best else unreachable
    if(b.height != 1080) { env.error("best video only should be 1080p"); return }
}

@test
public func CDM_yt_video_info_best_audio_only(env : &mut TestEnv) {
    var info = cdm::YtVideoInfo()
    var fmt1 = cdm::YtFormat()
    fmt1.format_id = string::make_no_len("140")
    fmt1.tbr = 128.0
    fmt1.vcodec = string::make_no_len("none")
    fmt1.acodec = string::make_no_len("mp4a")
    info.formats.push_back(fmt1)
    var fmt2 = cdm::YtFormat()
    fmt2.format_id = string::make_no_len("251")
    fmt2.tbr = 256.0
    fmt2.vcodec = string::make_no_len("none")
    fmt2.acodec = string::make_no_len("opus")
    info.formats.push_back(fmt2)

    var best = info.best_audio_only()
    if(best is std::Option.None) { env.error("should have best audio only"); return }
    var Some(b) = best else unreachable
    if(b.tbr != 256.0) { env.error("best audio should be 256kbps"); return }
}

// ---- Validation tests ----

@test
public func CDM_validate_url(env : &mut TestEnv) {
    var v1 = cdm::validate_url(string_view::make_no_len("https://example.com/file.zip"))
    if(!v1.is_ok()) { env.error("valid https URL"); return }

    var v2 = cdm::validate_url(string_view::make_no_len("http://example.com/file.zip"))
    if(!v2.is_ok()) { env.error("valid http URL"); return }

    var v3 = cdm::validate_url(string_view::make_no_len(""))
    if(v3.is_ok()) { env.error("empty URL should fail"); return }

    var v4 = cdm::validate_url(string_view::make_no_len("ftp://example.com/file"))
    if(v4.is_ok()) { env.error("ftp URL should fail"); return }

    var v5 = cdm::validate_url(string_view::make_no_len("https://"))
    if(v5.is_ok()) { env.error("URL with no host should fail"); return }

    var v6 = cdm::validate_url(string_view::make_no_len("https://example.com"))
    if(!v6.is_ok()) { env.error("valid URL with no path"); return }
}

@test
public func CDM_validate_max_concurrent(env : &mut TestEnv) {
    var v1 = cdm::validate_max_concurrent(3)
    if(!v1.is_ok()) { env.error("3 should be valid"); return }

    var v2 = cdm::validate_max_concurrent(0)
    if(v2.is_ok()) { env.error("0 should fail"); return }

    var v3 = cdm::validate_max_concurrent(-1)
    if(v3.is_ok()) { env.error("-1 should fail"); return }

    var v4 = cdm::validate_max_concurrent(100)
    if(v4.is_ok()) { env.error("100 should fail (too high)"); return }
}

@test
public func CDM_validate_max_segments(env : &mut TestEnv) {
    var v1 = cdm::validate_max_segments(4)
    if(!v1.is_ok()) { env.error("4 should be valid"); return }

    var v2 = cdm::validate_max_segments(0)
    if(v2.is_ok()) { env.error("0 should fail"); return }

    var v3 = cdm::validate_max_segments(50)
    if(v3.is_ok()) { env.error("50 should fail"); return }
}

@test
public func CDM_validate_speed_limit(env : &mut TestEnv) {
    var v1 = cdm::validate_speed_limit(500)
    if(!v1.is_ok()) { env.error("500 should be valid"); return }

    var v2 = cdm::validate_speed_limit(0)
    if(!v2.is_ok()) { env.error("0 should be valid"); return }

    var v3 = cdm::validate_speed_limit(-1)
    if(v3.is_ok()) { env.error("-1 should fail"); return }

    var v4 = cdm::validate_speed_limit(2000000)
    if(v4.is_ok()) { env.error("excessive speed should fail"); return }
}

@test
public func CDM_validate_priority(env : &mut TestEnv) {
    var v1 = cdm::validate_priority(0)
    if(!v1.is_ok()) { env.error("0 should be valid"); return }

    var v2 = cdm::validate_priority(5)
    if(!v2.is_ok()) { env.error("5 should be valid"); return }

    var v3 = cdm::validate_priority(-1)
    if(v3.is_ok()) { env.error("-1 should fail"); return }

    var v4 = cdm::validate_priority(200)
    if(v4.is_ok()) { env.error("200 should fail"); return }
}

@test
public func CDM_validate_max_retries(env : &mut TestEnv) {
    var v1 = cdm::validate_max_retries(-1)
    if(!v1.is_ok()) { env.error("-1 (infinite) should be valid"); return }

    var v2 = cdm::validate_max_retries(0)
    if(!v2.is_ok()) { env.error("0 should be valid"); return }

    var v3 = cdm::validate_max_retries(3)
    if(!v3.is_ok()) { env.error("3 should be valid"); return }

    var v4 = cdm::validate_max_retries(-2)
    if(v4.is_ok()) { env.error("-2 should fail"); return }

    var v5 = cdm::validate_max_retries(200)
    if(v5.is_ok()) { env.error("200 should fail"); return }
}

@test
public func CDM_validate_category_name(env : &mut TestEnv) {
    var v1 = cdm::validate_category_name(string_view::make_no_len("Video"))
    if(!v1.is_ok()) { env.error("Video should be valid"); return }

    var v2 = cdm::validate_category_name(string_view::make_no_len("Music"))
    if(!v2.is_ok()) { env.error("Music should be valid"); return }

    var v3 = cdm::validate_category_name(string_view::make_no_len(""))
    if(!v3.is_ok()) { env.error("empty should be valid (Other default)"); return }

    var v4 = cdm::validate_category_name(string_view::make_no_len("Unknown"))
    if(v4.is_ok()) { env.error("Unknown category should fail"); return }
}

@test
public func CDM_validate_not_empty(env : &mut TestEnv) {
    var v1 = cdm::validate_not_empty(string_view::make_no_len("hello"), string_view::make_no_len("field"))
    if(!v1.is_ok()) { env.error("non-empty should be valid"); return }

    var v2 = cdm::validate_not_empty(string_view::make_no_len(""), string_view::make_no_len("field"))
    if(v2.is_ok()) { env.error("empty should fail"); return }
}

@test
public func CDM_validate_directory(env : &mut TestEnv) {
    var v1 = cdm::validate_directory(string_view::make_no_len("/home/user/downloads"))
    if(!v1.is_ok()) { env.error("valid path should pass"); return }

    var v2 = cdm::validate_directory(string_view::make_no_len(""))
    if(v2.is_ok()) { env.error("empty path should fail"); return }
}

// ---- Error codes tests ----

@test
public func CDM_error_code_name(env : &mut TestEnv) {
    var n1 = cdm::error_code_name(cdm::CdmErrorCode.Ok)
    if(!n1.equals_view("ok")) { env.error("Ok -> ok"); return }

    var n2 = cdm::error_code_name(cdm::CdmErrorCode.InvalidUrl)
    if(!n2.equals_view("invalid_url")) { env.error("InvalidUrl -> invalid_url"); return }

    var n3 = cdm::error_code_name(cdm::CdmErrorCode.ItemNotFound)
    if(!n3.equals_view("item_not_found")) { env.error("ItemNotFound -> item_not_found"); return }

    var n4 = cdm::error_code_name(cdm::CdmErrorCode.UnknownMethod)
    if(!n4.equals_view("unknown_method")) { env.error("UnknownMethod -> unknown_method"); return }
}

@test
public func CDM_cdm_ok_and_err(env : &mut TestEnv) {
    var ok = cdm::cdm_ok()
    if(!ok.is_ok()) { env.error("cdm_ok should be ok"); return }

    var err = cdm::cdm_err(cdm::CdmErrorCode.InvalidUrl, string::make_no_len("bad url"))
    if(err.is_ok()) { env.error("cdm_err should not be ok"); return }

    var err_msg = cdm::cdm_err_msg(string::make_no_len("something wrong"))
    if(err_msg.is_ok()) { env.error("cdm_err_msg should not be ok"); return }
    if(err_msg.message.size() == 0) { env.error("err_msg should have message"); return }
}

// ---- Download manager tests ----

@test
public func CDM_yt_download_manager_add(env : &mut TestEnv) {
    var dm = cdm::YtDownloadManager()
    var id = dm.add_download(string_view::make_no_len("https://youtube.com/watch?v=abc"), string_view())
    if(id.empty()) { env.error("add_download should return id"); return }
    var snap = dm.snapshot()
    if(snap.size() != 1u) { env.error("should have 1 download"); return }
}

@test
public func CDM_yt_download_manager_find(env : &mut TestEnv) {
    var dm = cdm::YtDownloadManager()
    var id = dm.add_download(string_view::make_no_len("https://youtube.com/watch?v=abc"), string_view())
    var found = dm.find_download(&id)
    if(found is std::Option.None) { env.error("should find download"); return }
}

@test
public func CDM_yt_download_manager_cancel(env : &mut TestEnv) {
    var dm = cdm::YtDownloadManager()
    var id = dm.add_download(string_view::make_no_len("https://youtube.com/watch?v=abc"), string_view())
    dm.cancel_download(&id)
    var found = dm.find_download(&id)
    if(found is std::Option.None) { env.error("should find download"); return }
    var Some(d) = found else unreachable
    if(d.state != cdm::YtDownloadState.Cancelled) { env.error("should be cancelled"); return }
}

@test
public func CDM_yt_download_manager_remove(env : &mut TestEnv) {
    var dm = cdm::YtDownloadManager()
    var id = dm.add_download(string_view::make_no_len("https://youtube.com/watch?v=abc"), string_view())
    dm.remove_download(&id)
    var snap = dm.snapshot()
    if(snap.size() != 0u) { env.error("should have 0 downloads"); return }
}

@test
public func CDM_yt_download_manager_clear_finished(env : &mut TestEnv) {
    var dm = cdm::YtDownloadManager()
    var id1 = dm.add_download(string_view::make_no_len("https://youtube.com/watch?v=abc"), string_view())
    var id2 = dm.add_download(string_view::make_no_len("https://youtube.com/watch?v=def"), string_view())
    var id3 = dm.add_download(string_view::make_no_len("https://youtube.com/watch?v=ghi"), string_view())
    // Set states.
    dm.update_state(&id1, cdm::YtDownloadState.Done)
    dm.update_state(&id2, cdm::YtDownloadState.Failed)
    // id3 stays queued.
    var removed = dm.clear_finished()
    if(removed != 2) { env.error("should remove 2"); return }
    var snap = dm.snapshot()
    if(snap.size() != 1u) { env.error("should have 1 remaining"); return }
}

@test
public func CDM_yt_download_struct_json(env : &mut TestEnv) {
    var dl = cdm::YtDownload(string::make_no_len("test-id"), string::make_no_len("https://youtube.com/watch?v=abc"))
    dl.title = string::make_no_len("Test Video")
    dl.state = cdm::YtDownloadState.Downloading
    dl.progress = 45.5
    var json = dl.to_json()
    if(json.find("test-id") == std::NPOS) { env.error("missing id"); return }
    if(json.find("Test Video") == std::NPOS) { env.error("missing title"); return }
    if(json.find("downloading") == std::NPOS) { env.error("missing state"); return }
}

// ---- YtDownloadState name tests ----

@test
public func CDM_yt_state_names(env : &mut TestEnv) {
    var s1 = cdm::yt_state_name(cdm::YtDownloadState.Queued)
    if(!s1.equals_view("queued")) { env.error("Queued -> queued"); return }
    var s2 = cdm::yt_state_name(cdm::YtDownloadState.Downloading)
    if(!s2.equals_view("downloading")) { env.error("Downloading -> downloading"); return }
    var s3 = cdm::yt_state_name(cdm::YtDownloadState.Done)
    if(!s3.equals_view("done")) { env.error("Done -> done"); return }
    var s4 = cdm::yt_state_name(cdm::YtDownloadState.Failed)
    if(!s4.equals_view("failed")) { env.error("Failed -> failed"); return }
    var s5 = cdm::yt_state_name(cdm::YtDownloadState.Merging)
    if(!s5.equals_view("merging")) { env.error("Merging -> merging"); return }
    var s6 = cdm::yt_state_name(cdm::YtDownloadState.Cancelled)
    if(!s6.equals_view("cancelled")) { env.error("Cancelled -> cancelled"); return }
}

// ---- Playlist entry tests ----

@test
public func CDM_yt_playlist_entry_json(env : &mut TestEnv) {
    var entry = cdm::YtPlaylistEntry()
    entry.id = string::make_no_len("abc123")
    entry.title = string::make_no_len("Video Title")
    entry.url = string::make_no_len("https://youtube.com/watch?v=abc123")
    entry.duration = 180
    entry.index = 1
    var json = entry.to_json()
    if(json.find("abc123") == std::NPOS) { env.error("missing id"); return }
    if(json.find("Video Title") == std::NPOS) { env.error("missing title"); return }
    if(json.find("3:00") == std::NPOS) { env.error("missing duration_str 3:00"); return }
}

@test
public func CDM_yt_playlist_info_json(env : &mut TestEnv) {
    var info = cdm::YtPlaylistInfo()
    info.id = string::make_no_len("PLabc")
    info.title = string::make_no_len("My Playlist")
    var entry = cdm::YtPlaylistEntry()
    entry.id = string::make_no_len("v1")
    entry.title = string::make_no_len("Video 1")
    entry.index = 1
    info.entries.push_back(entry)
    var json = info.to_json()
    if(json.find("PLabc") == std::NPOS) { env.error("missing id"); return }
    if(json.find("My Playlist") == std::NPOS) { env.error("missing title"); return }
    if(json.find("entry_count") == std::NPOS) { env.error("missing entry_count"); return }
}

// ---- Validation error message tests ----

@test
public func CDM_validation_error_messages(env : &mut TestEnv) {
    var v1 = cdm::validate_url(string_view::make_no_len(""))
    if(v1.message.find("empty") == std::NPOS) { env.error("empty URL error should mention empty"); return }

    var v2 = cdm::validate_url(string_view::make_no_len("ftp://test.com"))
    if(v2.message.find("http") == std::NPOS) { env.error("ftp URL error should mention http"); return }

    var v3 = cdm::validate_max_concurrent(0)
    if(v3.message.find("at least 1") == std::NPOS) { env.error("zero concurrent error"); return }

    var v4 = cdm::validate_max_concurrent(100)
    if(v4.message.find("at most 64") == std::NPOS) { env.error("high concurrent error"); return }
}

using std::vector;

// ---- Process execution tests (exercises the crash path in make_exec_cfg) ----

@test
public func CDM_yt_make_exec_cfg_runs(env : &mut TestEnv) {
    var args = vector<string>()
    args.push_back(string::make_no_len("echo"))
    args.push_back(string::make_no_len("hello_from_cdm"))
    var cfg = cdm::make_exec_cfg(args)
    var res = process::execute(cfg)
    if(res is std::Result.Err) { env.error("execute should not error"); return }
    var Ok(pr) = res else unreachable
    if(pr.status.code != 0) { env.error("echo exit code should be 0"); return }
}

@test
public func CDM_yt_check_tools_status_runs(env : &mut TestEnv) {
    var json = cdm::check_tools_status_json()
    if(json.find("yt_dlp") == std::NPOS) { env.error("status JSON missing yt_dlp"); return }
    if(json.find("ffmpeg") == std::NPOS) { env.error("status JSON missing ffmpeg"); return }
}

@test
public func CDM_yt_ytdlp_is_available_no_crash(env : &mut TestEnv) {
    var result = cdm::ytdlp_is_available()
}

@test
public func CDM_yt_ffmpeg_is_available_no_crash(env : &mut TestEnv) {
    var result = cdm::ffmpeg_is_available()
}
