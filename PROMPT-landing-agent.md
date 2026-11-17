# Task: Rebuild the Dizzy landing page — 100x visuals, experience, and animation

You are working in the repo `C:\Users\opcha\Downloads\Dizzy-v3`. Your target is the static landing site in `site/` (deployed on Netlify). Read every file listed below before writing a single line.

## Do NOT touch anything outside `site/`

- Do NOT commit, push, or tag anything. Git operations are owner-gated. Leave your changes as working-tree files only.
- Do NOT modify the Flutter app, `admin-dashboard/`, or any CI files.

## What exists today (ground truth)

- `site/index.html` (~39 KB) — single page, sections in order: nav (sticky, with scroll-progress bar), hero (copy + phone screenshots strip + bottom fade), ticker strip, `#features`, `#why`, `#how`, shots rail, `#numbers`, download tabs (`#download` — android / windows / linux), footer.
- `site/assets/css/main.css` (~45 KB) — custom properties including `--surface: #0c0a0f`, `--surface-2: #131018`, plus reveal-on-scroll `.reveal` classes, download-tab logic, responsive rules.
- `site/assets/js/main.js` — scroll progress bar, mobile menu, `.reveal` IntersectionObserver, download tab switching, and **version wiring: the page pulls the current version from `site/releases.json`** (currently stale at v1.3.2 — that file is regenerated post-release; do not hand-edit it, keep the JS wiring that reads it intact).
- Everything is **vanilla HTML/CSS/JS, zero build step, zero framework**. It must stay that way.

## What the app actually looks like (your visual brief)

Use these real screenshots captured from the app as the source of truth for theme, typography feel, and imagery — embed/annotate with them, and match the landing page to them, not the other way around:

- `assets/screenshots/` — `1-intro.jpeg`, `2-home.jpeg`, `3-home2.jpeg`, `4-manga.jpeg`, `5-manga2.jpeg`, `6-anime.jpeg`, `7-anime2.jpeg`, `8-search1.jpeg`, `9-search2.jpeg`, `10-audiobook.jpeg`, `11-settings.jpeg` (a `small/` subfolder exists too).
- `.dashboard-preview/shots/` contains ADMIN dashboard screenshots — reference only if you need dark-UI color calibration; do not put dashboard content on the landing page.

App theme to match:

- **OLED true-black** base (near `#000`–`#0c0a0f`), not dark-grey. Content surfaces are slightly raised (`#131018` range) with hairline borders.
- **Ember/red gradient accents** — warm orange-red → deep red gradients used sparingly on CTAs, active states, and glow accents. Find the exact token values in the Flutter theme files (grep `lib/theme/` or similar for the color definitions) and reuse them verbatim in CSS custom properties.
- Dense media-card grids (anime/manga/audiobook covers), vertical page rhythm that feels like a streaming app, not a SaaS template.
- Rounded-media aesthetic, subtle shadows, content-first (imagery dominates chrome).

## Goals

1. **Visuals 100x**: rebuild the page's visual identity to genuinely look like the app. Hero should showcase the real screenshots prominently (device-framed if you like — pure CSS frames, no images of phones required). Section-to-section rhythm, type scale, spacing, and accent usage must feel designed by a human art director, not a template.
2. **Experience 100x**: narrative flow — hook → proof (real screenshots) → why/how → numbers → download. Every scroll position should offer a clear next action. Mobile experience must be excellent (the existing site is responsive; make it exceptional). Accessibility is non-negotiable: keep/extend existing `aria-*` patterns, keep landmark roles, maintain focus states, and respect `prefers-reduced-motion`.
3. **Animation 100x**: buttery scroll-driven reveals and micro-interactions. All animations **transform/opacity only** (no layout-thrashing width/height/top animations), `will-change` used sparingly, target 60fps on mid-range mobile. Scroll-linked effects via `IntersectionObserver` + CSS custom properties or a tiny vanilla rAF loop — no external animation libraries.

## Hard constraints

- **No frameworks, no build step, no CDN dependencies.** Vanilla HTML/CSS/JS only. Must remain Netlify-deployable as static files in `site/`.
- **Keep the `releases.json` version wiring** in `main.js` exactly functional (the download section must still show the version pulled from that file).
- **Keep the three download tabs** (android / windows / linux) with their behavior intact.
- Keep all current copy intent; you may rewrite wording but not lose any factual claim the page makes (open-source, platform support, feature claims).
- Preserve semantic structure: one `h1`, logical heading order, real `<section>`s with ids, working nav anchor links, working mobile menu.
- Performance: the page must stay fast. Compress/resize screenshot assets only into `site/assets/img/` (do not hotlink `assets/screenshots` from outside `site/`; copy what you need in). Lazy-load below-the-fold images with `loading="lazy"`.
- No generic template look: no generic gradient blobs, no "AI slop" typography (Inter-everything with purple gradients is exactly what we don't want), no fake metrics, no emoji decoration.
- `site/releases.json` is generated by a script post-release — never edit it by hand, and never break the code that reads it.

## Definition of done

- `site/index.html`, `site/assets/css/*`, `site/assets/js/*` updated; any new images under `site/assets/img/`.
- Page renders correctly from a plain static server (`npx serve site` or python http.server) with no console errors.
- All existing interactive behaviors (scroll progress, menu, reveal, download tabs, version display) still work.
- Lighthouse mobile pass: performance ≥ 90, accessibility ≥ 95, no layout shift on load.
- A short summary in your final response: what you changed, why each section looks the way it does, and anything the owner must regenerate/redeploy.
