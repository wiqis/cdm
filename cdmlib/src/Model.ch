// ChemicalDM — data model.

public namespace cdm {

using std::string;
using std::string_view;

    // Pure data pod describing one download task. No pointers, no sockets —
    // those live in the Engine. The manager swaps snapshots of this struct
    // behind a mutex so the UI (via JSON) and the engine (thread) never race.
    public struct DownloadItem {
        var id : string
        var url : string
        var dir : string        // destination directory
        var filename : string   // bare file name on disk
        var total_bytes : i64
        var downloaded_bytes : i64
        var speed_bytes_per_sec : i64
        var state : int
        var error : string
        var created_at : i64    // unix seconds
        var started_at : i64
        var finished_at : i64
        var pause_requested : bool
        var cancel_requested : bool
        var priority : int            // lower = downloaded first (0 highest)
        var max_segments : int        // 0 = use the manager default
        var speed_limit_kbps : i64    // 0 = no per-item limit
        var retry_count : int
        var duplicate_suffix : int    // 0 = original name; 1,2,.. = "name (N).ext"
        var category : int            // opaque category tag (0 = none)
        var segments_json : string    // pre-serialized JSON array of segment states
        var was_interrupted : bool    // true if download was active when app closed

        @constructor func constructor(id_ : string, url_ : string, dir_ : string, filename_ : string) {
            return DownloadItem {
                id = id_,
                url = url_,
                dir = dir_,
                filename = filename_,
                total_bytes = 0,
                downloaded_bytes = 0,
                speed_bytes_per_sec = 0,
                state = STATE_QUEUED,
                error = string(),
                created_at = 0,
                started_at = 0,
                finished_at = 0,
                pause_requested = false,
                cancel_requested = false,
                priority = 0,
                max_segments = 0,
                speed_limit_kbps = 0,
                retry_count = 0,
                duplicate_suffix = 0,
                category = 0,
                segments_json = string(),
                was_interrupted = false
            }
        }

        public func local_path(&self) : string {
            var s = string()
            s.append_string(&self.dir)
            s.append('/')
            s.append_string(&self.filename)
            return s
        }

        // The file name after applying duplicate renaming. When
        // duplicate_suffix > 0 the name becomes "base (N).ext".
        public func display_filename(&self) : string {
            if(self.duplicate_suffix <= 0) { return self.filename.copy() }
            var base = string()
            var ext = string()
            var dot = string_view::make_view(&self.filename).find_last(".")
            if(dot != std::NPOS && dot > 0) {
                base = self.filename.substring(0u, dot)
                ext = self.filename.substring(dot, self.filename.size())
            } else {
                base = self.filename.copy()
            }
            var out = base
            out.append_view(" (")
            var sfx = string()
            sfx.append_integer(self.duplicate_suffix as bigint)
            out.append_string(&sfx)
            out.append(')')
            out.append_string(&ext)
            return out
        }

        public func copy(&self) : DownloadItem {
            var c = DownloadItem(self.id.copy(), self.url.copy(), self.dir.copy(), self.filename.copy())
            c.total_bytes = self.total_bytes
            c.downloaded_bytes = self.downloaded_bytes
            c.speed_bytes_per_sec = self.speed_bytes_per_sec
            c.state = self.state
            c.error = self.error.copy()
            c.created_at = self.created_at
            c.started_at = self.started_at
            c.finished_at = self.finished_at
            c.pause_requested = self.pause_requested
            c.cancel_requested = self.cancel_requested
            c.priority = self.priority
            c.max_segments = self.max_segments
            c.speed_limit_kbps = self.speed_limit_kbps
            c.retry_count = self.retry_count
            c.duplicate_suffix = self.duplicate_suffix
            c.segments_json = self.segments_json.copy()
            c.was_interrupted = self.was_interrupted
            return c
        }
    }

} // end namespace cdm