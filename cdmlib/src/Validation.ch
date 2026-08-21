// ChemicalDM — input validation helpers.
//
// Centralizes all validation logic so the bridge, CLI, and settings code
// share a single source of truth for what constitutes valid input.

public namespace cdm {

using std::string;
using std::string_view;

    // Result of a validation check.
    public struct ValidationError {
        var ok : bool
        var message : string

        @constructor func constructor() {
            return ValidationError {
                ok = true,
                message = string()
            }
        }

        @constructor func fail(msg : string) {
            return ValidationError {
                ok = false,
                message = msg
            }
        }

        public func is_ok(&self) : bool {
            return self.ok
        }

        public func error_message(&self) : string {
            return self.message.copy()
        }
    }

    // ---- URL validation ----

    // Validate that a URL string is non-empty, starts with http:// or https://,
    // and contains at least a host component.
    public func validate_url(url : string_view) : ValidationError {
        if(url.size() == 0) {
            return ValidationError.fail(string::make_no_len("URL is empty"))
        }
        var lower = string(url.data(), url.size())
        for(var i = 0u; i < lower.size(); i++) {
            var c = lower.get(i)
            if(c >= 'A' && c <= 'Z') {
                lower.set(i, (c + 32) as char)
            }
        }
        var lv = string_view::make_view(&lower)
        if(!lv.starts_with(string_view::make_no_len("http://")) &&
           !lv.starts_with(string_view::make_no_len("https://"))) {
            return ValidationError.fail(string::make_no_len("URL must start with http:// or https://"))
        }
        // Check there is something after the scheme (a host).
        var after_scheme : usize = 0
        if(lv.starts_with(string_view::make_no_len("https://"))) {
            after_scheme = 8u
        } else {
            after_scheme = 7u
        }
        if(after_scheme >= url.size()) {
            return ValidationError.fail(string::make_no_len("URL has no host"))
        }
        // Ensure the host part is not all slashes or empty.
        var host_has_alpha = false
        var i = after_scheme
        while(i < url.size()) {
            var c = url.get(i)
            if(c == '/' || c == '?' || c == '#') { break }
            if((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '.') {
                host_has_alpha = true
            }
            i = i + 1u
        }
        if(!host_has_alpha) {
            return ValidationError.fail(string::make_no_len("URL host is empty or invalid"))
        }
        return ValidationError()
    }

    // ---- Settings validation ----

    // Validate that max_concurrent is within acceptable bounds.
    public func validate_max_concurrent(v : int) : ValidationError {
        if(v < 1) {
            return ValidationError.fail(string::make_no_len("max_concurrent must be at least 1"))
        }
        if(v > 64) {
            return ValidationError.fail(string::make_no_len("max_concurrent must be at most 64"))
        }
        return ValidationError()
    }

    // Validate that max_segments is within acceptable bounds.
    public func validate_max_segments(v : int) : ValidationError {
        if(v < 1) {
            return ValidationError.fail(string::make_no_len("max_segments must be at least 1"))
        }
        if(v > 32) {
            return ValidationError.fail(string::make_no_len("max_segments must be at most 32"))
        }
        return ValidationError()
    }

    // Validate speed limit (KB/s).
    public func validate_speed_limit(v : i64) : ValidationError {
        if(v < 0) {
            return ValidationError.fail(string::make_no_len("speed_limit_kbps must be non-negative"))
        }
        if(v > 1048576) {
            return ValidationError.fail(string::make_no_len("speed_limit_kbps exceeds maximum (1 TB/s)"))
        }
        return ValidationError()
    }

    // Validate priority (0 = highest).
    public func validate_priority(v : int) : ValidationError {
        if(v < 0) {
            return ValidationError.fail(string::make_no_len("priority must be non-negative"))
        }
        if(v > 100) {
            return ValidationError.fail(string::make_no_len("priority must be at most 100"))
        }
        return ValidationError()
    }

    // Validate max_retries (-1 = infinite, 0 = no retry, positive =有限).
    public func validate_max_retries(v : int) : ValidationError {
        if(v < -1) {
            return ValidationError.fail(string::make_no_len("max_retries must be -1 (infinite) or non-negative"))
        }
        if(v > 100) {
            return ValidationError.fail(string::make_no_len("max_retries must be at most 100"))
        }
        return ValidationError()
    }

    // Validate retry delay (milliseconds).
    public func validate_retry_delay(v : i64) : ValidationError {
        if(v < 0) {
            return ValidationError.fail(string::make_no_len("retry_delay_ms must be non-negative"))
        }
        if(v > 60000) {
            return ValidationError.fail(string::make_no_len("retry_delay_ms must be at most 60000 (1 minute)"))
        }
        return ValidationError()
    }

    // Validate per-task speed limit (KB/s).
    public func validate_task_speed_limit(v : i64) : ValidationError {
        if(v < 0) {
            return ValidationError.fail(string::make_no_len("task speed limit must be non-negative"))
        }
        if(v > 1048576) {
            return ValidationError.fail(string::make_no_len("task speed limit exceeds maximum"))
        }
        return ValidationError()
    }

    // Validate duplicate_action (0=rename, 1=overwrite, 2=skip).
    public func validate_duplicate_action(v : int) : ValidationError {
        if(v < 0 || v > 2) {
            return ValidationError.fail(string::make_no_len("duplicate_action must be 0 (rename), 1 (overwrite), or 2 (skip)"))
        }
        return ValidationError()
    }

    // Validate a non-empty string field (e.g. download dir, filename).
    public func validate_not_empty(value : string_view, field_name : string_view) : ValidationError {
        if(value.size() == 0) {
            var msg = string(field_name.data(), field_name.size())
            msg.append_view(string_view::make_no_len(" cannot be empty"))
            return ValidationError.fail(msg)
        }
        return ValidationError()
    }

    // Validate that a directory path looks reasonable (not all whitespace,
    // no embedded null bytes).
    public func validate_directory(path : string_view) : ValidationError {
        if(path.size() == 0) {
            return ValidationError.fail(string::make_no_len("directory path is empty"))
        }
        for(var i = 0u; i < path.size(); i++) {
            if(path.get(i) == '\0') {
                return ValidationError.fail(string::make_no_len("directory path contains null byte"))
            }
        }
        return ValidationError()
    }

    // Validate category name string (must match a known category).
    public func validate_category_name(cat_name : string_view) : ValidationError {
        if(cat_name.size() == 0) {
            return ValidationError()  // empty => Other (default)
        }
        var other = string_view::make_no_len("Other")
        var docs = string_view::make_no_len("Documents")
        var progs = string_view::make_no_len("Programs")
        var video = string_view::make_no_len("Video")
        var music = string_view::make_no_len("Music")
        var comp = string_view::make_no_len("Compressed")
        if(cat_name.equals(&other)) { return ValidationError() }
        if(cat_name.equals(&docs)) { return ValidationError() }
        if(cat_name.equals(&progs)) { return ValidationError() }
        if(cat_name.equals(&video)) { return ValidationError() }
        if(cat_name.equals(&music)) { return ValidationError() }
        if(cat_name.equals(&comp)) { return ValidationError() }
        var msg = string::make_no_len("unknown category: ")
        msg.append_view(&cat_name)
        return ValidationError.fail(msg)
    }

    // Validate a segment count for add_task_ex.
    public func validate_segments(v : int) : ValidationError {
        if(v < 0) {
            return ValidationError.fail(string::make_no_len("segments must be non-negative"))
        }
        if(v > 32) {
            return ValidationError.fail(string::make_no_len("segments must be at most 32"))
        }
        return ValidationError()
    }

} // end namespace cdm
