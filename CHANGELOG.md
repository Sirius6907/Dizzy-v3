# Changelog

All notable changes to PlayTorrio V3 will be documented in this file.

## [1.3.6+1038] - 2026-11-20 - "One App"

### The brand finally moves
- **A real intro, not a splash** — the app opens on a 3.15 s brand beat: the
  halo draws, the wordmark sweeps in, the line settles, then it lifts away.
  It plays *over* Home instead of gating boot, so a cold start is never slower
  than before.
- **It knows when to stop** — tap anywhere to skip; with reduced motion on it
  runs a 620 ms fade instead of the sweep; it plays once per launch.
- **Cold start is black, not white** — Android's launch theme and the v31
  splash now match the app, so there is no white flash before the first frame.

### Your queue survives a restart
- **Pause, close, come back** — the music queue (tracks, order, current
  position) is saved as you go and restored on the next launch, paused at the
  exact spot. It never autoplays, so opening the app in a quiet room cannot
  blast audio.

### Watch party, finished
- **Pick your voice quality** — High / Balanced / Data saver (48k / 24k / 12k)
  with echo cancellation, noise suppression and AGC on in every tier. The
  choice applies on the next join, never mid-call.
- **Invite from inside the room** — one tap posts the code into room chat; if
  chat is rate-limited or offline it falls back to the share sheet, then the
  clipboard. Any member can invite, not just the host.
- **The join sheet is readable in light theme** — fixed white-on-white text.

### Push you can actually control
- **One switch stops everything** — a single kill switch in the admin panel
  pauses every send (cron and manual) without unsubscribing anyone.
- **One paste finds one phone** — a support ticket's DIZ-code (current or
  retired), device id, user id or @username resolves to the exact account, so
  one notification can be aimed instead of broadcast.
- **Retries instead of silent loss** — FCM 429/503 answers are retried with
  backoff, so a broadcast no longer quietly drops the tail of the audience.
- **A receipt for every action** — sends, pauses and resumes land in an admin
  ledger with who, what, how many, and how it went.

### Profiles that look like people
- **A real identity block** — the profile page now has a photo (optional,
  local), monogram fallback, and honest stat tiles instead of placeholders.
- **Reachable from everywhere** — the account hub and the first-run gate both
  open it, and a saved custom background loads at boot instead of flashing the
  default first.

### Playback that keeps running
- **Media and downloads keep a foreground service** — playback and long
  downloads survive the app leaving the screen, with a now-playing card you
  can dismiss.

### Music starts on the actual track
- **The extractor was ignoring its own instructions** — `getAudioUrl` accepted
  a `verifyStream` flag and never used it, so every resolve probed each
  candidate against the CDN. The resolver asks for the *unverified* path and
  allows itself 12 s, while the extractor was spending up to 21 s (3
  candidates × 7 s) doing exactly the probing it had been told to skip.
- **The timeout was guaranteed** — on any slow network the resolver gave up,
  fell through Convertytmp3, and played the 30 s Deezer preview instead of the
  track. Unverified resolves now return the top-ranked stream immediately and
  let the player recover through its existing candidate fallback.
- **`n`-throttled clients are skipped** — a client that only offers throttled
  URLs no longer wins the rank, so audio does not stream at a crawl.
- **A real internal deadline** — extraction is capped at 10 s total and each
  candidate gets only the time that is left, so it cannot outlast the resolver
  again. Downloads keep the verified path, since they have no fallback.

### Anime sources that still exist
- **Four dead providers removed** — `anidb.app` now redirects every path to an
  APK download page, `anineko.to` no longer resolves, `123animehub.cc` does not
  answer, and `new.vidnest.fun` returns 403 everywhere. They were fanned out on
  every episode, so each one cost a timeout for nothing.
- **The sheet closes on time** — each provider is capped at 10 s, and the
  stream is closed in a `finally` block, so a silent host can no longer leave
  the source list spinning after every other result has arrived.
- **No more episode-list call to a dead host** — the details page and modal now
  count episodes from AniList data, which was the better authority anyway.

### Settings breathes properly
- **The Downloads card got its gap back** — it was the one row in the list with
  no spacing above it, so it sat flush against the card before it.
- **The list uses one rhythm** — gaps now match the card radius instead of the
  old hardcoded 12 px.
- **No double surface on switch rows** — switch tiles painted a smaller,
  differently-rounded rectangle inside their own card, letting the card corners
  peek out behind them. The card is the only surface now, and the shadow stays
  inside its gap instead of bleeding onto the next tile.

## [1.3.5+1036] - 2026-11-17 - "The Two Sources"

### The app answers from RiveStream and FlaxMovies only
- **Every movie and episode resolves through the verified pair** — all
  other built-in scrapers (plain HTTP, embed and torrent) are held back at
  registration. Nothing is deleted: a scraper is re-enabled with a
  one-line edit. Torrents stay available through the addons you turn on.
- **The result is speed and completeness** — no more waiting on a race
  between forty scrapers that mostly fail; the owner's manual test reports
  all content playable and fast, without the previous multi-source
  failure style failures.

### A ranker you can interrogate
- **One definition of a torrent, one text matcher, named weights** — the
  ranking rules were rewritten so the same classification is used by the
  tier order, the score and the failover chain (they previously carried
  three separate copies that could drift).
- **`explain()`** — every point of a source's score is now attributable by
  name (addon history, debrid, instant-play, failure penalty …), so "why
  did this source autoplay" is answerable without re-deriving arithmetic.

### The probe tool plays everything
- The source-probe exe (`tool/player_probe`) now plays every shape it
  lists — mp4, mkv, HLS, extension-less FILE links, and embeds through the
  app's own ad-blocked webview with automatic mpv handoff.

### The resolver finally works (this is the "few sources" fix)
- **The app reaches the resolver again** - the resolve call sent only an
  `apikey` to an edge function that verifies JWTs, so every call came back
  `401` and the app silently used the weaker fallback. The bearer token is
  sent now.
- **The right film, not a film with the same name** - the resolver matched
  on the title name alone. On the 50 latest Odia movies that answered 30
  titles, 10 were a completely different film (a Spanish "GAME OVER" for a
  2026 Odia request, a Japanese "Monster", a Korean "Midnight"). The year
  and the language are part of the answer now, and a wrong match is refused
  instead of played.
- **Regional titles resolve at all** - TMDB's search cannot see most
  regional titles (18 of 20 sampled Odia films return zero hits), so a new
  title corpus indexes the regional catalogue - Hindi, Telugu, Malayalam,
  Kannada, Odia and anime - and the resolver reads it first. It is built
  from the same feed the app already shows, so it needs no extra data.
- **The year travels with the request** - the API always accepted it, the
  call site dropped it.

### More sources, not fewer wrong ones
- **Torrent releases are matched on their real name** - a release is
  indexed as "Dahaan (2026)", the catalogue calls it "Dahaan: The Evil
  Within", and the old filter threw the correct release away. The name is
  compared on its core now, with the release year as the guard, so a short
  name can never be answered by a different film.

### The catalogue
- **A "latest releases" feed** - ordered by the day a title actually came
  out, per language, instead of by popularity, with a nightly warm so the
  rows are already there in the morning.

### Friends and DMs finally work end to end
- **Friend status updates live** — when someone accepts your request your
  "Sent ✓" turns into a "Chat" button the moment it happens (the app only
  listened for new requests, never for accepts, and no screen was even
  attached to the listener). Resume also refetches the friend list.
- **DMs are real now** — the chat page shows the actual conversation
  history from the server, receives messages live, and your own messages
  render on your side (they all used to render as incoming). The fake
  sample card is gone.
- **Tap a friend's Watch invite → you join their room** — inviting no
  longer creates a second room on the other side.
- **Real names instead of gibberish** — friends and pending requests show
  the @username the person signed up with (a new server resolver replaces
  the `friend_` + random letters fallback).
- **Mutual adds settle themselves** — if you and a friend request each
  other at the same time, one Accept makes both sides friends instead of
  both sitting on "Sent ✓" forever.

### Verified
- `flutter analyze`: no issues. `flutter test`: 1606 passed, 26 skipped,
  0 failed (the slow live bulk probe stays excluded).
- The resolver change is measured against the deployed function on the
  owner's own 50-title list: 20 right / 10 wrong / 20 unanswered before,
  **22 right / 5 wrong / 23 unanswered** after - the wrong answers are
  half, and the five that remain are titles the app's own search had
  already matched to a different film.

## [1.3.4+1035] - 2026-11-06 - "Verified Sources"

### Sources that are actually the right episode
- **A relevance gate** - a provider answering a different show, a
  different year or a different episode is rejected instead of played.
- **Verified stream addons by default** - Torrentio, TorrentsDB and
  AcuAnime, with a Kitsu fallback for anime.
- **Torrents warm up before playback** - a decoy-file guard, a 2 MB
  warm-up, and torrent-only autoplay when there is no HTTP source.
- **Assistant logs per user** - the support assistant records what it
  answered, with a global cap on the model budget.

## [1.3.3+1034] - 2026-10-29 - "Accounts, Support, Sound"

### Accounts that survive a reinstall
- **First-run @username gate** — the name is asked once, right after the intro, with a live "is this free?" check. A reinstalled device offers the previous name ("Welcome back, @name?") instead of silently creating a second, duplicate account; a name is the server truth, never a local first-launch flag.
- **Username durability + identity history** — a username is now reserved across devices and reinstalls, with an admin trail of renames instead of silent collisions.
- **Email OTP links fixed, full account merge, resend cooldown** — a broken verification link no longer strands a half-created account; two accounts can be merged, and the resend button now honours a cooldown.
- **Missed-call phone verification (stub-first)** — phone verification lands behind the same stub-first pattern the rest of the auth stack uses, with a webhook and an unread badge.

### Admin powers, typed and logged
- **Per-admin roles** — owner / admin / moderator each see only the tools they can use.
- **Typed remote config hot-fixes** — remote values are validated before they land, so a bad payload can't brick a screen.
- **Remote user powers + rich log trail** — every remote action on a user is recorded with who, what and when.

### Support and curation
- **Support inbox** — user tickets land in the dashboard with a reply path back to the app.
- **Curated publish** — curated shelves are published from the dashboard (`admin_curated_upsert` now auto-slugs and tolerates partial JSON).
- **Offline-first AI help** — the in-app help answers from a local FAQ before it ever asks the network.

### Music depth
- **JioSaavn edge proxy** — catalogue requests go through the edge function instead of the device.
- **Exact search policy** — the search never hands back a near-miss song.
- **Curated shelves** — hand-picked rows ship with the app.

### Frontend polish — Prism clay, both themes
- **Settings, Books, Live TV, Music, Anime, Manga, Audiobooks, Downloads, 18+ and the Arabic-anime screens** rebuilt on the Prism token set: light clay by default, dark equally crafted, no leftover dark islands.
- **Contrast fixed where it actually failed** — accent text, gold scores and status greens now use AA-safe tokens instead of vivid colours at 12–13px.
- **Layout fixed** — scrolling lists clear the floating dock via one shared clearance rule, long titles ellipsize instead of overflowing, anime details now sit on an opaque sheet over a clipped hero instead of scrolling text across artwork. The profile page also gained the back control it was missing.
- **Touch and screen readers** — icon-only controls carry tooltips and 48dp targets, subtitles/dub toggles announce their state, and nothing renders below 11px.

## [1.3.2+1033] — 2026-10-11 — "It Plays the Right Thing"

### Correct playback, every time
- **Exact-title gates** — a wrong match can no longer start a movie; closing a stream also kills the orphaned resolve job.
- **Resolve-edge bypass closed** — the cloud gate can't be skipped into serving the wrong video.
- **Anime timeouts** — megaplay and the anidb HTTP paths now time out instead of hanging the sheet.

### Media and caches
- **Desktop image cache** — sqflite FFI wired up so covers persist; music covers never render blank.
- **P2P defaults** — torrent source is ON out of the box, routed through the builtin addon so the Settings switch and the addon entry can't desync, with a Knaben fallback.

### New surfaces
- **18+ Heaven** — gated adult section behind a triple lock and an admin kill-switch.
- **India-first music** — desi-first home rows, artists, albums, playlists, plus browse/radio tiles.
- **Player refactor** — watch_screen (2716 → 400 lines) and player_screen (3262 → 610 lines) split into themed part files, no behaviour change.

## [1.3.1+1032] — 2026-09-30 — "Update Anything, From Anything"

### Fix — in-place updates for every install, no uninstall ever
- **Root cause of "package not valid" on v1.2.1 installs** — v1.2.1 shipped *split* APKs with Flutter's abiCode×1000 versionCode override (arm64 = 2031), while the v1.3.0 release accidentally packed *base-code copies* into the per-ABI filenames (arm64 = 32): the universal build step regenerates the whole output dir and the organize step copied the overwritten files. Android treats new-code < old-code as INSTALL_FAILED_VERSION_DOWNGRADE even when the signing key matches (and it did — both c513faef) — so every v1.2.1 phone hard-blocked.
- **Build order fixed** — split outputs are parked to `split-out/` *before* the universal build touches the directory; per-ABI assets rename from the parked copies, Universal from the fresh build. Never again the mixed set.
- **versionCode floor guard in CI** — every release APK must carry versionCode > 2031 (pubspec build number ≥ 1032 keeps arm64 at 3032+ even if the ABI override ever stops applying); a violation blocks the release with an explicit bump instruction.
- **Also fixed alongside** — releases v1.1.3–v1.1.5 shipped debug-signed (release keystore added only at v1.1.7) and some phones carry locally-built test installs; those installs get `Dizzy-v3-legacy-*` mirrors signed with the original key. The app reads its own signing-cert fingerprint (new `getCertSha256` channel) and fetches the matching asset.
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
