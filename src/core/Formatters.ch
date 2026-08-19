// ChemicalDM — formatting helpers for human-readable output.

public namespace cdm {

using std::string;

    // 123456789 -> "117.7 MB"
    public func format_bytes(bytes : i64) : string {
        if(bytes < 1024) {
            var s = string()
            s.append_integer(bytes as bigint)
            s.append(' ')
            s.append('B')
            return s
        }

        var value = bytes as double
        var units = string::make_no_len("KMGTPE")
        var idx = 0
        while(value >= 1024.0 && idx < 5) {
            value = value / 1024.0
            idx = idx + 1
        }

        var s = string()
        s.append_double(value, 1)
        s.append(' ')
        s.append(units.get(idx as uint))
        s.append('B')
        return s
    }

    // bytes/sec -> "1.5 MB/s"
    public func format_speed(speed : i64) : string {
        var s = format_bytes(speed)
        var suffix = string::make_no_len("/s")
        s.append_string(&suffix)
        return s
    }

    // ETA from remaining bytes and speed. Returns "" when unknown.
    public func format_eta(remaining : i64, speed : i64) : string {
        if(remaining <= 0 || speed <= 0) {
            return string()
        }
        var secs = (remaining as double) / (speed as double)
        return format_seconds(secs as i64)
    }

    public func format_seconds(secs : i64) : string {
        var s = string()
        if(secs < 60) {
            s.append_integer(secs as bigint)
            s.append('s')
            return s
        }
        var minutes = secs / 60
        var hours = minutes / 60
        if(hours > 0) {
            s.append_integer(hours as bigint)
            s.append('h')
            s.append(' ')
            s.append_integer((minutes % 60) as bigint)
            s.append('m')
        } else {
            s.append_integer(minutes as bigint)
            s.append('m')
            s.append(' ')
            s.append_integer((secs % 60) as bigint)
            s.append('s')
        }
        return s
    }

    public func format_state(state : int) : string {
        if(state == STATE_QUEUED) { return string::make_no_len("Queued") }
        if(state == STATE_DOWNLOADING) { return string::make_no_len("Downloading") }
        if(state == STATE_PAUSED) { return string::make_no_len("Paused") }
        if(state == STATE_DONE) { return string::make_no_len("Done") }
        if(state == STATE_FAILED) { return string::make_no_len("Failed") }
        if(state == STATE_CANCELLED) { return string::make_no_len("Cancelled") }
        return string::make_no_len("Unknown")
    }

} // end namespace cdm