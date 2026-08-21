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

    // App-wide limits.
    public const MAX_REDIRECTS : int = 10
    public const MAX_RETRIES : int = 3
    public const RETRY_DELAY_MILLIS : i64 = 1000
    public const SOCKET_TIMEOUT_SECS : int = 30
    public const PROGRESS_UPDATE_INTERVAL_MILLIS : i64 = 200

    // Default settings.
    public const DEFAULT_DOWNLOAD_DIR : *char = "/tmp/cdm/downloads"
    public const DEFAULT_MAX_CONCURRENT : int = 3
    public const DEFAULT_MAX_SEGMENTS : int = 4
    public comptime const DEFAULT_MIN_SEGMENT_SIZE : i64 = 256 * 1024
    public const DEFAULT_WORKERS_PER_TASK : int = 1

    // Persistent settings file (relative to $HOME).
    public const SETTINGS_FILE : *char = ".chemicaldm/config.txt"

} // end namespace cdm