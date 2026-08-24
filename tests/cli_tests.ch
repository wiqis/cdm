// ChemicalDM — app-level unit tests (CLI parsing, headless plumbing). The
// engine itself is tested in the cdmlib module; these cover pieces that only
// exist in the application (command line handling).

using std::string;
using std::string_view;

@test
public func CDM_cli_parse(env : &mut TestEnv) {
    var opts = cdm::CliOptions()
    var arg0 = string::make_no_len("cdm")
    var arg1 = string::make_no_len("https://a.com/f.bin")
    var arg2 = string::make_no_len("--dir")
    var arg3 = string::make_no_len("/tmp/out")

    unsafe var argv : [4]*char
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
    var want_url = string::make_no_len("https://a.com/f.bin")
    var want_dir = string::make_no_len("/tmp/out")
    if(!got_url.equals(&want_url)) { env.error("cli url mismatch"); return }
    if(!opts.download_dir.equals(&want_dir)) { env.error("cli dir mismatch"); return }
}

@test
public func CDM_cli_priority(env : &mut TestEnv) {
    var opts = cdm::CliOptions()
    var arg0 = string::make_no_len("cdm")
    var arg1 = string::make_no_len("--priority")
    var arg2 = string::make_no_len("2")
    var arg3 = string::make_no_len("https://a.com/f.bin")

    unsafe var argv : [4]*char
    argv[0] = arg0.data()
    argv[1] = arg1.data()
    argv[2] = arg2.data()
    argv[3] = arg3.data()

    var err = cdm::parse_cli(4, &raw mut argv[0], &mut opts)
    if(err != null) { env.error("cli priority parse error"); return }
    if(opts.priority != 2) { env.error("priority not set"); return }
    if(opts.urls.size() != 1u) { env.error("cli urls size"); return }
}