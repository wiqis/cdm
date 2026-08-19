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

public func main() : int {
    fflush(null)

    // Build the download manager. Lives for the whole run; the bridge handler
    // captures a pointer to it.
    var dm = cdm::DownloadManager()
    var dmp = &raw mut dm

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
    return 0
}