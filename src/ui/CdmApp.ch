// ChemicalDM — the webview UI, a single universal component.
// SSR renders the empty shell; after hydration it polls the native engine over
// the webview bridge every second and re-renders the live queue. No props.
// The bridge: window.webview_bridge.call(method, argsJson) -> JSON result
// (see webview::webview_bind; synchronous via WebKitGTK script-dialog).

#universal CdmApp(props) {
    state items = []
    state newUrl = ""
    state alert = ""
    state loading = true

    var refresh = () => {
        var d = JSON.parse(window.webview_bridge.call("state", "{}"))
        items = d.items
        loading = false
    }

    useEffect(() => {
        refresh()
        var t = setInterval(refresh, 1000)
        return () => clearInterval(t)
    }, [])

    var addDownload = () => {
        var u = newUrl.trim()
        if(u === "") return
        var d = JSON.parse(window.webview_bridge.call("add", JSON.stringify({url: u})))
        if(d.ok) { newUrl = ""; alert = ""; refresh() }
        else { alert = d.error || "Failed to add download" }
    }

    var post = (method, id) => {
        var d = JSON.parse(window.webview_bridge.call(method, JSON.stringify({id: id})))
        if(d.ok) refresh()
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

    var totalCount = items.length
    var activeCount = items.filter((u) => { return u.state === "Downloading" }).length

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
                <span class="cdm-stat">Total <b>{totalCount}</b></span>
            </div>
        </header>

        <div class="cdm-toolbar">
            <input class="cdm-url-input" type="text" spellcheck="false" autocomplete="off"
                placeholder="Paste a download URL and press Enter&#8230;" value={newUrl}
                onChange={(e) => { newUrl = e.target.value }}
                onKeyDown={(e) => { if(e.key === "Enter") addDownload() }} />
            <button class="cdm-add-btn" onClick={addDownload} disabled={newUrl.trim() === ""}>Add Download</button>
        </div>

        {alert !== "" ? <div class="cdm-alert" onClick={() => { alert = "" }}>{alert}</div> : null}

        {loading ? <div class="cdm-empty">Loading downloads&#8230;</div> : null}

        {!loading && items.length === 0 ? (
            <div class="cdm-empty">
                <div class="cdm-empty-icon">&#128229;</div>
                <p>No downloads yet.</p>
                <p class="cdm-empty-sub">Paste a URL above to start downloading.</p>
            </div>
        ) : null}

        <div class="cdm-list">
            {items.map((item) => {
                var pct = parseFloat(item.percent)
                if(isNaN(pct)) pct = 0
                if(pct < 0) pct = 0
                if(pct > 100) pct = 100
                var showProgress = item.state === "Downloading" || item.state === "Paused"
                var failed = item.state === "Failed" || item.state === "Cancelled"
                var running = item.state === "Downloading" || item.state === "Queued"
                return <div class={"cdm-item" + (failed ? " cdm-item-error" : "")}>
                    <div class="cdm-item-head">
                        <div class="cdm-item-name" title={item.url}>{item.filename}</div>
                        <span class={stateClass(item.state)}>{item.state}</span>
                    </div>
                    {showProgress ? (
                        <div class="cdm-progress">
                            <div class="cdm-progress-fill" style={"width: " + pct + "%;"}></div>
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
                        {running ? (
                            <button class="cdm-btn cdm-btn-danger" onClick={() => post("cancel", item.id)}>Cancel</button>
                        ) : null}
                        {!running ? (
                            <button class="cdm-btn cdm-btn-danger" onClick={() => post("remove", item.id)}>Remove</button>
                        ) : null}
                    </div>
                </div>
            })}
        </div>
    </div>
}