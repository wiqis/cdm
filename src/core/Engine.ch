// ChemicalDM — download engine. Runs one task per thread: probe, stream to
// file with range-based resume, pause/cancel handling, and bounded retries.
// All shared state lives in TaskRuntime behind a mutex so the UI (manager)
// and the worker thread never race.

public namespace cdm {

using std::string;
using std::string_view;
using std::mutex;
using std::Result;

    public comptime const STREAM_BUF_SIZE : usize = 128u * 1024u
    public const SPEED_SAMPLE_MS : i64 = 500
    public const PAUSE_POLL_MS : ulong = 150

    // Cross-thread progress snapshot.
    public struct TaskProgress {
        var total_bytes : i64
        var downloaded_bytes : i64
        var speed_bytes_per_sec : i64
        var state : int
        var error : string

        @constructor func constructor() {
            return TaskProgress {
                total_bytes = -1,
                downloaded_bytes = 0,
                speed_bytes_per_sec = 0,
                state = STATE_QUEUED,
                error = string()
            }
        }

        public func copy(&self) : TaskProgress {
            var p = TaskProgress()
            p.total_bytes = self.total_bytes
            p.downloaded_bytes = self.downloaded_bytes
            p.speed_bytes_per_sec = self.speed_bytes_per_sec
            p.state = self.state
            p.error = self.error.copy()
            return p
        }
    }

    // Per-task runtime state, heap-allocated and owned by the manager.
    public struct TaskRuntime {
        var id : string
        var info_mutex : mutex
        var progress : TaskProgress
        var pause_requested : bool
        var cancel_requested : bool
        var running : bool
        var thread : std::concurrent.Thread
        var thread_started : bool

        @constructor func constructor(id_ : string) {
            return TaskRuntime {
                id = id_,
                info_mutex = mutex(),
                progress = TaskProgress(),
                pause_requested = false,
                cancel_requested = false,
                running = false,
                thread = std::concurrent.Thread{ handle : 0 },
                thread_started = false
            }
        }
    }

    // Arguments for the worker thread.
    public struct DownloadJob {
        var rt : *mut TaskRuntime
        var url : string
        var dir : string
        var filename : string

        @constructor func constructor(rt_ : *mut TaskRuntime, url_ : string_view, dir_ : string_view, filename_ : string_view) {
            return DownloadJob {
                rt = rt_,
                url = string(url_.data(), url_.size()),
                dir = string(dir_.data(), dir_.size()),
                filename = string(filename_.data(), filename_.size())
            }
        }
    }

    public func now_millis() : i64 {
        var st = std::chrono::SystemTime::now()
        return st.as_unix_epoch_nanos() / 1000000
    }

    // ---- task control (called from the UI thread) ----

    public func request_pause(rt : *mut TaskRuntime) {
        rt.info_mutex.lock()
        rt.pause_requested = true
        rt.info_mutex.unlock()
    }

    public func request_cancel(rt : *mut TaskRuntime) {
        rt.info_mutex.lock()
        rt.cancel_requested = true
        rt.pause_requested = false
        rt.info_mutex.unlock()
    }

    public func resume_runtime(rt : *mut TaskRuntime) {
        rt.info_mutex.lock()
        rt.pause_requested = false
        rt.info_mutex.unlock()
    }

    public func snapshot_progress(rt : *mut TaskRuntime) : TaskProgress {
        rt.info_mutex.lock()
        var p = rt.progress.copy()
        rt.info_mutex.unlock()
        return p
    }

    // ---- task thread (internals) ----

    func locked_set_state(rt : *mut TaskRuntime, state : int) {
        rt.info_mutex.lock()
        rt.progress.state = state
        rt.info_mutex.unlock()
    }

    func locked_set_error(rt : *mut TaskRuntime, err : &string) {
        rt.info_mutex.lock()
        rt.progress.error = err.copy()
        rt.info_mutex.unlock()
    }

    func locked_set_total(rt : *mut TaskRuntime, total : i64) {
        rt.info_mutex.lock()
        rt.progress.total_bytes = total
        rt.info_mutex.unlock()
    }

    func locked_get_downloaded(rt : *mut TaskRuntime) : i64 {
        rt.info_mutex.lock()
        var v = rt.progress.downloaded_bytes
        rt.info_mutex.unlock()
        return v
    }

    func locked_get_total(rt : *mut TaskRuntime) : i64 {
        rt.info_mutex.lock()
        var v = rt.progress.total_bytes
        rt.info_mutex.unlock()
        return v
    }

    func locked_add_downloaded(rt : *mut TaskRuntime, n : i64) : i64 {
        rt.info_mutex.lock()
        rt.progress.downloaded_bytes = rt.progress.downloaded_bytes + n
        var v = rt.progress.downloaded_bytes
        rt.info_mutex.unlock()
        return v
    }

    func locked_set_speed(rt : *mut TaskRuntime, speed : i64) {
        rt.info_mutex.lock()
        rt.progress.speed_bytes_per_sec = speed
        rt.info_mutex.unlock()
    }

    func should_cancel(rt : *mut TaskRuntime) : bool {
        rt.info_mutex.lock()
        var v = rt.cancel_requested
        rt.info_mutex.unlock()
        return v
    }

    func should_pause(rt : *mut TaskRuntime) : bool {
        rt.info_mutex.lock()
        var v = rt.pause_requested && !rt.cancel_requested
        rt.info_mutex.unlock()
        return v
    }

    // Wait until the pause is lifted or the task is cancelled.
    func wait_resume_or_cancel(rt : *mut TaskRuntime) {
        while(true) {
            if(should_cancel(rt)) { return }
            rt.info_mutex.lock()
            var paused = rt.pause_requested
            rt.info_mutex.unlock()
            if(!paused) { return }
            std::concurrent.sleep_ms(PAUSE_POLL_MS)
        }
    }

    // Open the output file, truncating on a fresh start or opening in place
    // at `resume_from` for resumable sessions.
    func open_output(path : *char, resume_from : i64) : *mut FILE {
        if(resume_from <= 0) {
            return fopen(path, "wb")
        }
        var f = fopen(path, "r+b")
        if(f != null) {
            fseek(f, resume_from, SEEK_SET)
        }
        return f
    }

    // Stream the response body to disk. Returns: 1 complete, 2 paused,
    // 0 error (retryable).
    func stream_body(rt : *mut TaskRuntime, body : &mut http::Body, ofile : *mut FILE) : int {
        var buf : [STREAM_BUF_SIZE]u8
        var sample_start = now_millis()
        var sample_bytes : i64 = 0

        while(true) {
            if(should_cancel(rt)) {
                locked_set_state(rt, STATE_CANCELLED)
                return 0
            }
            if(should_pause(rt)) {
                locked_set_state(rt, STATE_PAUSED)
                body.close_socket()
                fflush(ofile)
                return 2
            }

            var n = body.read(&raw mut buf[0], STREAM_BUF_SIZE)
            if(n < 0) {
                // socket error — keep whatever we have; caller will retry
                fflush(ofile)
                return 0
            }
            if(n == 0) {
                // clean end of body
                fflush(ofile)
                return 1
            }

            var wrote = fwrite(&raw mut buf[0], 1, n as usize, ofile)
            if(wrote < (n as usize)) {
                // disk full / write error
                return 0
            }

            sample_bytes = sample_bytes + n
            var now = now_millis()
            if(now - sample_start >= SPEED_SAMPLE_MS) {
                var dt = now - sample_start
                if(dt > 0) {
                    var speed = (sample_bytes * 1000) / dt
                    locked_set_speed(rt, speed)
                }
                sample_start = now
                sample_bytes = 0
            }
            locked_add_downloaded(rt, n)
        }
        return 0
    }

    // The download worker: probe, open output, stream with retry/resume.
    public func run_download_task(rt : *mut TaskRuntime, url : string_view, dir : string_view, filename : string_view) {
        locked_set_state(rt, STATE_DOWNLOADING)
        var empty_err = string()
        locked_set_error(rt, &empty_err)

        var retries = 0
        var done = false

        // Probe for size/resume if we don't already have progress.
        var downloaded0 = locked_get_downloaded(rt)
        if(downloaded0 <= 0) {
            var p = probe(url, filename)
            if(p.ok) {
                if(p.total_bytes > 0) { locked_set_total(rt, p.total_bytes) }
                if(p.total_bytes > 0 && downloaded0 >= p.total_bytes) {
                    locked_set_state(rt, STATE_DONE)
                    return
                }
            }
        }

        while(!done && retries <= MAX_RETRIES) {
            if(should_cancel(rt)) {
                locked_set_state(rt, STATE_CANCELLED)
                return
            }
            if(should_pause(rt)) {
                locked_set_state(rt, STATE_PAUSED)
                wait_resume_or_cancel(rt)
                if(should_cancel(rt)) {
                    locked_set_state(rt, STATE_CANCELLED)
                    return
                }
                locked_set_state(rt, STATE_DOWNLOADING)
            }

            var resume_from = locked_get_downloaded(rt)
            var total = locked_get_total(rt)
            if(total > 0 && resume_from >= total) {
                locked_set_state(rt, STATE_DONE)
                return
            }

            var res = open_download(url, resume_from)
            if(res is Result.Err) {
                var Err(e) = res else unreachable
                locked_set_error(rt, &e)
                retries = retries + 1
                if(retries <= MAX_RETRIES) { std::concurrent.sleep_ms(RETRY_DELAY_MILLIS as ulong) }
                continue
            }

            // Build the destination path.
            var path = string(dir.data(), dir.size())
            path.append('/')
            var fname = string(filename.data(), filename.size())
            path.append_string(&fname)

            var Ok(rep) = res else unreachable
            var st = rep.status

            if(st == 200u && resume_from > 0) {
                // Server ignored our Range and restarted at byte 0; truncate the
                // file and reset progress so the file stays consistent.
                resume_from = 0
                locked_set_total(rt, locked_get_total(rt))
            }

            if(st == 200u || st == 206u) {
                var cl_opt = rep.headers.get("Content-Length")
                if(st == 200u && cl_opt is std::Option.Some) {
                    var Some(cl) = cl_opt else unreachable
                    var clen = parse_content_length(&cl)
                    if(clen > 0) { locked_set_total(rt, clen) }
                }

                var ofile = open_output(path.data(), resume_from)
                if(ofile == null) {
                    var msg = string::make_no_len("cannot open output file")
                    locked_set_error(rt, &msg)
                    rep.body.close_socket()
                    retries = retries + 1
                    if(retries <= MAX_RETRIES) { std::concurrent.sleep_ms(RETRY_DELAY_MILLIS as ulong) }
                    continue
                }

                var code = stream_body(rt, &mut rep.body, ofile)
                fclose(ofile)
                if(code == 1) {
                    // Success: mark done if the server promised a size, or if we
                    // simply reached EOF without one.
                    locked_set_state(rt, STATE_DONE)
                    done = true
                    break
                } else if(code == 2) {
                    // Paused — reconnect on the next loop iteration (no retry cost).
                    continue
                } else {
                    if(should_cancel(rt)) {
                        // state already CANCELLED inside stream_body
                        return
                    }
                    var msg = string::make_no_len("connection lost while downloading")
                    locked_set_error(rt, &msg)
                    retries = retries + 1
                    if(retries <= MAX_RETRIES) { std::concurrent.sleep_ms(RETRY_DELAY_MILLIS as ulong) }
                    continue
                }
            } else if(st == 416u) {
                // Range not satisfiable: the file is likely complete.
                var total_after = locked_get_total(rt)
                var served = locked_get_downloaded(rt)
                if(total_after > 0 && served >= total_after) {
                    locked_set_state(rt, STATE_DONE)
                    done = true
                    break
                }
                var msg = string::make_no_len("server rejected range request (416)")
                locked_set_error(rt, &msg)
                rep.body.close_socket()
                retries = retries + 1
                if(retries <= MAX_RETRIES) { std::concurrent.sleep_ms(RETRY_DELAY_MILLIS as ulong) }
                continue
            } else {
                // Unexpected status.
                var msg = string::make_no_len("unexpected HTTP status ")
                msg.append_uinteger(st as ubigint)
                locked_set_error(rt, &msg)
                rep.body.close_socket()
                retries = retries + 1
                if(retries <= MAX_RETRIES) { std::concurrent.sleep_ms(RETRY_DELAY_MILLIS as ulong) }
                continue
            }
        }

        if(!done) {
            var final_total = locked_get_total(rt)
            var final_dl = locked_get_downloaded(rt)
            if(final_total > 0 && final_dl >= final_total) {
                locked_set_state(rt, STATE_DONE)
            } else if(!should_cancel(rt)) {
                locked_set_state(rt, STATE_FAILED)
            }
        }
    }

    // Worker entry point (matches std::concurrent::spawn signature).
    func download_entry(arg : *void) : *void {
        var job = arg as *mut DownloadJob
        run_download_task(job.rt, string_view::make_view(&job.url),
                          string_view::make_view(&job.dir),
                          string_view::make_view(&job.filename))
        // The job was heap-allocated by the manager; free it here.
        delete job
        return null
    }

    // Spawn the worker thread for a ready-to-run task.
    public func start_task(rt : *mut TaskRuntime, url : string_view, dir : string_view, filename : string_view) : bool {
        var job = new DownloadJob(rt, url, dir, filename)
        if(job == null) { return false }
        rt.info_mutex.lock()
        if(rt.running) {
            rt.info_mutex.unlock()
            delete job
            return false
        }
        rt.running = true
        rt.thread_started = true
        rt.info_mutex.unlock()

        rt.thread = std::concurrent::spawn(download_entry, job as *void)
        return true
    }

    public func join_task(rt : *mut TaskRuntime) {
        rt.info_mutex.lock()
        var has = rt.thread_started
        rt.info_mutex.unlock()
        if(has) {
            rt.thread.join()
        }
        rt.info_mutex.lock()
        rt.running = false
        rt.info_mutex.unlock()
    }

} // end namespace cdm