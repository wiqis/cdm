// ChemicalDM — typed error codes and bridge result helpers.
//
// Instead of scattering raw error strings across the bridge, callers
// produce a CdmError which carries both a code and a human-readable
// message. The bridge converts these to JSON responses.

public namespace cdm {

using std::string;
using std::string_view;

    // All error categories in the app.
    public enum CdmErrorCode {
        // Success (not really an error, but keeps the enum contiguous).
        Ok = 0,
        // Client input errors (bad URL, missing field, out of range).
        InvalidUrl = 1,
        MissingParameter = 2,
        InvalidParameter = 3,
        // Queue / task errors.
        ItemNotFound = 10,
        DuplicateSkipped = 11,
        CannotRetryDone = 12,
        CannotEditRunning = 13,
        CannotChangeUrlRunning = 14,
        CannotRestartRunning = 15,
        // System / I/O errors.
        FileError = 20,
        NetworkError = 21,
        UnknownMethod = 30,
        JsonParseError = 31,
        // Settings errors.
        SettingsSaveFailed = 40,
        SettingsLoadFailed = 41
    }

    // A structured error with code + message.
    public struct CdmError {
        var code : CdmErrorCode
        var message : string

        @constructor func constructor() {
            return CdmError {
                code = CdmErrorCode.Ok,
                message = string()
            }
        }

        @constructor func make(c : CdmErrorCode, msg : string) {
            return CdmError {
                code = c,
                message = msg
            }
        }

        public func is_ok(&self) : bool {
            return self.code == CdmErrorCode.Ok
        }

        public func to_json(&self) : string {
            if(self.code == CdmErrorCode.Ok) {
                return ok_json()
            }
            return err_json(&self.message)
        }
    }

    // Convenience: create an Ok result (no error).
    public func cdm_ok() : CdmError {
        return CdmError()
    }

    // Convenience: create a failure result.
    public func cdm_err(code : CdmErrorCode, msg : string) : CdmError {
        return CdmError.make(code, msg)
    }

    // Convenience: create a failure from a message alone (defaults to InvalidParameter).
    public func cdm_err_msg(msg : string) : CdmError {
        return CdmError.make(CdmErrorCode.InvalidParameter, msg)
    }

    // ---- Human-readable state names (for UI consumption) ----

    // Map a CdmErrorCode to a user-facing label.
    public func error_code_name(c : CdmErrorCode) : string {
        if(c == CdmErrorCode.Ok) { return string::make_no_len("ok") }
        if(c == CdmErrorCode.InvalidUrl) { return string::make_no_len("invalid_url") }
        if(c == CdmErrorCode.MissingParameter) { return string::make_no_len("missing_parameter") }
        if(c == CdmErrorCode.InvalidParameter) { return string::make_no_len("invalid_parameter") }
        if(c == CdmErrorCode.ItemNotFound) { return string::make_no_len("item_not_found") }
        if(c == CdmErrorCode.DuplicateSkipped) { return string::make_no_len("duplicate_skipped") }
        if(c == CdmErrorCode.CannotRetryDone) { return string::make_no_len("cannot_retry_done") }
        if(c == CdmErrorCode.CannotEditRunning) { return string::make_no_len("cannot_edit_running") }
        if(c == CdmErrorCode.CannotChangeUrlRunning) { return string::make_no_len("cannot_change_url_running") }
        if(c == CdmErrorCode.CannotRestartRunning) { return string::make_no_len("cannot_restart_running") }
        if(c == CdmErrorCode.FileError) { return string::make_no_len("file_error") }
        if(c == CdmErrorCode.NetworkError) { return string::make_no_len("network_error") }
        if(c == CdmErrorCode.UnknownMethod) { return string::make_no_len("unknown_method") }
        if(c == CdmErrorCode.JsonParseError) { return string::make_no_len("json_parse_error") }
        if(c == CdmErrorCode.SettingsSaveFailed) { return string::make_no_len("settings_save_failed") }
        if(c == CdmErrorCode.SettingsLoadFailed) { return string::make_no_len("settings_load_failed") }
        return string::make_no_len("unknown")
    }

    // ---- JSON response helpers ----

    func ok_json() : string {
        return string::make_no_len("{\"ok\":true}")
    }

    func err_json(msg : &string) : string {
        var out = string::make_no_len("{\"ok\":false,\"error\":")
        out.append_string(&json_string(string_view::make_view(msg)))
        out.append('}')
        return out
    }

    // Build a success JSON with an extra field: {"ok":true,"id":"..."}.
    func ok_json_with_id(id : &string) : string {
        var out = string::make_no_len("{\"ok\":true,\"id\":")
        out.append_string(&json_string(string_view::make_view(id)))
        out.append('}')
        return out
    }

    // Build a success JSON with an extra integer field.
    func ok_json_with_int(key : string_view, value : int) : string {
        var out = string::make_no_len("{\"ok\":true,\"")
        out.append_view(&key)
        out.append_string(&string::make_no_len("\":"))
        var vs = string()
        vs.append_integer(value as bigint)
        out.append_string(&vs)
        out.append('}')
        return out
    }

} // end namespace cdm
