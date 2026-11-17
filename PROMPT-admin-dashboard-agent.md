# Task: Redesign the Dizzy admin dashboard — layout, IA, and UX, meaningfully

You are working in the repo `C:\Users\opcha\Downloads\Dizzy-v3`. Your target is the admin dashboard SPA in `admin-dashboard/`. Read every file listed below before writing a single line.

## Do NOT touch anything outside `admin-dashboard/`

- Do NOT commit, push, or tag anything. Git operations are owner-gated. Leave your changes as working-tree files only.
- Do NOT modify the Flutter app, `site/`, or any CI files.

## What exists today (ground truth)

Files: `index.html` (~40 KB), `app.js` (~83 KB), `ui.js`, `styles.css` (~39 KB), `config.js` (+`config.example.js`), `netlify.toml`, `_headers`.

Architecture you must respect:

- **Single-page app, vanilla JS, no build step, no framework.** It stays that way.
- One Supabase Realtime websocket in `app.js` subscribes via **`RT_MAP`** (`table → list of tabs`) using `postgres_changes`; a change fires the owning tab's loader (`RT_LOADERS`), debounced via `_rtTimers`. A slow-poll fallback refreshes long-open tabs. **Do not break or rename any of this.**
- Role gating: `loadMyRole()` shows/hides tabs (`Admins` tab is `hidden` unless the role allows; `navAdmins` id must keep working).
- Tabs are toggled by `show(name)` flipping `.on` on `main section` with ids `s-<name>`; nav buttons carry `data-s` and `onclick="show('...')"`.

The 13 sections, in current nav order: Overview, Rooms, Moderation, Scrapers, Fleet, Usernames, Announcements (id `push`), Config, Audit, Device logs (id `devicelogs`), Support, Curated, Admins. Two sections carry live nav badges (`navReports`, `navTickets`) — keep them functional.

Reference screenshots of the current dashboard exist in `.dashboard-preview/shots/` (`overview.png`, `rooms.png`, `moderation.png`, `scrapers.png`, `users.png`, `config.png`, `audit.png`, `devicelogs.png`, `push.png`, `login.png`, `mobile_overview.png`). Look at them to understand today's layout before redesigning.

## The redesign brief — meaningful, connected, not AI slop

The current dashboard is a flat list of 13 tabs with no information architecture: unrelated things sit next to each other, related things are far apart, and nothing communicates workflow. Your job is a **meaningful reorganization of layout, grouping, and UX** — a restructure, not a reskin.

**Regroup the 13 sections into coherent workspaces** (example grouping — refine it with your judgment after reading `app.js` loaders to see which sections share data/tables):

- **Operations** — Overview, Moderation, Support (what needs attention right now)
- **Community** — Rooms, Curated, Announcements (shaping what users see and hear)
- **Infrastructure** — Scrapers, Config (plumbing and settings)
- **Observability** — Audit, Device logs, Fleet (telemetry and history)
- **Identity** — Usernames, Admins (accounts and access)

Group them in the nav with clear group labels, and order by operator workflow: urgent → routine → plumbing. When Moderation has pending reports, the operator's eye should land there first.

**Additional requirements:**

- A persistent left sidebar (collapsible on mobile) with grouped nav, active-group context, and the existing badges — replacing the current top/bottom nav strip if present.
- Overview must become a genuine mission-control landing: the few numbers/actions an operator needs first (open reports, open tickets, scraper health), each linking straight into its section. No filler metrics, no vanity charts. Every number must earn its place.
- Consistent componentry: one table style, one card style, one empty-state, one loading-state, one error-state — shared via CSS classes and (if useful) small helpers in `ui.js`. Today every section hand-rolls its own markup; unify it.
- Dense, calm, readable: this is a tool used for hours. Comfortable 13–14px base, generous but not wasteful spacing, clear hierarchy, zero decorative noise.
- Mobile must not be an afterthought: nav collapses to a drawer, tables get a sane overflow strategy, primary actions stay reachable.

## Anti-slop rules (hard)

- No filler metrics, fake sparklines, or dummy KPI cards.
- No emoji-as-icon-system (the current `📊 🏠 🚩` nav emoji are to be replaced with a single consistent inline-SVG icon set or clean text-only nav — your call, but be consistent).
- No glassmorphism-everywhere, no purple AI-gradient theme, no floating blobs, no animated backgrounds.
- No gratuitous animations; only purposeful transitions (tab switches, badge updates, drawer open/close). Respect `prefers-reduced-motion`.
- Don't invent features or data that don't exist in `app.js` loaders.

## Hard constraints

- **No frameworks, no build step, no CDN dependencies.** Vanilla HTML/CSS/JS only. Must remain Netlify-deployable as static files in `admin-dashboard/` (keep `netlify.toml` and `_headers` semantics intact).
- **Do not rename tab ids, section ids (`s-*`), `RT_MAP` entries, `RT_LOADERS`, `show()`, `loadMyRole()`, badge element ids (`navReports`, `navTickets`, `navAdmins`), or any Supabase query.** You may restructure around them, split files, and add new helpers — but the data layer stays byte-compatible in behavior.
- Keep role gating exactly as-is (Admins tab visibility, any per-section gates in `app.js`).
- `config.js` is gitignored (contains the Supabase URL/key); never read or commit its values — use `config.example.js` as the contract.
- Preserve all existing functionality per section: every loader, filter, and action button in `app.js` must still work after the redesign. This is a UI/UX restructure of the shell and presentation, not a logic rewrite.
- Accessibility: keep `role="tablist"`/`aria-selected` semantics (upgrade them if you move the nav), keyboard-navigable nav, visible focus states, real buttons.

## Definition of done

- Redesigned shell (sidebar + workspace grouping) implemented across `index.html` / `styles.css` / (`ui.js` if needed); `app.js` touched only where strictly required for wiring (e.g., badge/sidebar state), with all loaders intact.
- Dashboard renders from a plain static server with the config pattern unchanged; login still works against the real backend when the owner supplies `config.js`.
- Every one of the 13 sections loads and displays correctly; realtime updates still fire the right loaders.
- A short summary in your final response: the new IA (groups, order, rationale), the component system you established, what changed in `app.js` and why, and anything the owner must deploy.
