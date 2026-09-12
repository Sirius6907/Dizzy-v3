# Changelog

All notable changes to PlayTorrio V3 will be documented in this file.

## [1.2.0+30] — 2026-09-12 — "Watch Together 10x" (P1–P19)

### P20–P23 (this batch)
- Release builds: `app-release.apk` (161.9 MB, debug-signed local gate build)
  + Windows `dizzy.exe` — both built clean, analyze zero.
- Cloud resolve API (P21): `resolve` edge fn client (`CloudResolveService`,
  30-day prefs cache, 2 reads + 1 write) wired as chain step 0 in tmdb_helper.
- Catalog warm-cache (P22): `catalog` edge read-through (`warm:true/false`,
  6h fresh) + `catalog_cache` table + app `CatalogService` (edge → snapshot → null).
- Instant-open player (P23): title on first frame + decode-capped skeleton
  (backdrop ≤960px, logo ≤400px) for ≤3GB RAM devices.
- Tests: +6 (cloud resolve guards, catalog cards).

### ⚠️ Needs you (Supabase — SQL Editor run once each, then deploy)
1. `supabase/migrations/20260912_wp_p11_chat_soul.sql` — chat soul columns.
2. `supabase/migrations/20260912_wp_p12_lobby.sql` — lobby watching columns.
3. `supabase/migrations/20260912_p22_catalog_cache.sql` — warm-cache table.
4. Dashboard → Edge Functions → deploy/redeploy: `resolve`, `catalog`,
   `tmdb-proxy`. Set secrets: `TMDB_API_KEY` (or BEARER).
5. Dashboard → Edge Functions → `catalog` → Schedules → New cron
   `30 6 * * *` (= 12:00 IST noon refresh of trending/popular feeds).

### Watch Together (flagship, 10x flawless + dead-easy)
- Persistent rooms (name + pass; P1) with LIVE lobby cards: watching title,
  headcount, Choosing… state, pull-to-refresh (P12).
- Host 2 Hz heartbeat + guest silent follow (1.5 s auto-fix, Catching up… past 5 s).
- Guest auto-open on media switch (P3): prefetch metadata first, title fallback,
  Easy-English toasts — guest never stares at a dead screen.
- Voice rail (P4): join-muted sheet, mute/deafen by Discord rules, speaking dots.
- Chat with soul (P11): host pins, reactions, timestamps, host badges.
- Room safety (P5): private passes, adult filter, 20-member cap, stale sweep.
- 3-card first-time guide flow (create → join → host plays), old key retired (P13).

### Player
- Manual quality menu (P7): Auto + 480p–4K from the real ladder; choice saved per device.
- Auto quality (P8): bandwidth tiers (<3→480, 3–8→720, 8–20→1080, 20+→max),
  10 s stability gate, Data Saver 720p cap, weak-device AV1 dodge.
- Rendition contract (P9): every rung one tap away; progressive first-match switch.
- Instant zapping (P10): verified-source prefetch, <1 s handoffs.
- Keyless TMDB (P14): own edge proxy first → build key → .env key → keyless
  last resort. Release APK carries no TMDB key.
- Format matrix: HLS VOD/live, progressive, torrents, debrid, external subs
  (`docs/format-support.md`).

### Engineering health
- Silent-catch triage (P15): network/parse = silent-but-logged (enum codes,
  consent-gated, throttled); user paths always toast (`docs/silent-catch-triage.md`).
- Log hygiene (P16): `AppLog.d` release-stripped logger across player/scraper/party.
- God-file split started (P17): resolve pipeline → `watch_resolve_controller.dart`,
  pure move + contract tests.
- Tests: stale DownloadTask telemetry fixed; +22 P18 tests (rooms, media_switch
  matrix, rendition policy, bandwidth tiers, deafen/mute, proxy fallback).
- Protocol frozen: `docs/party-protocol-v2.md` (v1–2 guard, guest rules).
  (Supabase manual steps moved to the P20–P23 section above.)

## [1.2.0] — 2026-09-12 — "Zero-Tech User"

### Watch Together 10x (flagship)
- One-tap rooms from any movie/TV page, big code card + Copy/Invite.
- Host heartbeat (2 Hz) + guest silent follow (1.5 s auto-fix, "Catching up" past 5 s).
- Guest transport lock with easy note; host LIVE pill in player.
- Join dialog with Paste + auto-uppercase; chat timestamps + host badges.
- One-tap voice sheet (join-muted); reconnect backoff 1 s/2 s/4 s.

### Guides (skipable, Easy English)
- First-time cards: Watch Together, Downloads, Cloud, Sources, Subtitles.
- Skip = never nags; Settings → "Show guides again" replays all.

### Everyday upgrades
- Sources health dashboard (green = good, red = resting, Retry).
- Search history (last 10 chips, 50 stored, Clear All).
- Words-on-screen subtitle styles with live preview.
- Genre taste learning (list-add + full watch) powers Because rows.
- Persistent downloads with resume; net-switch auto-pause/resume.
- Global error boundary: branded screen + Report + Restart, never white-screen.

## [3.0.0-early] — 2026-08-11

### Added
- Stremio-compatible addon protocol with catalog browsing, search, and metadata enrichment
- 9 VOD stream scrapers (FlyStream, Videasy, VidSrc, MultiEmbed, VidCore, 4KHDHub, XDownloader, Knaben, TorrentGalaxy)
- Native libtorrent streaming engine with intelligent file selection and real-time stats
- 9-source audiobook aggregator with torrent and direct streaming support
- WeebCentral manga reader with horizontal/vertical modes, zoom, and progress tracking
- Octave music streaming with library management, playlists, and keyboard shortcuts
- Subdl subtitle download and extraction with multi-language support
- Glassmorphism UI system with GPU shader effects and performance fallback toggle
- Custom route transitions (LiquidRevealRoute, CinematicSlideRoute)
- Responsive card layout adapting to phone, tablet, and desktop widths
- macOS-style liquid dock navigation
- 5-platform support (iOS, macOS, Android, Linux, Windows)
- Audiobook sleep timer and variable playback speed
- "More Like This" recommendations via BestSimilar scraper
- Search relevance scoring with exact-match-first ranking
- Progressive content loading across all sections
