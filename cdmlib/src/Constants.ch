// ChemicalDM — core constants.

public namespace cdm {

    public const CDM_VERSION : *char = "0.1.0"
    public const CDM_NAME : *char = "ChemicalDM"

    // Task lifecycle states. Mirrors XDM's int status codes.
    public const STATE_QUEUED : int = 0
    public const STATE_DOWNLOADING : int = 1
    public const STATE_PAUSED : int = 2
    public const STATE_DONE : int = 3
    public const STATE_FAILED : int = 4
    public const STATE_CANCELLED : int = 5

    // Retry policy — encapsulates retry behaviour so it can be shared between
    // the manager (defaults) and per-task runtimes (overrides).
    public struct RetryPolicy {
        var max_retries : int        // -1 = infinite retries
        var delay_ms : i64           // milliseconds between retries

        @constructor func constructor() {
            return RetryPolicy {
                max_retries = DEFAULT_MAX_RETRIES,
                delay_ms = DEFAULT_RETRY_DELAY_MS
            }
        }

        public func should_retry(&self, attempt : int) : bool {
            return self.max_retries < 0 || attempt <= self.max_retries
        }

        public func sleep_between_retries(&self) {
            if(self.delay_ms > 0) {
                std::concurrent.sleep_ms(self.delay_ms as ulong)
            }
        }
    }

    // App-wide limits.
    public const MAX_REDIRECTS : int = 10
    public const DEFAULT_MAX_RETRIES : int = 3
    public const DEFAULT_RETRY_DELAY_MS : i64 = 1000
    public const SOCKET_TIMEOUT_SECS : int = 30
    public const PROGRESS_UPDATE_INTERVAL_MILLIS : i64 = 200

    // Default settings. The "~" prefix is expanded at runtime to $HOME.
    public const DEFAULT_DOWNLOAD_DIR : *char = "~/Downloads/cdm"
    public const DEFAULT_MAX_CONCURRENT : int = 3
    public const DEFAULT_MAX_SEGMENTS : int = 4
    public comptime const DEFAULT_MIN_SEGMENT_SIZE : i64 = 256 * 1024
    public const DEFAULT_WORKERS_PER_TASK : int = 1

    // Persistent settings file (relative to $HOME).
    public const SETTINGS_FILE : *char = ".chemicaldm/config.txt"

} // end namespace cdm