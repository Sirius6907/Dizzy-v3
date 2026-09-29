# Changelog

All notable changes to PlayTorrio V3 will be documented in this file.

## [1.3.1+33] — 2026-09-30 — "Update Anything, From Anything"

### Fix — in-place updates for every install, no uninstall ever
- **Root cause of "package not valid"** — releases v1.1.3–v1.1.5 shipped debug-signed (the release keystore was added only at v1.1.7), and some phones carry locally-built test installs; Android only accepts an update signed with the *exact same key*, so those installs could never move to a v1.1.7+ build. Several downloads also failed and the old plugin handed the error body straight to the installer.
- **Dual-signing update channels** — the app now reads its own signing-cert fingerprint (new `getCertSha256` method channel) and fetches the matching GitHub asset: normal installs get the normal APK, legacy-key installs get `Dizzy-v3-legacy-*` mirrors signed with the original key. Legacy asset names drop the arch token (`legacy-arm64`, not `legacy-arm64-v8a`) so older pickers deterministically land on the normal APK.
- **Download integrity** — OTA verifies the GitHub asset's sha256 digest before the installer ever opens a file; failed/corrupt downloads now abort with a friendly retry message instead of a system invalid-package error.
- **Easy-English failures** — raw OTA status codes no longer reach users.
- **CI release guards** — missing `KEYSTORE_BASE64` fails the release; every APK's signing fingerprint verified (release vs legacy channel); all four base APKs required before publish.
- Tests: 13 asset-selection cases incl. order-proof guards for older pickers (939 total green).

## [1.3.0+32] — 2026-09-29 — "Learn It, Then It Just Works"

### P6 — UI/UX polish, finished
- **Legacy hex sweep** — 931 → 871 `Color(0xFF…)` literals under `lib/pages` + `lib/widgets`. Flat dark surfaces now read from the frozen `DizzyVoid` tiers; brand identity colours, gradient stops and alpha-tinted glows stay literal with a code comment saying why.
- **Narrow-screen contract** — 40 `AppBar` owners audited. Three hand-rolled bars really did overflow at 360px and now compact below 420px: the IPTV glass bar, the AI taste-match bar, and the direct-message title (long handles now ellipsize).
- **Music, proven** — 22 new tests lock down four shipped features: the ambient canvas can never black-flash (a hard luminance floor on the fast HSL palette), queue reordering maps upcoming indices to absolute ones, switching audio quality keeps your listening position, and Song Radio leads with the seed track and fails soft offline. The pure queue math moved into `music_queue_ops.dart` so it is testable without booting the media backend.

### P7 — Tutorial cards for every feature
- **25 intro cards**, one per flagship area (home, spotlight, movie, anime, manga, music studio, equaliser, books, audiobooks, downloads, offline, my list, profiles, debrid, live TV, calendar, stats, subtitles, sources, cloud sync, watch together, direct messages, social hub, accent studio, appearance).
- **Never more than 3 cards**, one Easy English line each, no tech words. Skip means never again.
- **No re-nag on upgrade** — a card you already dismissed in an earlier version stays dismissed, and the old 3-slide welcome tour carries over to the new 5-slide one.
- **Onboarding 2.0** — a 30-second, 5-slide tour: everything in one place, music that sounds right, watch together, works without internet, and yours alone.
- **Settings → Help → "Show guides again"** replays any card, and the welcome tour with it.

### P8 — Admin & observability
- Realtime device-log view with per-device *and* error-category filters.
- Tech-error feed, scraper quarantine dashboard, and live feature-flag toggles wired to remote config, so an error a user never sees is still one click from a fix.

### P9 — Perf budgets, verified
- Startup path, `ResourceGovernor` and `PerformanceMode` thresholds checked against the RAM / VRAM / CPU budgets.
- Split-per-ABI Android builds configured (~50MB release APKs). Numbers recorded in `PHASE_P9_PERF.md`.

### F-track (merged in this release)
Discover daily feed with mood quiz and reminders, My List custom lists with PIN lock and restore, a downloads hub with offline storage sweep, watch-together queue voting and late-join sync, and cross-device merge support.

### Gates
- `flutter analyze lib/` — 0 issues.
- Full test suite green.

## [1.2.1+31] — 2026-09-13 — "Spotify Music + 40-Phase Polish"

### Performance Foundation (Perf P0–P10)
- Bounded net retry (3 attempts, backoff, transient-family classification)
- Performance mode auto-detect: Budget / Mid / Flagship tiers
- Storage guard: disk-full choke, stale `.part`/`.tmp` cleanup, 5-min cached sync
- `DizzyImage` widget with enforced `memCacheWidth` caps across all cards
- Waveform seekbar visibility-aware ticker gating (zero GPU burn when hidden)
- Ambient background + liquid lens optimization (RepaintBoundary isolation)

### UX1–UX10: App Experience Upgrade
- **UX1** Universal Spotlight Search (Ctrl+K, cross-section movies/anime/music)
- **UX2** Download Hub (Active/Video/Music tabs, storage gauge, cache clean)
- **UX3** Low-End Mode (auto-tuning for 2GB phones at 60fps)
- **UX4** Onboarding Superpower Cards (3 slides, first launch only)
- **UX5** Media Dock (live pulse dot, video↔music conflict resolver)
- **UX6** Accent Studio (custom hex glow, AMOLED 0x000000 black, blur slider)
- **UX7** Calm Errors (offline banner, friendly messages, no tech codes)
- **UX8** Social Hub (Watch + Listen Together unified sheet)
- **UX9** TV/D-Pad Navigation (focus ring, keyboard shortcuts)
- **UX10** Release Notes Studio (What's New bottom-sheet cards)

### Music M1–M20: Spotify-Level Music Suite
- 5 tab views: Home, Browse, Library, Search, Radio
- Bottom player bar + expanded full-screen player + queue drawer
- Lyrics drawer, equalizer modal, audio visualizer
- Sleep timer, smart mixes, trending artists row
- Album/artist/playlist detail modals with hero transitions
- Listen Together (music co-listen rooms)
- Playlist sharing, music download manager, Wrapped stats modal
- Desktop mini-PiP widget + keyboard shortcuts

### Fixes
- UX4/UX6/UX8/UX10 entry points wired into home + settings pages
- Release builds now include `--dart-define-from-file=.env` (Supabase keys)

### Stats
- 118 files changed, 16,011 insertions, 73 new files
- 5 new test files (net_retry, performance_mode, storage_guard, ux5_ux10, music_m1_m20)
- `flutter analyze`: 0 issues

---

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

### ✅ Supabase — done via CLI (2026-09-12, no dashboard needed)
- `resolve`, `catalog`, `tmdb-proxy` deployed + live-tested (trending feed,
  Fight Club → tmdbId 550, movie/550 full data all OK).
- P11 (already ran) + P12 view + P22 `catalog_cache` applied + verified.
- `TMDB_API_KEY` secret set. `catalog-noon-refresh` cron live (`30 6 * * *`
  = 12:00 IST). Warm row confirmed: `trending|all|1` = 20 items.

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
