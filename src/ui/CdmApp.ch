// ChemicalDM — the webview UI, a single universal component.
// SSR renders the empty shell; after hydration it polls the native engine over
// the webview bridge every second and re-renders the live queue. 
// Bridges (window.webview_bridge.call(method, argsJson) -> JSON):
//   state, add, pause, resume, cancel, remove, remove_file, retry, restart,
//   edit, settings_get, settings_set, open_file, show_in_folder,
//   yt_status, yt_install, yt_info, yt_download, yt_download_playlist

#universal CdmApp(props) {
    state items = []
    state newUrl = ""
    state alert = ""
    state loading = true
    state settings = null
    state showSettings = false
    state filter = "All"          // All | Active | Done | Failed | Paused
    state catFilter = "All"       // All | Other | Documents | Programs | Video | Music | Compressed
    state searchQuery = ""
    state sortBy = "newest"       // newest | oldest | name | size
    state addOpen = false
    state addUrl = ""
    state addDir = ""
    state addName = ""
    state addCategory = "Other"
    state addPriority = "0"
    state addSpeedLimit = "0"
    // Change URL dialog state
    state changeUrlOpen = false
    state changeUrlItem = null
    state changeUrlValue = ""
    // Context menu state
    state ctxOpen = false
    state ctxX = 0
    state ctxY = 0
    state ctxItem = null
    // YouTube download state
    state ytOpen = false
    state ytUrl = ""
    state ytInfo = null           // fetched video/playlist info
    state ytLoading = false
    state ytError = ""
    state ytSelectedFormat = ""
    state ytSelectedAudio = "best"
    state ytFormatMode = "merged"
    state ytAudioExpanded = false
    state ytAutoMerge = true
    state ytDeleteSeparate = true
    state ytDownloading = false
    state ytMinQuality = 0
    state ytMaxQuality = 0
    state ytPlaylistEntries = []
    state ytPlaylistSelected = []  // indices of selected entries
    // Async download progress state
    state ytDlProgress = 0
    state ytDlSpeed = ""
    state ytDlEta = ""
    state ytDlStatus = ""
    state ytDlTitle = ""
    state ytDlError = ""
    state ytDlDone = false
    state ytDlVideoId = ""
    state ytDlAudioId = ""
    state ytDlMergeStatus = ""
    state ytDlMergeError = ""
    state ytDlNeedsMerge = false
    state ytDlContainerId = ""
    state ytPlProgress = 0
    state ytPlSpeed = ""
    state ytPlEta = ""
    state ytPlStatus = ""
    state ytPlItemsDone = 0
    state ytPlItemsTotal = 0
    state ytPlCurrentTitle = ""
    state ytPlError = ""
    state ytPlDone = false
    state ytPlVideos = []        // per-item status from the backend poll
    state ytPlContainerId = ""   // id of the PLAYLIST container card currently being polled
    state ytPlExpanded = {}      // index -> bool (expanded detail view)
    state ytPlMaxRetries = 3     // retries per video on link/merge failure
    state ytInfoPollId = null
    state ytDlPollId = null
    state ytPlPollId = null
    // Tool setup state
    state ytToolsOpen = false
    state ytTools = null           // {yt_dlp: {...}, ffmpeg: {...}}
    state ytToolsRaw = ""          // raw yt_status JSON for diagnostics (copy/paste)
    state ytInstallingTool = ""
    state ytInstallProgress = 0
    // Toast state
    state toastMsg = ""
    state toastType = "info"      // info | success | error
    state toastVisible = false
    // Button debounce state
    state busy = false

    // Sidebar navigation drives the same filter state as the old chips.
    var navPick = (f) => { filter = f; catFilter = "All" }

    var isUrl = (s) => {
        var t = s.trim().toLowerCase()
        return t.startsWith("http://") || t.startsWith("https://")
    }

    var pasteFromClipboard = () => {
        if(!navigator.clipboard) {
            alert = "Clipboard not available"
            return
        }
        navigator.clipboard.readText().then((text) => {
            if(text && isUrl(text)) {
                addUrl = text.trim()
                addDir = ""
                addName = ""
                addCategory = "Other"
                addPriority = "0"
                addSpeedLimit = "0"
                addOpen = true
            } else if(text) {
                alert = "Clipboard does not contain a URL"
            } else {
                alert = "Clipboard is empty"
            }
        }).catch(() => { alert = "Could not read clipboard" })
    }

    // Async bridge helper: calls webview_bridge.call and handles the Promise.
    // When debounce=true, sets busy=true during the call to prevent rapid re-submits.
    var asyncBridge = (method, body, onResult, debounce) => {
        if(debounce) { busy = true }
        window.webview_bridge.call(method, body || "{}").then(function(v) {
            if(debounce) { busy = false }
            onResult(v)
        }).catch(function(e) {
            if(debounce) { busy = false }
            console.error("[CDM-JS] bridge error for " + method + ": " + e)
            showToast("Bridge error: " + method, "error")
        })
    }

    // Route JS diagnostics to the terminal (native stderr) via the debug_log bridge.
    var jsLog = (msg) => {
        try { window.webview_bridge.call("debug_log", JSON.stringify({ msg: String(msg) })) } catch(e) {}
    }

    var refresh = () => {
        asyncBridge("state", "{}", function(d) {
            if(d && d.items) { items = d.items }
            loading = false
        })
    }

    var refreshSettings = () => {
        asyncBridge("settings_get", "{}", function(d) {
            if(d) { settings = d }
        })
    }

    useEffect(() => {
        refresh()
        refreshSettings()
        refreshTools()
        var t = setInterval(refresh, 1000)
        var alertTimer = null
        var watchAlert = () => {
            if(alert !== "") {
                if(alertTimer) { clearTimeout(alertTimer) }
                alertTimer = setTimeout(() => { alert = ""; alertTimer = null }, 5000)
            }
        }
        var closeCtx = (e) => {
            if(!ctxOpen) return
            var menuEl = e.target.closest && e.target.closest('.cdm-ctx-menu')
            if(menuEl) return
            ctxOpen = false
        }
        var onKeydown = (e) => {
            if(e.key === "Escape") {
                if(ctxOpen) { ctxOpen = false }
                else if(showSettings) { showSettings = false }
                else if(addOpen) { addOpen = false }
                else if(changeUrlOpen) { changeUrlOpen = false }
                else if(ytOpen && !ytLoading && !ytDownloading) { ytOpen = false }
                else if(ytToolsOpen) { ytToolsOpen = false }
            }
            // Focus trap: keep Tab inside the topmost dialog
            if(e.key === "Tab") {
                var overlay = document.querySelector('.cdm-dialog-overlay:last-of-type')
                if(!overlay) return
                var dialog = overlay.querySelector('.cdm-dialog')
                if(!dialog) return
                var focusable = dialog.querySelectorAll('button:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])')
                if(focusable.length === 0) return
                var first = focusable[0]
                var last = focusable[focusable.length - 1]
                if(e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus() }
                else if(!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus() }
            }
        }
        document.addEventListener("mousedown", closeCtx)
        document.addEventListener("keydown", onKeydown)
        return () => {
            clearInterval(t)
            if(alertTimer) { clearTimeout(alertTimer) }
            document.removeEventListener("mousedown", closeCtx)
            document.removeEventListener("keydown", onKeydown)
            if(ytInfoPollId) { clearInterval(ytInfoPollId) }
            if(ytDlPollId) { clearInterval(ytDlPollId) }
            if(ytPlPollId) { clearInterval(ytPlPollId) }
        }
    }, [])

    var post = (method, id, extra) => {
        var body = extra || {}
        body.id = id
        asyncBridge(method, JSON.stringify(body), function(d) {
            if(d && !d.ok) { alert = d.error || "Operation failed" }
            refresh()
        }, true)
    }

    var call = (method, body, onDone) => {
        asyncBridge(method, JSON.stringify(body || {}), function(d) {
            if(d && !d.ok) { showToast(d.error || "Operation failed", "error") }
            refresh()
            if(onDone) { onDone(d) }
        }, true)
    }

    var addDownload = () => {
        var u = addUrl.trim() || newUrl.trim()
        if(u === "" || busy) return
        var body = { url: u }
        if(addDir.trim() !== "") body.dir = addDir.trim()
        if(addName.trim() !== "") body.filename = addName.trim()
        if(addCategory !== "Other") body.category = addCategory
        var p = parseInt(addPriority)
        if(!isNaN(p) && p >= 0) body.priority = p
        var sl = parseInt(addSpeedLimit)
        if(!isNaN(sl) && sl > 0) body.speed_limit_kbps = sl
        asyncBridge("add", JSON.stringify(body), function(d) {
            if(d && d.ok) {
                newUrl = ""; addUrl = ""; addDir = ""; addName = ""; addCategory = "Other"; addPriority = "0"; addSpeedLimit = "0"
                addOpen = false; alert = ""
            } else {
                alert = (d && d.error) || "Failed to add download"
            }
            refresh()
        }, true)
    }

    var applySettings = () => {
        if(!settings) return
        // settings_get always returns all fields, so no || fallback needed.
        // Using || would incorrectly override 0 values (e.g. connect_timeout=0).
        var body = {
            download_dir: settings.download_dir,
            max_concurrent: settings.max_concurrent,
            max_segments: settings.max_segments,
            speed_limit_kbps: settings.speed_limit_kbps,
            duplicate_action: settings.duplicate_action,
            enable_resume: settings.enable_resume,
            allow_segments: settings.allow_segments,
            use_categories: settings.use_categories,
            auto_resume_failed: settings.auto_resume_failed,
            max_retries: settings.max_retries,
            retry_delay_ms: settings.retry_delay_ms,
            user_agent: settings.user_agent,
            cookie_file: settings.cookie_file,
            verify_ssl: settings.verify_ssl,
            connect_timeout: settings.connect_timeout,
            max_download_size: settings.max_download_size,
            min_disk_space_mb: settings.min_disk_space_mb,
            post_download_cmd: settings.post_download_cmd,
            yt_quality: settings.yt_quality,
            yt_format: settings.yt_format,
            yt_audio_only: settings.yt_audio_only,
            yt_max_playlist_items: settings.yt_max_playlist_items,
            yt_playlist_start: settings.yt_playlist_start || 0,
            yt_playlist_end: settings.yt_playlist_end || 0,
            yt_playlist_items: settings.yt_playlist_items || "",
            referer_header: settings.referer_header,
            auth_header: settings.auth_header,
            force_ipv4: settings.force_ipv4,
            force_ipv6: settings.force_ipv6,
            filename_template: settings.filename_template,
            checksum: settings.checksum,
            notifications_enabled: settings.notifications_enabled,
            language: settings.language,
            max_history: settings.max_history,
            theme: settings.theme,
            yt_output_template: settings.yt_output_template,
            yt_audio_format: settings.yt_audio_format,
            yt_audio_quality: settings.yt_audio_quality,
            yt_recode_video: settings.yt_recode_video,
            yt_merge_output_format: settings.yt_merge_output_format,
            yt_write_subs: settings.yt_write_subs,
            yt_write_auto_subs: settings.yt_write_auto_subs,
            yt_sub_langs: settings.yt_sub_langs,
            yt_embed_subs: settings.yt_embed_subs,
            yt_convert_subs: settings.yt_convert_subs,
            yt_embed_metadata: settings.yt_embed_metadata,
            yt_embed_thumbnail: settings.yt_embed_thumbnail,
            yt_write_description: settings.yt_write_description,
            yt_write_info_json: settings.yt_write_info_json,
            yt_write_comments: settings.yt_write_comments,
            yt_restrict_filenames: settings.yt_restrict_filenames,
            yt_trim_filenames: settings.yt_trim_filenames,
            yt_no_overwrites: settings.yt_no_overwrites,
            yt_proxy: settings.yt_proxy,
            yt_geo_bypass: settings.yt_geo_bypass,
            yt_geo_bypass_country: settings.yt_geo_bypass_country,
            yt_extractor_retries: settings.yt_extractor_retries,
            yt_socket_timeout: settings.yt_socket_timeout,
            yt_exec_cmd: settings.yt_exec_cmd,
            yt_ffmpeg_location: settings.yt_ffmpeg_location,
            yt_remove_sponsorblock: settings.yt_remove_sponsorblock,
            yt_sponsorblock_mark: settings.yt_sponsorblock_mark,
            yt_source_address: settings.yt_source_address,
            yt_legacy_server_connect: settings.yt_legacy_server_connect,
            yt_no_check_certificates: settings.yt_no_check_certificates,
            ffmpeg_video_codec: settings.ffmpeg_video_codec,
            ffmpeg_audio_codec: settings.ffmpeg_audio_codec,
            ffmpeg_audio_bitrate: settings.ffmpeg_audio_bitrate,
            bandwidth_limit_per: settings.bandwidth_limit_per,
            auto_rename_duplicates: settings.auto_rename_duplicates,
            move_completed_to: settings.move_completed_to,
            clipboard_monitor: settings.clipboard_monitor,
            proxy_host: settings.proxy_host,
            proxy_port: settings.proxy_port
        }
        call("settings_set", body, function(d) {
            if(d && d.ok) {
                alert = "Settings saved"
                showSettings = false
            }
            refreshSettings()
        })
    }

    // Edit one settings field in the draft. Used by Reset buttons.
    var resetField = (key) => {
        if(!settings) return
        settings[key] = ""
        if(key === "connect_timeout" || key === "yt_socket_timeout") { settings[key] = 30 }
        if(key === "yt_extractor_retries") { settings[key] = 3 }
        if(key === "max_retries") { settings[key] = 5 }
        if(key === "retry_delay_ms") { settings[key] = 5000 }
        if(key === "max_segments") { settings[key] = 4 }
        if(key === "max_concurrent") { settings[key] = 3 }
        if(key === "speed_limit_kbps" || key === "bandwidth_limit_per" || key === "max_download_size" || key === "min_disk_space_mb" || key === "max_history" || key === "yt_max_playlist_items" || key === "yt_trim_filenames" || key === "proxy_port") { settings[key] = 0 }
    }

    // ---- YouTube functions ----
    var showToast = (msg, type) => {
        toastMsg = msg
        toastType = type || "info"
        toastVisible = true
        setTimeout(() => { toastVisible = false }, 4000)
    }

    // Clipboard helper: navigator.clipboard often silently fails inside a WebKit
    // webview (no secure context / focus / permission), so fall back to the
    // legacy execCommand("copy") path which works synchronously here.
    var copyText = (txt) => {
        try {
            if(navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(txt)
                return
            }
        } catch (e) { }
        try {
            var ta = document.createElement("textarea")
            ta.value = txt
            ta.style.position = "fixed"
            ta.style.opacity = "0"
            document.body.appendChild(ta)
            ta.select()
            document.execCommand("copy")
            document.body.removeChild(ta)
        } catch (e) { }
    }

    var toolsFallback = () => ({
        yt_dlp: { name: "yt-dlp", status: "not_installed", version: "", path: "", error: "", progress: 0 },
        ffmpeg: { name: "ffmpeg", status: "not_installed", version: "", path: "", error: "", progress: 0 },
        both_ready: false
    })

    // Fetch yt-dlp/ffmpeg install status. The Tools tab must NEVER stay stuck on
    // "checking...": if the bridge call throws synchronously (bridge not ready) or
    // its promise never resolves, we keep a safe fallback instead of leaving
    // `ytTools` null. The real status replaces the fallback as soon as the bridge
    // responds.
    //
    // NOTE: the webview framework already parses the native JSON string into a JS
    // object before resolving the promise (every other `asyncBridge` consumer here
    // reads `d.items`/`d.x` directly, not a string). So do NOT `JSON.parse` the
    // result here — parsing an already-parsed object throws and the silent catch
    // would leave `ytTools` stuck on the "not_installed" fallback forever. Only
    // parse if we somehow get a raw string.
    var refreshTools = () => {
        if(!ytTools) { ytTools = toolsFallback() }
        try {
            window.webview_bridge.call("yt_status", "{}")
                .then(function(res) {
                    try {
                        var r = (typeof res === "string") ? JSON.parse(res) : res
                        ytToolsRaw = (typeof res === "string") ? res : JSON.stringify(res)
                        if(r && r.yt_dlp) { ytTools = r }
                    } catch (e) {
                        ytToolsRaw = "[refreshTools parse error] " + (e && e.message ? e.message : e)
                        if(window.__reportError) { window.__reportError("yt_status parse failed: " + (e && e.message ? e.message : e), (e && e.stack) ? e.stack : "") }
                    }
                })
                .catch(function(err) {
                    var msg = "[yt_status BRIDGE REJECTED] " + (err && err.message ? err.message : ("" + err))
                    ytToolsRaw = msg
                    if(window.__reportError) { window.__reportError(msg, (err && err.stack) ? err.stack : "") }
                })
        } catch (e) {
            ytToolsRaw = "[yt_status call threw] " + (e && e.message ? e.message : e)
            if(window.__reportError) { window.__reportError("yt_status call failed: " + (e && e.message ? e.message : e), (e && e.stack) ? e.stack : "") }
        }
    }

    var pollToolProgress = null

    var installTool = (toolName) => {
        console.log("[CDM-JS] installTool called for: " + toolName)
        ytInstallingTool = toolName
        ytInstallProgress = 0
        showToast("Installing " + toolName + "...", "info")
        console.log("[CDM-JS] calling yt_install bridge...")
        asyncBridge("yt_install", JSON.stringify({ tool: toolName }), function(d) {
            console.log("[CDM-JS] yt_install returned: " + JSON.stringify(d))
            if(!d || !d.ok) {
                ytInstallingTool = ""
                showToast("Failed to install " + toolName + ": " + ((d && d.error) || "unknown error"), "error")
                return
            }
            console.log("[CDM-JS] starting poll...")
            if(pollToolProgress) { clearInterval(pollToolProgress) }
            pollToolProgress = setInterval(() => {
                asyncBridge("yt_status", "{}", function(status) {
                    console.log("[CDM-JS] poll status: " + JSON.stringify(status))
                    var st = (typeof status === "string") ? JSON.parse(status) : status
                    var toolInfo = null
                    if(toolName === "yt-dlp" && st.yt_dlp) toolInfo = st.yt_dlp
                    if(toolName === "ffmpeg" && st.ffmpeg) toolInfo = st.ffmpeg
                    if(!toolInfo) {
                        if(window.__reportError) { window.__reportError("yt poll: no toolInfo for " + toolName + " (status was " + (typeof status) + ")") }
                        return
                    }
                    if(toolInfo.status === "downloading") {
                        ytInstallProgress = toolInfo.progress || 0
                        ytTools = st
                    } else if(toolInfo.status === "installed") {
                        clearInterval(pollToolProgress)
                        pollToolProgress = null
                        ytInstallingTool = ""
                        ytInstallProgress = 0
                        ytTools = st
                        showToast(toolName + " installed successfully!", "success")
                        refreshTools()
                    } else if(toolInfo.status === "error") {
                        clearInterval(pollToolProgress)
                        pollToolProgress = null
                        ytInstallingTool = ""
                        ytInstallProgress = 0
                        ytTools = st
                        showToast("Failed to install " + toolName + ": " + (toolInfo.error || "unknown error"), "error")
                    }
                })
            }, 500)
        })
    }

    var openYtDownload = () => {
        ytUrl = ""
        ytInfo = null
        ytError = ""
        ytSelectedFormat = "best"
        ytSelectedAudio = "best"
        ytFormatMode = "merged"
        ytAudioExpanded = false
        ytAutoMerge = true
        ytDeleteSeparate = true
        ytDownloading = false
        ytPlaylistEntries = []
        ytPlaylistSelected = []
        ytOpen = true
        refreshTools()
    }

    var fmtVideoLabel = (fmt) => {
        var hasVid = fmt.vcodec && fmt.vcodec !== "none"
        var hasAud = fmt.acodec && fmt.acodec !== "none"
        var combined = hasVid && hasAud
        var lbl = fmt.format_note || ""
        if(fmt.height > 0) { lbl = fmt.height + "p" }
        if(fmt.fps > 30) { lbl += " " + fmt.fps + "fps" }
        if(combined) { lbl += " (audio+video)" }
        else if(hasVid && !hasAud) { lbl += " [video only]" }
        else if(!hasVid && hasAud) { lbl += " [audio only]" }
        if(fmt.ext) { lbl += " \u2022 " + fmt.ext }
        return lbl
    }
    var fmtVideoSize = (fmt) => {
        if(fmt.filesize > 0) { return (fmt.filesize / 1048576).toFixed(1) + " MB" }
        if(fmt.filesize_approx > 0) { return "~" + (fmt.filesize_approx / 1048576).toFixed(1) + " MB" }
        return fmt.format_id
    }

    var fmtAudioLabel = (fmt) => {
        var lbl = ""
        if(fmt.abr && fmt.abr > 0) { lbl = fmt.abr + " kbps" }
        if(fmt.acodec && fmt.acodec != "none") { lbl += " \u2022 " + fmt.acodec }
        if(fmt.ext) { lbl += " \u2022 " + fmt.ext }
        return lbl || fmt.format_id
    }

    var pollYtInfo = () => {
        asyncBridge("yt_info_poll", "{}", function(d) {
            jsLog("pollYtInfo typeof(d)=" + typeof d + " d=" + (typeof d === "string" ? d : JSON.stringify(d)))
            if(d.done) {
                if(ytInfoPollId) { clearInterval(ytInfoPollId); ytInfoPollId = null }
                if(d.error) {
                    ytLoading = false
                    ytError = d.error
                    return
                }
                // Done — fetch the full info in a separate bridge call.
                // The webview library automatically chunks large responses.
                if(d.has_info) {
                    asyncBridge("yt_info_get", "{}", function(infoJson) {
                        jsLog("yt_info_get callback fired, typeof=" + typeof infoJson + " len=" + (infoJson ? infoJson.length : 0))
                        ytLoading = false
                        try {
                            var parsed = (typeof infoJson === "string") ? JSON.parse(infoJson) : infoJson
                            ytInfo = parsed
                            ytSelectedFormat = "best"
                            jsLog("ytInfo set, title=" + (parsed ? (parsed.title || "?") : "null") + " is_playlist=" + (parsed ? parsed.is_playlist : "?"))
                            if(parsed.is_playlist && parsed.entries) {
                                ytPlaylistEntries = parsed.entries
                                ytPlaylistSelected = parsed.entries.map((_, i) => i)
                            }
                        } catch(e) {
                            ytError = "Failed to parse video info: " + e.message
                            jsLog("yt_info_get parse error: " + e.message)
                        }
                    })
                } else {
                    ytLoading = false
                }
            }
        })
    }

    var pollYtDownload = () => {
        asyncBridge("yt_download_poll", "{}", function(d) {
            ytDlProgress = d.progress || 0
            ytDlSpeed = d.speed || ""
            ytDlEta = d.eta || ""
            ytDlStatus = d.status || ""
            ytDlVideoId = d.video_task_id || ""
            ytDlAudioId = d.audio_task_id || ""
            ytDlMergeStatus = d.merge_status || ""
            ytDlMergeError = d.merge_error || ""
            ytDlNeedsMerge = d.needs_merge || false
            if(d.container_id) { ytDlContainerId = d.container_id }
            if(d.title) { ytDlTitle = d.title }
            // Keep polling while merge is in progress (waiting or merging).
            if(d.needs_merge && (d.merge_status === "waiting" || d.merge_status === "merging")) {
                return
            }
            if(d.done) {
                if(ytDlPollId) { clearInterval(ytDlPollId); ytDlPollId = null }
                ytDownloading = false
                if(d.error && !d.needs_merge) {
                    ytDlError = d.error
                    showToast("Download failed: " + d.error, "error")
                } else if(d.merge_status === "merged") {
                    ytDlDone = true
                    showToast("Download merged successfully", "success")
                    refresh()
                } else if(d.merge_status === "failed") {
                    ytDlDone = true
                    showToast("Merge failed: " + (d.merge_error || "unknown"), "error")
                    refresh()
                } else {
                    ytDlDone = true
                    showToast("Download complete", "success")
                    refresh()
                }
            }
        })
    }

    var pollYtPlaylist = () => {
        asyncBridge("yt_download_playlist_poll", "{}", function(d) {
            ytPlProgress = d.progress || 0
            ytPlSpeed = d.speed || ""
            ytPlEta = d.eta || ""
            ytPlItemsDone = d.items_done || 0
            ytPlItemsTotal = d.items_total || 0
            if(d.videos) {
                ytPlVideos = d.videos
            }
            if(d.container_id) { ytPlContainerId = d.container_id }
            if(d.done) {
                if(ytPlPollId) { clearInterval(ytPlPollId); ytPlPollId = null }
                ytDownloading = false
                if(d.error) {
                    ytPlError = d.error
                    showToast("Playlist download failed: " + d.error, "error")
                } else {
                    ytPlDone = true
                    showToast("Playlist download complete!", "success")
                    refresh()
                }
            }
        })
    }

    var cancelYtInfo = () => {
        asyncBridge("yt_cancel", "{}", function(d) {
            ytLoading = false
            if(ytInfoPollId) { clearInterval(ytInfoPollId); ytInfoPollId = null }
            showToast("Info fetch cancelled", "info")
        })
    }

    var cancelYtDownload = () => {
        asyncBridge("yt_cancel", "{}", function(d) {
            ytDownloading = false
            if(ytDlPollId) { clearInterval(ytDlPollId); ytDlPollId = null }
            if(ytPlPollId) { clearInterval(ytPlPollId); ytPlPollId = null }
            showToast("Download cancelled", "info")
        })
    }

    var fetchYtInfo = () => {
        var u = ytUrl.trim()
        if(u === "") return
        if(!ytTools || (!ytTools.yt_dlp || !ytTools.yt_dlp.status || ytTools.yt_dlp.status !== "installed")) {
            ytError = "yt-dlp is not installed. Open Setup Tools to install it."
            return
        }
        ytLoading = true
        ytError = ""
        ytInfo = null
        asyncBridge("yt_info", JSON.stringify({ url: u }), function(d) {
            if(d.error) {
                ytLoading = false
                ytError = d.error
                return
            }
            if(ytInfoPollId) { clearInterval(ytInfoPollId) }
            ytInfoPollId = setInterval(pollYtInfo, 500)
            pollYtInfo()
        })
    }

    var startYtDownload = () => {
        if(!ytInfo) return
        ytDownloading = true
        ytError = ""
        ytDlProgress = 0
        ytDlSpeed = ""
        ytDlEta = ""
        ytDlStatus = ""
        var u = ytUrl.trim()
        var fmt = ytSelectedFormat || "best"
        // Never download an HLS (m3u8) format directly — the HTTP engine can't
        // fetch playlists; yt-dlp is required for those. Fall back to "best".
        if(fmt !== "best" && ytInfo && ytInfo.formats) {
            var sel = ytInfo.formats.find((f) => f.format_id === fmt)
            if(sel && sel.protocol && (sel.protocol.indexOf("m3u8") >= 0 || sel.protocol.indexOf("hls") >= 0)) {
                fmt = "best"
            }
        }
        var audioFmt = ytSelectedAudio || "best"
        var mode = ytFormatMode || "merged"
        if(ytInfo.is_playlist) {
            ytPlVideos = []
            ytPlExpanded = {}
            var body = { url: u, format: fmt, mode: mode, audio_format: audioFmt, min_quality: ytMinQuality, max_quality: ytMaxQuality, max_retries: ytPlMaxRetries, auto_merge: ytAutoMerge, delete_separate: ytDeleteSeparate }
            asyncBridge("yt_download_playlist", JSON.stringify(body), function(d) {
                if(d.error) {
                    ytDownloading = false
                    ytError = d.error
                    showToast("Playlist download failed: " + d.error, "error")
                    return
                }
                // Close dialog immediately — download runs in background.
                // Keep ytDownloading = true so the main list stays suppressed
                // until pollYtPlaylist (d.done) clears it.
                ytOpen = false
                showToast("Playlist download queued", "success")
                if(ytPlPollId) { clearInterval(ytPlPollId) }
                ytPlPollId = setInterval(pollYtPlaylist, 1000)
                pollYtPlaylist()
                refresh()
            })
        } else {
            var body = { url: u, format: fmt, mode: mode, audio_format: audioFmt, min_quality: ytMinQuality, max_quality: ytMaxQuality, auto_merge: ytAutoMerge, delete_separate: ytDeleteSeparate }
            asyncBridge("yt_download", JSON.stringify(body), function(d) {
                if(d.error) {
                    ytDownloading = false
                    ytError = d.error
                    showToast("Download failed: " + d.error, "error")
                    return
                }
                // Close dialog immediately — download runs in DM background
                ytOpen = false
                ytDownloading = false
                showToast("Download queued in main queue", "success")
                if(ytDlPollId) { clearInterval(ytDlPollId) }
                ytDlPollId = setInterval(pollYtDownload, 1000)
                pollYtDownload()
                refresh()
            })
        }
    }

    var togglePlaylistEntry = (idx) => {
        var pos = ytPlaylistSelected.indexOf(idx)
        if(pos === -1) {
            ytPlaylistSelected = ytPlaylistSelected.concat([idx])
        } else {
            ytPlaylistSelected = ytPlaylistSelected.filter(i => i !== idx)
        }
    }

    var selectAllPlaylist = () => {
        ytPlaylistSelected = ytPlaylistEntries.map((_, i) => i)
    }

    var deselectAllPlaylist = () => {
        ytPlaylistSelected = []
    }

    var fmtBytes = (b) => {
        if(b == null) b = 0
        if(b >= 1073741824) return (b / 1073741824).toFixed(2) + " GB"
        if(b >= 1048576) return (b / 1048576).toFixed(2) + " MB"
        if(b >= 1024) return (b / 1024).toFixed(1) + " KB"
        return b + " B"
    }

    var fmtSpeed = (bps) => {
        if(bps == null) bps = 0
        if(bps <= 0) return ""
        return fmtBytes(bps) + "/s"
    }

    var stateClass = (s) => "cdm-badge " +
        (s === "Downloading" ? "cdm-badge-active" :
         s === "Done" ? "cdm-badge-done" :
         (s === "Failed" || s === "Cancelled") ? "cdm-badge-error" :
         "cdm-badge-idle")

    // Category -> neutral file icon class (theme renders the glyph).
    var tileClass = (cat) => "cdm-ficon cdm-ficon-" +
        (cat === "Documents" ? "documents" :
         cat === "Programs" ? "programs" :
         cat === "Video" ? "video" :
         cat === "Music" ? "music" :
         cat === "Compressed" ? "compressed" :
         "other")
    var ytPlayTile = "cdm-ficon cdm-ficon-yt"

    var renderSegments = (segs) => {
        return <div class="cdm-segments">
            {segs.map((seg) => {
                var segPct = seg.total > 0 ? (seg.copied * 100 / seg.total) : 0
                var segClass = seg.done ? "cdm-seg-done" : (seg.copied > 0 ? "cdm-seg-active" : "cdm-seg-pending")
                return <div class={"cdm-seg " + segClass}
                    title={"Seg " + seg.index + ": " + fmtBytes(seg.copied) + " / " + fmtBytes(seg.total)}
                    style={"width:" + (100 / segs.length) + "%;"}>
                    <div class="cdm-seg-fill" style={"width:" + segPct + "%;"}></div>
                </div>
            })}
        </div>
    }

    var filterMatches = (s, cat) => {
        if(filter === "Active") {
            if(s !== "Downloading" && s !== "Queued") return false
        } else if(filter === "Done") {
            if(s !== "Done") return false
        } else if(filter === "Failed") {
            if(s !== "Failed" && s !== "Cancelled") return false
        } else if(filter === "Paused") {
            if(s !== "Paused") return false
        }
        if(catFilter !== "All") {
            if(cat !== catFilter) return false
        }
        return true
    }

    var openContextMenu = (e, item) => {
        e.preventDefault()
        e.stopPropagation()
        ctxX = e.clientX
        ctxY = e.clientY
        ctxItem = item
        ctxOpen = true
    }

    var ctxAction = (method) => {
        if(!ctxItem) return
        if(method === "open_file") {
            var path = ctxItem.dir + "/" + (ctxItem.display_name || ctxItem.filename)
            asyncBridge("open_file", JSON.stringify({ path: path }), function(d) {
                if(d && !d.ok) {
                    showToast(d.error || "Could not open file", "error")
                }
                refresh()
            })
        } else if(method === "show_in_folder") {
            call("show_in_folder", { path: ctxItem.dir })
        } else {
            post(method, ctxItem.id)
        }
        ctxOpen = false
    }

    var CARD_NORMAL = 0
    var CARD_PLAYLIST = 1
    var CARD_YT_SINGLE = 2
    var CARD_YT_CHILD = 3
    // Children (video/audio streams of a playlist / single-YT job) are real DM
    // tasks, but they live NESTED inside their parent card — never as top-level
    // cards. Top-level cards are NORMAL, PLAYLIST, or YT_SINGLE.
    var mainItems = items.filter((u) => u.card_type !== CARD_YT_CHILD)
    var visibleItems = mainItems.filter((u) => {
        if(!filterMatches(u.state, u.category)) return false
        if(searchQuery.trim() !== "") {
            var q = searchQuery.trim().toLowerCase()
            var name = (u.display_name || u.filename || "").toLowerCase()
            var url = (u.url || "").toLowerCase()
            if(name.indexOf(q) === -1 && url.indexOf(q) === -1) return false
        }
        return true
    })

    // Sort
    visibleItems.sort((a, b) => {
        if(sortBy === "newest") return (b.created_at || 0) - (a.created_at || 0)
        if(sortBy === "oldest") return (a.created_at || 0) - (b.created_at || 0)
        if(sortBy === "name") {
            var na = (a.display_name || a.filename || "").toLowerCase()
            var nb = (b.display_name || b.filename || "").toLowerCase()
            return na > nb ? 1 : (na < nb ? -1 : 0)
        }
        if(sortBy === "size") return (b.total_bytes || 0) - (a.total_bytes || 0)
        return 0
    })
        var totalCount = mainItems.length
        var activeCount = mainItems.filter((u) => u.state === "Downloading").length
        var doneCount = mainItems.filter((u) => u.state === "Done").length
        var pausedCount = mainItems.filter((u) => u.state === "Paused").length
        var failedCount = mainItems.filter((u) => u.state === "Failed" || u.state === "Cancelled").length
        var catCount = (c) => mainItems.filter((u) => u.category === c).length

        // Sidebar navigation model (filter + live counts).
        var sidebarNav = [
            { filter: "All", label: "All", icon: "cdm-ic-inbox", count: totalCount },
            { filter: "Active", label: "Active", icon: "cdm-ic-download", count: activeCount },
            { filter: "Paused", label: "Paused", icon: "cdm-ic-pause", count: pausedCount },
            { filter: "Done", label: "Done", icon: "cdm-ic-check", count: doneCount },
            { filter: "Failed", label: "Failed", icon: "cdm-ic-alert", count: failedCount }
        ]
        var sidebarCats = [
            { name: "Documents", label: "Documents", icon: "cdm-ic-file", count: catCount("Documents") },
            { name: "Programs", label: "Programs", icon: "cdm-ic-terminal", count: catCount("Programs") },
            { name: "Video", label: "Video", icon: "cdm-ic-film", count: catCount("Video") },
            { name: "Music", label: "Music", icon: "cdm-ic-music", count: catCount("Music") },
            { name: "Compressed", label: "Compressed", icon: "cdm-ic-archive", count: catCount("Compressed") }
        ]

        // --- Shared nested-row renderer (used by playlist + single-YT cards) ---
        var ytStreamRow = (it, label) => {
            if(!it) return null
            var p = parseFloat(it.percent); if(isNaN(p)) p = 0; if(p < 0) p = 0; if(p > 100) p = 100
            var showProg = it.state === "Downloading" || it.state === "Paused"
            var failed = it.state === "Failed" || it.state === "Cancelled"
            var segs = []
            if(it.segments && it.segments.length > 0) { segs = it.segments }
            var hasSegs = segs.length > 1
            return <div class={"cdm-yt-row" + (failed ? " cdm-yt-row-error" : "")}>
                <div class="cdm-yt-row-head">
                    <span class="cdm-yt-row-label">{label}</span>
                    <span class="cdm-yt-row-name" title={it.url}>{it.display_name || it.filename}</span>
                    <span class={stateClass(it.state)}>{it.state}</span>
                </div>
                {showProg ? <div class="cdm-progress"><div class="cdm-progress-fill" style={"width: " + p + "%;"}></div></div> : null}
                {showProg && hasSegs ? renderSegments(segs) : null}
                <div class="cdm-item-meta">
                    <span>{fmtBytes(it.downloaded_bytes)} / {it.total_bytes >= 0 ? fmtBytes(it.total_bytes) : "?"}</span>
                    <span class="cdm-item-pct">{p.toFixed(1)}%</span>
                    <span class="cdm-item-speed">{fmtSpeed(it.speed_bytes_per_sec)}</span>
                    <span class="cdm-item-eta">{it.eta !== "" && showProg ? it.eta : ""}</span>
                </div>
            </div>
        }

        // --- PLAYLIST card: a container whose children render nested inside it ---
        var renderPlaylistCard = (item) => {
            var isActive = item.id === ytPlContainerId
            var videos = isActive ? ytPlVideos : []
            var sorted = videos.slice().sort((a, b) => (a.index || 0) - (b.index || 0))
            var itemsDone = isActive ? ytPlItemsDone : (item.total_bytes > 0 ? item.downloaded_bytes : 0)
            var itemsTotal = isActive ? ytPlItemsTotal : (item.total_bytes > 0 ? item.total_bytes : 0)
            var plProg = isActive ? ytPlProgress : (itemsTotal > 0 ? (itemsDone * 100 / itemsTotal) : 0)
            var plDone = item.state === "Done"
            var plName = item.display_name || item.filename || item.url || "YouTube Playlist"
            return <div class="cdm-item cdm-yt-playlist" onContextMenu={(e) => { openContextMenu(e, item) }}>
                <div class="cdm-item-head">
                    <div class="cdm-item-title">
                        <span class={ytPlayTile}></span>
                        <div class="cdm-item-titletext">
                            <div class="cdm-item-name" title={plName}>{plName}</div>
                            <div class="cdm-item-meta-line">
                                {plDone ? <span class="cdm-badge-ok">Complete</span>
                                    : <span class="cdm-badge-busy">Downloading…</span>}
                                <span class="cdm-item-cat">Playlist</span>
                            </div>
                        </div>
                    </div>
                    <span class="cdm-item-pct">{itemsDone}/{itemsTotal}</span>
                </div>
                <div class="cdm-progress" style={{ margin: "2px 0" }}>
                    <div class="cdm-progress-fill" style={"width: " + (plProg || 0) + "%;"}></div>
                </div>
                {sorted.map((v) => {
                    var expanded = ytPlExpanded[v.index]
                    var vItem = v.video_task_id ? items.find((it) => it.id === v.video_task_id) : null
                    var aItem = v.audio_task_id ? items.find((it) => it.id === v.audio_task_id) : null
                    var stateClass2 = v.state === "done" ? "cdm-merge-ok"
                        : v.state === "failed" ? "cdm-merge-fail"
                        : v.state === "merging" || v.state === "downloading" ? "cdm-merge-wait"
                        : "cdm-badge-busy"
                    return <div class="cdm-yt-pl-video">
                        <div class="cdm-yt-pl-row" onClick={() => {
                            var next = Object.assign({}, ytPlExpanded)
                            next[v.index] = !expanded
                            ytPlExpanded = next
                            refresh()
                        }}>
                            <span class="cdm-yt-pl-caret">{expanded ? "▾" : "▸"}</span>
                            <span class="cdm-yt-pl-title" title={v.title}>{v.title}</span>
                            <span class={stateClass2}>{v.state}</span>
                            <span class="cdm-item-pct">{(v.progress || 0).toFixed(1)}%</span>
                        </div>
                        <div class="cdm-progress" style={{ margin: "2px 0 4px 18px" }}>
                            <div class="cdm-progress-fill" style={"width: " + (v.progress || 0) + "%;"}></div>
                        </div>
                        {expanded ? (
                            <div class="cdm-yt-pl-detail">
                                {ytStreamRow(vItem, "Video")}
                                {ytStreamRow(aItem, "Audio")}
                                {v.merge_status === "merged" ? (
                                    <div class="cdm-yt-merge-ok">✓ Merged into: {v.output_path ? v.output_path : "output file"}</div>
                                ) : v.merge_status === "failed" ? (
                                    <div class="cdm-yt-merge-fail">✗ Merge failed: {v.merge_error ? v.merge_error : "unknown error"}</div>
                                ) : v.merge_status === "merging" ? (
                                    <div class="cdm-yt-merge-wait">⟳ Merging video + audio…</div>
                                ) : null}
                                <div class="cdm-item-actions">
                                    {v.state === "failed" ? (
                                        <button class="cdm-btn cdm-btn-warn"
                                            onClick={() => { asyncBridge("yt_download_playlist_retry", JSON.stringify({ index: v.index }), function() { pollYtPlaylist() }) }}>
                                            <span class="cdm-ic cdm-ic-retry"></span>Retry
                                        </button>
                                    ) : null}
                                    {v.state === "done" ? (
                                        <button class="cdm-btn"
                                            onClick={() => { asyncBridge("yt_download_playlist_open", JSON.stringify({ index: v.index })) }}>
                                            <span class="cdm-ic cdm-ic-external"></span>Open
                                        </button>
                                    ) : null}
                                    {(vItem && (vItem.state === "Downloading" || vItem.state === "Queued")) ? (
                                        <button class="cdm-btn cdm-btn-danger"
                                            onClick={() => { post("cancel", vItem.id); if(aItem) post("cancel", aItem.id) }}>
                                            <span class="cdm-ic cdm-ic-xcircle"></span>Cancel
                                        </button>
                                    ) : null}
                                </div>
                            </div>
                        ) : null}
                    </div>
                })}
                <div class="cdm-item-actions">
                    {item.state === "Downloading" ? (
                        <button class="cdm-btn cdm-btn-danger" onClick={() => { asyncBridge("yt_cancel", "{}", function() { }) }}><span class="cdm-ic cdm-ic-xcircle"></span>Cancel Playlist</button>
                    ) : null}
                    {item.state !== "Downloading" && item.state !== "Queued" ? (
                        <button class="cdm-btn cdm-btn-danger" onClick={() => {
                            if(confirm("Remove this playlist from the queue?")) { post("remove", item.id) }
                        }}><span class="cdm-ic cdm-ic-trash"></span>Remove</button>
                    ) : null}
                </div>
            </div>
        }

        // --- SINGLE YOUTUBE VIDEO card: container with nested video+audio ---
        var renderYtVideoCard = (item) => {
            var isActive = item.id === ytDlContainerId
            var vItem = isActive ? (ytDlVideoId ? items.find((it) => it.id === ytDlVideoId) : null) : null
            var aItem = isActive ? (ytDlAudioId ? items.find((it) => it.id === ytDlAudioId) : null) : null
            var cardName = isActive && ytDlTitle ? ytDlTitle : (item.display_name || item.filename || "YouTube download")
            var mergeBadge = (isActive && ytDlMergeStatus !== "") ? (
                <span class={ytDlMergeStatus === "merged" ? "cdm-merge-ok" : ytDlMergeStatus === "failed" ? "cdm-merge-fail" : "cdm-merge-wait"}>
                    {ytDlMergeStatus === "merged" ? "✓ Merged" : ytDlMergeStatus === "merging" ? "⟳ Merging..." : ytDlMergeStatus === "waiting" ? "⏳ Waiting..." : ytDlMergeStatus === "failed" ? "✗ Merge failed" : ytDlMergeStatus}
                </span>
            ) : null
            return <div class="cdm-item cdm-yt-combined" onContextMenu={(e) => {
                var target = vItem || aItem
                if(target) openContextMenu(e, target)
            }}>
                <div class="cdm-item-head">
                    <div class="cdm-item-title">
                        <span class={ytPlayTile}></span>
                        <div class="cdm-item-titletext">
                            <div class="cdm-item-name" title={cardName}>{cardName}</div>
                            <div class="cdm-item-meta-line">YouTube</div>
                        </div>
                    </div>
                    {mergeBadge}
                </div>
                {ytStreamRow(vItem, "Video")}
                {ytStreamRow(aItem, "Audio")}
                {isActive && ytDlMergeStatus === "merged" ? (
                    <div class="cdm-yt-merge-ok">✓ Merged into: {vItem ? (vItem.display_name || vItem.filename) : "output file"}</div>
                ) : isActive && ytDlMergeStatus === "failed" ? (
                    <div class="cdm-yt-merge-fail">✗ Merge failed: {ytDlMergeError !== "" ? ytDlMergeError : "unknown error"}</div>
                ) : isActive && ytDlMergeStatus === "merging" ? (
                    <div class="cdm-yt-merge-wait">⟳ Merging video + audio...</div>
                ) : isActive && ytDlMergeStatus === "waiting" ? (
                    <div class="cdm-yt-merge-wait">⏳ Waiting for streams to finish before merging...</div>
                ) : null}
                <div class="cdm-item-actions">
                    {(vItem && (vItem.state === "Downloading" || vItem.state === "Queued")) || (aItem && (aItem.state === "Downloading" || aItem.state === "Queued")) ? (
                        <button class="cdm-btn cdm-btn-danger" onClick={() => { if(vItem) post("cancel", vItem.id); if(aItem) post("cancel", aItem.id) }}><span class="cdm-ic cdm-ic-xcircle"></span>Cancel</button>
                    ) : null}
                </div>
            </div>
        }

        // --- NORMAL download row (dense, hover actions) ---
        var renderNormalCard = (item) => {
            var pct = parseFloat(item.percent)
            if(isNaN(pct)) pct = 0
            if(pct < 0) pct = 0
            if(pct > 100) pct = 100
            var showProgress = item.state === "Downloading" || item.state === "Paused"
            var failed = item.state === "Failed" || item.state === "Cancelled"
            var running = item.state === "Downloading" || item.state === "Queued"
            var name = item.display_name || item.filename
            var segs = []
            if(item.segments && item.segments.length > 0) { segs = item.segments }
            var hasSegs = segs.length > 1
            return <div class={"cdm-row" + (failed ? " cdm-row-error" : "")}
                onContextMenu={(e) => openContextMenu(e, item)}>
                <span class={tileClass(item.category)}></span>
                <div class="cdm-row-body">
                    <div class="cdm-row-top">
                        <span class="cdm-row-name" title={item.url}>{name}</span>
                        <span class={stateClass(item.state)}>{item.state}</span>
                        <span class="cdm-row-size">{item.total_bytes >= 0 ? fmtBytes(item.total_bytes) : "?"}</span>
                    </div>
                    {showProgress ? (
                        <div class="cdm-progress">
                            <div class="cdm-progress-fill" style={"width: " + pct + "%;"}></div>
                        </div>
                    ) : null}
                    {showProgress && hasSegs ? renderSegments(segs) : null}
                    <div class="cdm-row-sub">
                        <span class="cdm-item-cat">{item.category}</span>
                        {item.priority > 0 ? <span class="cdm-item-prio">P{item.priority}</span> : null}
                        {item.speed_limit_kbps > 0 ? <span>&#9203; {item.speed_limit_kbps} KB/s</span> : null}
                        <span>{fmtBytes(item.downloaded_bytes)}{item.total_bytes >= 0 ? " / " + fmtBytes(item.total_bytes) : ""}</span>
                        {showProgress ? <span class="cdm-row-speed">{fmtSpeed(item.speed_bytes_per_sec)}</span> : null}
                        {showProgress && item.eta !== "" ? <span>{item.eta}</span> : null}
                        <span class="cdm-row-dir" title={item.dir}>{item.dir}</span>
                        {failed && item.error !== "" ? <span class="cdm-row-err" title={item.error}>{item.error}</span> : null}
                    </div>
                </div>
                <span class="cdm-row-pct">{pct.toFixed(0)}%</span>
                <div class="cdm-row-end">
                    <div class="cdm-row-actions">
                        {running ? (
                            <button class="cdm-iconbtn" title="Pause" aria-label="Pause" disabled={busy} onClick={() => post("pause", item.id)}><span class="cdm-ic cdm-ic-pause"></span></button>
                        ) : null}
                        {(item.state === "Paused" || (item.state === "Failed" && item.error === "interrupted by shutdown") || (item.state === "Cancelled" && item.downloaded_bytes > 0)) ? (
                            <button class="cdm-iconbtn" title="Resume" aria-label="Resume" disabled={busy} onClick={() => post("resume", item.id)}><span class="cdm-ic cdm-ic-play"></span></button>
                        ) : null}
                        {item.state === "Failed" && item.error !== "interrupted by shutdown" ? (
                            <button class="cdm-iconbtn" title="Retry" aria-label="Retry" disabled={busy} onClick={() => post("retry", item.id)}><span class="cdm-ic cdm-ic-retry"></span></button>
                        ) : null}
                        {item.state === "Done" || item.state === "Failed" || item.state === "Cancelled" ? (
                            <button class="cdm-iconbtn" title="Restart from scratch" aria-label="Restart" disabled={busy} onClick={() => post("restart", item.id)}><span class="cdm-ic cdm-ic-restart"></span></button>
                        ) : null}
                        {item.state !== "Downloading" && item.state !== "Queued" ? (
                            <button class="cdm-iconbtn" title="Change URL" aria-label="Change URL" disabled={busy} onClick={() => { changeUrlItem = item; changeUrlValue = item.url; changeUrlOpen = true }}><span class="cdm-ic cdm-ic-link"></span></button>
                        ) : null}
                        {item.state === "Done" || item.state === "Failed" || item.state === "Cancelled" ? (
                            <button class="cdm-iconbtn" title="Open file" aria-label="Open file" onClick={() => {
                                asyncBridge("open_file", JSON.stringify({ path: item.dir + "/" + (item.display_name || item.filename) }), function(d) {
                                    if(d && !d.ok) { showToast(d.error || "Could not open file", "error") }
                                })
                            }}><span class="cdm-ic cdm-ic-external"></span></button>
                        ) : null}
                        {running ? (
                            <button class="cdm-iconbtn cdm-iconbtn-danger" title="Cancel" aria-label="Cancel" disabled={busy} onClick={() => post("cancel", item.id)}><span class="cdm-ic cdm-ic-xcircle"></span></button>
                        ) : null}
                        {item.state !== "Downloading" && item.state !== "Queued" ? (
                            <button class="cdm-iconbtn cdm-iconbtn-danger" title="Remove file" aria-label="Remove file" disabled={busy} onClick={() => {
                                if(confirm("Delete the downloaded file? This cannot be undone.")) { post("remove_file", item.id) }
                            }}><span class="cdm-ic cdm-ic-trash"></span></button>
                        ) : null}
                        {item.state !== "Downloading" && item.state !== "Queued" ? (
                            <button class="cdm-iconbtn cdm-iconbtn-danger" title="Remove from queue" aria-label="Remove" disabled={busy} onClick={() => {
                                if(confirm("Remove this download from the queue?")) { post("remove", item.id) }
                            }}><span class="cdm-ic cdm-ic-trash"></span></button>
                        ) : null}
                    </div>
                </div>
            </div>
        }


    return <div class="cdm-shell">
        <aside class="cdm-side">
            <div class="cdm-side-brand">
                <span class="cdm-side-mark"><span class="cdm-ic cdm-ic-download"></span></span>
                <span class="cdm-side-name">ChemicalDM</span>
            </div>
            <div class="cdm-side-scroll">
                <div class="cdm-side-label">Library</div>
                {sidebarNav.map((n) => (
                    <button class={"cdm-side-item" + (filter === n.filter ? " cdm-side-item-on" : "")}
                        onClick={() => navPick(n.filter)}>
                        <span class={"cdm-ic " + n.icon}></span>
                        {n.label}
                        <span class="cdm-side-count">{n.count}</span>
                    </button>
                ))}
                <div class="cdm-side-label">Categories</div>
                {sidebarCats.map((c) => (
                    <button class={"cdm-side-item" + (catFilter === c.name ? " cdm-side-item-on" : "")}
                        onClick={() => { catFilter = (catFilter === c.name ? "All" : c.name) }}>
                        <span class={"cdm-ic " + c.icon}></span>
                        {c.label}
                        <span class="cdm-side-count">{c.count}</span>
                    </button>
                ))}
            </div>
            <div class="cdm-side-foot">
                <button class="cdm-side-item" onClick={() => { ytToolsOpen = true; refreshTools() }}>
                    <span class="cdm-ic cdm-ic-wrench"></span>Tools
                </button>
                <button class="cdm-side-item" onClick={() => { showSettings = true; refreshSettings() }}>
                    <span class="cdm-ic cdm-ic-sliders"></span>Settings
                </button>
            </div>
        </aside>
        <div class="cdm-main">
            <div class="cdm-topbar">
                <input class="cdm-search-input" type="text" placeholder="Search filename or URL…"
                    value={searchQuery} onChange={(e) => { searchQuery = e.target.value }} />
                <select class="cdm-sort-select" value={sortBy} onChange={(e) => { sortBy = e.target.value }}>
                    <option value="newest">Newest first</option>
                    <option value="oldest">Oldest first</option>
                    <option value="name">Name A-Z</option>
                    <option value="size">Largest first</option>
                </select>
                <span class="cdm-topbar-spacer"></span>
                <button class="cdm-btn" onClick={pasteFromClipboard}><span class="cdm-ic cdm-ic-clipboard"></span>Paste URL</button>
                <button class="cdm-yt-btn" onClick={openYtDownload}><span class="cdm-ic cdm-ic-play"></span>YouTube</button>
            </div>
            <div class="cdm-commandbar">
                <div class="cdm-url-field">
                    <span class="cdm-ic cdm-ic-link cdm-command-ic"></span>
                    <input class="cdm-url-input" type="text" spellcheck="false" autocomplete="off"
                        placeholder="Paste a download link and press Enter…" value={newUrl}
                        onChange={(e) => { newUrl = e.target.value }}
                        onKeyDown={(e) => { if(e.key === "Enter") addDownload() }} />
                    <button class="cdm-btn" style="border:none;padding:4px 6px;" onClick={() => { addUrl = newUrl; addOpen = true }} disabled={newUrl.trim() === "" || busy}>Options…</button>
                </div>
                <button class="cdm-add-btn" onClick={addDownload} disabled={newUrl.trim() === "" || busy}><span class="cdm-ic cdm-ic-plus"></span>Add</button>
            </div>
            <div class="cdm-content">

        {showSettings && settings ? <CdmSettingsDialog settings={settings} reset={resetField} apply={applySettings} bridge={asyncBridge} toast={showToast} refresh={refreshSettings} close={() => { showSettings = false }} /> : null}

        {addOpen ? (
            <div class="cdm-dialog-overlay" onClick={() => { addOpen = false }}>
                <div class="cdm-dialog" onClick={(e) => { e.stopPropagation() }}>
                    <div class="cdm-dialog-header">
                        <div class="cdm-dialog-title"><span class="cdm-ic cdm-ic-plus"></span> Add Download</div>
                        <button class="cdm-dialog-close" onClick={() => { addOpen = false }}>&#10005;</button>
                    </div>
                    <div class="cdm-dialog-body">
                        <label>URL
                            <input type="text" value={addUrl} onChange={(e) => { addUrl = e.target.value }} />
                        </label>
                        <label>Save to folder (blank = default / category)
                            <input type="text" placeholder={settings ? settings.download_dir : "/tmp"} value={addDir}
                                onChange={(e) => { addDir = e.target.value }} />
                        </label>
                        <label>File name (blank = auto-detect)
                            <input type="text" value={addName} onChange={(e) => { addName = e.target.value }} />
                        </label>
                        <label>Category
                            <select value={addCategory} onChange={(e) => { addCategory = e.target.value }}>
                                <option value="Other">Other</option>
                                <option value="Documents">Documents</option>
                                <option value="Programs">Programs</option>
                                <option value="Video">Video</option>
                                <option value="Music">Music</option>
                                <option value="Compressed">Compressed</option>
                            </select>
                        </label>
                        <label>Priority (0 = highest)
                            <input type="number" min="0" value={addPriority} onChange={(e) => { addPriority = e.target.value }} />
                        </label>
                        <label>Per-task speed limit (KB/s, 0 = unlimited)
                            <input type="number" min="0" value={addSpeedLimit} onChange={(e) => { addSpeedLimit = e.target.value }} />
                        </label>
                    </div>
                    <div class="cdm-dialog-footer">
                        <button class="cdm-btn" onClick={() => { addOpen = false }}>Cancel</button>
                        <button class="cdm-add-btn" onClick={addDownload}>Start Download</button>
                    </div>
                </div>
            </div>
        ) : null}

        {changeUrlOpen && changeUrlItem ? (
            <div class="cdm-dialog-overlay" onClick={() => { changeUrlOpen = false }}>
                <div class="cdm-dialog" onClick={(e) => { e.stopPropagation() }}>
                    <div class="cdm-dialog-header">
                        <div class="cdm-dialog-title"><span class="cdm-ic cdm-ic-link"></span> Change URL</div>
                        <button class="cdm-dialog-close" onClick={() => { changeUrlOpen = false }}>&#10005;</button>
                    </div>
                    <div class="cdm-dialog-body">
                        <p class="cdm-dialog-info">Current file: {changeUrlItem.display_name || changeUrlItem.filename}</p>
                        <p class="cdm-dialog-info">Downloaded: {changeUrlItem.downloaded_bytes} bytes</p>
                        <label>New URL
                            <input type="text" value={changeUrlValue}
                                onChange={(e) => { changeUrlValue = e.target.value }}
                                placeholder="Paste the new download URL" />
                        </label>
                    </div>
                    <div class="cdm-dialog-footer">
                        <button class="cdm-btn" onClick={() => { changeUrlOpen = false }}>Cancel</button>
                        <button class="cdm-add-btn" onClick={() => {
                            if(changeUrlValue.trim() !== "" && changeUrlItem) {
                                call("change_url", { id: changeUrlItem.id, url: changeUrlValue.trim() })
                                changeUrlOpen = false; changeUrlItem = null; changeUrlValue = ""
                            }
                        }}>Apply & Resume</button>
                    </div>
                </div>
            </div>
        ) : null}

        {ytOpen ? (
            <div class="cdm-dialog-overlay" onClick={() => { if(!ytLoading && !ytDownloading) ytOpen = false }}>
                <div class="cdm-dialog" style="max-width:560px;" onClick={(e) => { e.stopPropagation() }}>
                    <div class="cdm-dialog-header">
                        <div class="cdm-dialog-title"><span class="cdm-ic cdm-ic-play"></span> YouTube Download</div>
                        <button class="cdm-dialog-close" onClick={() => { ytOpen = false }}>&#10005;</button>
                    </div>
                    <div class="cdm-dialog-body">
                        {(!ytTools || !ytTools.yt_dlp || ytTools.yt_dlp.status !== "installed") ? (
                            <div class="cdm-yt-tool-status">
                                <div class="cdm-yt-tool-dot cdm-yt-tool-dot-miss"></div>
                                <span class="cdm-yt-tool-name">yt-dlp not installed</span>
                                <button class="cdm-btn cdm-btn-accent cdm-yt-tool-install" onClick={() => { ytToolsOpen = true; ytOpen = false }}>Setup Tools</button>
                            </div>
                        ) : null}

                        <label>YouTube URL
                            <input type="text" value={ytUrl}
                                onChange={(e) => { ytUrl = e.target.value; ytInfo = null; ytError = "" }}
                                placeholder="https://youtube.com/watch?v=..."
                                disabled={ytLoading || ytDownloading}
                                onKeyDown={(e) => { if(e.key === "Enter" && !ytLoading) fetchYtInfo() }} />
                        </label>

                        {ytLoading ? (
                            <div style="display:flex;align-items:center;gap:8px;">
                                <span class="cdm-yt-spinner"></span>
                                <span style="font-size:13px;color:hsl(var(--muted-foreground));">Fetching video info...</span>
                                <button class="cdm-btn cdm-btn-danger" style="font-size:11px;padding:2px 8px;" onClick={() => cancelYtInfo()}>Cancel</button>
                            </div>
                        ) : null}

                        {ytError ? (
                            <div class="cdm-alert" style="font-size:13px;"><span class="cdm-ic cdm-ic-alert"></span>{ytError}</div>
                        ) : null}

                        {!ytLoading && !ytInfo && ytUrl.trim() !== "" ? (
                            <button class="cdm-add-btn" onClick={fetchYtInfo} style="align-self:flex-start;"><span class="cdm-ic cdm-ic-search"></span>Fetch Info</button>
                        ) : null}

                        {ytInfo ? (
                            <div class="cdm-yt-info-card">
                                <div class="cdm-yt-title">{ytInfo.title || "Unknown"}</div>
                                <div class="cdm-yt-meta">
                                    {ytInfo.duration_str ? <span>Duration: {ytInfo.duration_str}</span> : null}
                                    {ytInfo.is_playlist ? <span>{ytInfo.entries ? ytInfo.entries.length : 0} videos</span> : null}
                                </div>

                                {ytInfo.is_playlist && ytPlaylistEntries.length > 0 ? (
                                    <div>
                                        <div style="display:flex;gap:8px;margin-bottom:8px;">
                                            <button class="cdm-btn" onClick={selectAllPlaylist} style="font-size:12px;">Select All</button>
                                            <button class="cdm-btn" onClick={deselectAllPlaylist} style="font-size:12px;">Deselect All</button>
                                            <span style="font-size:12px;color:hsl(var(--muted-foreground));align-self:center;">{ytPlaylistSelected.length} / {ytPlaylistEntries.length} selected</span>
                                        </div>
                                        <div class="cdm-yt-formats" style="max-height:160px;">
                                            {ytPlaylistEntries.map((entry, i) => (
                                                <div class="cdm-yt-playlist-item" onClick={() => togglePlaylistEntry(i)} style={{ cursor: "pointer", background: ytPlaylistSelected.indexOf(i) !== -1 ? "hsl(var(--primary) / 0.08)" : "" }}>
                                                    <input type="checkbox" checked={ytPlaylistSelected.indexOf(i) !== -1} readOnly style={{ accentColor: "hsl(var(--destructive))" }} />
                                                    <span class="cdm-yt-playlist-idx">{entry.index || (i+1)}</span>
                                                    <span class="cdm-yt-playlist-title">{entry.title || "Unknown"}</span>
                                                    <span class="cdm-yt-playlist-dur">{entry.duration_str || ""}</span>
                                                </div>
                                            ))}
                                        </div>
                                        <div style="margin-top:8px;">
                                            <label style={{ fontSize: "12px", color: "hsl(var(--muted-foreground))" }}>Min Quality</label>
                                            <div class="cdm-yt-quality-select">
                                                {[0, 360, 480, 720, 1080, 1440, 2160].map((q) => (
                                                    <button class={"cdm-yt-quality-chip" + (ytMinQuality === q ? " cdm-yt-quality-chip-on" : "")}
                                                        onClick={() => { ytMinQuality = q }}>{q === 0 ? "Any" : q + "p"}</button>
                                                ))}
                                            </div>
                                        </div>
                                    </div>
                                ) : null}

                                {!ytInfo.is_playlist && ytInfo.formats && ytInfo.formats.length > 0 ? (
                                    <div>
                                        <div style="display:flex;gap:6px;margin-bottom:8px;">
                                            <button class={"cdm-yt-quality-chip" + (ytFormatMode == "merged" ? " cdm-yt-quality-chip-on" : "")}
                                                onClick={() => { ytFormatMode = "merged" }}>Video + Audio</button>
                                            <button class={"cdm-yt-quality-chip" + (ytFormatMode == "video_only" ? " cdm-yt-quality-chip-on" : "")}
                                                onClick={() => { ytFormatMode = "video_only" }}>Video Only</button>
                                            <button class={"cdm-yt-quality-chip" + (ytFormatMode == "audio_only" ? " cdm-yt-quality-chip-on" : "")}
                                                onClick={() => { ytFormatMode = "audio_only" }}>Audio Only</button>
                                        </div>
                                        <label style={{ fontSize: "12px", color: "hsl(var(--muted-foreground))", marginBottom: "4px", display: "block" }}>Quality</label>
                                        <div class="cdm-yt-formats">
                                            <div class={"cdm-yt-format-item" + (ytSelectedFormat === "best" ? " cdm-yt-format-item-selected" : "")}
                                                onClick={() => { ytSelectedFormat = "best" }}>
                                                <span class="cdm-yt-format-label">Best quality (auto)</span>
                                                <span class="cdm-yt-format-size">mp4</span>
                                            </div>
                                            {ytInfo.formats.map((fmt) => (
                                                fmt.vcodec && fmt.vcodec !== "none"
                                                    && (!fmt.protocol || (fmt.protocol.indexOf("m3u8") < 0 && fmt.protocol.indexOf("hls") < 0)) ? (
                                                    <div class={"cdm-yt-format-item" + (ytSelectedFormat === fmt.format_id ? " cdm-yt-format-item-selected" : "")}
                                                        onClick={() => { ytSelectedFormat = fmt.format_id }}>
                                                        <span class="cdm-yt-format-label">{fmtVideoLabel(fmt)}</span>
                                                        <span class="cdm-yt-format-size">{fmtVideoSize(fmt)}</span>
                                                    </div>
                                                ) : null
                                            ))}
                                        </div>
                                        <div style="margin-top:8px;">
                                            <label style={{ fontSize: "12px", color: "hsl(var(--muted-foreground))" }}>Min Quality</label>
                                            <div class="cdm-yt-quality-select">
                                                {[0, 360, 480, 720, 1080, 1440, 2160].map((q) => (
                                                    <button class={"cdm-yt-quality-chip" + (ytMinQuality === q ? " cdm-yt-quality-chip-on" : "")}
                                                        onClick={() => { ytMinQuality = q }}>{q === 0 ? "Any" : q + "p"}</button>
                                                ))}
                                            </div>
                                        </div>
                                        <div style="margin-top:4px;">
                                            <label style={{ fontSize: "12px", color: "hsl(var(--muted-foreground))" }}>Max Quality</label>
                                            <div class="cdm-yt-quality-select">
                                                {[0, 360, 480, 720, 1080, 1440, 2160].map((q) => (
                                                    <button class={"cdm-yt-quality-chip" + (ytMaxQuality === q ? " cdm-yt-quality-chip-on" : "")}
                                                        onClick={() => { ytMaxQuality = q }}>{q === 0 ? "Any" : q + "p"}</button>
                                                ))}
                                            </div>
                                        </div>
                                    </div>
                                ) : null}

                                <div class="cdm-yt-toggle" style="margin-top:10px;">
                                    <Switch checked={ytAutoMerge} size="sm" onChange={(e) => { ytAutoMerge = e.target.checked }}>Auto-merge video + audio</Switch>
                                </div>
                                <div class="cdm-yt-toggle">
                                    <Switch checked={ytDeleteSeparate} size="sm" onChange={(e) => { ytDeleteSeparate = e.target.checked }}>Delete separate files after merge</Switch>
                                </div>
                                {ytInfo && ytInfo.is_playlist ? (
                                    <div style="margin-top:8px;">
                                        <label style={{ fontSize: "12px", color: "hsl(var(--muted-foreground))" }}>Retries per video (on link/merge failure)</label>
                                        <div class="cdm-yt-quality-select">
                                            {[1, 2, 3, 5, 10].map((n) => (
                                                <button class={"cdm-yt-quality-chip" + (ytPlMaxRetries === n ? " cdm-yt-quality-chip-on" : "")}
                                                    onClick={() => { ytPlMaxRetries = n }}>{n}</button>
                                            ))}
                                        </div>
                                    </div>
                                ) : null}
                            </div>
                        ) : null}
                    </div>
                    {ytDownloading ? (
                        <div class="cdm-yt-dl-progress">
                            <div class="cdm-progress" style="height:10px;margin-bottom:8px;">
                                <div class="cdm-progress-fill" style={"width: " + ytDlProgress + "%;"}></div>
                            </div>
                            <div class="cdm-yt-dl-meta">
                                <span class="cdm-yt-dl-pct">{ytDlProgress.toFixed(1)}%</span>
                                <span class="cdm-yt-dl-speed">{ytDlSpeed}</span>
                                <span class="cdm-yt-dl-eta">{ytDlEta}</span>
                            </div>
                        </div>
                    ) : null}
                    <div class="cdm-dialog-footer">
                        <button class="cdm-btn" onClick={() => { ytOpen = false }}>Close</button>
                        {ytDownloading ? (
                            <button class="cdm-btn cdm-btn-danger" onClick={cancelYtDownload}>Cancel Download</button>
                        ) : null}
                        {ytInfo && !ytDownloading ? (
                            <button class="cdm-yt-btn" onClick={startYtDownload}><span class="cdm-ic cdm-ic-download"></span>Download</button>
                        ) : null}
                    </div>
                </div>
            </div>
        ) : null}

        {ytToolsOpen ? (
            <div class="cdm-dialog-overlay" onClick={() => { ytToolsOpen = false }}>
                <div class="cdm-dialog" style="max-width:480px;" onClick={(e) => { e.stopPropagation() }}>
                    <div class="cdm-dialog-header">
                        <div class="cdm-dialog-title"><span class="cdm-ic cdm-ic-wrench"></span> Setup Tools</div>
                        <button class="cdm-dialog-close" onClick={() => { ytToolsOpen = false }}>&#10005;</button>
                    </div>
                    <div class="cdm-dialog-body">
                        <p style={{ fontSize: "13px", color: "hsl(var(--muted-foreground))", margin: 0 }}>Required for YouTube/video downloads</p>

                        <div class="cdm-yt-tool-status">
                            <div class={"cdm-yt-tool-dot " + (ytTools && ytTools.yt_dlp && ytTools.yt_dlp.status === "installed" ? "cdm-yt-tool-dot-ok" : "cdm-yt-tool-dot-miss")}></div>
                            <div style="flex:1;">
                                <div class="cdm-yt-tool-name">yt-dlp</div>
                                <div class="cdm-yt-tool-ver">{ytTools && ytTools.yt_dlp ? ((ytTools.yt_dlp.version || ytTools.yt_dlp.status || "not installed") + (ytTools.yt_dlp.path ? (" @ " + ytTools.yt_dlp.path) : "")) : "checking..."}</div>
                                {ytInstallingTool === "yt-dlp" ? (
                                    <div style="margin-top:6px;">
                                        <div class="cdm-progress" style="height:6px;">
                                            <div class="cdm-progress-fill" style={{ width: (ytInstallProgress || 0) + "%" }}></div>
                                        </div>
                                        <div style={{ fontSize: "11px", color: "hsl(var(--muted-foreground))", marginTop: "2px" }}>
                                            {ytTools && ytTools.yt_dlp && ytTools.yt_dlp.speed ? ytTools.yt_dlp.speed : "Starting download..."}
                                            {ytInstallProgress > 0 ? " — " + ytInstallProgress.toFixed(1) + "%" : ""}
                                        </div>
                                    </div>
                                ) : null}
                                {ytTools && ytTools.yt_dlp && ytTools.yt_dlp.error ? (
                                    <div style={{ fontSize: "11px", color: "hsl(var(--destructive))", marginTop: "2px" }}>{ytTools.yt_dlp.error}</div>
                                ) : null}
                            </div>
                            <button class="cdm-btn cdm-yt-tool-install" disabled={ytInstallingTool === "yt-dlp"}
                                onClick={() => installTool("yt-dlp")}>
                                {ytInstallingTool === "yt-dlp" ? <span class="cdm-yt-spinner"></span> : null}
                                {ytTools && ytTools.yt_dlp && ytTools.yt_dlp.status === "installed" ? "Update" : "Install"}
                            </button>
                        </div>

                        <div class="cdm-yt-tool-status">
                            <div class={"cdm-yt-tool-dot " + (ytTools && ytTools.ffmpeg && ytTools.ffmpeg.status === "installed" ? "cdm-yt-tool-dot-ok" : "cdm-yt-tool-dot-miss")}></div>
                            <div style="flex:1;">
                                <div class="cdm-yt-tool-name">ffmpeg</div>
                                <div class="cdm-yt-tool-ver">{ytTools && ytTools.ffmpeg ? ((ytTools.ffmpeg.version || ytTools.ffmpeg.status || "not installed") + (ytTools.ffmpeg.path ? (" @ " + ytTools.ffmpeg.path) : "")) : "checking..."}</div>
                                {ytInstallingTool === "ffmpeg" ? (
                                    <div style={{ marginTop: "6px" }}>
                                        <div class="cdm-progress" style={{ height: "6px" }}>
                                            <div class="cdm-progress-fill" style={{ width: (ytInstallProgress || 0) + "%" }}></div>
                                        </div>
                                        <div style={{ fontSize: "11px", color: "hsl(var(--muted-foreground))", marginTop: "2px" }}>
                                            {ytTools && ytTools.ffmpeg && ytTools.ffmpeg.speed ? ytTools.ffmpeg.speed : "Starting download..."}
                                            {ytInstallProgress > 0 ? " \u2014 " + ytInstallProgress.toFixed(1) + "%" : ""}
                                        </div>
                                    </div>
                                ) : null}
                                {ytTools && ytTools.ffmpeg && ytTools.ffmpeg.error ? (
                                    <div style={{ fontSize: "11px", color: "hsl(var(--destructive))", marginTop: "2px" }}>{ytTools.ffmpeg.error}</div>
                                ) : null}
                            </div>
                            <button class="cdm-btn cdm-yt-tool-install" disabled={ytInstallingTool === "ffmpeg"}
                                onClick={() => installTool("ffmpeg")}>
                                {ytInstallingTool === "ffmpeg" ? <span class="cdm-yt-spinner"></span> : null}
                                {ytTools && ytTools.ffmpeg && ytTools.ffmpeg.status === "installed" ? "Update" : "Install"}
                            </button>
                        </div>

                        <p style={{ fontSize: "12px", color: "hsl(var(--muted-foreground))", margin: 0 }}>
                            yt-dlp downloads videos. ffmpeg merges separate video+audio streams.
                            Both are required for full YouTube support.
                        </p>
                    </div>
                    <div class="cdm-dialog-footer">
                        <button class="cdm-add-btn" onClick={() => { ytToolsOpen = false }}>Done</button>
                    </div>
                </div>
            </div>
        ) : null}

        {toastVisible ? (
            <div class="cdm-toast-container">
                <div class={"cdm-yt-toast cdm-yt-toast-" + toastType} onClick={() => { toastVisible = false }}>
                    {toastMsg}
                </div>
            </div>
        ) : null}

        {ctxOpen && ctxItem ? (
            <div class="cdm-ctx-menu" style={"left:" + ctxX + "px;top:" + ctxY + "px;"} onClick={(e) => { e.stopPropagation() }}>
                {(ctxItem.state === "Done" || ctxItem.state === "Failed" || ctxItem.state === "Cancelled") ? (
                    <div class="cdm-ctx-item" onClick={() => ctxAction("open_file")}><span class="cdm-ic cdm-ic-external"></span>Open</div>
                ) : null}
                <div class="cdm-ctx-item" onClick={() => ctxAction("show_in_folder")}><span class="cdm-ic cdm-ic-folder"></span>Show in Folder</div>
                <div class="cdm-ctx-sep"></div>
                {ctxItem.state === "Downloading" || ctxItem.state === "Queued" ? (
                    <div class="cdm-ctx-item" onClick={() => ctxAction("pause")}><span class="cdm-ic cdm-ic-pause"></span>Pause</div>
                ) : null}
                {ctxItem.state === "Paused" ? (
                    <div class="cdm-ctx-item" onClick={() => ctxAction("resume")}><span class="cdm-ic cdm-ic-play"></span>Resume</div>
                ) : null}
                {ctxItem.state === "Cancelled" && ctxItem.downloaded_bytes > 0 ? (
                    <div class="cdm-ctx-item" onClick={() => ctxAction("resume")}><span class="cdm-ic cdm-ic-play"></span>Resume</div>
                ) : null}
                {ctxItem.state === "Failed" && ctxItem.error === "interrupted by shutdown" ? (
                    <div class="cdm-ctx-item" onClick={() => ctxAction("resume")}><span class="cdm-ic cdm-ic-play"></span>Resume</div>
                ) : null}
                {ctxItem.state === "Failed" && ctxItem.error !== "interrupted by shutdown" ? (
                    <div class="cdm-ctx-item" onClick={() => ctxAction("retry")}><span class="cdm-ic cdm-ic-retry"></span>Retry</div>
                ) : null}
                {ctxItem.state === "Done" || ctxItem.state === "Failed" || ctxItem.state === "Cancelled" ? (
                    <div class="cdm-ctx-item" onClick={() => ctxAction("restart")}><span class="cdm-ic cdm-ic-restart"></span>Restart</div>
                ) : null}
                {ctxItem.state === "Downloading" || ctxItem.state === "Queued" ? (
                    <div class="cdm-ctx-item cdm-ctx-danger" onClick={() => ctxAction("cancel")}><span class="cdm-ic cdm-ic-xcircle"></span>Cancel</div>
                ) : null}
                <div class="cdm-ctx-sep"></div>
                <div class="cdm-ctx-item cdm-ctx-danger" onClick={() => {
                    if(confirm("Remove this download from the queue?")) { ctxAction("remove") }
                    else { ctxOpen = false }
                }}><span class="cdm-ic cdm-ic-trash"></span>Remove</div>
                {ctxItem.state !== "Downloading" && ctxItem.state !== "Queued" ? (
                    <div class="cdm-ctx-item" onClick={() => {
                        ctxOpen = false
                        changeUrlItem = ctxItem; changeUrlValue = ctxItem.url; changeUrlOpen = true
                    }}><span class="cdm-ic cdm-ic-link"></span>Change URL</div>
                ) : null}
            </div>
        ) : null}

        {alert !== "" ? <div class="cdm-alert" onClick={() => { alert = "" }}><span class="cdm-ic cdm-ic-alert"></span>{alert}</div> : null}

        {loading ? <div class="cdm-list">
            {[1, 2, 3].map((i) => (
                <div class="cdm-skeleton-card" key={i}>
                    <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
                        <div class="cdm-skeleton" style={{ width: "40px", height: "40px", borderRadius: "12px", flexShrink: "0" }}></div>
                        <div class="cdm-skeleton cdm-skeleton-line cdm-skeleton-line-long" style={{ height: "14px", flex: "1" }}></div>
                        <div class="cdm-skeleton cdm-skeleton-line cdm-skeleton-line-short" style={{ height: "20px", width: "72px", borderRadius: "999px", flexShrink: "0" }}></div>
                    </div>
                    <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
                        <div style={{ width: "40px", flexShrink: "0" }}></div>
                        <div class="cdm-skeleton cdm-skeleton-line cdm-skeleton-line-med" style={{ height: "10px", flex: "1" }}></div>
                        <div class="cdm-skeleton cdm-skeleton-line cdm-skeleton-line-short" style={{ height: "20px", width: "72px", borderRadius: "999px" }}></div>
                    </div>
                    <div class="cdm-skeleton cdm-skeleton-bar"></div>
                    <div class="cdm-skeleton-meta">
                        <div class="cdm-skeleton cdm-skeleton-line" style={{ width: "80px" }}></div>
                        <div class="cdm-skeleton cdm-skeleton-line" style={{ width: "50px" }}></div>
                        <div class="cdm-skeleton cdm-skeleton-line" style={{ width: "60px" }}></div>
                    </div>
                </div>
            ))}
        </div> : null}

        {!loading && visibleItems.length === 0 && !ytDownloading ? (
            <div class="cdm-empty">
                <div class="cdm-empty-tile"><span class="cdm-ic cdm-ic-inbox"></span></div>
                <p class="cdm-empty-title">{mainItems.length === 0 ? "Nothing downloading yet" : "No downloads match this filter"}</p>
                <p>Paste a link above, or grab one straight from your clipboard.</p>
                {mainItems.length === 0 ? (
                    <button class="cdm-empty-cta" onClick={pasteFromClipboard}><span class="cdm-ic cdm-ic-clipboard"></span>Paste URL from Clipboard</button>
                ) : null}
            </div>
        ) : null}


        <div class="cdm-list">
            {visibleItems.map((item) => {
                if(item.card_type === CARD_PLAYLIST) { return renderPlaylistCard(item) }
                if(item.card_type === CARD_YT_SINGLE) { return renderYtVideoCard(item) }
                return renderNormalCard(item)
            })}
        </div>
            </div>
        </div>
        {<ErrorOverlay />}
    </div>
}

// Settings dialog building blocks. Top-level #universal components so the
// framework's component resolver finds them (local var-components have no
// precedent in this codebase). CdmSec renders a titled section with a plain-
// language description; CdmRow is one label/description + control line.
#universal CdmSec(props) {
    return <div class="cdm-set-sec" id={props.id}>
        <div class="cdm-set-sec-head">
            <div class="cdm-set-title">{props.title}</div>
            {props.desc ? <div class="cdm-set-desc">{props.desc}</div> : null}
        </div>
        {props.children}
    </div>
}

#universal CdmRow(props) {
    return <div class="cdm-set-row">
        <div class="cdm-set-row-text">
            <div class="cdm-set-row-label">{props.label}</div>
            {props.desc ? <div class="cdm-set-row-desc">{props.desc}</div> : null}
        </div>
        {props.children}
    </div>
}
// ─── Settings dialog ───────────────────────────────────────────────────────
// Extracted into its own component: the deep tab ternaries live in a fresh
// component scope (a current parser bug mis-tracks deeply nested ternaries in
// the main tree), and the dialog keeps its own nav state.
#universal CdmSettingsDialog(props) {
    state settingsTab = "general"
    state settingsSection = "general"
    return <div class="cdm-dialog-overlay" onClick={props.close}>
                <div class="cdm-dialog cdm-dialog-wide" onClick={(e) => { e.stopPropagation() }}>
                    <div class="cdm-dialog-header">
                        <div class="cdm-dialog-title"><span class="cdm-ic cdm-ic-sliders"></span> Settings</div>
                        <button class="cdm-dialog-close" onClick={props.close}>&#10005;</button>
                    </div>
                    <div class="cdm-dialog-body cdm-set-body">
                        <div class="cdm-set-rail">
                            <div class="cdm-set-group">General</div>
                            <button class={"cdm-set-nav" + (settingsSection === "general" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "general"; settingsSection = "general"; setTimeout(() => { var el = document.getElementById("download-folder"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Downloads</button>
                            <button class={"cdm-set-nav" + (settingsSection === "speed" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "general"; settingsSection = "speed"; setTimeout(() => { var el = document.getElementById("speed"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Speed</button>
                            <button class={"cdm-set-nav" + (settingsSection === "reliability" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "general"; settingsSection = "reliability"; setTimeout(() => { var el = document.getElementById("reliability"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Reliability</button>
                            <button class={"cdm-set-nav" + (settingsSection === "organization" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "general"; settingsSection = "organization"; setTimeout(() => { var el = document.getElementById("organization"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Organization</button>
                            <button class={"cdm-set-nav" + (settingsSection === "automation" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "general"; settingsSection = "automation"; setTimeout(() => { var el = document.getElementById("automation"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Automation</button>
                            <div class="cdm-set-group">Network</div>
                            <button class={"cdm-set-nav" + (settingsSection === "headers" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "network"; settingsSection = "headers"; setTimeout(() => { var el = document.getElementById("identification"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Headers</button>
                            <button class={"cdm-set-nav" + (settingsSection === "connection" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "network"; settingsSection = "connection"; setTimeout(() => { var el = document.getElementById("connection"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Connection</button>
                            <button class={"cdm-set-nav" + (settingsSection === "security" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "network"; settingsSection = "security"; setTimeout(() => { var el = document.getElementById("cookies-and-ssl"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Cookies and SSL</button>
                            <button class={"cdm-set-nav" + (settingsSection === "proxy" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "network"; settingsSection = "proxy"; setTimeout(() => { var el = document.getElementById("proxy"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Proxy</button>
                            <div class="cdm-set-group">YouTube</div>
                            <button class={"cdm-set-nav" + (settingsSection === "ytvideo" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "youtube"; settingsSection = "ytvideo"; setTimeout(() => { var el = document.getElementById("video"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Video</button>
                            <button class={"cdm-set-nav" + (settingsSection === "ytaudio" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "youtube"; settingsSection = "ytaudio"; setTimeout(() => { var el = document.getElementById("audio"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Audio</button>
                            <button class={"cdm-set-nav" + (settingsSection === "ytsubs" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "youtube"; settingsSection = "ytsubs"; setTimeout(() => { var el = document.getElementById("subtitles"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Subtitles</button>
                            <button class={"cdm-set-nav" + (settingsSection === "ytmeta" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "youtube"; settingsSection = "ytmeta"; setTimeout(() => { var el = document.getElementById("metadata"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Metadata</button>
                            <button class={"cdm-set-nav" + (settingsSection === "ytpl" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "youtube"; settingsSection = "ytpl"; setTimeout(() => { var el = document.getElementById("playlists"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Playlists</button>
                            <button class={"cdm-set-nav" + (settingsSection === "ytadv" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "youtube"; settingsSection = "ytadv"; setTimeout(() => { var el = document.getElementById("sponsorblock"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>YouTube Advanced</button>
                            <div class="cdm-set-group">System</div>
                            <button class={"cdm-set-nav" + (settingsSection === "limits" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "advanced"; settingsSection = "limits"; setTimeout(() => { var el = document.getElementById("limits"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Limits</button>
                            <button class={"cdm-set-nav" + (settingsSection === "files" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "advanced"; settingsSection = "files"; setTimeout(() => { var el = document.getElementById("files"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Files</button>
                            <button class={"cdm-set-nav" + (settingsSection === "ffmpeg" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "advanced"; settingsSection = "ffmpeg"; setTimeout(() => { var el = document.getElementById("ffmpeg"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>ffmpeg</button>
                            <button class={"cdm-set-nav" + (settingsSection === "appearance" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "advanced"; settingsSection = "appearance"; setTimeout(() => { var el = document.getElementById("appearance"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Appearance</button>
                            <button class={"cdm-set-nav" + (settingsSection === "backup" ? " cdm-set-nav-active" : "")} onClick={() => { settingsTab = "advanced"; settingsSection = "backup"; setTimeout(() => { var el = document.getElementById("backup"); if(el) { el.scrollIntoView({ block: "start", behavior: "instant" }) } }, 60) }}>Backup</button>
                        </div>
                        <div class="cdm-set-panel">

                        {settingsTab === "general" ? <div>
                        <CdmSec id="download-folder" title="Download folder" desc="Where completed files are saved. Category subfolders may add a folder inside this one.">
                            <CdmRow label="Save files to" desc="">
                                <div class="cdm-set-controls">
                                <input type="text" value={props.settings.download_dir}
                                    onChange={(e) => { props.settings.download_dir = e.target.value }} />
                                <button class="cdm-btn" onClick={() => {
                                    props.bridge("browse_folder", "{}", function(d) {
                                        if(d && d.ok && d.path) {
                                            props.settings.download_dir = d.path
                                            // Persist to native so settings_json reflects the change,
                                            // then re-fetch to trigger a full re-render.
                                            props.bridge("settings_set", JSON.stringify({download_dir: d.path}), function() {
                                                props.refresh()
                                            })
                                            props.toast("Folder: " + d.path, "success")
                                        }
                                    })
                                }}>Browse</button>
                                </div>
                            </CdmRow>
                        </CdmSec>
                        <CdmSec id="parallel-downloads" title="Parallel downloads" desc="How many downloads run at the same time. More is not always faster — some servers throttle.">
                            <CdmRow label="At the same time" desc="1 to 10. If a download looks stuck, try lowering this.">
                                <div class="cdm-set-controls"><input type="number" min="1" max="10" value={props.settings.max_concurrent}
                                    onChange={(e) => { props.settings.max_concurrent = parseInt(e.target.value) || 1 }} /></div>
                            </CdmRow>
                        </CdmSec>
                        <CdmSec id="splitting" title="Splitting" desc="Big files are downloaded in several pieces at once, which is usually faster. Small files are never split.">
                            <CdmRow label="Pieces per download" desc="2 to 32. More pieces help on fast, reliable servers.">
                                <div class="cdm-set-controls"><input type="number" min="2" max="32" value={props.settings.max_segments}
                                    onChange={(e) => { props.settings.max_segments = parseInt(e.target.value) || 4 }} /></div>
                            </CdmRow>
                            <CdmRow label="Allow splitting" desc="Turn off to always download in one piece. Some servers behave better that way.">
                                <Switch checked={props.settings.allow_segments} size="sm" onChange={(e) => { props.settings.allow_segments = e.target.checked }}> </Switch>
                            </CdmRow>
                        </CdmSec>
                        <CdmSec id="speed" title="Speed" desc="Limits how fast ChemicalDM downloads. Useful when you need your connection for other things.">
                            <CdmRow label="Overall speed limit" desc="KB per second, shared by all downloads. 0 means no limit.">
                                <div class="cdm-set-controls"><input type="number" min="0" value={props.settings.speed_limit_kbps}
                                    onChange={(e) => { props.settings.speed_limit_kbps = parseInt(e.target.value) || 0 }} /></div>
                            </CdmRow>
                        </CdmSec>
                        <label>Duplicate files handling
                            <select value={props.settings.duplicate_action}
                                onChange={(e) => { props.settings.duplicate_action = parseInt(e.target.value) || 0 }}>
                                <option value="0">Rename (report (1).pdf)</option>
                                <option value="1">Overwrite</option>
                                <option value="2">Skip</option>
                            </select>
                        </label>
                        <CdmSec id="organization" title="Organization" desc="How finished files are sorted and named when two files would share a name.">
                            <CdmRow label="Sort into category folders" desc="Videos, music, programs and archives each get their own folder inside the download folder.">
                                <Switch checked={props.settings.use_categories} size="sm" onChange={(e) => { props.settings.use_categories = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Duplicate files" desc="What to do when the download folder already has a file with the same name.">
                                <select value={props.settings.duplicate_action}
                                    onChange={(e) => { props.settings.duplicate_action = parseInt(e.target.value) || 0 }}>
                                    <option value="0">Rename new file as "name (1).ext"</option>
                                    <option value="1">Overwrite the old file</option>
                                    <option value="2">Skip the download</option>
                                </select>
                            </CdmRow>
                            <CdmRow label="Auto-rename duplicates" desc="Extra safety net: rename even if the duplicate check is off.">
                                <Switch checked={props.settings.auto_rename_duplicates || false} size="sm" onChange={(e) => { props.settings.auto_rename_duplicates = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Move completed files to" desc="Leave empty to keep files in the download folder.">
                                <div class="cdm-set-controls"><input type="text" value={props.settings.move_completed_to || ""}
                                    placeholder="Leave in the download folder"
                                    onChange={(e) => { props.settings.move_completed_to = e.target.value }} /></div>
                            </CdmRow>
                        </CdmSec>
                        <CdmSec id="reliability" title="Reliability" desc="What ChemicalDM does when a connection drops mid-download.">
                            <CdmRow label="Resume interrupted downloads" desc="Continue where the download left off instead of starting over. Works with most modern servers.">
                                <Switch checked={props.settings.enable_resume} size="sm" onChange={(e) => { props.settings.enable_resume = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Retry failed downloads" desc="How many times to retry automatically. Use -1 to keep trying forever, 0 to never retry.">
                                <div class="cdm-set-controls"><input type="number" min="-1" value={props.settings.max_retries}
                                    onChange={(e) => { props.settings.max_retries = parseInt(e.target.value) }} /></div>
                            </CdmRow>
                            <CdmRow label="Wait between retries" desc="Seconds to wait before each retry attempt.">
                                <div class="cdm-set-controls"><input type="number" min="0" value={Math.round((props.settings.retry_delay_ms || 0) / 1000)}
                                    onChange={(e) => { props.settings.retry_delay_ms = (parseInt(e.target.value) || 0) * 1000 }} /></div>
                            </CdmRow>
                            <CdmRow label="Auto-resume failed downloads at launch" desc="When the app starts, automatically retry downloads that failed last time.">
                                <Switch checked={props.settings.auto_resume_failed} size="sm" onChange={(e) => { props.settings.auto_resume_failed = e.target.checked }}> </Switch>
                            </CdmRow>
                        </CdmSec>
                        <CdmSec id="automation" title="Automation" desc="Hands-free conveniences.">
                            <CdmRow label="Monitor clipboard for URLs" desc="Offer to download when a link is copied.">
                                <Switch checked={props.settings.clipboard_monitor || false} size="sm" onChange={(e) => { props.settings.clipboard_monitor = e.target.checked }}> </Switch>
                            </CdmRow>
                        </CdmSec>
                        </div> : null}

                        {settingsTab === "youtube" ? <div>
                        <CdmSec id="video" title="Video" desc="Quality and container for YouTube downloads.">
                            <CdmRow label="Video quality" desc="Best available picks the highest resolution the video offers.">
                                <select value={props.settings.yt_quality || ""}
                                    onChange={(e) => { props.settings.yt_quality = e.target.value }}>
                                    <option value="">Best available</option>
                                    <option value="2160">2160p (4K)</option>
                                    <option value="1440">1440p (2K)</option>
                                    <option value="1080">1080p</option>
                                    <option value="720">720p</option>
                                    <option value="480">480p</option>
                                </select>
                            </CdmRow>
                            <CdmRow label="Container" desc="MP4 plays on everything.">
                                <select value={props.settings.yt_format || ""}
                                    onChange={(e) => { props.settings.yt_format = e.target.value }}>
                                    <option value="">Best compatibility</option>
                                    <option value="mp4">MP4</option>
                                    <option value="mkv">MKV</option>
                                    <option value="webm">WebM</option>
                                </select>
                            </CdmRow>
                            <CdmRow label="Merge format" desc="When video and audio come as separate streams, they are merged into this container.">
                                <select value={props.settings.yt_merge_output_format || "mp4"}
                                    onChange={(e) => { props.settings.yt_merge_output_format = e.target.value }}>
                                    <option value="mp4">MP4</option>
                                    <option value="mkv">MKV</option>
                                    <option value="webm">WebM</option>
                                    <option value="avi">AVI</option>
                                </select>
                            </CdmRow>
                            <CdmRow label="Recode after download" desc="Extra re-encoding pass. Only use if you need a specific format.">
                                <select value={props.settings.yt_recode_video || ""}
                                    onChange={(e) => { props.settings.yt_recode_video = e.target.value }}>
                                    <option value="">Do not recode</option>
                                    <option value="mp4">MP4</option>
                                    <option value="mkv">MKV</option>
                                    <option value="webm">WebM</option>
                                </select>
                            </CdmRow>
                        </CdmSec>
                        <CdmSec id="audio" title="Audio" desc="Save just the sound, or attach audio handling to video downloads.">
                            <CdmRow label="Download audio only" desc="Saves an audio file instead of a video.">
                                <Switch checked={props.settings.yt_audio_only || false} size="sm" onChange={(e) => { props.settings.yt_audio_only = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Audio format" desc="Used when downloading audio only.">
                                <select value={props.settings.yt_audio_format || ""}
                                    onChange={(e) => { props.settings.yt_audio_format = e.target.value }}>
                                    <option value="">Best available</option>
                                    <option value="mp3">MP3</option>
                                    <option value="aac">AAC</option>
                                    <option value="flac">FLAC</option>
                                    <option value="opus">Opus</option>
                                    <option value="vorbis">Vorbis</option>
                                </select>
                            </CdmRow>
                            <CdmRow label="Audio quality" desc="0 is best, 10 is worst. Applies to lossy formats like MP3.">
                                <div class="cdm-set-controls"><input type="number" min="0" max="10" value={props.settings.yt_audio_quality || 0}
                                    onChange={(e) => { props.settings.yt_audio_quality = parseInt(e.target.value) || 0 }} /></div>
                            </CdmRow>
                        </CdmSec>
                        <CdmSec id="playlists" title="Playlists" desc="How playlists are downloaded.">
                            <CdmRow label="Limit items per playlist" desc="0 downloads the whole playlist.">
                                <div class="cdm-set-controls"><input type="number" min="0" value={props.settings.yt_max_playlist_items || 0}
                                    onChange={(e) => { props.settings.yt_max_playlist_items = parseInt(e.target.value) || 0 }} /></div>
                            </CdmRow>
                            <CdmRow label="Start at item" desc="First video to download, counting from 1.">
                                <div class="cdm-set-controls"><input type="number" min="0" value={props.settings.yt_playlist_start || 0}
                                    onChange={(e) => { props.settings.yt_playlist_start = parseInt(e.target.value) || 0 }} /></div>
                            </CdmRow>
                            <CdmRow label="Stop after item" desc="0 downloads to the end of the playlist.">
                                <div class="cdm-set-controls"><input type="number" min="0" value={props.settings.yt_playlist_end || 0}
                                    onChange={(e) => { props.settings.yt_playlist_end = parseInt(e.target.value) || 0 }} /></div>
                            </CdmRow>
                            <CdmRow label="Only these items" desc="Comma-separated positions, e.g. 1,2,5-10. Leave empty for all.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.yt_playlist_items || ""}
                                        placeholder="All items"
                                        onChange={(e) => { props.settings.yt_playlist_items = e.target.value }} />
                                    {props.settings.yt_playlist_items ? <button class="cdm-set-reset" onClick={() => { props.reset("yt_playlist_items") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                            <CdmRow label="Output name pattern" desc="Advanced: yt-dlp output template, e.g. %(title)s.%(ext)s.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.yt_output_template || ""}
                                        placeholder="Title.ext (default)"
                                        onChange={(e) => { props.settings.yt_output_template = e.target.value }} />
                                    {props.settings.yt_output_template ? <button class="cdm-set-reset" onClick={() => { props.reset("yt_output_template") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                        </CdmSec>                        <CdmSec id="subtitles" title="Subtitles" desc="Download and embed subtitle tracks.">
                            <CdmRow label="Download subtitles" desc="Save subtitle files next to the video.">
                                <Switch checked={props.settings.yt_write_subs || false} size="sm" onChange={(e) => { props.settings.yt_write_subs = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Include auto-generated" desc="Also fetch YouTube's auto-generated captions.">
                                <Switch checked={props.settings.yt_write_auto_subs || false} size="sm" onChange={(e) => { props.settings.yt_write_auto_subs = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Languages" desc="Comma-separated codes, e.g. en,ja,es.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.yt_sub_langs || ""}
                                        placeholder="English only"
                                        onChange={(e) => { props.settings.yt_sub_langs = e.target.value }} />
                                    {props.settings.yt_sub_langs ? <button class="cdm-set-reset" onClick={() => { props.reset("yt_sub_langs") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                            <CdmRow label="Embed subtitles in video" desc="Bake subtitles into the container so players show them without extra files.">
                                <Switch checked={props.settings.yt_embed_subs || false} size="sm" onChange={(e) => { props.settings.yt_embed_subs = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Convert subtitles to" desc="SRT works in most players.">
                                <select value={props.settings.yt_convert_subs || ""}
                                    onChange={(e) => { props.settings.yt_convert_subs = e.target.value }}>
                                    <option value="">Keep original format</option>
                                    <option value="srt">SRT</option>
                                    <option value="vtt">VTT</option>
                                    <option value="ass">ASS</option>
                                </select>
                            </CdmRow>
                        </CdmSec>
                        <CdmSec id="metadata" title="Metadata" desc="Extra information saved with or inside the video.">
                            <CdmRow label="Embed metadata" desc="Write title, artist and other tags into the file.">
                                <Switch checked={props.settings.yt_embed_metadata !== false} size="sm" onChange={(e) => { props.settings.yt_embed_metadata = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Embed thumbnail as cover art" desc="Shows the video thumbnail in music players and file managers.">
                                <Switch checked={props.settings.yt_embed_thumbnail || false} size="sm" onChange={(e) => { props.settings.yt_embed_thumbnail = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Write description file" desc="Saves video description as a .description text file.">
                                <Switch checked={props.settings.yt_write_description || false} size="sm" onChange={(e) => { props.settings.yt_write_description = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Write info.json file" desc="All known video data as JSON. Useful for archiving.">
                                <Switch checked={props.settings.yt_write_info_json || false} size="sm" onChange={(e) => { props.settings.yt_write_info_json = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Write comments" desc="Also saves video comments. Slows things down for large videos.">
                                <Switch checked={props.settings.yt_write_comments || false} size="sm" onChange={(e) => { props.settings.yt_write_comments = e.target.checked }}> </Switch>
                            </CdmRow>
                        </CdmSec>
                        <CdmSec id="sponsorblock" title="SponsorBlock" desc="Skip or remove in-video sponsor reads and self-promotion, using the community SponsorBlock database.">
                            <CdmRow label="Remove sponsor segments" desc="Cuts sponsor reads out of the saved video.">
                                <Switch checked={props.settings.yt_remove_sponsorblock || false} size="sm" onChange={(e) => { props.settings.yt_remove_sponsorblock = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Mark sponsor segments" desc="Keeps the video intact but tags segments with these SponsorBlock categories.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.yt_sponsorblock_mark || ""}
                                        placeholder="Do not mark"
                                        onChange={(e) => { props.settings.yt_sponsorblock_mark = e.target.value }} />
                                    {props.settings.yt_sponsorblock_mark ? <button class="cdm-set-reset" onClick={() => { props.reset("yt_sponsorblock_mark") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                            <CdmRow label="Run command after each download" desc="Advanced: yt-dlp --exec, with {} as the output file.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.yt_exec_cmd || ""}
                                        placeholder="No command"
                                        onChange={(e) => { props.settings.yt_exec_cmd = e.target.value }} />
                                    {props.settings.yt_exec_cmd ? <button class="cdm-set-reset" onClick={() => { props.reset("yt_exec_cmd") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                            <CdmRow label="ASCII-only filenames" desc="Avoid special characters in saved file names.">
                                <Switch checked={props.settings.yt_restrict_filenames || false} size="sm" onChange={(e) => { props.settings.yt_restrict_filenames = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Limit filename length" desc="Truncate file names to this many characters. 0 keeps full names.">
                                <div class="cdm-set-controls"><input type="number" min="0" value={props.settings.yt_trim_filenames || 0}
                                    onChange={(e) => { props.settings.yt_trim_filenames = parseInt(e.target.value) || 0 }} /></div>
                            </CdmRow>
                            <CdmRow label="Do not overwrite existing files" desc="Skip a YouTube download when its file already exists.">
                                <Switch checked={props.settings.yt_no_overwrites || false} size="sm" onChange={(e) => { props.settings.yt_no_overwrites = e.target.checked }}> </Switch>
                            </CdmRow>
                        </CdmSec>
                        </div> : null}

                        {settingsTab === "network" ? <div>
                        <CdmSec id="identification" title="Identification" desc="How ChemicalDM presents itself to websites. Most downloads work fine with the defaults.">
                            <CdmRow label="User-Agent" desc="Only change this if a site blocks the default.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.user_agent || ""}
                                        placeholder="Default (ChemicalDM)"
                                        onChange={(e) => { props.settings.user_agent = e.target.value }} />
                                    {props.settings.user_agent ? <button class="cdm-set-reset" onClick={() => { props.reset("user_agent") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                            <CdmRow label="Referer header" desc="Sends a referring address with requests. Rarely needed.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.referer_header || ""}
                                        placeholder="None"
                                        onChange={(e) => { props.settings.referer_header = e.target.value }} />
                                    {props.settings.referer_header ? <button class="cdm-set-reset" onClick={() => { props.reset("referer_header") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                            <CdmRow label="Authorization header" desc="For servers that require a token, e.g. Bearer abc123.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.auth_header || ""}
                                        placeholder="None"
                                        onChange={(e) => { props.settings.auth_header = e.target.value }} />
                                    {props.settings.auth_header ? <button class="cdm-set-reset" onClick={() => { props.reset("auth_header") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                        </CdmSec>
                        <CdmSec id="connection" title="Connection" desc="Low-level network behaviour. Leave as is unless downloads misbehave.">
                            <CdmRow label="Connect timeout" desc="Give up connecting after this many seconds.">
                                <div class="cdm-set-controls"><input type="number" min="1" value={props.settings.connect_timeout || 30}
                                    onChange={(e) => { props.settings.connect_timeout = parseInt(e.target.value) || 30 }} /></div>
                            </CdmRow>
                            <CdmRow label="Force IPv4" desc="Skip IPv6 entirely. Helps on networks with broken IPv6.">
                                <Switch checked={props.settings.force_ipv4 || false} size="sm" onChange={(e) => { props.settings.force_ipv4 = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Force IPv6" desc="IPv4 and IPv6 cannot both be forced.">
                                <Switch checked={props.settings.force_ipv6 || false} size="sm" onChange={(e) => { props.settings.force_ipv6 = e.target.checked }}> </Switch>
                            </CdmRow>
                        </CdmSec>
                        <CdmSec id="cookies-and-ssl" title="Cookies and SSL" desc="Signed-in downloads and certificate handling.">
                            <CdmRow label="Cookie file" desc="Export a cookies.txt from your browser to download from sites you are signed in to.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.cookie_file || ""}
                                        placeholder="Not using cookies"
                                        onChange={(e) => { props.settings.cookie_file = e.target.value }} />
                                    {props.settings.cookie_file ? <button class="cdm-set-reset" onClick={() => { props.reset("cookie_file") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                            <CdmRow label="Verify SSL certificates" desc="Turn off only for servers with self-signed certificates — this reduces security.">
                                <Switch checked={props.settings.verify_ssl !== false} size="sm" onChange={(e) => { props.settings.verify_ssl = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Skip SSL verification for YouTube" desc="yt-dlp only. For networks that intercept HTTPS traffic.">
                                <Switch checked={props.settings.yt_no_check_certificates || false} size="sm" onChange={(e) => { props.settings.yt_no_check_certificates = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Legacy SSL connections" desc="Allow older TLS versions for very old servers.">
                                <Switch checked={props.settings.yt_legacy_server_connect || false} size="sm" onChange={(e) => { props.settings.yt_legacy_server_connect = e.target.checked }}> </Switch>
                            </CdmRow>
                        </CdmSec>

                        <CdmSec id="proxy" title="Proxy" desc="Route downloads through a proxy server. All fields are optional.">
                            <CdmRow label="HTTP proxy host" desc="Address of the proxy, e.g. 127.0.0.1. Leave empty for direct connection.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.proxy_host || ""}
                                        placeholder="Direct connection"
                                        onChange={(e) => { props.settings.proxy_host = e.target.value }} />
                                    {props.settings.proxy_host ? <button class="cdm-set-reset" onClick={() => { props.reset("proxy_host") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                            <CdmRow label="HTTP proxy port" desc="Usually 8080 or 1080.">
                                <div class="cdm-set-controls"><input type="number" min="0" max="65535" value={props.settings.proxy_port || 0}
                                    onChange={(e) => { props.settings.proxy_port = parseInt(e.target.value) || 0 }} /></div>
                            </CdmRow>
                            <CdmRow label="YouTube proxy" desc="Separate proxy for yt-dlp, e.g. socks5://127.0.0.1:1080.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.yt_proxy || ""}
                                        placeholder="Same as above (none by default)"
                                        onChange={(e) => { props.settings.yt_proxy = e.target.value }} />
                                    {props.settings.yt_proxy ? <button class="cdm-set-reset" onClick={() => { props.reset("yt_proxy") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                            <CdmRow label="Source IP address" desc="Use a specific network interface. Leave empty for automatic.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.yt_source_address || ""}
                                        placeholder="Automatic"
                                        onChange={(e) => { props.settings.yt_source_address = e.target.value }} />
                                    {props.settings.yt_source_address ? <button class="cdm-set-reset" onClick={() => { props.reset("yt_source_address") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                            <CdmRow label="Geo-restriction bypass" desc="Work around region-locked videos.">
                                <Switch checked={props.settings.yt_geo_bypass || false} size="sm" onChange={(e) => { props.settings.yt_geo_bypass = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="Geo-bypass country" desc="Pretend to browse from this country code, e.g. US.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.yt_geo_bypass_country || ""}
                                        placeholder="Automatic"
                                        onChange={(e) => { props.settings.yt_geo_bypass_country = e.target.value }} />
                                    {props.settings.yt_geo_bypass_country ? <button class="cdm-set-reset" onClick={() => { props.reset("yt_geo_bypass_country") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                            <CdmRow label="Socket timeout (YouTube)" desc="Give up on stalled YouTube requests after this many seconds.">
                                <div class="cdm-set-controls"><input type="number" min="1" value={props.settings.yt_socket_timeout || 30}
                                    onChange={(e) => { props.settings.yt_socket_timeout = parseInt(e.target.value) || 30 }} /></div>
                            </CdmRow>
                            <CdmRow label="Extractor retries (YouTube)" desc="Retry failed video-page lookups this many times.">
                                <div class="cdm-set-controls"><input type="number" min="0" value={props.settings.yt_extractor_retries || 3}
                                    onChange={(e) => { props.settings.yt_extractor_retries = parseInt(e.target.value) || 3 }} /></div>
                            </CdmRow>
                        </CdmSec>
                        </div> : null}

                        {settingsTab === "advanced" ? <div>
                        <CdmSec id="limits" title="Limits" desc="Guard rails for large downloads and full disks.">
                            <CdmRow label="Max download size" desc="Downloads bigger than this are rejected. 0 disables the check.">
                                <div class="cdm-set-controls"><input type="number" min="0" value={Math.round((props.settings.max_download_size || 0) / 1048576)}
                                    onChange={(e) => { props.settings.max_download_size = (parseInt(e.target.value) || 0) * 1048576 }} /></div>
                            </CdmRow>
                            <CdmRow label="Min free disk space" desc="Pause before writing if the disk has less than this much room left.">
                                <div class="cdm-set-controls"><input type="number" min="0" value={props.settings.min_disk_space_mb || 0}
                                    onChange={(e) => { props.settings.min_disk_space_mb = parseInt(e.target.value) || 0 }} /></div>
                            </CdmRow>
                            <CdmRow label="Per-download speed limit" desc="KB per second for each individual download. 0 means no limit.">
                                <div class="cdm-set-controls"><input type="number" min="0" value={props.settings.bandwidth_limit_per || 0}
                                    onChange={(e) => { props.settings.bandwidth_limit_per = parseInt(e.target.value) || 0 }} /></div>
                            </CdmRow>
                        </CdmSec>
                        <CdmSec id="files" title="Files" desc="Naming and automatic actions for finished downloads.">
                            <CdmRow label="Filename template" desc="Advanced: available placeholders are name, ext and date.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.filename_template || ""}
                                        placeholder="Original names"
                                        onChange={(e) => { props.settings.filename_template = e.target.value }} />
                                    {props.settings.filename_template ? <button class="cdm-set-reset" onClick={() => { props.reset("filename_template") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                            <CdmRow label="Checksum verification" desc="Verify finished downloads against a published checksum.">
                                <select value={props.settings.checksum || ""}
                                    onChange={(e) => { props.settings.checksum = e.target.value }}>
                                    <option value="">Disabled</option>
                                    <option value="md5">MD5</option>
                                    <option value="sha256">SHA-256</option>
                                </select>
                            </CdmRow>
                            <CdmRow label="Run command after download" desc="Runs with the output file path. Leave empty for nothing.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.post_download_cmd || ""}
                                        placeholder="No command"
                                        onChange={(e) => { props.settings.post_download_cmd = e.target.value }} />
                                    {props.settings.post_download_cmd ? <button class="cdm-set-reset" onClick={() => { props.reset("post_download_cmd") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                        </CdmSec>
                        <CdmSec id="ffmpeg" title="ffmpeg" desc="Re-encoding options for merged YouTube videos. Default keeps the original quality.">
                            <CdmRow label="Video codec" desc="Re-encoding is slower. Keep original unless you need a specific codec.">
                                <select value={props.settings.ffmpeg_video_codec || ""}
                                    onChange={(e) => { props.settings.ffmpeg_video_codec = e.target.value }}>
                                    <option value="">Keep original</option>
                                    <option value="h264">H.264 (most compatible)</option>
                                    <option value="h265">H.265 / HEVC (smaller files)</option>
                                    <option value="vp9">VP9</option>
                                    <option value="av1">AV1</option>
                                </select>
                            </CdmRow>
                            <CdmRow label="Audio codec">
                                <select value={props.settings.ffmpeg_audio_codec || ""}
                                    onChange={(e) => { props.settings.ffmpeg_audio_codec = e.target.value }}>
                                    <option value="">Keep original</option>
                                    <option value="aac">AAC</option>
                                    <option value="mp3">MP3</option>
                                    <option value="opus">Opus</option>
                                </select>
                            </CdmRow>
                            <CdmRow label="Audio bitrate" desc="Only used when an audio codec is set.">
                                <select value={props.settings.ffmpeg_audio_bitrate || ""}
                                    onChange={(e) => { props.settings.ffmpeg_audio_bitrate = e.target.value }}>
                                    <option value="">Automatic</option>
                                    <option value="128K">128 Kbps</option>
                                    <option value="192K">192 Kbps</option>
                                    <option value="256K">256 Kbps</option>
                                    <option value="320K">320 Kbps</option>
                                </select>
                            </CdmRow>
                            <CdmRow label="ffmpeg location" desc="Leave empty to use the version bundled with or installed by the app.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.yt_ffmpeg_location || ""}
                                        placeholder="Automatic"
                                        onChange={(e) => { props.settings.yt_ffmpeg_location = e.target.value }} />
                                    {props.settings.yt_ffmpeg_location ? <button class="cdm-set-reset" onClick={() => { props.reset("yt_ffmpeg_location") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                        </CdmSec>

                        <CdmSec id="appearance" title="Appearance" desc="How ChemicalDM looks and sounds.">
                            <CdmRow label="Theme" desc="Auto follows your system appearance.">
                                <select value={props.settings.theme || "auto"}
                                    onChange={(e) => { props.settings.theme = e.target.value }}>
                                    <option value="auto">Auto (system)</option>
                                    <option value="dark">Dark</option>
                                    <option value="light">Light</option>
                                </select>
                            </CdmRow>
                            <CdmRow label="Language" desc="Application language. Empty uses your system language.">
                                <div class="cdm-set-controls">
                                    <input type="text" value={props.settings.language || ""}
                                        placeholder="System language"
                                        onChange={(e) => { props.settings.language = e.target.value }} />
                                    {props.settings.language ? <button class="cdm-set-reset" onClick={() => { props.reset("language") }}>Reset</button> : null}
                                </div>
                            </CdmRow>
                            <CdmRow label="Desktop notifications" desc="Notify when downloads finish or fail.">
                                <Switch checked={props.settings.notifications_enabled !== false} size="sm" onChange={(e) => { props.settings.notifications_enabled = e.target.checked }}> </Switch>
                            </CdmRow>
                            <CdmRow label="History length" desc="How many finished downloads to keep in the list. 0 keeps everything.">
                                <div class="cdm-set-controls"><input type="number" min="0" value={props.settings.max_history || 0}
                                    onChange={(e) => { props.settings.max_history = parseInt(e.target.value) || 0 }} /></div>
                            </CdmRow>
                        </CdmSec>
                        <CdmSec id="backup" title="Backup" desc="Move your settings between machines.">
                            <div class="cdm-set-buttons">
                                <button class="cdm-btn" onClick={() => {
                                    var path = prompt("Export settings to file:", "/tmp/cdm-props.settings.json")
                                    if(path) {
                                        props.bridge("settings_export", JSON.stringify({ path: path }), function(d) {
                                            if(d && d.ok) { props.toast("Settings exported to " + path) }
                                            else { props.toast(d && d.error ? d.error : "Export failed", "error") }
                                        })
                                    }
                                }}>Export Settings</button>
                                <button class="cdm-btn" onClick={() => {
                                    var path = prompt("Import settings from file:", "/tmp/cdm-props.settings.json")
                                    if(path) {
                                        props.bridge("settings_import", JSON.stringify({ path: path }), function(d) {
                                            if(d && d.ok) {
                                                props.toast("Settings imported — refreshing")
                                                props.refresh()
                                            } else {
                                                props.toast(d && d.error ? d.error : "Import failed", "error")
                                            }
                                        })
                                    }
                                }}>Import Settings</button>
                            </div>
                            <div class="cdm-set-note">Export saves all current settings to a JSON file. Import applies settings from such a file and saves them immediately.</div>
                        </CdmSec>
                        </div> : null}
                    </div>
                    </div>
                    <div class="cdm-dialog-footer">
                        <button class="cdm-btn" onClick={props.close}>Cancel</button>
                        <button class="cdm-add-btn" onClick={props.apply}>Save Settings</button>
                    </div>
                </div>
            </div>
}

