// ChemicalDM — command-line interface.
//
// The app can run headless from the terminal: `cdm <url> [url...]` downloads
// the given URLs and prints progress to stdout. Without any arguments (or with
// `--gui`) it opens the desktop GUI. Options mirror the settings the GUI can
// change, so scripts and the UI share the same engine.

public namespace cdm {

using std::string;
using std::string_view;
using std::vector;
using std::Result;
using std::Option;

    public struct CliOptions {
        var urls : vector<string>
        var download_dir : string        // empty => keep manager default
        var output_name : string         // empty => auto-detect from URL
        var segments : int               // 0 => keep configured default
        var concurrent : int             // 0 => keep configured default
        var speed_limit_kbps : i64       // 0 => unlimited
        var priority : int               // 0 = high/drop default; higher = lower
        var use_categories : bool        // route into category folders
        var no_categories : bool          // --no-categories override
        var category : string            // forced category name (e.g. "Video")
        var quiet : bool
        var show_help : bool
        var show_version : bool
        var batch_file : string          // empty => none
        var gui_forced : bool            // --gui was passed
        var start_gui : bool             // no urls and no batch => GUI
        var user_agent : string           // --user-agent
        var cookie_file : string          // --cookies
        var no_ssl_verify : bool          // --no-ssl-verify
        var connect_timeout : int         // --connect-timeout
        var max_download_size : i64       // --max-size
        var min_disk_space_mb : int       // --min-disk
        var post_download_cmd : string    // --post-cmd
        var yt_quality : string           // --yt-quality
        var yt_format : string            // --yt-format
        var yt_audio_only : bool          // --yt-audio-only
        var yt_max_playlist : int         // --yt-max-playlist
        var referer : string              // --referer
        var auth : string                 // --auth
        var force_ipv4 : bool             // --ipv4
        var force_ipv6 : bool             // --ipv6
        var filename_template : string    // --template
        var checksum : string             // --checksum

        @constructor func constructor() {
            return CliOptions {
                urls = vector<string>(),
                download_dir = string(),
                output_name = string(),
                segments = 0,
                concurrent = 0,
                speed_limit_kbps = 0,
                priority = 0,
                use_categories = false,
                no_categories = false,
                category = string(),
                quiet = false,
                show_help = false,
                show_version = false,
                batch_file = string(),
                gui_forced = false,
                start_gui = false,
                user_agent = string(),
                cookie_file = string(),
                no_ssl_verify = false,
                connect_timeout = 0,
                max_download_size = 0,
                min_disk_space_mb = 0,
                post_download_cmd = string(),
                yt_quality = string(),
                yt_format = string(),
                yt_audio_only = false,
                yt_max_playlist = 0,
                force_ipv4 = false,
                force_ipv6 = false
            }
        }
    }

    // Parse a non-negative integer from a C string. Returns -1 on failure.
    func cli_parse_int(s : *char) : int {
        var p = s
        var val = 0
        var started = false
        while(*p != 0) {
            if(*p >= '0' && *p <= '9') {
                val = val * 10 + (*p as int - '0' as int)
                started = true
            } else {
                return -1
            }
            p = p + 1
        }
        if(!started) { return -1 }
        return val
    }

    // Parse the command line into CliOptions. Returns an error string on
    // failure (null when parsing succeeded).
    public func parse_cli(argc : int, argv : **char, out : &mut CliOptions) : *char {
        var i = 1
        while(i < argc) {
            var arg = argv[i]
            if(arg == null) { i = i + 1; continue }
            var h = fnv1_hash(arg)

            if(h == comptime_fnv1_hash("--help") || h == comptime_fnv1_hash("-h")) {
                out.show_help = true
            } else if(h == comptime_fnv1_hash("--version") || h == comptime_fnv1_hash("-v")) {
                out.show_version = true
            } else if(h == comptime_fnv1_hash("--gui") || h == comptime_fnv1_hash("-g")) {
                out.gui_forced = true
            } else if(h == comptime_fnv1_hash("--quiet") || h == comptime_fnv1_hash("-q")) {
                out.quiet = true
            } else if(h == comptime_fnv1_hash("--dir") || h == comptime_fnv1_hash("-d")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--dir requires a directory argument" }
                out.download_dir = string::make_no_len(argv[i])
            } else if(h == comptime_fnv1_hash("--output") || h == comptime_fnv1_hash("-o")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--output requires a filename argument" }
                out.output_name = string::make_no_len(argv[i])
            } else if(h == comptime_fnv1_hash("--segments") || h == comptime_fnv1_hash("-p")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--segments requires a number" }
                var n = cli_parse_int(argv[i])
                if(n <= 0) { return "invalid segment count" }
                out.segments = n
            } else if(h == comptime_fnv1_hash("--concurrent") || h == comptime_fnv1_hash("-j")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--concurrent requires a number" }
                var n = cli_parse_int(argv[i])
                if(n <= 0) { return "invalid concurrent count" }
                out.concurrent = n
            } else if(h == comptime_fnv1_hash("--speed-limit") || h == comptime_fnv1_hash("--limit")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--speed-limit requires a number in KB/s" }
                var n = cli_parse_int(argv[i])
                if(n < 0) { return "invalid speed limit" }
                out.speed_limit_kbps = n as i64
            } else if(h == comptime_fnv1_hash("--priority") || h == comptime_fnv1_hash("--prio")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--priority requires a number (0 = highest)" }
                var n = cli_parse_int(argv[i])
                if(n < 0) { return "invalid priority" }
                out.priority = n
            } else if(h == comptime_fnv1_hash("--categories")) {
                out.use_categories = true
            } else if(h == comptime_fnv1_hash("--no-categories")) {
                out.no_categories = true
            } else if(h == comptime_fnv1_hash("--category")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--category requires a name (Documents/Programs/Video/Music/Compressed)" }
                out.category = string::make_no_len(argv[i])
            } else if(h == comptime_fnv1_hash("--no-category")) {
                out.category = string()
            } else if(h == comptime_fnv1_hash("--file") || h == comptime_fnv1_hash("-f")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--file requires a path argument" }
                out.batch_file = string::make_no_len(argv[i])
            } else if(h == comptime_fnv1_hash("--user-agent") || h == comptime_fnv1_hash("--ua")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--user-agent requires a string" }
                out.user_agent = string::make_no_len(argv[i])
            } else if(h == comptime_fnv1_hash("--cookies")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--cookies requires a file path" }
                out.cookie_file = string::make_no_len(argv[i])
            } else if(h == comptime_fnv1_hash("--no-ssl-verify")) {
                out.no_ssl_verify = true
            } else if(h == comptime_fnv1_hash("--connect-timeout") || h == comptime_fnv1_hash("--cto")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--connect-timeout requires seconds" }
                var n = cli_parse_int(argv[i])
                if(n <= 0) { return "invalid connect timeout" }
                out.connect_timeout = n
            } else if(h == comptime_fnv1_hash("--max-size")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--max-size requires bytes" }
                var n = cli_parse_int(argv[i])
                if(n < 0) { return "invalid max size" }
                out.max_download_size = n as i64
            } else if(h == comptime_fnv1_hash("--min-disk")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--min-disk requires MB" }
                var n = cli_parse_int(argv[i])
                if(n < 0) { return "invalid min disk space" }
                out.min_disk_space_mb = n
            } else if(h == comptime_fnv1_hash("--post-cmd")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--post-cmd requires a shell command" }
                out.post_download_cmd = string::make_no_len(argv[i])
            } else if(h == comptime_fnv1_hash("--yt-quality")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--yt-quality requires a value (best/worst/720/1080)" }
                out.yt_quality = string::make_no_len(argv[i])
            } else if(h == comptime_fnv1_hash("--yt-format")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--yt-format requires a value (video+audio/bestvideo/bestaudio)" }
                out.yt_format = string::make_no_len(argv[i])
            } else if(h == comptime_fnv1_hash("--yt-audio-only")) {
                out.yt_audio_only = true
            } else if(h == comptime_fnv1_hash("--yt-max-playlist")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--yt-max-playlist requires a number" }
                var n = cli_parse_int(argv[i])
                if(n < 0) { return "invalid playlist limit" }
                out.yt_max_playlist = n
            } else if(h == comptime_fnv1_hash("--referer") || h == comptime_fnv1_hash("--ref")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--referer requires a URL" }
                out.referer = string::make_no_len(argv[i])
            } else if(h == comptime_fnv1_hash("--auth")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--auth requires a header value (e.g. Bearer token)" }
                out.auth = string::make_no_len(argv[i])
            } else if(h == comptime_fnv1_hash("--ipv4")) {
                out.force_ipv4 = true
            } else if(h == comptime_fnv1_hash("--ipv6")) {
                out.force_ipv6 = true
            } else if(h == comptime_fnv1_hash("--template") || h == comptime_fnv1_hash("--name")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--template requires a pattern (e.g. {title}.{ext})" }
                out.filename_template = string::make_no_len(argv[i])
            } else if(h == comptime_fnv1_hash("--checksum")) {
                i = i + 1
                if(i >= argc || argv[i] == null) { return "--checksum requires algo:hex (e.g. md5:abc123)" }
                out.checksum = string::make_no_len(argv[i])
            } else if(arg[0] == '-') {
                return "unknown option"
            } else {
                // plain argument => a URL
                out.urls.push_back(string::make_no_len(arg))
            }
            i = i + 1
        }
        return null
    }

    // Read a batch file: one URL per line, blank lines and # comments skipped.
    func read_batch_urls(path : string_view, out : &mut vector<string>) : bool {
        var f = fopen(path.data(), "rb")
        if(f == null) { return false }
        var chunk : [4096u]u8
        var content = string()
        while(true) {
            var n = fread(&raw mut chunk[0], 1, 4096u, f)
            if(n == 0u) { break }
            content.append_with_len(&raw mut chunk[0] as *char, n)
        }
        fclose(f)

        var line = string()
        var line_started = false
        for(var i = 0u; i < content.size(); i++) {
            var c = content.get(i)
            if(c == '\n' || c == '\r') {
                if(line_started) {
                    if(line.empty() || line.get(0) != '#') {
                        out.push_back(line.copy())
                    }
                    line = string()
                    line_started = false
                }
            } else {
                line.append(c)
                line_started = true
            }
        }
        if(line_started && (line.empty() || line.get(0) != '#')) {
            out.push_back(line.copy())
        }
        return true
    }

    // Print a one-line progress summary for every item.
    func print_progress(snap : &vector<DownloadItem>, quiet : bool) {
        var buf = string()
        for(var i = 0u; i < snap.size(); i++) {
            var it = snap.get_ptr(i)
            var pct : double = 0.0
            if(it.total_bytes > 0) { pct = (it.downloaded_bytes as double) * 100.0 / (it.total_bytes as double) }
            var line = string()
            line.append_string(&it.id)
            line.append(' ')
            line.append_string(&format_state(it.state))
            line.append(' ')
            line.append_string(&format_bytes(it.downloaded_bytes))
            line.append_string(&string::make_no_len("/"))
            if(it.total_bytes > 0) { line.append_string(&format_bytes(it.total_bytes)) } else { line.append('#') }
            line.append(' ')
            if(it.state == STATE_DOWNLOADING) {
                line.append_string(&format_speed(it.speed_bytes_per_sec))
            }
            if(it.error.size() > 0) {
                line.append(' ')
                line.append_string(&it.error)
            }
            if(buf.size() > 0) { buf.append('\n') }
            buf.append_string(&line)
        }
        if(!quiet) {
            printf("%s\n", buf.data())
            fflush(null)
        }
    }

    func is_terminal(state : int) : bool {
        return state == STATE_DONE || state == STATE_FAILED || state == STATE_CANCELLED
    }

    // Resolve the destination directory + category tag for a CLI download,
    // honoring --category (forced) then --categories (auto by extension).
    // Returns an empty dir string when no routing applies (library default).
    func cli_route(opts : &CliOptions, dm : &DownloadManager, fname : string_view, cat_tag : &mut int) : string {
        *cat_tag = 0
        if(opts.category.size() > 0) {
            var c = category_from_name(string_view::make_view(&opts.category))
            *cat_tag = c as int
            var sub = category_dir(c)
            if(sub.size() > 0) {
                var out = dm.download_dir.copy()
                out.append('/')
                out.append_string(&sub)
                return out
            }
            return dm.download_dir.copy()
        }
        if(opts.use_categories) {
            return categorize_path(string_view::make_view(&dm.download_dir), fname)
        }
        return string()
    }

    // Headless runner: add the URLs, schedule them, and block until every task
    // reaches a terminal state. Returns process exit code (0 = all succeeded).
    public func run_headless(opts : &CliOptions) : int {
        var dm = DownloadManager()

        // Apply persisted settings first, then let explicit CLI flags override.
        var settings = CdmSettings()
        if(load_settings(&raw mut settings)) {
            apply_settings_to_dm(&mut dm, &settings)
        }

        if(opts.download_dir.size() > 0) {
            dm.download_dir = opts.download_dir.copy()
        }
        if(opts.concurrent > 0) {
            dm.max_concurrent = opts.concurrent
        }
        if(opts.segments > 0) {
            dm.max_segments = opts.segments
        }
        if(opts.speed_limit_kbps > 0) {
            dm.set_speed_limit_kbps(opts.speed_limit_kbps)
        }
        if(opts.user_agent.size() > 0) {
            dm.user_agent = opts.user_agent.copy()
        }
        if(opts.cookie_file.size() > 0) {
            dm.cookie_file = opts.cookie_file.copy()
        }
        if(opts.no_ssl_verify) {
            dm.verify_ssl = false
        }
        if(opts.connect_timeout > 0) {
            dm.connect_timeout = opts.connect_timeout
        }
        if(opts.max_download_size > 0) {
            dm.max_download_size = opts.max_download_size
        }
        if(opts.min_disk_space_mb > 0) {
            dm.min_disk_space_mb = opts.min_disk_space_mb
        }
        if(opts.post_download_cmd.size() > 0) {
            dm.post_download_cmd = opts.post_download_cmd.copy()
        }
        if(opts.yt_quality.size() > 0) {
            dm.yt_quality = opts.yt_quality.copy()
        }
        if(opts.yt_format.size() > 0) {
            dm.yt_format = opts.yt_format.copy()
        }
        if(opts.yt_audio_only) {
            dm.yt_audio_only = true
        }
        if(opts.yt_max_playlist > 0) {
            dm.yt_max_playlist_items = opts.yt_max_playlist
        }
        // HTTP options are now passed through TaskRuntime, not globals.

        // Make sure the destination directory exists.
        var mk = fs::create_dir_all(dm.download_dir.data())
        // create_dir_all's Result is not actionable here; ignore failures.

        var batch = vector<string>()
        if(opts.batch_file.size() > 0) {
            var bv = string_view::make_view(&opts.batch_file)
            if(!read_batch_urls(bv, &mut batch)) {
                printf("cdm: cannot read batch file %s\n", opts.batch_file.data())
                return 1
            }
        }

        var total = opts.urls.size() + batch.size()
        if(total == 0u) {
            printf("cdm: nothing to download\n")
            return 1
        }

        var added : i64 = 0
        for(var i = 0u; i < opts.urls.size(); i++) {
            var u = opts.urls.get_ref(i)
            var uv = string_view::make_view(u)
            var fname = string()
            if(i == 0u && opts.output_name.size() > 0u) {
                fname = opts.output_name.copy()
            } else {
                fname = suggested_filename(uv)
            }
            var cat_tag = 0
            var dest = cli_route(opts, &dm, string_view::make_view(&fname), &mut cat_tag)
            var dest_v = string_view::make_view(&dest)
            var fname_v = string_view::make_view(&fname)
            var id = add_task_ex(&mut dm, uv, dest_v, fname_v, opts.priority, cat_tag)
            added = added + 1
            if(!opts.quiet) {
                printf("cdm: [%lld/%lld] queued %s (%s)\n", (added as bigint), (total as bigint), u.data(), id.data())
            }
        }
        for(var i = 0u; i < batch.size(); i++) {
            var u = batch.get_ref(i)
            var uv = string_view::make_view(u)
            var fname = suggested_filename(uv)
            var cat_tag = 0
            var dest = cli_route(opts, &dm, string_view::make_view(&fname), &mut cat_tag)
            var dest_v = string_view::make_view(&dest)
            var fname_v = string_view::make_view(&fname)
            var id = add_task_ex(&mut dm, uv, dest_v, fname_v, opts.priority, cat_tag)
            added = added + 1
            if(!opts.quiet) {
                printf("cdm: [%lld/%lld] queued %s (%s)\n", (added as bigint), (total as bigint), u.data(), id.data())
            }
        }

        // Wait for completion. The manager auto-starts up to max_concurrent.
        var all_done = false
        while(!all_done) {
            std::concurrent.sleep_ms(250)
            var snap = vector<DownloadItem>()
            snapshot_into(&mut dm, &mut snap)
            all_done = true
            for(var i = 0u; i < snap.size(); i++) {
                var it = snap.get_ptr(i)
                if(!is_terminal(it.state)) {
                    all_done = false
                    break
                }
            }
            if(!opts.quiet) {
                print_progress(&snap, opts.quiet)
            }
        }

        // Final summary (from the live snapshot so states are authoritative).
        var fail_count = 0
        var done_count = 0
        var final_snap = vector<DownloadItem>()
        snapshot_into(&mut dm, &mut final_snap)
        for(var i = 0u; i < final_snap.size(); i++) {
            var it = final_snap.get_ptr(i)
            var lpath = it.local_path()
            if(it.state == STATE_DONE) {
                done_count = done_count + 1
                if(!opts.quiet) {
                    printf("cdm: done %s -> %s\n", it.url.data(), lpath.data())
                }
            } else {
                fail_count = fail_count + 1
                if(!opts.quiet) {
                    var st_s = format_state(it.state)
                    var err_s = it.error.copy()
                    printf("cdm: %s %s (%s)\n", st_s.data(), it.url.data(), err_s.data())
                }
            }
        }
        shutdown(&mut dm)

        if(fail_count > 0) {
            return 1
        }
        return 0
    }

    func print_help() {
        printf("ChemicalDM %s\n", CDM_VERSION)
        printf("\n")
        printf("Usage:\n")
        printf("  cdm [options] <url> [url...]   download URLs and exit\n")
        printf("  cdm [options] --file <path>    download URLs listed in a file\n")
        printf("  cdm (no arguments)             open the desktop GUI\n")
        printf("\n")
        printf("Options:\n")
        printf("  -d, --dir <dir>       destination directory\n")
        printf("  -o, --output <name>   output filename\n")
        printf("  -p, --segments <n>    connections per download\n")
        printf("  -j, --concurrent <n>  max concurrent downloads\n")
        printf("      --speed-limit kb  global speed limit in KB/s\n")
        printf("      --priority <n>    queue priority (0 = highest)\n")
        printf("      --categories      route downloads into category folders (by file type)\n")
        printf("      --no-categories   do not route into category folders\n")
        printf("      --category <name> force a category folder (Documents/Programs/Video/Music/Compressed)\n")
        printf("      --no-category     clear a forced category\n")
        printf("  -f, --file <path>     read URLs from a file\n")
        printf("  -q, --quiet           don't print progress\n")
        printf("  -g, --gui             force the GUI\n")
        printf("  -v, --version         print version\n")
        printf("  -h, --help            show this help\n")
    }

} // end namespace cdm