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
    """)
}