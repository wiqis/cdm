// ChemicalDM — custom UI theme on top of the shadcn tokens from the
// components library (page.injectDefaultComponentsTheme()).

using std::string_view;

public func CdmTheme(page : &mut HtmlPage) {
    page.append_css_view("""
        .cdm-app {
            max-width: 860px;
            margin: 0 auto;
            padding: 20px 20px 64px;
            display: flex;
            flex-direction: column;
            gap: 16px;
        }
        .cdm-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 16px;
            padding-bottom: 14px;
            border-bottom: 1px solid hsl(var(--border));
        }
        .cdm-header-title {
            display: flex;
            align-items: center;
            gap: 12px;
        }
        .cdm-logo {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 42px;
            height: 42px;
            border-radius: 12px;
            background: hsl(var(--primary) / 0.12);
            color: hsl(var(--primary));
            font-size: 20px;
        }
        .cdm-header h1 {
            font-size: 19px;
            font-weight: 700;
            letter-spacing: -0.02em;
            margin: 0;
        }
        .cdm-subtitle {
            font-size: 12.5px;
            color: hsl(var(--muted-foreground));
        }
        .cdm-header-stats {
            display: flex;
            gap: 12px;
        }
        .cdm-stat {
            font-size: 13px;
            color: hsl(var(--muted-foreground));
        }
        .cdm-stat b {
            color: hsl(var(--foreground));
        }
        .cdm-toolbar {
            display: flex;
            gap: 8px;
        }
        .cdm-url-input {
            flex: 1;
            padding: 10px 14px;
            font-size: 14px;
            font-family: var(--font-mono);
            background: hsl(var(--background));
            color: hsl(var(--foreground));
            border: 1px solid hsl(var(--input));
            border-radius: calc(var(--radius) - 2px);
            outline: none;
            transition: border-color 0.15s, box-shadow 0.15s;
        }
        .cdm-url-input:focus {
            border-color: hsl(var(--ring));
            box-shadow: 0 0 0 3px hsl(var(--ring) / 0.25);
        }
        .cdm-add-btn {
            padding: 10px 18px;
            font-size: 14px;
            font-weight: 600;
            color: hsl(var(--primary-foreground));
            background: hsl(var(--primary));
            border: none;
            border-radius: calc(var(--radius) - 2px);
            cursor: pointer;
            transition: opacity 0.15s;
        }
        .cdm-add-btn:hover { opacity: 0.9; }
        .cdm-add-btn:disabled { opacity: 0.4; cursor: default; }
        .cdm-alert {
            padding: 10px 14px;
            font-size: 13.5px;
            color: hsl(var(--destructive));
            background: hsl(var(--destructive) / 0.08);
            border: 1px solid hsl(var(--destructive) / 0.4);
            border-radius: calc(var(--radius) - 2px);
            cursor: pointer;
        }
        .cdm-empty {
            text-align: center;
            padding: 56px 24px;
            color: hsl(var(--muted-foreground));
            font-size: 15px;
        }
        .cdm-empty-icon {
            font-size: 40px;
            margin-bottom: 10px;
            opacity: 0.6;
        }
        .cdm-empty-sub {
            font-size: 13px;
            margin-top: 4px;
            color: hsl(var(--muted-foreground) / 0.8);
        }
        .cdm-list {
            display: flex;
            flex-direction: column;
            gap: 12px;
        }
        .cdm-item {
            background: hsl(var(--card));
            border: 1px solid hsl(var(--border));
            border-radius: var(--radius);
            padding: 14px 16px;
            display: flex;
            flex-direction: column;
            gap: 10px;
            transition: border-color 0.15s;
        }
        .cdm-item:hover { border-color: hsl(var(--ring) / 0.5); }
        .cdm-item-error { border-color: hsl(var(--destructive) / 0.5); }
        .cdm-item-head {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 12px;
        }
        .cdm-item-name {
            font-size: 14.5px;
            font-weight: 600;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .cdm-badge {
            flex-shrink: 0;
            padding: 3px 10px;
            border-radius: 999px;
            font-size: 11.5px;
            font-weight: 600;
        }
        .cdm-badge-active { background: hsl(var(--info) / 0.15); color: hsl(var(--info)); }
        .cdm-badge-done   { background: hsl(var(--success) / 0.15); color: hsl(var(--success)); }
        .cdm-badge-error  { background: hsl(var(--destructive) / 0.15); color: hsl(var(--destructive)); }
        .cdm-badge-idle   { background: hsl(var(--muted)); color: hsl(var(--muted-foreground)); }
        .cdm-progress {
            height: 8px;
            background: hsl(var(--muted));
            border-radius: 999px;
            overflow: hidden;
        }
        .cdm-progress-fill {
            height: 100%;
            background: linear-gradient(90deg, hsl(var(--info)), hsl(var(--ring)));
            border-radius: 999px;
            transition: width 0.4s ease;
        }
        .cdm-item-meta {
            display: flex;
            gap: 16px;
            font-size: 12.5px;
            color: hsl(var(--muted-foreground));
        }
        .cdm-item-pct { font-weight: 700; color: hsl(var(--foreground)); }
        .cdm-item-speed { color: hsl(var(--info)); }
        .cdm-item-eta { margin-left: auto; }
        .cdm-item-error-text {
            font-size: 12.5px;
            color: hsl(var(--destructive));
        }
        .cdm-item-actions {
            display: flex;
            gap: 8px;
        }
        .cdm-btn {
            padding: 6px 14px;
            font-size: 13px;
            font-weight: 600;
            color: hsl(var(--foreground));
            background: transparent;
            border: 1px solid hsl(var(--border));
            border-radius: calc(var(--radius) - 2px);
            cursor: pointer;
            transition: background 0.15s, border-color 0.15s;
        }
        .cdm-btn:hover { background: hsl(var(--secondary)); }
        .cdm-btn-danger { color: hsl(var(--destructive)); border-color: hsl(var(--destructive) / 0.4); }
        .cdm-btn-danger:hover { background: hsl(var(--destructive) / 0.1); }
        .cdm-btn-accent {
            padding: 6px 14px;
            font-size: 13px;
            font-weight: 600;
            color: hsl(var(--primary-foreground));
            background: hsl(var(--primary));
            border: 1px solid hsl(var(--primary));
            border-radius: calc(var(--radius) - 2px);
            cursor: pointer;
            transition: opacity 0.15s;
        }
        .cdm-btn-accent:hover { opacity: 0.85; }
        .cdm-filterbar {
            display: flex;
            gap: 6px;
            flex-wrap: wrap;
        }
        .cdm-filter-chip {
            padding: 4px 12px;
            font-size: 12px;
            font-weight: 600;
            color: hsl(var(--muted-foreground));
            background: transparent;
            border: 1px solid hsl(var(--border));
            border-radius: 999px;
            cursor: pointer;
            transition: background 0.15s, color 0.15s;
        }
        .cdm-filter-chip:hover { background: hsl(var(--secondary)); }
        .cdm-filter-chip-on {
            color: hsl(var(--primary-foreground));
            background: hsl(var(--primary));
            border-color: hsl(var(--primary));
        }
        .cdm-dialog-overlay {
            position: fixed;
            inset: 0;
            z-index: 1000;
            background: rgba(0, 0, 0, 0.55);
            display: flex;
            align-items: center;
            justify-content: center;
            backdrop-filter: blur(4px);
            animation: cdm-fade-in 0.15s ease;
        }
        @keyframes cdm-fade-in {
            from { opacity: 0; }
            to { opacity: 1; }
        }
        .cdm-dialog {
            background: hsl(var(--card));
            border: 1px solid hsl(var(--border));
            border-radius: calc(var(--radius) + 2px);
            width: 90%;
            max-width: 480px;
            max-height: 85vh;
            display: flex;
            flex-direction: column;
            box-shadow: 0 16px 48px rgba(0, 0, 0, 0.3);
            animation: cdm-dialog-in 0.18s ease;
        }
        @keyframes cdm-dialog-in {
            from { opacity: 0; transform: scale(0.96) translateY(8px); }
            to { opacity: 1; transform: scale(1) translateY(0); }
        }
        .cdm-dialog-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 16px 20px 12px;
            border-bottom: 1px solid hsl(var(--border));
        }
        .cdm-dialog-title {
            font-size: 16px;
            font-weight: 700;
        }
        .cdm-dialog-close {
            width: 28px;
            height: 28px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 15px;
            color: hsl(var(--muted-foreground));
            background: transparent;
            border: none;
            border-radius: calc(var(--radius) - 2px);
            cursor: pointer;
            transition: background 0.12s;
        }
        .cdm-dialog-close:hover { background: hsl(var(--secondary)); }
        .cdm-dialog-body {
            padding: 16px 20px;
            display: flex;
            flex-direction: column;
            gap: 14px;
            overflow-y: auto;
        }
        .cdm-dialog-body label {
            display: flex;
            flex-direction: column;
            gap: 4px;
            font-size: 12.5px;
            color: hsl(var(--muted-foreground));
        }
        .cdm-dialog-body input,
        .cdm-dialog-body select {
            padding: 8px 10px;
            font-size: 13.5px;
            font-family: var(--font-mono);
            background: hsl(var(--background));
            color: hsl(var(--foreground));
            border: 1px solid hsl(var(--input));
            border-radius: calc(var(--radius) - 2px);
            outline: none;
            transition: border-color 0.15s, box-shadow 0.15s;
        }
        .cdm-dialog-body input:focus,
        .cdm-dialog-body select:focus {
            border-color: hsl(var(--ring));
            box-shadow: 0 0 0 3px hsl(var(--ring) / 0.25);
        }
        .cdm-dialog-footer {
            display: flex;
            gap: 8px;
            justify-content: flex-end;
            padding: 12px 20px 16px;
            border-top: 1px solid hsl(var(--border));
        }
        .cdm-dialog-info {
            font-size: 12.5px;
            color: hsl(var(--muted-foreground));
            margin: 0;
            padding: 2px 0;
        }
        .cdm-item-meta-line {
            display: flex;
            gap: 10px;
            font-size: 12px;
            color: hsl(var(--muted-foreground));
            align-items: center;
            flex-wrap: wrap;
        }
        .cdm-item-cat {
            padding: 1px 8px;
            border-radius: 999px;
            background: hsl(var(--muted));
            font-weight: 600;
        }
        .cdm-item-prio { font-weight: 700; color: hsl(var(--info)); }
        .cdm-item-dir {
            margin-left: auto;
            max-width: 320px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            opacity: 0.75;
        }
        .cdm-merge-ok, .cdm-merge-fail, .cdm-merge-wait {
            padding: 1px 8px;
            border-radius: 999px;
            font-weight: 600;
            font-size: 12px;
        }
        .cdm-merge-ok { background: hsl(142 76% 36% / 0.2); color: hsl(142 76% 46%); }
        .cdm-merge-fail { background: hsl(0 84% 60% / 0.2); color: hsl(0 84% 60%); }
        .cdm-merge-wait { background: hsl(48 96% 53% / 0.2); color: hsl(48 96% 53%); }
        .cdm-ctx-menu {
            position: fixed;
            z-index: 2000;
            min-width: 180px;
            background: hsl(var(--card));
            border: 1px solid hsl(var(--border));
            border-radius: var(--radius);
            box-shadow: 0 8px 24px rgba(0, 0, 0, 0.25);
            padding: 4px 0;
            animation: cdm-ctx-in 0.1s ease;
        }
        @keyframes cdm-ctx-in {
            from { opacity: 0; transform: scale(0.95); }
            to { opacity: 1; transform: scale(1); }
        }
        .cdm-ctx-item {
            padding: 7px 14px;
            font-size: 13px;
            cursor: pointer;
            color: hsl(var(--foreground));
            transition: background 0.1s;
        }
        .cdm-ctx-item:hover { background: hsl(var(--secondary)); }
        .cdm-ctx-danger { color: hsl(var(--destructive)); }
        .cdm-ctx-danger:hover { background: hsl(var(--destructive) / 0.08); }
        .cdm-ctx-sep {
            height: 1px;
            margin: 4px 0;
            background: hsl(var(--border));
        }
        .cdm-segments {
            display: flex;
            gap: 2px;
            height: 6px;
        }
        .cdm-seg {
            position: relative;
            background: hsl(var(--muted));
            border-radius: 3px;
            overflow: hidden;
        }
        .cdm-seg-fill {
            height: 100%;
            border-radius: 3px;
            transition: width 0.4s ease;
        }
        .cdm-seg-done .cdm-seg-fill {
            background: hsl(var(--success));
        }
        .cdm-seg-active .cdm-seg-fill {
            background: linear-gradient(90deg, hsl(var(--info)), hsl(var(--ring)));
        }
        .cdm-seg-pending .cdm-seg-fill {
            background: hsl(var(--muted));
        }
        .cdm-filter-row {
            display: flex;
            gap: 6px;
            flex-wrap: wrap;
            align-items: center;
        }
        .cdm-filter-secondary {
            margin-top: 4px;
        }
        .cdm-filter-sep {
            width: 1px;
            height: 20px;
            background: hsl(var(--border));
            margin: 0 4px;
        }
        .cdm-filter-cat {
            font-size: 11px;
            padding: 3px 10px;
        }
        .cdm-search-input {
            flex: 1;
            min-width: 180px;
            padding: 5px 10px;
            font-size: 12.5px;
            font-family: var(--font-mono);
            background: hsl(var(--background));
            color: hsl(var(--foreground));
            border: 1px solid hsl(var(--input));
            border-radius: calc(var(--radius) - 2px);
            outline: none;
            transition: border-color 0.15s, box-shadow 0.15s;
        }
        .cdm-search-input:focus {
            border-color: hsl(var(--ring));
            box-shadow: 0 0 0 2px hsl(var(--ring) / 0.2);
        }
        .cdm-sort-select {
            padding: 5px 8px;
            font-size: 12px;
            font-family: var(--font-mono);
            background: hsl(var(--background));
            color: hsl(var(--foreground));
            border: 1px solid hsl(var(--input));
            border-radius: calc(var(--radius) - 2px);
            outline: none;
            cursor: pointer;
        }
        .cdm-toggle-row {
            display: flex;
            align-items: center;
        }
        .cdm-toggle-label {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 13px;
            color: hsl(var(--foreground));
            cursor: pointer;
        }
        .cdm-toggle-label input[type="checkbox"] {
            width: 16px;
            height: 16px;
            accent-color: hsl(var(--primary));
            cursor: pointer;
        }
        /* ---- YouTube download styles ---- */
        .cdm-yt-btn {
            padding: 10px 18px;
            font-size: 14px;
            font-weight: 600;
            color: hsl(var(--primary-foreground));
            background: #ff0000;
            border: none;
            border-radius: calc(var(--radius) - 2px);
            cursor: pointer;
            transition: opacity 0.15s;
            display: flex;
            align-items: center;
            gap: 6px;
        }
        .cdm-yt-btn:hover { opacity: 0.9; }
        .cdm-yt-btn:disabled { opacity: 0.4; cursor: default; }
        .cdm-yt-icon {
            width: 18px;
            height: 18px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
        }
        .cdm-yt-info-card {
            background: hsl(var(--card));
            border: 1px solid hsl(var(--border));
            border-radius: var(--radius);
            padding: 16px;
            display: flex;
            flex-direction: column;
            gap: 12px;
        }
        .cdm-yt-title {
            font-size: 15px;
            font-weight: 600;
            color: hsl(var(--foreground));
        }
        .cdm-yt-meta {
            font-size: 13px;
            color: hsl(var(--muted-foreground));
            display: flex;
            gap: 12px;
        }
        .cdm-yt-formats {
            display: flex;
            flex-direction: column;
            gap: 6px;
            max-height: 200px;
            overflow-y: auto;
            border: 1px solid hsl(var(--border));
            border-radius: calc(var(--radius) - 2px);
            padding: 4px;
        }
        .cdm-yt-format-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 8px 12px;
            border-radius: calc(var(--radius) - 4px);
            cursor: pointer;
            transition: background 0.1s;
            font-size: 13px;
            color: hsl(var(--foreground));
        }
        .cdm-yt-format-item:hover { background: hsl(var(--secondary)); }
        .cdm-yt-format-item-selected {
            background: hsl(var(--primary) / 0.12);
            border: 1px solid hsl(var(--primary) / 0.3);
        }
        .cdm-yt-format-label { flex: 1; }
        .cdm-yt-format-size {
            font-size: 12px;
            color: hsl(var(--muted-foreground));
            margin-left: 8px;
        }
        .cdm-yt-playlist-item {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 8px 12px;
            border-radius: calc(var(--radius) - 4px);
            font-size: 13px;
            color: hsl(var(--foreground));
            border-bottom: 1px solid hsl(var(--border));
        }
        .cdm-yt-playlist-item:last-child { border-bottom: none; }
        .cdm-yt-playlist-idx {
            font-size: 12px;
            color: hsl(var(--muted-foreground));
            min-width: 30px;
        }
        .cdm-yt-playlist-title { flex: 1; }
        .cdm-yt-playlist-dur {
            font-size: 12px;
            color: hsl(var(--muted-foreground));
        }
        .cdm-yt-tool-status {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 12px 16px;
            background: hsl(var(--card));
            border: 1px solid hsl(var(--border));
            border-radius: var(--radius);
        }
        .cdm-yt-tool-dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            flex-shrink: 0;
        }
        .cdm-yt-tool-dot-ok { background: hsl(var(--success)); }
        .cdm-yt-tool-dot-miss { background: hsl(var(--destructive)); }
        .cdm-yt-tool-name {
            font-size: 14px;
            font-weight: 600;
            color: hsl(var(--foreground));
        }
        .cdm-yt-tool-ver {
            font-size: 12px;
            color: hsl(var(--muted-foreground));
        }
        .cdm-yt-tool-install {
            margin-left: auto;
        }
        .cdm-yt-progress {
            background: hsl(var(--card));
            border: 1px solid hsl(var(--border));
            border-radius: var(--radius);
            padding: 14px 16px;
            display: flex;
            flex-direction: column;
            gap: 8px;
        }
        .cdm-yt-progress-header {
            display: flex;
            justify-content: space-between;
            font-size: 13px;
        }
        .cdm-yt-progress-title {
            font-weight: 600;
            color: hsl(var(--foreground));
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .cdm-yt-progress-status {
            color: hsl(var(--muted-foreground));
            font-size: 12px;
        }
        .cdm-yt-progress-bar {
            height: 6px;
            background: hsl(var(--muted));
            border-radius: 999px;
            overflow: hidden;
        }
        .cdm-yt-progress-fill {
            height: 100%;
            background: #ff0000;
            border-radius: 999px;
            transition: width 0.3s ease;
        }
        .cdm-yt-progress-meta {
            display: flex;
            gap: 12px;
            font-size: 12px;
            color: hsl(var(--muted-foreground));
        }
        .cdm-yt-progress-speed { color: hsl(var(--info)); }
        .cdm-yt-toast {
            position: fixed;
            bottom: 20px;
            right: 20px;
            z-index: 9999;
            padding: 12px 20px;
            border-radius: var(--radius);
            font-size: 13px;
            font-weight: 500;
            box-shadow: 0 8px 24px rgba(0,0,0,0.2);
            animation: cdm-toast-in 0.3s ease;
            cursor: pointer;
        }
        .cdm-yt-toast-success {
            background: hsl(var(--success));
            color: white;
        }
        .cdm-yt-toast-error {
            background: hsl(var(--destructive));
            color: white;
        }
        .cdm-yt-toast-info {
            background: hsl(var(--info));
            color: white;
        }
        @keyframes cdm-toast-in {
            from { opacity: 0; transform: translateY(12px); }
            to { opacity: 1; transform: translateY(0); }
        }
        .cdm-yt-spinner {
            display: inline-block;
            width: 16px;
            height: 16px;
            border: 2px solid hsl(var(--border));
            border-top-color: hsl(var(--primary));
            border-radius: 50%;
            animation: cdm-spin 0.6s linear infinite;
        }
        @keyframes cdm-spin {
            to { transform: rotate(360deg); }
        }
        .cdm-yt-quality-select {
            display: flex;
            gap: 6px;
            flex-wrap: wrap;
        }
        .cdm-yt-quality-chip {
            padding: 4px 12px;
            font-size: 12px;
            font-weight: 600;
            color: hsl(var(--muted-foreground));
            background: transparent;
            border: 1px solid hsl(var(--border));
            border-radius: 999px;
            cursor: pointer;
            transition: background 0.15s, color 0.15s;
        }
        .cdm-yt-quality-chip:hover { background: hsl(var(--secondary)); }
        .cdm-yt-quality-chip-on {
            color: hsl(var(--primary-foreground));
            background: #ff0000;
            border-color: #ff0000;
        }
        .cdm-yt-tool-status {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 12px 14px;
            background: hsl(var(--card));
            border: 1px solid hsl(var(--border));
            border-radius: calc(var(--radius) - 2px);
        }
        .cdm-yt-tool-dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            flex-shrink: 0;
        }
        .cdm-yt-tool-dot-ok {
            background: hsl(var(--success));
        }
        .cdm-yt-tool-dot-miss {
            background: hsl(var(--muted-foreground) / 0.4);
        }
        .cdm-yt-tool-name {
            font-size: 14px;
            font-weight: 600;
            color: hsl(var(--foreground));
        }
        .cdm-yt-tool-ver {
            font-size: 12px;
            color: hsl(var(--muted-foreground));
        }
        .cdm-yt-tool-install {
            margin-left: auto;
            flex-shrink: 0;
        }
        .cdm-yt-dl-progress {
            padding: 12px 0;
            display: flex;
            flex-direction: column;
            gap: 6px;
        }
        .cdm-yt-dl-meta {
            display: flex;
            gap: 16px;
            font-size: 13px;
            color: hsl(var(--muted-foreground));
            align-items: center;
        }
        .cdm-yt-dl-pct {
            font-weight: 700;
            color: hsl(var(--foreground));
            min-width: 48px;
        }
        .cdm-yt-dl-speed {
            color: hsl(var(--info));
            font-weight: 600;
        }
        .cdm-yt-dl-eta {
            margin-left: auto;
        }
    """)
}