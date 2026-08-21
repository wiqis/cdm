// ChemicalDM — download engine. Runs tasks on worker threads. Each task first
// probes the resource, then either streams it in one connection or splits the
// byte range into N parallel segments (one thread per segment, each writing a
// .part file) and assembles the parts when every segment finishes. Pause,
// cancel, retries and resume are all handled; progress is published under a
// per-task mutex so the UI thread never races the workers.

public namespace cdm {

using std::string;
using std::string_view;
using std::mutex;
using std::Result;
using std::vector;

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
        var segments : vector<SegmentState>
        var segmented : bool
        var speed_limit_kbps : i64    // 0 = unlimited
        var part_dir : string
        var allow_segments : bool
        var max_segments : int
        var supports_resume : bool
        var enable_resume : bool

        @constructor func constructor(id_ : string) {
            return TaskRuntime {
                id = id_,
                info_mutex = mutex(),
                progress = TaskProgress(),
                pause_requested = false,
                cancel_requested = false,
                running = false,
                thread = std::concurrent.Thread{ handle : 0 },
                thread_started = false,
                segments = vector<SegmentState>(),
                segmented = false,
                speed_limit_kbps = 0,
                part_dir = string(),
                allow_segments = true,
                max_segments = DEFAULT_MAX_SEGMENTS,
                supports_resume = false,
                enable_resume = true
            }
        }
    }

    // One byte range of a segmented download. Coordinates are absolute in the
    // final file. `copied` is how many bytes have already been written for this
    // segment; `total` is the full range size.
    public struct SegmentState {
        var index : int
        var start : i64
        var end : i64     // inclusive
        var total : i64
        var copied : i64
        var done : bool
        var part_file : string

        @constructor func constructor() {
            return SegmentState {
                index = 0,
                start = 0,
                end = -1,
                total = 0,
                copied = 0,
                done = false,
                part_file = string()
            }
        }
    }

    // Arguments for a segment worker thread. Only primitive fields (no strings
    // that could be aliased across threads); the worker builds its own part
    // file path from the URL/dir/filename.
    public struct SegmentJob {
        var rt : *mut TaskRuntime
        var url : string
        var dir : string
        var filename : string
        var index : int
        var start : i64
        var end : i64
        var total : i64
        var copied : i64

        @constructor func constructor(rt_ : *mut TaskRuntime, url_ : string_view, dir_ : string_view, filename_ : string_view, index_ : int, start_ : i64, end_ : i64, total_ : i64, copied_ : i64) {
            return SegmentJob {
                rt = rt_,
                url = string(url_.data(), url_.size()),
                dir = string(dir_.data(), dir_.size()),
                filename = string(filename_.data(), filename_.size()),
                index = index_,
                start = start_,
                end = end_,
                total = total_,
                copied = copied_
            }
        }
    }

    // Arguments for a task worker thread (non-segmented download).
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

    // Enforce a per-task speed limit. Bytes flowing through a segment are
    // throttled against rt.speed_limit_kbps (KB/s). Each call block briefly.
    func throttle(rt : *mut TaskRuntime, bytes : i64) {
        rt.info_mutex.lock()
        var kbps = rt.speed_limit_kbps
        rt.info_mutex.unlock()
        if(kbps <= 0) { return }
        // time_budget_ms = bytes / (kbps * 1024 bytes/s) * 1000 = bytes/kbps
        var budget_ms = bytes / kbps
        if(budget_ms > 0) {
            std::concurrent.sleep_ms(budget_ms as ulong)
        }
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

    // Compute the number of segments for a file of `total` bytes given the
    // configured maximum and the minimum segment size. Returns 0 when the file
    // is too small or unknown.
    func compute_segment_count(total : i64, max_segments : int, min_size : i64) : int {
        if(total <= 0) { return 0 }
        if(max_segments <= 1) { return 0 }
        var per = total / (max_segments as i64)
        if(per < min_size) {
            // Too small for N segments: use as many as the min size allows.
            var n = (total / min_size) as int
            if(n < 2) { return 0 }
            if(n > max_segments) { n = max_segments }
            return n
        }
        return max_segments
    }

    // Split [0, total) into `count` contiguous segments.
    func build_segments(fname : string_view, count : int, total : i64, part_dir : string_view) : vector<SegmentState> {
        var out = vector<SegmentState>()
        if(count <= 0) { return out }
        var base = total / (count as i64)
        var rem = total % (count as i64)
        var pos : i64 = 0
        for(var i = 0; i < count; i++) {
            var seg = SegmentState()
            seg.index = i
            seg.start = pos
            var extra : i64 = 0
            if(rem > 0 && i < (rem as int)) { extra = 1 }
            var len = base + extra
            seg.end = pos + len - 1
            seg.total = len
            seg.copied = 0
            seg.done = false
            seg.part_file = segment_part_path(part_dir, fname, i)
            out.push_back(seg)
            pos = pos + len
        }
        return out
    }

    // Sum up the current byte counts of all segment part files so a resumed
    // session does not re-download already-written bytes. Updates the runtime
    // segments in place (no vector copy).
    func load_segment_state(rt : *mut TaskRuntime) {
        var total_copied : i64 = 0
        rt.info_mutex.lock()
        for(var i = 0u; i < rt.segments.size(); i++) {
            var seg = rt.segments.get_ptr(i)
            seg.copied = segment_copied_from_disk(seg.part_file.data(), seg.total)
            if(seg.copied >= seg.total && seg.total > 0) { seg.done = true }
            total_copied = total_copied + seg.copied
        }
        if(total_copied > rt.progress.downloaded_bytes) {
            rt.progress.downloaded_bytes = total_copied
        }
        rt.info_mutex.unlock()
    }

    // Stream the response body to `ofile`, respecting byte limits, pause and
    // cancel. Returns: 1 complete, 2 paused, 0 error (retryable).
    // When max_bytes >= 0, stops after that many bytes have been written.
    func stream_body(rt : *mut TaskRuntime, body : &mut http::Body, ofile : *mut FILE, max_bytes : i64) : int {
        var buf : [STREAM_BUF_SIZE]u8
        var sample_start = now_millis()
        var sample_bytes : i64 = 0
        var written : i64 = 0

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

            var want = STREAM_BUF_SIZE
            if(max_bytes >= 0 && (max_bytes - written) < (want as i64)) {
                want = (max_bytes - written) as usize
                if(want == 0u) {
                    fflush(ofile)
                    return 1
                }
            }

            var n = body.read(&raw mut buf[0], want)
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

            written = written + n
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
            throttle(rt, n)
            if(max_bytes >= 0 && written >= max_bytes) {
                fflush(ofile)
                return 1
            }
        }
        return 0
    }

    // ---- segment worker threads ----

    // Build a segment's dedicated part-file path on the target directory.
    func segment_part_path(dir : string_view, filename : string_view, index : int) : string {
        var pf = string(dir.data(), dir.size())
        pf.append('/')
        pf.append_with_len(filename.data(), filename.size())
        var idxs = string()
        idxs.append_integer(index as bigint)
        pf.append('.')
        pf.append_with_len(idxs.data(), idxs.size())
        var ext = string::make_no_len(".part")
        pf.append_with_len(ext.data(), ext.size())
        return pf
    }

    // Copy an already-downloaded segment's byte count (based on its part file
    // size) so a resumed session does not re-download written bytes.
    func segment_copied_from_disk(path : *char, total : i64) : i64 {
        var f = fopen(path, "rb")
        if(f == null) { return 0 }
        fseek(f, 0, SEEK_END)
        var sz = ftell(f)
        fclose(f)
        if(sz <= 0) { return 0 }
        var copied = sz as i64
        if(copied > total) { copied = total }
        return copied
    }

    // Worker for one byte range. Opens a bounded range request covering exactly
    // [start, end] and streams the partial content into the segment's .part
    // file. Returns 1 on completion, 2 on pause, 0 on failure.
    func raw_download_segment(rt : *mut TaskRuntime, url : string_view, part_path : *char, start : i64, end : i64, total : i64, copied_in : i64) : int {
        var resume_from = start + copied_in
        var res = open_download_range(url, resume_from, end)
        if(res is Result.Err) {
            return 0
        }
        var Ok(rep) = res else unreachable
        var st = rep.status

        if(st == 200u) {
            // Server ignored our Range. Only valid for the first segment.
            if(resume_from != 0) {
                rep.body.close_socket()
                return 0
            }
            var ofile = open_output(part_path, 0)
            if(ofile == null) { rep.body.close_socket(); return 0 }
            var code = stream_body(rt, &mut rep.body, ofile, -1)
            fclose(ofile)
            rep.body.close_socket()
            if(code == 1) {
                return 1
            }
            return code
        }

        if(st != 206u) {
            rep.body.close_socket()
            return 0
        }

        var ofile = open_output(part_path, copied_in)
        if(ofile == null) { rep.body.close_socket(); return 0 }
        var remaining = end - resume_from + 1
        if(remaining < 0) { remaining = 0 }
        var code = stream_body(rt, &mut rep.body, ofile, remaining)
        fclose(ofile)
        rep.body.close_socket()
        if(code == 1) {
            return 1
        }
        return code
    }

    // Thread entry for a segment worker. Publishes the segment's completion
    // back into the runtime (held under the same mutex).
    func segment_entry(arg : *void) : *void {
        var job = arg as *mut SegmentJob
        var part = segment_part_path(string_view::make_view(&job.dir),
                                     string_view::make_view(&job.filename), job.index)
        var copied = job.copied
        var res = raw_download_segment(job.rt, string_view::make_view(&job.url),
                                       part.data(), job.start, job.end, job.total, copied)
        if(res == 1) {
            job.rt.info_mutex.lock()
            for(var i = 0u; i < job.rt.segments.size(); i++) {
                var s = job.rt.segments.get_ptr(i)
                if(s.index == job.index) {
                    s.copied = job.total
                    s.done = true
                    break
                }
            }
            job.rt.info_mutex.unlock()
        } else if(res == 2) {
            // paused: record whatever made it to disk
            var sz = segment_copied_from_disk(part.data(), job.total)
            job.rt.info_mutex.lock()
            for(var i = 0u; i < job.rt.segments.size(); i++) {
                var s = job.rt.segments.get_ptr(i)
                if(s.index == job.index) {
                    s.copied = sz
                    break
                }
            }
            job.rt.info_mutex.unlock()
        }
        delete job
        return null
    }

    // Concatenate the .part files in order into the final output file.
    func assemble_segments(rt : *mut TaskRuntime, dir : *char, filename : *char) : bool {
        var dest = string(dir)
        dest.append('/')
        dest.append_char_ptr(filename)

        var out = fopen(dest.data(), "wb")
        if(out == null) { return false }
        var buf : [1024u * 1024u]u8

        // Sort segments by index (they are built in order, so just iterate).
        // Iterate the runtime's segments under the lock.
        rt.info_mutex.lock()
        var seg_count = rt.segments.size()
        for(var i = 0u; i < seg_count; i++) {
            var seg = rt.segments.get_ptr(i)
            var f = fopen(seg.part_file.data(), "rb")
            if(f == null) { rt.info_mutex.unlock(); fclose(out); return false }
            while(true) {
                var n = fread(&raw mut buf[0], 1, 1024u * 1024u, f)
                if(n == 0u) { break }
                var w = fwrite(&raw mut buf[0], 1, n, out)
                if(w != n) { fclose(f); fclose(out); rt.info_mutex.unlock(); return false }
            }
            fclose(f)
        }
        rt.info_mutex.unlock()
        fclose(out)

        // Clean up part files (paths are stable; read again under lock).
        rt.info_mutex.lock()
        seg_count = rt.segments.size()
        for(var i = 0u; i < seg_count; i++) {
            var seg = rt.segments.get_ptr(i)
            remove(seg.part_file.data())
        }
        rt.info_mutex.unlock()
        return true
    }

    // The download runner: probe, choose segmented vs single-stream, then
    // download all segments in parallel and assemble.
    public func run_download_task(rt : *mut TaskRuntime, url : string_view, dir : string_view, filename : string_view) {
        locked_set_state(rt, STATE_DOWNLOADING)
        var empty_err = string()
        locked_set_error(rt, &empty_err)

        var retries = 0
        var done = false

        // Probe for size/resume if we don't already have progress.
        var downloaded0 = locked_get_downloaded(rt)
        var total0 = locked_get_total(rt)
        if(total0 <= 0 && downloaded0 <= 0) {
            var p = probe(url, filename)
            if(p.ok) {
                if(p.total_bytes > 0) { locked_set_total(rt, p.total_bytes) }
                if(p.supports_resume) {
                    rt.info_mutex.lock()
                    rt.supports_resume = true
                    rt.info_mutex.unlock()
                }
            }
        }
        total0 = locked_get_total(rt)

        // Decide whether to use segments. Only when the server supports Range,
        // the configured max allows it, and the file is big enough.
        var use_segments = false
        var seg_count = 0
        rt.info_mutex.lock()
        var allow_segments = rt.allow_segments
        var max_segments = rt.max_segments
        var supports_resume = rt.supports_resume
        rt.info_mutex.unlock()
        if(total0 > 0 && downloaded0 < total0 && rt.segments.empty()) {
            if(allow_segments && supports_resume) {
                seg_count = compute_segment_count(total0, max_segments, DEFAULT_MIN_SEGMENT_SIZE)
                use_segments = seg_count > 1
            }
        } else if(!rt.segments.empty()) {
            // Resume from a previous segmented download (parts exist on disk).
            use_segments = true
            seg_count = rt.segments.size() as int
            load_segment_state(rt)
        }

        if(use_segments && seg_count > 0 && rt.segments.empty()) {
            rt.info_mutex.lock()
            rt.segments = build_segments(filename, seg_count, total0, dir)
            rt.segmented = true
            rt.info_mutex.unlock()
            load_segment_state(rt)
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
                if(rt.segmented && !rt.segments.empty() && fs::exists(rt.segments.get_ptr(0).part_file.data())) {
                    if(assemble_segments(rt, dir.data(), filename.data())) {
                        locked_set_state(rt, STATE_DONE)
                        return
                    }
                    // assembly failed: fall through to retry
                } else {
                    locked_set_state(rt, STATE_DONE)
                    return
                }
            }

            if(rt.segmented && !rt.segments.empty()) {
                // Download each unfinished segment in parallel.
                var threads = vector<std::concurrent.Thread>()
                var jobs = vector<*mut SegmentJob>()

                // Build the worker jobs under the lock (reading segment args),
                // then spawn them outside it.
                rt.info_mutex.lock()
                var any_started = false
                for(var i = 0u; i < rt.segments.size(); i++) {
                    var seg = rt.segments.get_ptr(i)
                    if(seg.done) { continue }
                    var job = new SegmentJob(rt, url, dir, filename,
                                             seg.index, seg.start, seg.end, seg.total, seg.copied)
                    if(job == null) { continue }
                    jobs.push_back(job)
                    any_started = true
                }
                rt.info_mutex.unlock()

                for(var i = 0u; i < jobs.size(); i++) {
                    var j = jobs.get_ptr(i)
                    threads.push_back(std::concurrent::spawn(segment_entry, (*j) as *void))
                }

                if(!any_started) {
                    // All segments are done; assemble.
                    if(assemble_segments(rt, dir.data(), filename.data())) {
                        locked_set_state(rt, STATE_DONE)
                        done = true
                        break
                    }
                    var msg = string::make_no_len("failed to assemble segments")
                    locked_set_error(rt, &msg)
                    retries = retries + 1
                    if(retries <= MAX_RETRIES) { std::concurrent.sleep_ms(RETRY_DELAY_MILLIS as ulong) }
                    continue
                }

                // Join all workers.
                for(var i = 0u; i < threads.size(); i++) {
                    var t = threads.get_ptr(i)
                    t.join()
                }

                // Check results.
                var all_done = true
                var total_copied : i64 = 0
                rt.info_mutex.lock()
                for(var i = 0u; i < rt.segments.size(); i++) {
                    var s = rt.segments.get_ptr(i)
                    total_copied = total_copied + s.copied
                    if(!s.done) { all_done = false }
                }
                rt.progress.downloaded_bytes = total_copied
                rt.info_mutex.unlock()

                if(all_done) {
                    if(assemble_segments(rt, dir.data(), filename.data())) {
                        locked_set_state(rt, STATE_DONE)
                        done = true
                        break
                    }
                    var msg = string::make_no_len("failed to assemble segments")
                    locked_set_error(rt, &msg)
                    retries = retries + 1
                    if(retries <= MAX_RETRIES) { std::concurrent.sleep_ms(RETRY_DELAY_MILLIS as ulong) }
                    continue
                }

                if(should_cancel(rt)) {
                    locked_set_state(rt, STATE_CANCELLED)
                    return
                }
                if(should_pause(rt)) {
                    locked_set_state(rt, STATE_PAUSED)
                    // Loop again; the pause check at loop top waits.
                    continue
                }
                if(threads.size() == 0u) {
                    var msg = string::make_no_len("no segment started")
                    locked_set_error(rt, &msg)
                    retries = retries + 1
                    if(retries <= MAX_RETRIES) { std::concurrent.sleep_ms(RETRY_DELAY_MILLIS as ulong) }
                    continue
                }
                // A segment failed (connection dropped) — retry the unfinished ones.
                retries = retries + 1
                if(retries <= MAX_RETRIES) {
                    // refresh segments' copied from disk (in case of partial writes)
                    load_segment_state(rt)
                    std::concurrent.sleep_ms(RETRY_DELAY_MILLIS as ulong)
                }
                continue
            }

            // ---- non-segmented path ----
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

                var code = stream_body(rt, &mut rep.body, ofile, -1)
                fclose(ofile)
                if(code == 1) {
                    locked_set_state(rt, STATE_DONE)
                    done = true
                    break
                } else if(code == 2) {
                    // Paused — reconnect on the next loop iteration (no retry cost).
                    continue
                } else {
                    if(should_cancel(rt)) {
                        return
                    }
                    var msg = string::make_no_len("connection lost while downloading")
                    locked_set_error(rt, &msg)
                    retries = retries + 1
                    if(retries <= MAX_RETRIES) { std::concurrent.sleep_ms(RETRY_DELAY_MILLIS as ulong) }
                    continue
                }
            } else if(st == 416u) {
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
                if(rt.segmented && !rt.segments.empty() && fs::exists(rt.segments.get_ptr(0).part_file.data())) {
                    if(assemble_segments(rt, dir.data(), filename.data())) {
                        locked_set_state(rt, STATE_DONE)
                        return
                    }
                } else {
                    locked_set_state(rt, STATE_DONE)
                    return
                }
            }
            if(!should_cancel(rt)) {
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