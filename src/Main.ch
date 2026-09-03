// ChemicalDM entry point.
//
// Phase-5: standalone desktop app. Renders the HtmlPage UI (universal
// component) and opens it in a WebKitGTK webview. The UI talks to the native
// download engine through webview::webview_bind — a synchronous JS<>native
// bridge — so there is no local HTTP server, no ports, and nothing extra to
// keep running.

using std::string;
using std::string_view;
using std::Result;
using std::vector;

// Render the full UI document (SSR output + components theme + universal JS).
func build_ui_html() : string {
    var page = HtmlPage()
    page.defaultPrepare()
    page.defaultUniversalSetup()
    page.injectDefaultComponentsTheme()
    page.appendViewportMeta()
    page.appendTitle(string_view::make_no_len(cdm::CDM_NAME))
    CdmTheme(&mut page)
    #html {
        <CdmApp />
    }
    return page.toString(string_view::make_no_len(""), string_view::make_no_len("dark"), string_view::make_no_len("chx-default"))
}

public func main(argc : int, argv : **char) : int {
    fflush(null)

    // Test mode: when launched with --test/--test-id/--comm-id the process is a
    // child of the test runner. Dispatch to the shared test_runner before any
    // other CLI handling so `./scripts/test.sh` can drive the suite.
    var is_test = false
    for(var i = 1; i < argc; i++) {
        var a = argv[i]
        if(a == null) { continue }
        var h = fnv1_hash(a)
        if(h == comptime_fnv1_hash("--test") || h == comptime_fnv1_hash("--test-id") || h == comptime_fnv1_hash("--comm-id") || h == comptime_fnv1_hash("--test-ids") || h == comptime_fnv1_hash("--test-names")) {
            is_test = true
            break
        }
    }
    if(is_test) {
        fflush(null)
        return test_runner(argc, argv)
    }

    // TEMP DEBUG REPRO: faithfully drive a real single/playlist YT download and
    // then return (destroying dm) while background YT threads may still be live,
    // to reproduce the use-after-free crash at shutdown.
    if(argc >= 2) {
        var a0 = string(argv[1])
        if(a0.equals_view(string_view::make_no_len("--yt-repro")) || a0.equals_view(string_view::make_no_len("--yt-repro-pl")) || a0.equals_view(string_view::make_no_len("--proc-repro")) || a0.equals_view(string_view::make_no_len("--mt-repro")) || a0.equals_view(string_view::make_no_len("--di-repro")) || a0.equals_view(string_view::make_no_len("--sc-repro"))) {
            return run_yt_repro(argc, argv)
        }
    }

    // Parse command-line arguments. Anything other than plain URLs opts into
    // headless mode; "cdm" with no arguments opens the GUI.
    var opts = cdm::CliOptions()
    var parse_err = cdm::parse_cli(argc, argv, &mut opts)
    if(parse_err != null) {
        printf("cdm: %s\n", parse_err)
        cdm::print_help()
        return 1
    }

    if(opts.show_help) {
        cdm::print_help()
        return 0
    }
    if(opts.show_version) {
        printf("ChemicalDM %s\n", cdm::CDM_VERSION)
        return 0
    }

    var should_run_gui = opts.gui_forced || (opts.urls.size() == 0u && opts.batch_file.size() == 0u)
    if(should_run_gui) {
        return run_gui()
    }

    return cdm::run_headless(&opts)
}

// TEMP DEBUG REPRO (see main() dispatch above).
func mt_worker_entry(arg : *void) : *void {
    for(var k = 0; k < 5; k++) {
        var cfg = process::ProcessConfig.default()
        cfg.args = vector<string>()
        cfg.args.push_back(string::make_no_len("yt-dlp"))
        cfg.args.push_back(string::make_no_len("--version"))
        var r = process::execute(cfg)
        if(r is Result.Err) { fprintf(stderr, "[MT] worker err\n") } else { var Ok(pr2) = r else unreachable; fprintf(stderr, "[MT] worker out=%d\n", pr2.output.stdout_data.size()) }
    }
    return null
}

func sc_worker_entry(arg : *void) : *void {
    var dmptr = arg as *mut cdm::DownloadManager
    for(var k = 0; k < 60; k++) {
        cdm::add_task(&mut *dmptr, string_view::make_no_len("https://example.com/file.zip"))
        var s = vector<cdm::DownloadItem>(); cdm::snapshot_into(&mut *dmptr, &mut s)
        fprintf(stderr, "[SC] bg items=%d\n", s.size())
        var cfg = process::ProcessConfig.default()
        cfg.args = vector<string>()
        cfg.args.push_back(string::make_no_len("sh"))
        cfg.args.push_back(string::make_no_len("-c"))
        cfg.args.push_back(string::make_no_len("printf 'https://a.com/1\\nhttps://a.com/2\\nhttps://a.com/3'"))
        var r = process::execute(cfg)
        if(r is Result.Err) { fprintf(stderr, "[SC] bg exec err\n") } else {
            var Ok(pr2) = r else unreachable
            var out_s = string(pr2.output.stdout_data.data() as *char, pr2.output.stdout_data.size())
            var vs = vector<string>()
            vs.push_back(out_s.copy())
            vs.push_back(out_s.copy())
            fprintf(stderr, "[SC] bg exec out=%d vs=%d\n", pr2.output.stdout_data.size(), vs.size())
        }
        std::concurrent.sleep_ms(10u)
    }
    return null
}

func run_yt_repro(argc : int, argv : **char) : int {
    cdm::set_repro_disable_merge(true)
    var is_pl = string(argv[1]).equals_view(string_view::make_no_len("--yt-repro-pl"))

    if(string(argv[1]).equals_view(string_view::make_no_len("--proc-repro"))) {
        var cfg = process::ProcessConfig.default()
        cfg.args = vector<string>()
        cfg.args.push_back(string::make_no_len("yt-dlp"))
        cfg.args.push_back(string::make_no_len("--version"))
        var res = process::execute(cfg)
        if(res is Result.Err) {
            fprintf(stderr, "[PROC] failed\n")
        } else {
            var Ok(pr) = res else unreachable
            fprintf(stderr, "[PROC] out size=%d\n", pr.output.stdout_data.size())
        }
        fprintf(stderr, "[PROC] returning\n")
        return 0
    }

    if(string(argv[1]).equals_view(string_view::make_no_len("--mt-repro"))) {
        var t1 = std::concurrent::spawn(mt_worker_entry, null)
        var t2 = std::concurrent::spawn(mt_worker_entry, null)
        for(var i = 0; i < 100000; i++) {
            var s = string::make_no_len("hello world this is a test string number ")
            var n2 = string(); n2.append_integer(i as bigint)
            s.append_string(&n2)
        }
        t1.join(); t2.join()
        fprintf(stderr, "[MT] done\n")
        return 0
    }

    if(string(argv[1]).equals_view(string_view::make_no_len("--di-repro"))) {
        var url = string(argv[2])
        var dir : string
        if(argc > 3 && argv[3] != null) { dir = string(argv[3]) } else { dir = string("/tmp/cdm_repro") }
        var dm = cdm::DownloadManager()
        dm.download_dir = dir.copy()
        var dl =         cdm::async_dl_for_test(string_view::make_view(&url), string_view::make_view(&dir), &raw mut dm)
        cdm::set_repro_disable_merge(true)
        fprintf(stderr, "[DI] calling do_item_download (single-threaded, merge disabled)\n")
        cdm::do_item_download(dl)
        fprintf(stderr, "[DI] do_item_download returned; snapshotting\n")
        var snap = vector<cdm::DownloadItem>(); cdm::snapshot_into(&mut dm, &mut snap)
        fprintf(stderr, "[DI] items=%d\n", snap.size())
        fprintf(stderr, "[DI] returning\n")
        return 0
    }
    if(argc >= 2 && string(argv[1]).equals_view(string_view::make_no_len("--sc-repro"))) {
        var dm = cdm::DownloadManager()
        var h = std::concurrent::spawn(sc_worker_entry, &raw mut dm as *void)
        for(var k = 0; k < 60; k++) {
            var s = vector<cdm::DownloadItem>(); cdm::snapshot_into(&mut dm, &mut s)
            fprintf(stderr, "[SC] main items=%d\n", s.size())
            std::concurrent.sleep_ms(10u)
        }
        h.join()
        fprintf(stderr, "[SC] done\n")
        return 0
    }
    var url = string(argv[2])
    var dir : string
    if(argc > 3 && argv[3] != null) { dir = string(argv[3]) } else { dir = string("/tmp/cdm_repro") }
    fs::create_dir_all(dir.data())

    var dm = cdm::DownloadManager()
    dm.download_dir = dir.copy()

    var probe = false
    if(argc > 3 && argv[3] != null && string(argv[3]).equals_view(string_view::make_no_len("__probe__"))) { probe = true }

    if(probe) {
        cdm::create_container_item(&mut dm, cdm::ITEM_TYPE_YT_SINGLE, string_view::make_no_len("https://yt/"), string_view::make_no_len("/tmp/x"), string_view::make_no_len("cont"))
        return 0
    }

    if(is_pl) {
        cdm::start_async_playlist_download(string_view::make_view(&url), string_view::make_no_len("best"),
            string_view::make_no_len("video_and_audio"), string_view(), string_view::make_view(&dir), 0, 0, 3, &raw mut dm)
    } else {
        cdm::start_async_download(string_view::make_view(&url), string_view::make_no_len("best"),
            string_view::make_no_len("video_and_audio"), string_view(), 0, 0, string_view::make_view(&dir), &raw mut dm)
    }

    var elapsed = 0
    while(elapsed < 1800) {
        var p : string
        if(is_pl) { p = cdm::poll_async_playlist_download() } else { p = cdm::poll_async_download() }
        fprintf(stderr, "[REPRO] %s\n", p.data())
        if(argc > 4 && argv[4] != null && string(argv[4]).equals_view(string_view::make_no_len("noshot"))) {
            fprintf(stderr, "[REPRO] noshot break\n")
            return 0
        }
        var snap = vector<cdm::DownloadItem>(); cdm::snapshot_into(&mut dm, &mut snap)
        fprintf(stderr, "[REPRO] items=%d\n", snap.size())
        if(is_pl) { if(cdm::async_playlist_done()) { break } } else { if(cdm::async_download_done()) { break } }
        std::concurrent.sleep_ms(2000u)
        elapsed = elapsed + 2
    }
    fprintf(stderr, "[REPRO] loop done, returning (dm will be destroyed while YT threads may still be live)\n")
    return 0
}

// Open the desktop GUI (webview + bridge).
func run_gui() : int {
    // Build the download manager. Lives for the whole run; the bridge handler
    // captures a pointer to it.
    var dm = cdm::DownloadManager()
    var dmp = &raw mut dm

    // Apply persisted settings (trace the download dir, concurrency, speed,
    // categories, duplicate policy) so a restart keeps the user's choices.
    var settings = cdm::CdmSettings()
    if(cdm::load_settings(&raw mut settings)) {
        cdm::apply_settings_to_dm(&mut dm, &settings)
    }

    // Ensure the root download directory exists before any task is added.
    fs::create_dir_all(dm.download_dir.data())

    // Set up periodic progress persistence for crash recovery.
    dm.progress_file_path = cdm::progress_file()

    // Restore previously queued downloads so a restart resumes them.
    var restored = cdm::restore_queue(&mut dm)
    if(restored > 0) {
        printf("ChemicalDM: restored %d pending downloads\n", restored)
    }

    // Overlay the latest progress from progress.txt (crash recovery).
    var progress_path = cdm::progress_file()
    var progress_restored = cdm::restore_progress(&mut dm, string_view::make_view(&progress_path))
    if(progress_restored > 0) {
        printf("ChemicalDM: restored progress for %d items\n", progress_restored)
    }

    // Now that all items and progress are restored, start the scheduler once
    // to kick off any QUEUED items. Items that were PAUSED or FAILED stay
    // queued until the user manually resumes them.
    cdm::start_pending(&mut dm)

    // Refresh any stored YouTube media URLs that may have expired while the app
    // was closed, so half-finished playlist/single downloads resume cleanly.
    cdm::refresh_stale_yt_links(&raw mut dm)

    // Render the UI before opening the window so the page is ready instantly.
    var ui_html = build_ui_html()

    // Open the app window with the webview.
    var wv_result = webview::create(cdm::CDM_NAME as *char, 1080, 720)
    if(wv_result is Result.Err) {
        printf("ChemicalDM: failed to create webview\n")
        fflush(null)
        return 1
    }
    var Ok(wv) = wv_result else unreachable

    // Wire the JS bridge: window.webview_bridge.call(method, args) dispatches
    // to cdm::bridge_call and returns the JSON result synchronously.
    webview::webview_bind(&raw mut wv, (|dmp|(method, args) => {
        return cdm::bridge_call(dmp, method, args)
    }))

    webview::webview_load_html(&raw mut wv, ui_html.data() as *char)
    webview::webview_show(&raw mut wv)
    webview::webview_run(&raw mut wv)
    webview::webview_destroy(&raw mut wv)

    cdm::shutdown(&mut dm)
    cdm::save_queue(&mut dm)
    return 0
}