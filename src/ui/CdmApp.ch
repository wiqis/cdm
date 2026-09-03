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
    var asyncBridge = (method, body, onResult) => {
        window.webview_bridge.call(method, body || "{}").then(function(v) {
            onResult(v)
        }).catch(function(e) {
            console.error("[CDM-JS] bridge error for " + method + ": " + e)
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
        var closeCtx = (e) => {
            if(!ctxOpen) return
            var menuEl = e.target.closest && e.target.closest('.cdm-ctx-menu')
            if(menuEl) return
            ctxOpen = false
        }
        document.addEventListener("mousedown", closeCtx)
        return () => {
            clearInterval(t)
            document.removeEventListener("mousedown", closeCtx)
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
        })
    }

    var call = (method, body) => {
        asyncBridge(method, JSON.stringify(body || {}), function(d) {
            refresh()
        })
    }

    var addDownload = () => {
        var u = addUrl.trim() || newUrl.trim()
        if(u === "") return
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
        })
    }

    var applySettings = () => {
        if(!settings) return
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
            user_agent: settings.user_agent || "",
            cookie_file: settings.cookie_file || "",
            verify_ssl: settings.verify_ssl !== false,
            connect_timeout: settings.connect_timeout || 30,
            max_download_size: settings.max_download_size || 0,
            min_disk_space_mb: settings.min_disk_space_mb || 0,
            post_download_cmd: settings.post_download_cmd || "",
            yt_quality: settings.yt_quality || "",
            yt_format: settings.yt_format || "",
            yt_audio_only: settings.yt_audio_only || false,
            yt_max_playlist_items: settings.yt_max_playlist_items || 0,
            referer_header: settings.referer_header || "",
            auth_header: settings.auth_header || "",
            force_ipv4: settings.force_ipv4 || false,
            force_ipv6: settings.force_ipv6 || false,
            filename_template: settings.filename_template || "",
            checksum: settings.checksum || "",
            notifications_enabled: settings.notifications_enabled !== false,
            language: settings.language || "",
            max_history: settings.max_history || 1000,
            theme: settings.theme || "auto"
        }
        call("settings_set", body)
        alert = "Settings saved"
        showSettings = false
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
            call("open_file", { path: path })
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
        if(sortBy === "newest") return b.id > a.id ? 1 : (b.id < a.id ? -1 : 0)
        if(sortBy === "oldest") return a.id > b.id ? 1 : (a.id < b.id ? -1 : 0)
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
                {showProg && hasSegs ? (
                    <div class="cdm-segments">
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
                ) : null}
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
                    <div class="cdm-item-name">
                        <span style={{ marginRight: "6px" }}>&#128228;</span>
                        <span>{plName}</span>
                        {plDone ? <span class="cdm-badge-ok">Complete</span>
                            : <span class="cdm-badge-busy">Downloading…</span>}
                    </div>
                    <span class="cdm-item-pct">{itemsDone}/{itemsTotal}</span>
                </div>
                <div class="cdm-progress" style={{ margin: "4px 0" }}>
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
                                            Retry
                                        </button>
                                    ) : null}
                                    {v.state === "done" ? (
                                        <button class="cdm-btn"
                                            onClick={() => { asyncBridge("yt_download_playlist_open", JSON.stringify({ index: v.index })) }}>
                                            Open
                                        </button>
                                    ) : null}
                                    {(vItem && (vItem.state === "Downloading" || vItem.state === "Queued")) ? (
                                        <button class="cdm-btn cdm-btn-danger"
                                            onClick={() => { post("cancel", vItem.id); if(aItem) post("cancel", aItem.id) }}>
                                            Cancel
                                        </button>
                                    ) : null}
                                </div>
                            </div>
                        ) : null}
                    </div>
                })}
                <div class="cdm-item-actions">
                    {item.state === "Downloading" ? (
                        <button class="cdm-btn cdm-btn-danger" onClick={() => { asyncBridge("yt_cancel", "{}", function() { }) }}>Cancel Playlist</button>
                    ) : null}
                    {item.state !== "Downloading" && item.state !== "Queued" ? (
                        <button class="cdm-btn cdm-btn-danger" onClick={() => post("remove", item.id)}>Remove</button>
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
                    <div class="cdm-item-name" title={cardName}>{cardName}</div>
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
                        <button class="cdm-btn cdm-btn-danger" onClick={() => { if(vItem) post("cancel", vItem.id); if(aItem) post("cancel", aItem.id) }}>Cancel</button>
                    ) : null}
                </div>
            </div>
        }

        // --- NORMAL download card ---
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
            return <div class={"cdm-item" + (failed ? " cdm-item-error" : "")}
                onContextMenu={(e) => openContextMenu(e, item)}>
                <div class="cdm-item-head">
                    <div class="cdm-item-name" title={item.url}>{name}</div>
                    <span class={stateClass(item.state)}>{item.state}</span>
                </div>
                <div class="cdm-item-meta-line">
                    <span class="cdm-item-cat">{item.category}</span>
                    <span class="cdm-item-prio">P{item.priority}</span>
                    {item.max_segments > 0 ? <span class="cdm-item-cat">segs {item.max_segments}</span> : null}
                    {item.speed_limit_kbps > 0 ? <span class="cdm-item-cat">&#9203; {item.speed_limit_kbps} KB/s</span> : null}
                    <span class="cdm-item-dir" title={item.dir}>{item.dir}</span>
                </div>
                {showProgress ? (
                    <div class="cdm-progress">
                        <div class="cdm-progress-fill" style={"width: " + pct + "%;"}></div>
                    </div>
                ) : null}
                {showProgress && hasSegs ? (
                    <div class="cdm-segments">
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
                ) : null}
                <div class="cdm-item-meta">
                    <span>{fmtBytes(item.downloaded_bytes)} / {item.total_bytes >= 0 ? fmtBytes(item.total_bytes) : "?"}</span>
                    <span class="cdm-item-pct">{pct.toFixed(1)}%</span>
                    <span class="cdm-item-speed">{fmtSpeed(item.speed_bytes_per_sec)}</span>
                    <span class="cdm-item-eta">{item.eta !== "" && showProgress ? item.eta : ""}</span>
                </div>
                {item.error !== "" ? <div class="cdm-item-error-text">{item.error}</div> : null}
                <div class="cdm-item-actions">
                    {item.state === "Downloading" || item.state === "Queued" ? (
                        <button class="cdm-btn" onClick={() => post("pause", item.id)}>Pause</button>
                    ) : null}
                    {(item.state === "Paused" || (item.state === "Failed" && item.error === "interrupted by shutdown")) ? (
                        <button class="cdm-btn" onClick={() => post("resume", item.id)}>Resume</button>
                    ) : null}
                    {item.state === "Failed" && item.error !== "interrupted by shutdown" ? (
                        <button class="cdm-btn" onClick={() => post("retry", item.id)}>Retry</button>
                    ) : null}
                    {item.state === "Cancelled" && item.downloaded_bytes > 0 ? (
                        <button class="cdm-btn" onClick={() => post("resume", item.id)}>Resume</button>
                    ) : null}
                    {item.state === "Done" || item.state === "Failed" || item.state === "Cancelled" ? (
                        <button class="cdm-btn" onClick={() => post("restart", item.id)}>&#10227; Restart</button>
                    ) : null}
                    {item.state !== "Downloading" && item.state !== "Queued" ? (
                        <button class="cdm-btn" onClick={() => { changeUrlItem = item; changeUrlValue = item.url; changeUrlOpen = true }}>Change URL</button>
                    ) : null}
                    {running ? (
                        <button class="cdm-btn cdm-btn-danger" onClick={() => post("cancel", item.id)}>Cancel</button>
                    ) : null}
                    {item.state !== "Downloading" && item.state !== "Queued" ? (
                        <button class="cdm-btn cdm-btn-danger" onClick={() => post("remove_file", item.id)}>&#128465; Remove file</button>
                    ) : null}
                    {item.state !== "Downloading" && item.state !== "Queued" ? (
                        <button class="cdm-btn cdm-btn-danger" onClick={() => post("remove", item.id)}>Remove</button>
                    ) : null}
                </div>
            </div>
        }


    return <div class="cdm-app">
        <header class="cdm-header">
            <div class="cdm-header-title">
                <span class="cdm-logo">&#8681;</span>
                <div>
                    <h1>ChemicalDM</h1>
                    <div class="cdm-subtitle">High-performance download manager</div>
                </div>
            </div>
            <div class="cdm-header-stats">
                <span class="cdm-stat">Active <b>{activeCount}</b></span>
                <span class="cdm-stat">Done <b>{doneCount}</b></span>
                <span class="cdm-stat">Total <b>{totalCount}</b></span>
                <button class="cdm-btn cdm-btn-accent" onClick={pasteFromClipboard}>&#128203; Paste URL</button>
                <button class="cdm-yt-btn" onClick={openYtDownload}>&#9654; YouTube</button>
                <button class="cdm-btn" onClick={() => { ytToolsOpen = true; refreshTools() }}>&#128295; Tools</button>
                <button class="cdm-btn" onClick={() => { showSettings = true; refreshSettings() }}>&#9881; Settings</button>
            </div>
        </header>

        <div class="cdm-toolbar">
            <input class="cdm-url-input" type="text" spellcheck="false" autocomplete="off"
                placeholder="Type or paste a download URL and press Enter&#8230;" value={newUrl}
                onChange={(e) => { newUrl = e.target.value }}
                onKeyDown={(e) => { if(e.key === "Enter") addDownload() }} />
            <button class="cdm-add-btn" onClick={addDownload} disabled={newUrl.trim() === ""}>Add Download</button>
            <button class="cdm-btn" onClick={() => { addUrl = newUrl; addOpen = true }} disabled={newUrl.trim() === ""}>Options&#8230;</button>
        </div>

        <div class="cdm-filterbar">
            <div class="cdm-filter-row">
                {["All", "Active", "Paused", "Done", "Failed"].map((f) => (
                    <button class={"cdm-filter-chip" + (filter === f ? " cdm-filter-chip-on" : "")}
                        onClick={() => { filter = f }}>{f}</button>
                ))}
                <span class="cdm-filter-sep"></span>
                {["All", "Other", "Documents", "Programs", "Video", "Music", "Compressed"].map((c) => (
                    <button class={"cdm-filter-chip cdm-filter-cat" + (catFilter === c ? " cdm-filter-chip-on" : "")}
                        onClick={() => { catFilter = c }}>{c}</button>
                ))}
            </div>
            <div class="cdm-filter-row cdm-filter-secondary">
                <input class="cdm-search-input" type="text" placeholder="Search filename or URL&#8230;"
                    value={searchQuery} onChange={(e) => { searchQuery = e.target.value }} />
                <select class="cdm-sort-select" value={sortBy} onChange={(e) => { sortBy = e.target.value }}>
                    <option value="newest">Newest first</option>
                    <option value="oldest">Oldest first</option>
                    <option value="name">Name A-Z</option>
                    <option value="size">Largest first</option>
                </select>
            </div>
        </div>

        {showSettings && settings ? (
            <div class="cdm-dialog-overlay" onClick={() => { showSettings = false }}>
                <div class="cdm-dialog" onClick={(e) => { e.stopPropagation() }}>
                    <div class="cdm-dialog-header">
                        <div class="cdm-dialog-title">&#9881; Settings</div>
                        <button class="cdm-dialog-close" onClick={() => { showSettings = false }}>&#10005;</button>
                    </div>
                    <div class="cdm-dialog-body">
                        <label>Download folder
                            <input type="text" value={settings.download_dir}
                                onChange={(e) => { settings.download_dir = e.target.value }} />
                        </label>
                        <label>Max concurrent downloads
                            <input type="number" min="1" value={settings.max_concurrent}
                                onChange={(e) => { settings.max_concurrent = parseInt(e.target.value) || 1 }} />
                        </label>
                        <label>Max segments per download
                            <input type="number" min="1" value={settings.max_segments}
                                onChange={(e) => { settings.max_segments = parseInt(e.target.value) || 1 }} />
                        </label>
                        <label>Global speed limit (KB/s, 0 = unlimited)
                            <input type="number" min="0" value={settings.speed_limit_kbps}
                                onChange={(e) => { settings.speed_limit_kbps = parseInt(e.target.value) || 0 }} />
                        </label>
                        <label>Duplicate files handling
                            <select value={settings.duplicate_action}
                                onChange={(e) => { settings.duplicate_action = parseInt(e.target.value) || 0 }}>
                                <option value="0">Rename (report (1).pdf)</option>
                                <option value="1">Overwrite</option>
                                <option value="2">Skip</option>
                            </select>
                        </label>
                        <div class="cdm-toggle-row">
                            <label class="cdm-toggle-label">
                                <input type="checkbox" checked={settings.enable_resume}
                                    onChange={(e) => { settings.enable_resume = e.target.checked }} />
                                Enable resume (HTTP Range)
                            </label>
                        </div>
                        <div class="cdm-toggle-row">
                            <label class="cdm-toggle-label">
                                <input type="checkbox" checked={settings.allow_segments}
                                    onChange={(e) => { settings.allow_segments = e.target.checked }} />
                                Allow segmented downloads
                            </label>
                        </div>
                        <div class="cdm-toggle-row">
                            <label class="cdm-toggle-label">
                                <input type="checkbox" checked={settings.use_categories}
                                    onChange={(e) => { settings.use_categories = e.target.checked }} />
                                Use category subfolders
                            </label>
                        </div>
                        <div class="cdm-toggle-row">
                            <label class="cdm-toggle-label">
                                <input type="checkbox" checked={settings.auto_resume_failed}
                                    onChange={(e) => { settings.auto_resume_failed = e.target.checked }} />
                                Auto-resume failed downloads
                            </label>
                        </div>
                        <label>Max retries (-1 = infinite, 0 = no retry)
                            <input type="number" min="-1" value={settings.max_retries}
                                onChange={(e) => { settings.max_retries = parseInt(e.target.value) || 0 }} />
                        </label>
                        <label>Retry delay (ms)
                            <input type="number" min="0" value={settings.retry_delay_ms}
                                onChange={(e) => { settings.retry_delay_ms = parseInt(e.target.value) || 0 }} />
                        </label>

                        <div class="cdm-section-header">HTTP</div>

                        <label>User-Agent
                            <input type="text" value={settings.user_agent || ""}
                                placeholder="ChemicalDM/0.1"
                                onChange={(e) => { settings.user_agent = e.target.value }} />
                        </label>
                        <label>Cookie file path
                            <input type="text" value={settings.cookie_file || ""}
                                placeholder="/path/to/cookies.txt"
                                onChange={(e) => { settings.cookie_file = e.target.value }} />
                        </label>
                        <label>Referer header
                            <input type="text" value={settings.referer_header || ""}
                                placeholder="https://example.com"
                                onChange={(e) => { settings.referer_header = e.target.value }} />
                        </label>
                        <label>Authorization header
                            <input type="text" value={settings.auth_header || ""}
                                placeholder="Bearer ..."
                                onChange={(e) => { settings.auth_header = e.target.value }} />
                        </label>
                        <label>Connect timeout (seconds)
                            <input type="number" min="1" value={settings.connect_timeout || 30}
                                onChange={(e) => { settings.connect_timeout = parseInt(e.target.value) || 30 }} />
                        </label>
                        <div class="cdm-toggle-row">
                            <label class="cdm-toggle-label">
                                <input type="checkbox" checked={settings.verify_ssl !== false}
                                    onChange={(e) => { settings.verify_ssl = e.target.checked }} />
                                Verify SSL certificates
                            </label>
                        </div>
                        <div class="cdm-toggle-row">
                            <label class="cdm-toggle-label">
                                <input type="checkbox" checked={settings.force_ipv4 || false}
                                    onChange={(e) => { settings.force_ipv4 = e.target.checked }} />
                                Force IPv4
                            </label>
                        </div>
                        <div class="cdm-toggle-row">
                            <label class="cdm-toggle-label">
                                <input type="checkbox" checked={settings.force_ipv6 || false}
                                    onChange={(e) => { settings.force_ipv6 = e.target.checked }} />
                                Force IPv6
                            </label>
                        </div>

                        <div class="cdm-section-header">Limits</div>

                        <label>Max download size (bytes, 0 = unlimited)
                            <input type="number" min="0" value={settings.max_download_size || 0}
                                onChange={(e) => { settings.max_download_size = parseInt(e.target.value) || 0 }} />
                        </label>
                        <label>Min free disk space (MB, 0 = check disabled)
                            <input type="number" min="0" value={settings.min_disk_space_mb || 0}
                                onChange={(e) => { settings.min_disk_space_mb = parseInt(e.target.value) || 0 }} />
                        </label>
                        <label>Filename template ({name}, {ext}, {date} placeholders)
                            <input type="text" value={settings.filename_template || ""}
                                placeholder="{name}.{ext}"
                                onChange={(e) => { settings.filename_template = e.target.value }} />
                        </label>
                        <label>Post-download command ({path} = output file)
                            <input type="text" value={settings.post_download_cmd || ""}
                                placeholder="mpv {}"
                                onChange={(e) => { settings.post_download_cmd = e.target.value }} />
                        </label>
                        <label>Checksum verification (md5, sha256)
                            <input type="text" value={settings.checksum || ""}
                                placeholder="sha256"
                                onChange={(e) => { settings.checksum = e.target.value }} />
                        </label>

                        <div class="cdm-section-header">YouTube</div>

                        <label>Quality (best, 1080, 720, 480)
                            <input type="text" value={settings.yt_quality || ""}
                                placeholder="best"
                                onChange={(e) => { settings.yt_quality = e.target.value }} />
                        </label>
                        <label>Format (mp4, mkv, webm)
                            <input type="text" value={settings.yt_format || ""}
                                placeholder="mp4"
                                onChange={(e) => { settings.yt_format = e.target.value }} />
                        </label>
                        <div class="cdm-toggle-row">
                            <label class="cdm-toggle-label">
                                <input type="checkbox" checked={settings.yt_audio_only || false}
                                    onChange={(e) => { settings.yt_audio_only = e.target.checked }} />
                                Audio only (YouTube)
                            </label>
                        </div>
                        <label>Max playlist items (0 = all)
                            <input type="number" min="0" value={settings.yt_max_playlist_items || 0}
                                onChange={(e) => { settings.yt_max_playlist_items = parseInt(e.target.value) || 0 }} />
                        </label>

                        <div class="cdm-section-header">Appearance</div>

                        <label>Theme
                            <select value={settings.theme || "auto"}
                                onChange={(e) => { settings.theme = e.target.value }}>
                                <option value="auto">Auto (system)</option>
                                <option value="light">Light</option>
                                <option value="dark">Dark</option>
                            </select>
                        </label>
                        <label>Language (empty = auto)
                            <input type="text" value={settings.language || ""}
                                placeholder="en"
                                onChange={(e) => { settings.language = e.target.value }} />
                        </label>
                        <div class="cdm-toggle-row">
                            <label class="cdm-toggle-label">
                                <input type="checkbox" checked={settings.notifications_enabled !== false}
                                    onChange={(e) => { settings.notifications_enabled = e.target.checked }} />
                                Desktop notifications
                            </label>
                        </div>
                        <label>Max history items (0 = unlimited)
                            <input type="number" min="0" value={settings.max_history || 0}
                                onChange={(e) => { settings.max_history = parseInt(e.target.value) || 0 }} />
                        </label>

                        <div class="cdm-section-header">Backup</div>

                        <div style={{ display: "flex", gap: "8px", marginTop: "4px" }}>
                            <button class="cdm-btn" onClick={() => {
                                var path = prompt("Export settings to file:", "/tmp/cdm-settings.json")
                                if(path) { call("settings_export", {path: path}); alert = "Settings exported to " + path }
                            }}>Export Settings</button>
                            <button class="cdm-btn" onClick={() => {
                                var path = prompt("Import settings from file:")
                                if(path) { call("settings_import", {path: path}, () => { refreshSettings() }); alert = "Settings imported" }
                            }}>Import Settings</button>
                        </div>
                    </div>
                    <div class="cdm-dialog-footer">
                        <button class="cdm-btn" onClick={() => { showSettings = false }}>Cancel</button>
                        <button class="cdm-add-btn" onClick={applySettings}>Save Settings</button>
                    </div>
                </div>
            </div>
        ) : null}

        {addOpen ? (
            <div class="cdm-dialog-overlay" onClick={() => { addOpen = false }}>
                <div class="cdm-dialog" onClick={(e) => { e.stopPropagation() }}>
                    <div class="cdm-dialog-header">
                        <div class="cdm-dialog-title">&#10010; Add Download</div>
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
                        <div class="cdm-dialog-title">&#128279; Change URL</div>
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
                        <div class="cdm-dialog-title">&#9654; YouTube Download</div>
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
                            <div class="cdm-alert" style="font-size:13px;">&#9888; {ytError}</div>
                        ) : null}

                        {!ytLoading && !ytInfo && ytUrl.trim() !== "" ? (
                            <button class="cdm-add-btn" onClick={fetchYtInfo} style="align-self:flex-start;">Fetch Info</button>
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
                                                    <input type="checkbox" checked={ytPlaylistSelected.indexOf(i) !== -1} readOnly style={{ accentColor: "#ff0000" }} />
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

                                <div class="cdm-toggle-row" style="margin-top:10px;">
                                    <label class="cdm-toggle-label">
                                        <input type="checkbox" checked={ytAutoMerge}
                                            onChange={(e) => { ytAutoMerge = e.target.checked }} />
                                        Auto-merge video + audio
                                    </label>
                                </div>
                                <div class="cdm-toggle-row">
                                    <label class="cdm-toggle-label">
                                        <input type="checkbox" checked={ytDeleteSeparate}
                                            onChange={(e) => { ytDeleteSeparate = e.target.checked }} />
                                        Delete separate files after merge
                                    </label>
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
                            <button class="cdm-yt-btn" onClick={startYtDownload}>Download</button>
                        ) : null}
                    </div>
                </div>
            </div>
        ) : null}

        {ytToolsOpen ? (
            <div class="cdm-dialog-overlay" onClick={() => { ytToolsOpen = false }}>
                <div class="cdm-dialog" style="max-width:480px;" onClick={(e) => { e.stopPropagation() }}>
                    <div class="cdm-dialog-header">
                        <div class="cdm-dialog-title">&#128295; Setup Tools</div>
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
            <div class={"cdm-yt-toast cdm-yt-toast-" + toastType} onClick={() => { toastVisible = false }}>
                {toastMsg}
            </div>
        ) : null}

        {ctxOpen && ctxItem ? (
            <div class="cdm-ctx-menu" style={"left:" + ctxX + "px;top:" + ctxY + "px;"} onClick={(e) => { e.stopPropagation() }}>
                {(ctxItem.state === "Done" || ctxItem.state === "Failed" || ctxItem.state === "Cancelled") ? (
                    <div class="cdm-ctx-item" onClick={() => ctxAction("open_file")}>&#128194; Open</div>
                ) : null}
                <div class="cdm-ctx-item" onClick={() => ctxAction("show_in_folder")}>&#128193; Show in Folder</div>
                <div class="cdm-ctx-sep"></div>
                {ctxItem.state === "Downloading" || ctxItem.state === "Queued" ? (
                    <div class="cdm-ctx-item" onClick={() => ctxAction("pause")}>&#9208; Pause</div>
                ) : null}
                {ctxItem.state === "Paused" ? (
                    <div class="cdm-ctx-item" onClick={() => ctxAction("resume")}>&#9654; Resume</div>
                ) : null}
                {ctxItem.state === "Cancelled" && ctxItem.downloaded_bytes > 0 ? (
                    <div class="cdm-ctx-item" onClick={() => ctxAction("resume")}>&#9654; Resume</div>
                ) : null}
                {ctxItem.state === "Failed" ? (
                    <div class="cdm-ctx-item" onClick={() => ctxAction("retry")}>&#10227; Retry</div>
                ) : null}
                {ctxItem.state === "Done" || ctxItem.state === "Failed" || ctxItem.state === "Cancelled" ? (
                    <div class="cdm-ctx-item" onClick={() => ctxAction("restart")}>&#10227; Restart</div>
                ) : null}
                {ctxItem.state === "Downloading" || ctxItem.state === "Queued" ? (
                    <div class="cdm-ctx-item cdm-ctx-danger" onClick={() => ctxAction("cancel")}>&#9209; Cancel</div>
                ) : null}
                <div class="cdm-ctx-sep"></div>
                <div class="cdm-ctx-item cdm-ctx-danger" onClick={() => ctxAction("remove")}>&#128465; Remove</div>
                {ctxItem.state !== "Downloading" && ctxItem.state !== "Queued" ? (
                    <div class="cdm-ctx-item" onClick={() => {
                        ctxOpen = false
                        changeUrlItem = ctxItem; changeUrlValue = ctxItem.url; changeUrlOpen = true
                    }}>&#128279; Change URL</div>
                ) : null}
            </div>
        ) : null}

        {alert !== "" ? <div class="cdm-alert" onClick={() => { alert = "" }}>{alert}</div> : null}

        {loading ? <div class="cdm-empty">Loading downloads&#8230;</div> : null}

        {!loading && visibleItems.length === 0 && !ytDownloading ? (
            <div class="cdm-empty">
                <div class="cdm-empty-icon">&#128229;</div>
                <p>{mainItems.length === 0 ? "No downloads yet." : "No downloads match this filter."}</p>
                <p class="cdm-empty-sub">Paste a URL above, or click the Paste button to grab one from your clipboard.</p>
            </div>
        ) : null}


        <div class="cdm-list">
            {visibleItems.map((item) => {
                if(item.card_type === CARD_PLAYLIST) { return renderPlaylistCard(item) }
                if(item.card_type === CARD_YT_SINGLE) { return renderYtVideoCard(item) }
                return renderNormalCard(item)
            })}
        </div>
        {<ErrorOverlay />}
    </div>
}
