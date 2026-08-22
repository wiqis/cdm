using std::string;
using std::vector;
using std::Result;

@test
public func CDM_process_exec_basic(env : &mut TestEnv) {
    var cfg = process::ProcessConfig.default()
    cfg.args.push_back(string::make_no_len("echo"))
    cfg.args.push_back(string::make_no_len("proc_test_ok"))
    cfg.capture_stdout = true
    cfg.capture_stderr = true
    var res = process::execute(cfg)
    if(res is Result.Err) { env.error("execute errored"); return }
    var Ok(pr) = res else unreachable
    if(!pr.success) { env.error("echo should succeed"); return }
}
