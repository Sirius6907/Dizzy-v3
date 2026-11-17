# Dizzy — FINAL HANDOFF (2026-11-12): everything end to end, flawless

You (OpenCode) now OWN the full remaining work on Dizzy. No other agent is
working on this repo. Finish everything end to end with ZERO loose ends.

## The owner's vision — understand this BEFORE any code

Dizzy is a solo-built, India-first EVERYTHING app: movies, series, anime,
music, manga, books, audiobooks, Live TV — one dock, one audience
(Indian users), zero marketing budget. It wins on logic and experience,
not on scale. The owner's vision, stated as achievable goals:

1. **India-first is the identity.** The default audience is Indian:
   JioSaavn/Desi content leads music, TMDB-IN leads movies, language
   rails (Hindi/Tamil/Telugu/Malayalam) are first-class, prices/languages/
   trending reflect what India actually watches and hears today. Global
   content is a secondary layer, never the front door.
2. **Everything is REAL-TIME and DYNAMIC.** No stale rails, no hardcoded
   playlists, no content frozen at build time. Trending must be what is
   trending TODAY; mixes must refresh daily; recommendations must come
   from live clients and the user's own behavior. A rail that shows the
   same content two days in a row without a data-driven reason is a bug.
3. **ZERO AI-slop.** No mashup titles ("F. Barkati · F. Toigo — Happy
   Birthday"), no duplicated rails wearing different emoji headers, no
   escaped HTML entities, no fake curation. If a section exists, it must
   exist for a reason a human product manager would defend. Titles read
   like a human wrote them ("Lo-fi Evenings", "Romantic Golden Hour").
4. **Music is VIBE-first.** People listen by mood/feel, not by artist
   similarity — the engine must match FEEL first and treat favorite
   artists as accents. The onboarding wizard (artists → style → mood)
   is how Dizzy learns who the listener is, and it must feel like
   Spotify's first-run quality.
5. **The standard is the current 2026 giants.** Home must work like
   Netflix, music like Spotify, anime like Crunchyroll — their app logic
   and system design patterns (cold-start-to-content speed, personal
   rails, continue-watching done right, queue/radio quality, library).
   Dizzy will never out-spend them; it must out-THINK them on Indian
   soil: one app, all content types, localized, dynamic.
6. **The user must be able to TRUST every pixel.** No "no data" dead ends
   where cached content could show; no silent failures; honest error and
   retry states; evidence-based behavior everywhere. When something is
   missing, the app explains itself instead of showing a blank.
7. **Achievable bar, not fantasy.** 99.3% eval success is the target for
   everything IN the app's control (flows, states, correctness, polish).
   Things bounded by external services (addon catalog depth, live source
   uptime) are reported honestly, not padded.
8. **Solo-dev economics.** Every feature must be maintainable by one
   person: reuse existing services, no parallel engines, pure testable
   cores, no speculative abstractions. Boring, correct, dynamic.

Understand what the owner RESPECTS (from every review round so far):
real-time freshness over static curation; taste-continuation over flat
lists; complete albums/tracklists over stubs; correct deep-links over
"Details unavailable"; one consolidated brand rail over five duplicate
rows; human copy over machine slop; and honest UNVERIFIED lists over
inflated claims. These are the standards every decision you make must
serve.

## What has happened so far

- `VIBE_ENGINE_BRIEF.md` (round 1): Part A home fixes, Part B onboarding
  wizard, Part C vibe engine, Part D builds, Part E emulator testing.
  When this handoff is read, that run may or may not be finished — FIRST
  verify its state: does `## Vibe engine round (2026-11-12)` exist in
  `docs/audit/2026-11-09-music-creator.md`? If NO, finish the vibe brief
  first, exactly as written there.
- `STRESS_BRAND_BATTLE_BRIEF.md` (round 2): full-app stress test, brand
  battle vs Netflix/Spotify/Crunchyroll (2026), 99.3% eval gate. Run it
  AFTER round 1 is done and its report section exists.

## Quality bar — "flawless end to end" means ALL of these, no exceptions

1. `flutter analyze --no-pub` → "No issues found!" before you declare any
   part done. Fix every warning.
2. `flutter test` → fully green (0 failures). If an old test breaks because
   of a behavior change, update the test AND say so in the report.
3. Every feature claim needs on-device evidence: adb interaction +
   `adb exec-out screencap -p` → downscale to 540px JPEG with
   /c/ffmpeg/bin/ffmpeg → READ the image yourself → only then claim it.
   Never claim a UI state you did not see. Unverified = failed, never pass.
4. No fake green anywhere: the 99.3% eval reports the MEASURED number.
   If a check cannot reach the bar this round (e.g. catalog depth bounded
   by external addons), state the measured number and the reason plainly.
5. Honest about Playwright/Selenium: Flutter does not render a DOM. Attempt
   the honest routes (integration_test / flutter_driver), save script
   skeletons under `artifacts/audit-dsh/scripts/`, and document in the
   report why browser automation cannot see Flutter widgets. Do not fake it.
6. Edge cases are in scope everywhere: offline start, network flap mid-flow,
   refresh spam, rapid dock switching, theme toggle mid-flow, kill+relaunch
   state restore, empty states, addon-down states. Every failure → fix root
   cause, re-verify, no symptom patches.
7. Regression discipline: after EVERY fix, re-run analyze + tests, and
   re-verify the ADJACENT flows (the fix must not break neighbors). State
   in the report what you re-verified and what remains unverified.
8. Do not touch unrelated uncommitted work. Two-clay tokens only. No
   hardcoded track/artist lists (the no-hardcode grep test must keep
   passing).

## Execution order (strict)

1. Finish `VIBE_ENGINE_BRIEF.md` (if not already complete) — Parts A–C,
   then Part D builds (fresh exe + APKs, freshness via
   `data/app.so` mtime), then Part E evidence (`vibe-*.jpg`).
2. Run `STRESS_BRAND_BATTLE_BRIEF.md` — stress test (`stress-*.jpg`),
   brand battle scorecards, eval harness in
   `docs/superpowers/evals/2026-11-12-dizzy-eval.md`, measured score.
3. Rebuild BOTH artifacts one final time AFTER all fixes:
   - Windows: PATH=/c/Users/opcha/flutter/bin,
     TORRSERVER_FLUTTER_LOCAL_BINARIES="C:\\Users\\opcha\\Downloads\\Dizzy-v3\\release-artifacts\\windows-x64",
     `flutter build windows --release`; copy Release dir over
     `release-artifacts/windows-x64/` (keep its `.env`) + exe to
     `release-artifacts/dizzy.exe`.
   - APKs: `flutter build apk --release` + `--split-per-abi`; publish as
     `release-artifacts/Dizzy-Universal.apk`, `Dizzy-arm64-v8a.apk`,
     `Dizzy-armeabi-v7a.apk`, `Dizzy-x86_64.apk`.
4. Final report: append
   `## FINAL HANDOFF (2026-11-12)` to
   `docs/audit/2026-11-09-music-creator.md` with:
   - VERIFIED list (each with evidence file name),
   - UNVERIFIED list (each with the reason),
   - the measured eval score vs the 99.3% bar,
   - what changed in `release-artifacts/` (file + mtime proof).

## Hard rules (unchanged)

- NO git commit, NO git push, NO Supabase deploys, NO releases.
- Stop immediately on any quota or rate-limit error and write what remains
  in the report instead of half-finishing silently.
- Emulator: `emulator-5554` / AVD `dizzy_test` (start via
  `/c/tools/emulator/emulator.exe -avd dizzy_test` if down), package
  `com.sirius6907.dizzyv3`, `MSYS_NO_PATHCONV=1` for /sdcard paths.
- The owner's standard: Dizzy's app logic and system design must match
  2026 Netflix (home), Spotify (music), Crunchyroll (anime). Compare
  honestly; same-weight-class framing; no invented competitor features.
