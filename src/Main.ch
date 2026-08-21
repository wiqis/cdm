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
        dm.apply_settings(&settings)
    }

    // Restore previously queued downloads so a restart resumes them.
    var restored = cdm::restore_queue(&mut dm)
    if(restored > 0) {
        printf("ChemicalDM: restored %d pending downloads\n", restored)
    }

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
    cdm::save_queue(&dm)
    return 0
}