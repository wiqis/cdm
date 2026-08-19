// ChemicalDM — data model.

public namespace cdm {

using std::string;

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
                cancel_requested = false
            }
        }

        public func local_path(&self) : string {
            var s = string()
            s.append_string(&self.dir)
            s.append('/')
            s.append_string(&self.filename)
            return s
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
            return c
        }
    }

} // end namespace cdm