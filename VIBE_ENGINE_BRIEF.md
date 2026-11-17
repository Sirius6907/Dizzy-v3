# Dizzy — Music Onboarding + Vibe Engine + Home Fixes (2026-11-12 brief)

You are continuing work on Dizzy (Flutter media app) in the same session.
Read `docs/audit/2026-11-09-music-creator.md` FIRST (rounds 1, 2, follow-ups
and the 2026-11-11 Sirius audit pass are all there).

The user tested the fresh Windows exe and reported:

- Home cards: clicking some cards shows "no data" / nothing loads.
- Streaming Catalogs brand rail (Netflix / HBO Max / Prime / Apple TV /
  Disney+) does NOT show reliably — it comes and goes.
- The entire music section is NOT India-localized and reads like duplicated
  AI-generated playlists ("Made For You" mashup titles like
  "F. Barkati, F. Toigo, W. O. Landron — Happy Birthday" (13 artists) and
  an `&amp;` HTML-entity leak in "Dadju · Vishal &amp; Shekhar").
- Music must learn WHO the listener is, not just chase global charts.

## The user's locked design (do not redesign, do not ask)

Core insight from the user: **people listen by VIBE/MOOD, not by artist
similarity.** Two different singers can share the same feel. Artists are the
SEED, vibe is the ENGINE.

### Part A — Home bugs (do first)

1. Diagnose the streaming-catalogs addon flakiness. The brand rail renders
   only when sections with `subtitle == 'Streaming Catalogs'` arrive from
   the addon (see `providerAddonName` in `lib/pages/home/home_rails.dart`,
   consumed in `home_page.dart` `_loadHome`). Check both addon sources
   (baby-beamup.club and the workers.dev mirror) with real HTTP calls and
   logcat evidence. Fix root cause: if one source is dead, fail over to the
   other; if both are slow, cache last-good brand sections so the rail
   survives a cold session. Brand rail missing = bug, intermittent = bug.
2. Cards that show "no data": reproduce, identify which section/catalog the
   failing cards come from, fix the failure path (graceful retry + cached
   last-good instead of an empty error state).
3. Fix the `&amp;` HTML-entity leak in music mix/artist titles (unescape
   HTML entities wherever titles are displayed — find the client that
   returns escaped names).

### Part B — Music onboarding wizard (Spotify-style first open)

On the FIRST open of the Music tab, show a 3-step wizard (skippable,
editable later in Music Settings):

1. **Favorite singers/artists** — pick from live trending artists (existing
   `fetchTrendingArtists` + JioSaavn/Deezer search) plus free-text search.
   Minimum 0 (skippable), no maximum.
2. **Music style** — lofi / romantic / energetic / party / focus /
   devotional (multi-select chips; map onto the existing `MusicMood`
   system where it fits, add new style categories only if the mood enum
   cannot express them).
3. **Default mood preference** — the mood the app should optimize for by
   default.

Persist via a new `MusicOnboardingService` (SharedPreferences-backed,
follow the pattern of `LanguageChipState` / `MusicSettings`). One pref flag
`music_onboarding_done` gates the wizard. Never re-show after completion
or skip; editable from Music Settings.

### Part C — Vibe engine (rewire the EXISTING engagement engine)

Do NOT build a second engine. Rewire what exists
(`music_engagement_service.dart`, `music_smart_mix_service.dart`,
`music_radio_service.dart`, `music_service.dart`):

1. **Vibe profile**: from the user's favorite artists + chosen styles +
   default mood, derive a vibe profile (mood weights via the existing
   `MusicMoodFilter` scoring + duration bands). Cache it, refresh it when
   favorites change, and day-rotate the exploration part.
2. **Made For You**: mixes become VIBE-seeded (vibe profile picks the
   pool from live clients; favorite artists are sprinkled in as accents,
   roughly 1-in-4). Titles must be human: "Lo-fi Evenings",
   "Romantic Golden Hour" — derived from the vibe/style, NEVER artist-name
   mashups. This replaces the current artist-concatenation titles.
3. **Home rails**: when onboarding is done, 'Your Artists' and 'Your Vibe'
   rails lead the music home; global trending moves below. When the user
   skipped onboarding, today's behavior stays exactly as it is.
4. **Radio / next-up**: keep taste-continuation and steering, but the
   selection pool is vibe-first: same feel, any artist, favorites woven in.
5. Everything stays dynamic: live clients (JioSaavn, Deezer), daily
   rotation via the existing day-seed machinery, NO hardcoded track or
   artist lists anywhere (the no-hardcode grep test must keep passing).
6. India-first: region defaults to India — JioSaavn content leads, Deezer
   global chart is secondary, not primary.

## Part D — Fresh builds (AFTER Parts A–C are done and verified)

Build BOTH artifacts fresh:

1. **Windows exe**:
   `export PATH="/c/Users/opcha/flutter/bin:$PATH"` and
   `export TORRSERVER_FLUTTER_LOCAL_BINARIES="C:\\Users\\opcha\\Downloads\\Dizzy-v3\\release-artifacts\\windows-x64"`,
   then `flutter build windows --release`.
   Freshness proof = `build/windows/x64/runner/Release/data/app.so` mtime
   (the runner exe mtime never moves — do not use it as evidence).
   Copy the whole Release dir over `release-artifacts/windows-x64/`
   (that dir carries its own `.env` — do not delete it) and the exe to
   `release-artifacts/dizzy.exe`.
2. **APKs**: `flutter build apk --release` then
   `flutter build apk --release --split-per-abi`; publish as
   `release-artifacts/Dizzy-Universal.apk`, `Dizzy-arm64-v8a.apk`,
   `Dizzy-armeabi-v7a.apk`, `Dizzy-x86_64.apk`.
3. Gates before ANY build: `flutter analyze --no-pub` prints
   "No issues found!" and `flutter test` is fully green.

## Part E — Emulator testing with vision verification

Emulator `emulator-5554` (AVD `dizzy_test`, may need
`/c/tools/emulator/emulator.exe -avd dizzy_test` to start). Package
`com.sirius6907.dizzyv3`. Screenshot workflow: capture PNG with
`adb exec-out screencap -p`, downscale to 540px wide JPEG with ffmpeg
(/c/ffmpeg/bin/ffmpeg), and READ the image to verify — never claim a UI
state you did not see. `MSYS_NO_PATHCONV=1` for /sdcard paths.

The user explicitly asked for Playwright and Selenium scripts. Be honest
about feasibility: Flutter desktop/mobile does NOT render a DOM, so stock
Playwright/Selenium cannot drive the real app. Attempt the honest Flutter
routes first (flutter integration_test / flutter_driver); if that is not
workable in this round, do the verification with adb-driven interaction +
screenshot vision verification instead, save whatever script skeletons you
tried under `artifacts/audit-dsh/scripts/`, and clearly document in the
report WHY Playwright/Selenium cannot see Flutter widgets — do not fake
green results.

Required on-device evidence (screenshots in `artifacts/audit-dsh/`,
`vibe-*.jpg` naming):
1. Onboarding wizard renders on first Music open; each step captured;
   skip works; wizard does not reappear after skip; Settings edit works.
2. Favorite artists + lofi style picked → 'Your Artists' + 'Your Vibe'
   rails lead the home; Made For You titles are human vibe titles (no
   artist mashups, no `&amp;`).
3. Radio/next-up on a favorite-artist song: vibe continuation visible.
4. Brand rail present on home after your Part A fix (cold start too).
5. Play one track end-to-end (audio or at least the player state) to prove
   no playback regression.

## Hard rules

- NO git commit, NO git push, NO Supabase deploys, NO releases.
- Evidence for every claim; stop immediately on any quota error.
- Do not touch other uncommitted work outside your task files.
- Two-clay theme tokens only; no raw Colors.white/black in new UI.
- Append a `## Vibe engine round (2026-11-12)` section to
  `docs/audit/2026-11-09-music-creator.md` with VERIFIED / UNVERIFIED lists.
