using std::string;

@never_destructed
var g_server : server::HttpServer

public func main() : int {
    var port = server::find_free_port()
    g_server.port = port
    g_server.listen_sock = net::listen_addr(null, port as uint)
    g_server.running = false
    g_server.dm = download::dm_init()

    if(g_server.listen_sock == 0 as net::Socket) {
        return 1
    }

    var thread = std::concurrent::spawn(server_thread_func, &raw mut g_server as *mut void)

    var wv = webview::WebView.make()
    var r = webview::webview_create(&raw mut wv)
    if(r is std::Result.Err) {
        g_server.running = false
        net::close_socket(g_server.listen_sock)
        return 2
    }

    webview::webview_set_title(&raw mut wv, "ChemicalDM")
    webview::webview_set_size(&raw mut wv, 1200, 800)

    var url = string("http://127.0.0.1:")
    var port_str = server::int_to_str(port)
    url.append_string(&port_str)

    webview::webview_load_url(&raw mut wv, url.data())
    webview::webview_show(&raw mut wv)
    webview::webview_run(&raw mut wv)

    g_server.running = false
    net::close_socket(g_server.listen_sock)
    webview::webview_destroy(&raw mut wv)
    thread.join()
    return 0
}

func server_thread_func(arg : *mut void) : *void {
    var srv = arg as *mut server::HttpServer
    server::start_server(srv)
    return null as *void
}
