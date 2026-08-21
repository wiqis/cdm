// ChemicalDM — the webview UI, a single universal component.
// SSR renders the empty shell; after hydration it polls the native engine over
// the webview bridge every second and re-renders the live queue. 
// Bridges (window.webview_bridge.call(method, argsJson) -> JSON):
//   state, add, pause, resume, cancel, remove, remove_file, retry, restart,
//   edit, settings_get, settings_set, open_file, show_in_folder

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
    // Context menu state
    state ctxOpen = false
    state ctxX = 0
    state ctxY = 0
    state ctxItem = null

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
                addOpen = true
            } else if(text) {
                alert = "Clipboard does not contain a URL"
            } else {
                alert = "Clipboard is empty"
            }
        }).catch(() => { alert = "Could not read clipboard" })
    }

    var refresh = () => {
        var d = JSON.parse(window.webview_bridge.call("state", "{}"))
        items = d.items
        loading = false
    }

    var refreshSettings = () => {
        settings = JSON.parse(window.webview_bridge.call("settings_get", "{}"))
    }

    useEffect(() => {
        refresh()
        refreshSettings()
        var t = setInterval(refresh, 1000)
        var closeCtx = (e) => {
            if(!ctxOpen) return
            // Don't close if clicking inside the context menu itself.
            var menuEl = e.target.closest && e.target.closest('.cdm-ctx-menu')
            if(menuEl) return
            ctxOpen = false
        }
        document.addEventListener("mousedown", closeCtx)
        return () => { clearInterval(t); document.removeEventListener("mousedown", closeCtx) }
    }, [])

    var post = (method, id, extra) => {
        var body = extra || {}
        body.id = id
        var d = JSON.parse(window.webview_bridge.call(method, JSON.stringify(body)))
        if(!d.ok) { alert = d.error || "Operation failed" }
        refresh()
    }

    var call = (method, body) => {
        var d = JSON.parse(window.webview_bridge.call(method, JSON.stringify(body || {})))
        refresh()
        return d
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
        var d = call("add", body)
        if(d.ok) {
            newUrl = ""; addUrl = ""; addDir = ""; addName = ""; addCategory = "Other"; addPriority = "0"
            addOpen = false; alert = ""
        } else {
            alert = d.error || "Failed to add download"
        }
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
            auto_resume_failed: settings.auto_resume_failed
        }
        call("settings_set", body)
        alert = "Settings saved"
        showSettings = false
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

    var visibleItems = items.filter((u) => {
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
    var totalCount = items.length
    var activeCount = items.filter((u) => u.state === "Downloading").length
    var doneCount = items.filter((u) => u.state === "Done").length

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
                    </div>
                    <div class="cdm-dialog-footer">
                        <button class="cdm-btn" onClick={() => { addOpen = false }}>Cancel</button>
                        <button class="cdm-add-btn" onClick={addDownload}>Start Download</button>
                    </div>
                </div>
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
            </div>
        ) : null}

        {alert !== "" ? <div class="cdm-alert" onClick={() => { alert = "" }}>{alert}</div> : null}

        {loading ? <div class="cdm-empty">Loading downloads&#8230;</div> : null}

        {!loading && visibleItems.length === 0 ? (
            <div class="cdm-empty">
                <div class="cdm-empty-icon">&#128229;</div>
                <p>{items.length === 0 ? "No downloads yet." : "No downloads match this filter."}</p>
                <p class="cdm-empty-sub">Paste a URL above, or click the Paste button to grab one from your clipboard.</p>
            </div>
        ) : null}

        <div class="cdm-list">
            {visibleItems.map((item) => {
                var pct = parseFloat(item.percent)
                if(isNaN(pct)) pct = 0
                if(pct < 0) pct = 0
                if(pct > 100) pct = 100
                var showProgress = item.state === "Downloading" || item.state === "Paused"
                var failed = item.state === "Failed" || item.state === "Cancelled"
                var running = item.state === "Downloading" || item.state === "Queued"
                var name = item.display_name || item.filename
                // Parse segments JSON for per-segment progress display
                var segs = []
                if(item.segments && item.segments.length > 0) {
                    segs = item.segments
                }
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
                        {item.state === "Paused" ? (
                            <button class="cdm-btn" onClick={() => post("resume", item.id)}>Resume</button>
                        ) : null}
                        {item.state === "Failed" ? (
                            <button class="cdm-btn" onClick={() => post("retry", item.id)}>Retry</button>
                        ) : null}
                        {item.state === "Done" || item.state === "Failed" || item.state === "Cancelled" ? (
                            <button class="cdm-btn" onClick={() => post("restart", item.id)}>&#10227; Restart</button>
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
            })}
        </div>
    </div>
}
