// ChemicalDM — UI theme (v2).
//
// Design rules (deliberate):
//   - Flat dark surfaces. Elevation via hairline 1px borders only — no glows,
//     no gradients, no backdrop blur, no tinted tiles.
//   - ONE accent (indigo-blue) used sparingly: primary buttons, progress fill,
//     active states. Everything else is neutral.
//   - App layout: fixed sidebar (nav + categories) / topbar / scrolling content.
//   - Dense list rows with hover-revealed actions, tabular numerals.

using std::string_view;

public func CdmTheme(page : &mut HtmlPage) {
    page.append_css_view("""
        /* ================================================================
           1. TOKENS & BASE
           ================================================================ */
        :root {
            --accent: 216 92% 58%;
            --ok: 152 48% 46%;
            --warn: 38 80% 54%;
            --bad: 0 68% 58%;
            --r: 8px;
        }

        html, body { margin: 0; padding: 0; }

        ::selection { background: hsl(var(--accent) / 0.3); }

        ::-webkit-scrollbar { width: 9px; height: 9px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb {
            background: hsl(var(--muted-foreground) / 0.22);
            border-radius: 8px;
            border: 2px solid transparent;
            background-clip: padding-box;
        }
        ::-webkit-scrollbar-thumb:hover { background-color: hsl(var(--muted-foreground) / 0.38); }

        button { font-family: inherit; }
        button:focus-visible, input:focus-visible, select:focus-visible {
            outline: 2px solid hsl(var(--accent) / 0.55);
            outline-offset: 1px;
        }

        /* ================================================================
           2. ICONS (CSS mask, recolorable via currentColor)
           ================================================================ */
        .cdm-ic {
            display: inline-block;
            width: 15px;
            height: 15px;
            flex-shrink: 0;
            background-color: currentColor;
            -webkit-mask-repeat: no-repeat;
            -webkit-mask-position: center;
            -webkit-mask-size: contain;
            mask-repeat: no-repeat;
            mask-position: center;
            mask-size: contain;
        }
        .cdm-ic-plus {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M12 5v14M5 12h14'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M12 5v14M5 12h14'/%3E%3C/svg%3E");
        }
        .cdm-ic-clipboard {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2'/%3E%3Crect x='8' y='2' width='8' height='4' rx='1' ry='1'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2'/%3E%3Crect x='8' y='2' width='8' height='4' rx='1' ry='1'/%3E%3C/svg%3E");
        }
        .cdm-ic-play {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='white'%3E%3Cpath d='M6 4l14 8-14 8z'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='white'%3E%3Cpath d='M6 4l14 8-14 8z'/%3E%3C/svg%3E");
        }
        .cdm-ic-wrench {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z'/%3E%3C/svg%3E");
        }
        .cdm-ic-sliders {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6'/%3E%3C/svg%3E");
        }
        .cdm-ic-link {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71'/%3E%3Cpath d='M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71'/%3E%3Cpath d='M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71'/%3E%3C/svg%3E");
        }
        .cdm-ic-download {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3'/%3E%3C/svg%3E");
        }
        .cdm-ic-file {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z'/%3E%3Cpath d='M14 2v6h6'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z'/%3E%3Cpath d='M14 2v6h6'/%3E%3C/svg%3E");
        }
        .cdm-ic-film {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Crect x='2' y='2' width='20' height='20' rx='2.18'/%3E%3Cpath d='M7 2v20M17 2v20M2 12h20M2 7h5M2 17h5M17 17h5M17 7h5'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Crect x='2' y='2' width='20' height='20' rx='2.18'/%3E%3Cpath d='M7 2v20M17 2v20M2 12h20M2 7h5M2 17h5M17 17h5M17 7h5'/%3E%3C/svg%3E");
        }
        .cdm-ic-music {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M9 18V5l12-2v13'/%3E%3Ccircle cx='6' cy='18' r='3'/%3E%3Ccircle cx='18' cy='16' r='3'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M9 18V5l12-2v13'/%3E%3Ccircle cx='6' cy='18' r='3'/%3E%3Ccircle cx='18' cy='16' r='3'/%3E%3C/svg%3E");
        }
        .cdm-ic-archive {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M21 8v13H3V8'/%3E%3Cpath d='M1 3h22v5H1z'/%3E%3Cpath d='M10 12h4'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M21 8v13H3V8'/%3E%3Cpath d='M1 3h22v5H1z'/%3E%3Cpath d='M10 12h4'/%3E%3C/svg%3E");
        }
        .cdm-ic-terminal {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M4 17l6-6-6-6'/%3E%3Cpath d='M12 19h8'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M4 17l6-6-6-6'/%3E%3Cpath d='M12 19h8'/%3E%3C/svg%3E");
        }
        .cdm-ic-folder {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z'/%3E%3C/svg%3E");
        }
        .cdm-ic-inbox {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M22 12h-6l-2 3h-4l-2-3H2'/%3E%3Cpath d='M5.45 5.11L2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M22 12h-6l-2 3h-4l-2-3H2'/%3E%3Cpath d='M5.45 5.11L2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z'/%3E%3C/svg%3E");
        }
        .cdm-ic-pause {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='white'%3E%3Crect x='6' y='4' width='4' height='16' rx='1'/%3E%3Crect x='14' y='4' width='4' height='16' rx='1'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='white'%3E%3Crect x='6' y='4' width='4' height='16' rx='1'/%3E%3Crect x='14' y='4' width='4' height='16' rx='1'/%3E%3C/svg%3E");
        }
        .cdm-ic-retry {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8'/%3E%3Cpath d='M3 3v5h5'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8'/%3E%3Cpath d='M3 3v5h5'/%3E%3C/svg%3E");
        }
        .cdm-ic-restart {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8'/%3E%3Cpath d='M21 3v5h-5'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8'/%3E%3Cpath d='M21 3v5h-5'/%3E%3C/svg%3E");
        }
        .cdm-ic-xcircle {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Ccircle cx='12' cy='12' r='10'/%3E%3Cpath d='M15 9l-6 6M9 9l6 6'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Ccircle cx='12' cy='12' r='10'/%3E%3Cpath d='M15 9l-6 6M9 9l6 6'/%3E%3C/svg%3E");
        }
        .cdm-ic-trash {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M3 6h18'/%3E%3Cpath d='M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6'/%3E%3Cpath d='M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2'/%3E%3Cpath d='M10 11v6M14 11v6'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M3 6h18'/%3E%3Cpath d='M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6'/%3E%3Cpath d='M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2'/%3E%3Cpath d='M10 11v6M14 11v6'/%3E%3C/svg%3E");
        }
        .cdm-ic-external {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6'/%3E%3Cpath d='M15 3h6v6'/%3E%3Cpath d='M10 14L21 3'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6'/%3E%3Cpath d='M15 3h6v6'/%3E%3Cpath d='M10 14L21 3'/%3E%3C/svg%3E");
        }
        .cdm-ic-check {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M20 6L9 17l-5-5'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M20 6L9 17l-5-5'/%3E%3C/svg%3E");
        }
        .cdm-ic-clock {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Ccircle cx='12' cy='12' r='10'/%3E%3Cpath d='M12 6v6l4 2'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Ccircle cx='12' cy='12' r='10'/%3E%3Cpath d='M12 6v6l4 2'/%3E%3C/svg%3E");
        }
        .cdm-ic-alert {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z'/%3E%3Cpath d='M12 9v4M12 17h.01'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z'/%3E%3Cpath d='M12 9v4M12 17h.01'/%3E%3C/svg%3E");
        }
        .cdm-ic-merge {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M23 4v6h-6'/%3E%3Cpath d='M1 20v-6h6'/%3E%3Cpath d='M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M23 4v6h-6'/%3E%3Cpath d='M1 20v-6h6'/%3E%3Cpath d='M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15'/%3E%3C/svg%3E");
        }
        .cdm-ic-search {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Ccircle cx='11' cy='11' r='8'/%3E%3Cpath d='M21 21l-4.35-4.35'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Ccircle cx='11' cy='11' r='8'/%3E%3Cpath d='M21 21l-4.35-4.35'/%3E%3C/svg%3E");
        }

        /* ================================================================
           3. APP SHELL — sidebar + main
           ================================================================ */
        .cdm-shell {
            display: flex;
            height: 100vh;
            background: hsl(var(--background));
            color: hsl(var(--foreground));
        }

        /* ---- Sidebar ---- */
        .cdm-side {
            display: flex;
            flex-direction: column;
            width: 218px;
            flex-shrink: 0;
            background: hsl(var(--card) / 0.5);
            border-right: 1px solid hsl(var(--border));
        }
        .cdm-side-brand {
            display: flex;
            align-items: center;
            gap: 9px;
            padding: 14px 14px 10px;
        }
        .cdm-side-mark {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 24px;
            height: 24px;
            border-radius: 7px;
            color: white;
            background: hsl(var(--accent));
            flex-shrink: 0;
        }
        .cdm-side-mark .cdm-ic { width: 13px; height: 13px; }
        .cdm-side-name { font-size: 13px; font-weight: 700; letter-spacing: -0.01em; }

        .cdm-side-scroll { flex: 1; overflow-y: auto; padding: 4px 8px 8px; }
        .cdm-side-label {
            padding: 12px 8px 5px;
            font-size: 10.5px;
            font-weight: 700;
            letter-spacing: 0.07em;
            text-transform: uppercase;
            color: hsl(var(--muted-foreground) / 0.8);
        }
        .cdm-side-item {
            display: flex;
            align-items: center;
            gap: 9px;
            width: 100%;
            padding: 6px 8px;
            font-size: 13px;
            font-weight: 500;
            color: hsl(var(--muted-foreground));
            background: transparent;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            text-align: left;
            transition: background 0.1s, color 0.1s;
        }
        .cdm-side-item:hover { background: hsl(var(--secondary) / 0.7); color: hsl(var(--foreground)); }
        .cdm-side-item-on {
            background: hsl(var(--secondary));
            color: hsl(var(--foreground));
            font-weight: 600;
        }
        .cdm-side-item .cdm-ic { width: 14px; height: 14px; }
        .cdm-side-count {
            margin-left: auto;
            font-size: 11px;
            font-weight: 500;
            color: hsl(var(--muted-foreground) / 0.7);
            font-variant-numeric: tabular-nums;
        }
        .cdm-side-item-on .cdm-side-count { color: hsl(var(--muted-foreground)); }

        .cdm-side-foot {
            padding: 10px;
            border-top: 1px solid hsl(var(--border));
            display: flex;
            flex-direction: column;
            gap: 2px;
        }

        /* ---- Main column ---- */
        .cdm-main {
            display: flex;
            flex-direction: column;
            flex: 1;
            min-width: 0;
        }
        .cdm-topbar {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 10px 16px;
            border-bottom: 1px solid hsl(var(--border));
            flex-shrink: 0;
        }
        .cdm-topbar-spacer { flex: 1; }
        .cdm-search-input {
            width: 240px;
            padding: 6px 10px 6px 28px;
            font-size: 12.5px;
            font-family: var(--font-mono);
            color: hsl(var(--foreground));
            background-color: hsl(var(--muted) / 0.4);
            background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23888' stroke-width='2' stroke-linecap='round'%3E%3Ccircle cx='11' cy='11' r='8'/%3E%3Cpath d='M21 21l-4.35-4.35'/%3E%3C/svg%3E");
            background-repeat: no-repeat;
            background-position: 9px center;
            background-size: 12px 12px;
            border: 1px solid transparent;
            border-radius: var(--r);
            outline: none;
            transition: border-color 0.12s, background-color 0.12s;
        }
        .cdm-search-input:focus {
            border-color: hsl(var(--accent) / 0.5);
            background-color: hsl(var(--background));
        }
        .cdm-search-input::placeholder { color: hsl(var(--muted-foreground) / 0.55); }
        .cdm-sort-select {
            padding: 6px 26px 6px 9px;
            font-size: 12px;
            font-family: var(--font-mono);
            color: hsl(var(--foreground));
            background-color: hsl(var(--muted) / 0.4);
            border: 1px solid transparent;
            border-radius: var(--r);
            outline: none;
            cursor: pointer;
            -webkit-appearance: none;
            appearance: none;
            background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 12 12'%3E%3Cpath fill='%23888' d='M2 4l4 4 4-4'/%3E%3C/svg%3E");
            background-repeat: no-repeat;
            background-position: right 8px center;
        }

        .cdm-commandbar {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 12px 16px;
            flex-shrink: 0;
        }
        .cdm-url-field {
            display: flex;
            align-items: center;
            gap: 8px;
            flex: 1;
            min-width: 0;
            padding: 0 10px;
            background: hsl(var(--muted) / 0.4);
            border: 1px solid transparent;
            border-radius: var(--r);
            transition: border-color 0.12s, background-color 0.12s;
        }
        .cdm-url-field:focus-within {
            border-color: hsl(var(--accent) / 0.5);
            background-color: hsl(var(--background));
        }
        .cdm-command-ic { color: hsl(var(--muted-foreground) / 0.7); }
        .cdm-url-input {
            flex: 1;
            min-width: 0;
            padding: 8px 0;
            font-size: 13.5px;
            font-family: var(--font-mono);
            background: transparent;
            color: hsl(var(--foreground));
            border: none;
            outline: none;
        }
        .cdm-url-input::placeholder { color: hsl(var(--muted-foreground) / 0.5); }

        .cdm-content {
            flex: 1;
            overflow-y: auto;
            padding: 0 16px 24px;
        }

        /* ================================================================
           4. BUTTONS
           ================================================================ */
        .cdm-btn {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 6px 11px;
            font-size: 12.5px;
            font-weight: 500;
            color: hsl(var(--foreground));
            background: transparent;
            border: 1px solid hsl(var(--border));
            border-radius: var(--r);
            cursor: pointer;
            white-space: nowrap;
            transition: background 0.1s, border-color 0.1s;
        }
        .cdm-btn:hover { background: hsl(var(--secondary)); }
        .cdm-btn:disabled { opacity: 0.4; cursor: default; }
        .cdm-btn:disabled:hover { background: transparent; }

        .cdm-btn-danger { color: hsl(var(--bad)); border-color: hsl(var(--bad) / 0.35); }
        .cdm-btn-danger:hover { background: hsl(var(--bad) / 0.1); }
        .cdm-btn-warn { color: hsl(var(--warn)); border-color: hsl(var(--warn) / 0.4); }
        .cdm-btn-warn:hover { background: hsl(var(--warn) / 0.1); }

        .cdm-btn-accent, .cdm-add-btn {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 6px 13px;
            font-size: 12.5px;
            font-weight: 600;
            color: white;
            background: hsl(var(--accent));
            border: 1px solid transparent;
            border-radius: var(--r);
            cursor: pointer;
            white-space: nowrap;
            transition: filter 0.1s;
        }
        .cdm-add-btn { padding: 8px 15px; font-size: 13px; }
        .cdm-btn-accent:hover, .cdm-add-btn:hover { filter: brightness(1.1); }
        .cdm-btn-accent:disabled, .cdm-add-btn:disabled { opacity: 0.4; cursor: default; filter: none; }

        .cdm-yt-btn {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 6px 11px;
            font-size: 12.5px;
            font-weight: 500;
            color: hsl(var(--bad));
            background: transparent;
            border: 1px solid hsl(var(--bad) / 0.35);
            border-radius: var(--r);
            cursor: pointer;
            white-space: nowrap;
            transition: background 0.1s;
        }
        .cdm-yt-btn:hover { background: hsl(var(--bad) / 0.1); }
        .cdm-yt-btn:disabled { opacity: 0.4; cursor: default; }

        .cdm-iconbtn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 26px;
            height: 26px;
            padding: 0;
            color: hsl(var(--muted-foreground));
            background: transparent;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            transition: background 0.1s, color 0.1s;
        }
        .cdm-iconbtn:hover { background: hsl(var(--secondary)); color: hsl(var(--foreground)); }
        .cdm-iconbtn-danger:hover { background: hsl(var(--bad) / 0.12); color: hsl(var(--bad)); }
        .cdm-iconbtn .cdm-ic { width: 14px; height: 14px; }

        .cdm-btn-spin {
            display: inline-block;
            width: 13px;
            height: 13px;
            border: 2px solid hsl(var(--border));
            border-top-color: hsl(var(--accent));
            border-radius: 50%;
            animation: cdm-spin 0.5s linear infinite;
        }
        @keyframes cdm-spin { to { transform: rotate(360deg); } }

        .cdm-alert {
            display: flex;
            align-items: center;
            gap: 9px;
            margin: 0 0 10px;
            padding: 9px 12px;
            font-size: 13px;
            color: hsl(var(--bad));
            background: hsl(var(--bad) / 0.08);
            border: 1px solid hsl(var(--bad) / 0.25);
            border-radius: var(--r);
            cursor: pointer;
        }
        .cdm-alert .cdm-ic { width: 14px; height: 14px; }

        /* ================================================================
           5. DOWNLOAD ROWS
           ================================================================ */
        .cdm-list { display: flex; flex-direction: column; }

        .cdm-row {
            display: flex;
            align-items: flex-start;
            gap: 12px;
            padding: 11px 10px;
            border-bottom: 1px solid hsl(var(--border) / 0.6);
            transition: background 0.1s;
        }
        .cdm-row:hover { background: hsl(var(--secondary) / 0.45); }
        .cdm-row-error .cdm-row-name { color: hsl(var(--bad)); }

        .cdm-ficon {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 30px;
            height: 30px;
            border-radius: 7px;
            color: hsl(var(--muted-foreground));
            background: hsl(var(--muted) / 0.55);
            flex-shrink: 0;
            margin-top: 1px;
        }
        .cdm-ficon::after {
            content: "";
            width: 15px;
            height: 15px;
            background-color: currentColor;
            -webkit-mask-repeat: no-repeat;
            -webkit-mask-position: center;
            -webkit-mask-size: contain;
            mask-repeat: no-repeat;
            mask-position: center;
            mask-size: contain;
        }
        .cdm-ficon-file::after, .cdm-ficon-other::after {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z'/%3E%3Cpath d='M14 2v6h6'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z'/%3E%3Cpath d='M14 2v6h6'/%3E%3C/svg%3E");
        }
        .cdm-ficon-documents::after {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z'/%3E%3Cpath d='M14 2v6h6'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z'/%3E%3Cpath d='M14 2v6h6'/%3E%3C/svg%3E");
        }
        .cdm-ficon-programs::after {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M4 17l6-6-6-6'/%3E%3Cpath d='M12 19h8'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M4 17l6-6-6-6'/%3E%3Cpath d='M12 19h8'/%3E%3C/svg%3E");
        }
        .cdm-ficon-video::after {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Crect x='2' y='2' width='20' height='20' rx='2.18'/%3E%3Cpath d='M7 2v20M17 2v20M2 12h20M2 7h5M2 17h5M17 17h5M17 7h5'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Crect x='2' y='2' width='20' height='20' rx='2.18'/%3E%3Cpath d='M7 2v20M17 2v20M2 12h20M2 7h5M2 17h5M17 17h5M17 7h5'/%3E%3C/svg%3E");
        }
        .cdm-ficon-music::after {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M9 18V5l12-2v13'/%3E%3Ccircle cx='6' cy='18' r='3'/%3E%3Ccircle cx='18' cy='16' r='3'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M9 18V5l12-2v13'/%3E%3Ccircle cx='6' cy='18' r='3'/%3E%3Ccircle cx='18' cy='16' r='3'/%3E%3C/svg%3E");
        }
        .cdm-ficon-compressed::after {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M21 8v13H3V8'/%3E%3Cpath d='M1 3h22v5H1z'/%3E%3Cpath d='M10 12h4'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M21 8v13H3V8'/%3E%3Cpath d='M1 3h22v5H1z'/%3E%3Cpath d='M10 12h4'/%3E%3C/svg%3E");
        }
        .cdm-ficon-yt {
            color: hsl(var(--bad));
            background: hsl(var(--bad) / 0.1);
        }
        .cdm-ficon-yt::after {
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='white'%3E%3Cpath d='M6 4l14 8-14 8z'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='white'%3E%3Cpath d='M6 4l14 8-14 8z'/%3E%3C/svg%3E");
        }

        .cdm-row-body { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 5px; }
        .cdm-row-top {
            display: flex;
            align-items: baseline;
            gap: 12px;
            min-width: 0;
        }
        .cdm-row-name {
            flex: 1;
            min-width: 0;
            font-size: 13.5px;
            font-weight: 550;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .cdm-row-size {
            flex-shrink: 0;
            font-size: 11.5px;
            color: hsl(var(--muted-foreground));
            font-variant-numeric: tabular-nums;
        }
        .cdm-row-sub {
            display: flex;
            align-items: center;
            gap: 10px;
            font-size: 11.5px;
            color: hsl(var(--muted-foreground));
            font-variant-numeric: tabular-nums;
            min-width: 0;
        }
        .cdm-row-dir {
            max-width: 260px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            opacity: 0.75;
            font-family: var(--font-mono);
            font-size: 10.5px;
        }
        .cdm-row-speed { color: hsl(var(--accent)); font-weight: 600; }
        .cdm-row-err {
            color: hsl(var(--bad));
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .cdm-row-pct {
            flex-shrink: 0;
            width: 46px;
            text-align: right;
            font-size: 12.5px;
            font-weight: 600;
            font-variant-numeric: tabular-nums;
            align-self: center;
            color: hsl(var(--muted-foreground));
        }
        .cdm-row-end {
            display: flex;
            align-items: center;
            gap: 4px;
            flex-shrink: 0;
            align-self: center;
        }
        .cdm-row-actions {
            display: flex;
            align-items: center;
            gap: 2px;
            opacity: 0;
            transition: opacity 0.12s;
        }
        .cdm-row:hover .cdm-row-actions,
        .cdm-row:focus-within .cdm-row-actions { opacity: 1; }

        /* ---- State labels (small, flat) ---- */
        .cdm-badge {
            display: inline-flex;
            align-items: center;
            flex-shrink: 0;
            padding: 1px 7px;
            border-radius: 5px;
            font-size: 10.5px;
            font-weight: 650;
            letter-spacing: 0.02em;
        }
        .cdm-badge-active { background: hsl(var(--accent) / 0.13); color: hsl(var(--accent)); }
        .cdm-badge-done { background: hsl(var(--ok) / 0.13); color: hsl(var(--ok)); }
        .cdm-badge-error { background: hsl(var(--bad) / 0.12); color: hsl(var(--bad)); }
        .cdm-badge-idle { background: hsl(var(--muted) / 0.8); color: hsl(var(--muted-foreground)); }

        /* ---- Progress ---- */
        .cdm-progress {
            height: 3px;
            background: hsl(var(--muted) / 0.8);
            border-radius: 2px;
            overflow: hidden;
        }
        .cdm-progress-fill {
            height: 100%;
            background: hsl(var(--accent));
            border-radius: 2px;
            transition: width 0.5s cubic-bezier(0.22, 1, 0.36, 1);
        }

        .cdm-segments {
            display: flex;
            gap: 2px;
            height: 3px;
        }
        .cdm-seg {
            position: relative;
            background: hsl(var(--muted) / 0.8);
            border-radius: 2px;
            overflow: hidden;
        }
        .cdm-seg-fill { height: 100%; transition: width 0.5s cubic-bezier(0.22, 1, 0.36, 1); }
        .cdm-seg-done .cdm-seg-fill { background: hsl(var(--accent)); }
        .cdm-seg-active .cdm-seg-fill { background: hsl(var(--accent) / 0.65); }
        .cdm-seg-pending .cdm-seg-fill { background: transparent; }

        /* ================================================================
           6. YOUTUBE CONTAINER CARDS (playlist / combined)
           ================================================================ */
        .cdm-yt-combined, .cdm-yt-playlist {
            border: 1px solid hsl(var(--border));
            border-radius: 10px;
            padding: 12px 14px;
            margin: 8px 0;
            display: flex;
            flex-direction: column;
            gap: 9px;
            background: hsl(var(--card) / 0.4);
        }
        .cdm-item-head { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
        .cdm-item-title { display: flex; align-items: center; gap: 11px; min-width: 0; flex: 1; }
        .cdm-item-titletext { display: flex; flex-direction: column; gap: 4px; min-width: 0; }
        .cdm-item-name {
            font-size: 13.5px;
            font-weight: 600;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .cdm-item-meta-line {
            display: flex;
            gap: 8px;
            font-size: 11px;
            color: hsl(var(--muted-foreground));
            align-items: center;
            flex-wrap: wrap;
        }
        .cdm-item-cat {
            padding: 1px 6px;
            border-radius: 4px;
            background: hsl(var(--muted) / 0.7);
            font-size: 10px;
            font-weight: 650;
            letter-spacing: 0.04em;
            text-transform: uppercase;
        }
        .cdm-item-pct {
            font-weight: 600;
            font-variant-numeric: tabular-nums;
        }
        .cdm-item-meta {
            display: flex;
            align-items: center;
            gap: 12px;
            font-size: 11.5px;
            color: hsl(var(--muted-foreground));
            font-variant-numeric: tabular-nums;
        }
        .cdm-item-speed { color: hsl(var(--accent)); }
        .cdm-item-eta { margin-left: auto; }
        .cdm-item-actions { display: flex; gap: 6px; flex-wrap: wrap; }
        .cdm-item-actions .cdm-btn { padding: 4px 10px; font-size: 12px; }
        .cdm-item-error-text {
            font-size: 12px;
            color: hsl(var(--bad));
        }
        .cdm-item-prio {
            font-weight: 600;
            font-size: 11px;
            color: hsl(var(--accent));
        }
        .cdm-item-dir {
            margin-left: auto;
            max-width: 300px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            opacity: 0.7;
            font-family: var(--font-mono);
            font-size: 10.5px;
        }

        .cdm-yt-row { padding: 7px 0 8px; border-top: 1px solid hsl(var(--border) / 0.6); }
        .cdm-yt-row:first-of-type { border-top: none; }
        .cdm-yt-row-error .cdm-yt-row-label { color: hsl(var(--bad)); }
        .cdm-yt-row-head { display: flex; align-items: center; gap: 8px; margin-bottom: 5px; }
        .cdm-yt-row-label {
            font-weight: 650;
            font-size: 10px;
            text-transform: uppercase;
            letter-spacing: 0.06em;
            color: hsl(var(--muted-foreground));
            min-width: 42px;
            text-align: center;
            padding: 2px 6px;
            border-radius: 4px;
            background: hsl(var(--muted) / 0.7);
        }
        .cdm-yt-row-name {
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-size: 12px;
        }
        .cdm-yt-row .cdm-item-meta { margin-top: 4px; font-size: 11px; }

        .cdm-merge-ok, .cdm-merge-fail, .cdm-merge-wait {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 2px 8px;
            border-radius: 5px;
            font-weight: 600;
            font-size: 11px;
            flex-shrink: 0;
        }
        .cdm-merge-ok { background: hsl(var(--ok) / 0.12); color: hsl(var(--ok)); }
        .cdm-merge-fail { background: hsl(var(--bad) / 0.12); color: hsl(var(--bad)); }
        .cdm-merge-wait { background: hsl(var(--warn) / 0.12); color: hsl(var(--warn)); }

        .cdm-yt-merge-ok, .cdm-yt-merge-fail, .cdm-yt-merge-wait {
            margin-top: 6px;
            padding: 6px 10px;
            border-radius: 6px;
            font-weight: 500;
            font-size: 12px;
            word-break: break-word;
        }
        .cdm-yt-merge-ok { background: hsl(var(--ok) / 0.1); color: hsl(var(--ok)); }
        .cdm-yt-merge-fail { background: hsl(var(--bad) / 0.1); color: hsl(var(--bad)); }
        .cdm-yt-merge-wait { background: hsl(var(--warn) / 0.1); color: hsl(var(--warn)); }

        .cdm-badge-ok, .cdm-badge-busy {
            display: inline-flex;
            align-items: center;
            padding: 1px 7px;
            border-radius: 5px;
            font-weight: 600;
            font-size: 10.5px;
            flex-shrink: 0;
        }
        .cdm-badge-ok { background: hsl(var(--ok) / 0.12); color: hsl(var(--ok)); }
        .cdm-badge-busy { background: hsl(var(--warn) / 0.12); color: hsl(var(--warn)); }

        .cdm-yt-pl-video { border-top: 1px solid hsl(var(--border) / 0.6); padding: 4px 0; }
        .cdm-yt-pl-video:first-of-type { border-top: none; }
        .cdm-yt-pl-row {
            display: flex;
            align-items: center;
            gap: 8px;
            cursor: pointer;
            padding: 4px 6px;
            border-radius: 5px;
            transition: background 0.1s;
        }
        .cdm-yt-pl-row:hover { background: hsl(var(--secondary) / 0.6); }
        .cdm-yt-pl-caret { width: 13px; text-align: center; color: hsl(var(--muted-foreground)); font-size: 10px; }
        .cdm-yt-pl-title {
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-size: 12px;
        }
        .cdm-yt-pl-detail { padding: 3px 0 6px 20px; }

        /* ================================================================
           7. DIALOGS
           ================================================================ */
        .cdm-dialog-overlay {
            position: fixed;
            inset: 0;
            z-index: 1000;
            background: rgba(0, 0, 0, 0.6);
            display: flex;
            align-items: center;
            justify-content: center;
            animation: cdm-fade-in 0.1s ease;
        }
        @keyframes cdm-fade-in {
            from { opacity: 0; }
            to { opacity: 1; }
        }
        .cdm-dialog {
            background: hsl(var(--card));
            border: 1px solid hsl(var(--border));
            border-radius: 10px;
            width: 90%;
            max-width: 480px;
            max-height: 85vh;
            display: flex;
            flex-direction: column;
            box-shadow: 0 16px 48px rgba(0, 0, 0, 0.45);
            animation: cdm-dialog-in 0.14s cubic-bezier(0.22, 1, 0.36, 1);
        }
        @keyframes cdm-dialog-in {
            from { opacity: 0; transform: scale(0.98) translateY(6px); }
            to { opacity: 1; transform: scale(1) translateY(0); }
        }
        .cdm-dialog-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 14px 18px 12px;
            border-bottom: 1px solid hsl(var(--border));
        }
        .cdm-dialog-title {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 14px;
            font-weight: 650;
        }
        .cdm-dialog-title .cdm-ic { color: hsl(var(--muted-foreground)); }
        .cdm-dialog-close {
            width: 26px;
            height: 26px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 13px;
            color: hsl(var(--muted-foreground));
            background: transparent;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            transition: background 0.1s, color 0.1s;
        }
        .cdm-dialog-close:hover { background: hsl(var(--secondary)); color: hsl(var(--foreground)); }
        .cdm-dialog-body {
            padding: 16px 18px;
            display: flex;
            flex-direction: column;
            gap: 13px;
            overflow-y: auto;
        }
        .cdm-dialog-body label {
            display: flex;
            flex-direction: column;
            gap: 5px;
            font-size: 12px;
            font-weight: 500;
            color: hsl(var(--muted-foreground));
        }
        .cdm-dialog-body input,
        .cdm-dialog-body select {
            padding: 8px 10px;
            font-size: 13px;
            font-family: var(--font-mono);
            background: hsl(var(--background) / 0.6);
            color: hsl(var(--foreground));
            border: 1px solid hsl(var(--input));
            border-radius: var(--r);
            outline: none;
            transition: border-color 0.12s;
        }
        .cdm-dialog-body select {
            -webkit-appearance: none;
            appearance: none;
            padding-right: 26px;
            background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 12 12'%3E%3Cpath fill='%23888' d='M2 4l4 4 4-4'/%3E%3C/svg%3E");
            background-repeat: no-repeat;
            background-position: right 9px center;
            cursor: pointer;
        }
        .cdm-dialog-body input:focus,
        .cdm-dialog-body select:focus {
            border-color: hsl(var(--accent) / 0.55);
        }
        .cdm-dialog-footer {
            display: flex;
            gap: 8px;
            justify-content: flex-end;
            padding: 12px 18px 14px;
            border-top: 1px solid hsl(var(--border));
        }
        .cdm-dialog-info {
            font-size: 12px;
            color: hsl(var(--muted-foreground));
            margin: 0;
        }
        .cdm-dialog:focus-within { outline: none; }
        .cdm-dialog-tabs {
            position: sticky;
            top: 0;
            z-index: 1;
            background: hsl(var(--card));
        }
        .cdm-settings-tabs {
            display: flex;
            gap: 14px;
            margin-bottom: 14px;
            border-bottom: 1px solid hsl(var(--border));
        }
        .cdm-settings-tab {
            padding: 8px 2px;
            font-size: 12.5px;
            font-weight: 550;
            cursor: pointer;
            color: hsl(var(--muted-foreground));
            background: transparent;
            border: none;
            border-bottom: 2px solid transparent;
            margin-bottom: -1px;
            transition: color 0.1s, border-color 0.1s;
        }
        .cdm-settings-tab:hover { color: hsl(var(--foreground)); }
        .cdm-settings-tab-active {
            color: hsl(var(--foreground));
            border-bottom-color: hsl(var(--accent));
        }
        .cdm-section-header {
            font-size: 11px;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.06em;
            color: hsl(var(--muted-foreground) / 0.85);
            margin-top: 16px;
            margin-bottom: 7px;
        }
        .cdm-toggle-row { display: flex; align-items: center; }
        .cdm-toggle-label {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 12.5px;
            font-weight: 450;
            color: hsl(var(--foreground));
            cursor: pointer;
        }
        .cdm-toggle-label input[type="checkbox"] {
            width: 15px;
            height: 15px;
            accent-color: hsl(var(--accent));
            cursor: pointer;
        }

        /* ================================================================
           8. YOUTUBE DIALOG WIDGETS
           ================================================================ */
        .cdm-yt-info-card {
            background: hsl(var(--muted) / 0.3);
            border: 1px solid hsl(var(--border) / 0.8);
            border-radius: 8px;
            padding: 13px;
            display: flex;
            flex-direction: column;
            gap: 11px;
        }
        .cdm-yt-title { font-size: 14px; font-weight: 600; }
        .cdm-yt-meta {
            font-size: 12px;
            color: hsl(var(--muted-foreground));
            display: flex;
            gap: 12px;
        }
        .cdm-yt-formats {
            display: flex;
            flex-direction: column;
            gap: 2px;
            max-height: 200px;
            overflow-y: auto;
            border: 1px solid hsl(var(--border) / 0.8);
            border-radius: 7px;
            padding: 4px;
            background: hsl(var(--background) / 0.4);
        }
        .cdm-yt-format-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 7px 10px;
            border-radius: 5px;
            cursor: pointer;
            border: 1px solid transparent;
            transition: background 0.1s;
            font-size: 12.5px;
        }
        .cdm-yt-format-item:hover { background: hsl(var(--secondary)); }
        .cdm-yt-format-item-selected {
            background: hsl(var(--accent) / 0.1);
            border-color: hsl(var(--accent) / 0.35);
        }
        .cdm-yt-format-label { flex: 1; }
        .cdm-yt-format-size {
            font-size: 11.5px;
            color: hsl(var(--muted-foreground));
            margin-left: 8px;
            font-variant-numeric: tabular-nums;
        }
        .cdm-yt-playlist-item {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 7px 10px;
            border-radius: 5px;
            font-size: 12.5px;
            border-bottom: 1px solid hsl(var(--border) / 0.5);
            transition: background 0.1s;
        }
        .cdm-yt-playlist-item:last-child { border-bottom: none; }
        .cdm-yt-playlist-item:hover { background: hsl(var(--secondary) / 0.6); }
        .cdm-yt-playlist-idx {
            font-size: 11px;
            color: hsl(var(--muted-foreground));
            min-width: 26px;
            font-variant-numeric: tabular-nums;
        }
        .cdm-yt-playlist-title { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .cdm-yt-playlist-dur { font-size: 11px; color: hsl(var(--muted-foreground)); }
        .cdm-yt-quality-select { display: flex; gap: 5px; flex-wrap: wrap; }
        .cdm-yt-quality-chip {
            padding: 3px 10px;
            font-size: 11.5px;
            font-weight: 550;
            color: hsl(var(--muted-foreground));
            background: transparent;
            border: 1px solid hsl(var(--border));
            border-radius: 5px;
            cursor: pointer;
            transition: background 0.1s, color 0.1s, border-color 0.1s;
        }
        .cdm-yt-quality-chip:hover { background: hsl(var(--secondary)); color: hsl(var(--foreground)); }
        .cdm-yt-quality-chip-on {
            color: white;
            background: hsl(var(--bad));
            border-color: hsl(var(--bad));
        }
        .cdm-yt-spinner {
            display: inline-block;
            width: 15px;
            height: 15px;
            border: 2px solid hsl(var(--border));
            border-top-color: hsl(var(--accent));
            border-radius: 50%;
            animation: cdm-spin 0.5s linear infinite;
        }
        .cdm-yt-dl-progress {
            padding: 12px 18px;
            display: flex;
            flex-direction: column;
            gap: 6px;
            border-top: 1px solid hsl(var(--border));
        }
        .cdm-yt-dl-progress .cdm-progress { height: 4px; }
        .cdm-yt-dl-meta {
            display: flex;
            gap: 14px;
            font-size: 12px;
            color: hsl(var(--muted-foreground));
            font-variant-numeric: tabular-nums;
        }
        .cdm-yt-dl-pct { font-weight: 650; color: hsl(var(--foreground)); min-width: 44px; }
        .cdm-yt-dl-speed { color: hsl(var(--accent)); font-weight: 550; }
        .cdm-yt-dl-eta { margin-left: auto; }

        .cdm-yt-tool-status {
            display: flex;
            align-items: center;
            gap: 11px;
            padding: 11px 13px;
            background: hsl(var(--muted) / 0.3);
            border: 1px solid hsl(var(--border) / 0.8);
            border-radius: 8px;
        }
        .cdm-yt-tool-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
        .cdm-yt-tool-dot-ok { background: hsl(var(--ok)); }
        .cdm-yt-tool-dot-miss { background: hsl(var(--bad)); }
        .cdm-yt-tool-name { font-size: 13px; font-weight: 600; }
        .cdm-yt-tool-ver {
            font-size: 11px;
            color: hsl(var(--muted-foreground));
            font-family: var(--font-mono);
            word-break: break-all;
        }
        .cdm-yt-tool-install { margin-left: auto; flex-shrink: 0; }

        /* ================================================================
           9. TOASTS / CONTEXT MENU
           ================================================================ */
        .cdm-toast-container {
            position: fixed;
            bottom: 16px;
            right: 16px;
            z-index: 9999;
            display: flex;
            flex-direction: column;
            gap: 8px;
            pointer-events: none;
        }
        .cdm-toast-container > * { pointer-events: auto; }
        .cdm-yt-toast {
            padding: 10px 14px;
            border-radius: var(--r);
            font-size: 12.5px;
            font-weight: 500;
            color: hsl(var(--foreground));
            background: hsl(var(--card));
            border: 1px solid hsl(var(--border));
            border-left-width: 2px;
            box-shadow: 0 8px 24px rgba(0, 0, 0, 0.35);
            animation: cdm-toast-in 0.18s cubic-bezier(0.22, 1, 0.36, 1);
            cursor: pointer;
        }
        .cdm-yt-toast-success { border-left-color: hsl(var(--ok)); }
        .cdm-yt-toast-error { border-left-color: hsl(var(--bad)); }
        .cdm-yt-toast-info { border-left-color: hsl(var(--accent)); }
        @keyframes cdm-toast-in {
            from { opacity: 0; transform: translateY(8px); }
            to { opacity: 1; transform: translateY(0); }
        }

        .cdm-ctx-menu {
            position: fixed;
            z-index: 2000;
            min-width: 190px;
            background: hsl(var(--card));
            border: 1px solid hsl(var(--border));
            border-radius: 8px;
            box-shadow: 0 10px 32px rgba(0, 0, 0, 0.4);
            padding: 4px;
            animation: cdm-ctx-in 0.1s ease;
        }
        @keyframes cdm-ctx-in {
            from { opacity: 0; transform: scale(0.97) translateY(-3px); }
            to { opacity: 1; transform: scale(1) translateY(0); }
        }
        .cdm-ctx-item {
            display: flex;
            align-items: center;
            gap: 9px;
            padding: 6px 9px;
            font-size: 12.5px;
            cursor: pointer;
            color: hsl(var(--foreground));
            border-radius: 5px;
            transition: background 0.08s;
        }
        .cdm-ctx-item .cdm-ic { width: 13px; height: 13px; color: hsl(var(--muted-foreground)); }
        .cdm-ctx-item:hover { background: hsl(var(--secondary)); }
        .cdm-ctx-item:hover .cdm-ic { color: hsl(var(--foreground)); }
        .cdm-ctx-danger { color: hsl(var(--bad)); }
        .cdm-ctx-danger .cdm-ic { color: hsl(var(--bad)); }
        .cdm-ctx-danger:hover { background: hsl(var(--bad) / 0.1); }
        .cdm-ctx-danger:hover .cdm-ic { color: hsl(var(--bad)); }
        .cdm-ctx-sep { height: 1px; margin: 4px 6px; background: hsl(var(--border)); }

        /* ================================================================
           10. EMPTY / SKELETON / MISC
           ================================================================ */
        .cdm-empty {
            text-align: center;
            padding: 88px 24px 64px;
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 4px;
            color: hsl(var(--muted-foreground));
            font-size: 13px;
        }
        .cdm-empty-tile {
            display: flex;
            align-items: center;
            justify-content: center;
            width: 56px;
            height: 56px;
            border-radius: 12px;
            margin-bottom: 12px;
            color: hsl(var(--muted-foreground) / 0.7);
            background: hsl(var(--muted) / 0.5);
        }
        .cdm-empty-tile .cdm-ic { width: 24px; height: 24px; }
        .cdm-empty-title {
            font-size: 14.5px;
            font-weight: 600;
            color: hsl(var(--foreground));
        }
        .cdm-empty p { margin: 0; }
        .cdm-empty-sub { font-size: 12px; margin-top: 3px; }
        .cdm-empty-cta {
            display: inline-flex;
            align-items: center;
            gap: 7px;
            margin-top: 16px;
            padding: 8px 16px;
            font-size: 12.5px;
            font-weight: 600;
            color: white;
            background: hsl(var(--accent));
            border: none;
            border-radius: var(--r);
            cursor: pointer;
            transition: filter 0.1s;
        }
        .cdm-empty-cta:hover { filter: brightness(1.1); }

        @keyframes cdm-skeleton-shimmer {
            0% { background-position: -200% 0; }
            100% { background-position: 200% 0; }
        }
        .cdm-skeleton {
            background: linear-gradient(90deg, hsl(var(--muted) / 0.7) 25%, hsl(var(--muted) / 0.4) 50%, hsl(var(--muted) / 0.7) 75%);
            background-size: 200% 100%;
            animation: cdm-skeleton-shimmer 1.5s ease-in-out infinite;
            border-radius: 5px;
        }
        .cdm-skeleton-card {
            padding: 12px 10px;
            border-bottom: 1px solid hsl(var(--border) / 0.6);
            display: flex;
            flex-direction: column;
            gap: 10px;
        }
        .cdm-skeleton-line { height: 11px; border-radius: 5px; }
        .cdm-skeleton-line-short { width: 40%; }
        .cdm-skeleton-line-med { width: 65%; }
        .cdm-skeleton-line-long { width: 85%; }
        .cdm-skeleton-bar { height: 3px; border-radius: 2px; }
        .cdm-skeleton-meta { display: flex; gap: 12px; }
        .cdm-skeleton-meta span { height: 9px; border-radius: 4px; }

        .cdm-item-removing {
            opacity: 0;
            transition: opacity 0.2s ease;
        }

        /* ================================================================
           11. RESPONSIVE
           ================================================================ */
        @media (max-width: 860px) {
            .cdm-side { width: 190px; }
            .cdm-search-input { width: 170px; }
            .cdm-row-dir { display: none; }
        }
    """)
}
