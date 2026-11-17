# HANDOFF PROMPT — v1.3.5 Playback Milestones (M1 → M3, end at test build)

Copy everything below the line into the agent. Do not edit the plan file — it is the source of truth.

---

You are taking over implementation work on the Dizzy Flutter app. Work in
`C:\Users\opcha\Downloads\Dizzy-v3`, branch `prism/v2-reskin`, Windows, Git Bash.

## Read first (in this order)

1. `docs/superpowers/plans/2026-11-16-v135-playback-milestones.md` — THE plan. Execute its tasks 1→12 in order. Everything below is context and constraints; the plan has the code, file paths, and step details.
2. `docs/superpowers/specs/2026-11-14-dizzy-private-addon-engine-design.md` — background on the source architecture (skim).
3. `artifacts/audit-dsh/vidfast/` — root-cause evidence for why the old VidFast scraper is dead (RSC page, VF1 protection VM, TLS gate; sample captures).
4. `lib/services/scraper/stream_scraper.dart`, `lib/services/stream/stream_health_checker.dart`, `lib/services/stream/source_ranker.dart`, `lib/pages/player/player_screen_part_playback.dart` — the pipeline you are extending.

## What you are building (goal, in one line)

VidFast plays in-app, ad-free, via its own official embed + Brave's open-source
adblock-rust engine in a webview that hands the m3u8 to mpv — then every other
source is audited/repaired and the torrent tier hardened — ending with release
builds ready for the owner's manual testing.

## Decisions already frozen by the owner — do NOT relitigate or re-research

1. **VidFast = the site's OWN documented embed** (`https://vidfast.vc/movie/{imdbOrTmdbId}?autoPlay=true`, `/tv/{id}/{season}/{episode}?autoPlay=true` — it accepts IMDb ids too). **NEVER use enc-dec.app chains** for vidfast. Do not try to reverse-engineer the VF1 protection VM.
2. **Ad-block engine = Rust `adblock-rust` 0.8 via flutter_rust_bridge v2**, filter DATA = open-source lists (EasyList + uBlock filters, fetched+cached, 7-day refresh) + the measured supplemental rules in the plan (domains observed live on vidfast: vinnyvower.cfd, contain.remanpurflertawneys.cyou, lpxu3ovf7r…cfd, GTM/GA/umami/flagsapi/cloudflareinsights).
3. **Webview = flutter_inappwebview** (Android + Windows WebView2). Playback flow: embed webview (adblocked) → intercept the m3u8/mp4 request (plain CDN traffic) → hand off to mpv with `Referer: https://vidfast.vc/` → in-webview playback as fallback if handoff fails within 30 s.
4. **"Dead source" ≠ "no content".** A scraper yielding 0 sources is verified against its live site in a real browser BEFORE any dead verdict — most 0-yields are stale parsers (VidFast proved this: site alive and playing while our parser saw nothing). Verdicts: ALIVE-direct / EMBED-PORTABLE / PARSER-BROKEN (repair) / TRULY-DEAD (retire). User reports of unavailable content are an app-code suspect first.
5. **Odia/regional movies are OUT OF SCOPE entirely** — exclude from every corpus, audit, and metric. Owner will build a dedicated scraper later.
6. Books section: untouched (v1.3.6).

## Hard constraints

- **NO git commit, push, tag, release, or Supabase deploy/schema/data change.** The owner commits after their manual testing. Commit checkpoints named in the plan are OWNER-gated — when you reach one, note it and move on.
- No `adb uninstall` or clear-data on the test device. Never kill another agent's or unfamiliar process.
- Secrets only in gitignored `.env`; never print signed stream URLs, tokens, or keys.
- Exactly Light Clay / Dark Clay; semantic palette tokens in any new UI.
- Fix root causes with failing tests first (TDD); no "should work" claims — every completion claim carries the command output that proves it.
- Do not start work outside the plan's file list; do not refactor beyond tasks.

## Environment facts (this machine)

- Flutter is NOT on PATH: `export PATH="/c/Users/opcha/flutter/bin:$PATH"` before every flutter command.
- Windows builds need: `export TORRSERVER_FLUTTER_LOCAL_BINARIES="C:\\Users\\opcha\\Downloads\\Dizzy-v3\\release-artifacts\\windows-x64"`.
- Gates: `flutter analyze --no-pub` must print "No issues found!"; full suite: `flutter test --no-pub --name '^(?!bulk corpus probe$)'` (live-probe network tests are excluded by that filter; current baseline 1645 pass / 26 skip).
- C: has ~30 GB free; Rust toolchain + NDK targets need 1–2 GB. Check `df -h /c` before Task 1.
- NDK exists at `C:\tools\ndk` (pick the newest platform dir for cargo-ndk).
- Full Windows+APK build recipe is in the plan's Task 12 and works today — follow it exactly.

## Stop conditions (report to owner, do not improvise)

- rustup/MSVC/cargo-ndk cannot be made to work after honest attempts (~30 min of troubleshooting): STOP and report — switching to a Dart matcher is an owner decision, not yours.
- Any Quota/rate-limit error from your provider: save a checkpoint summary (task numbers done, tests green, next step) and stop.
- Disk < 5 GB free at any point.
- If flutter_inappwebview's installed version lacks a documented interception hook on Windows (WebView2), implement Android first, log the Windows gap in `OPENCODE_V135_HANDOFF_PROGRESS.md`, and continue — Android is the owner's primary test surface.

## Required progress ledger

Maintain `OPENCODE_V135_HANDOFF_PROGRESS.md` in the repo root, updated after EVERY task:
`Task N <name> — DONE|BLOCKED — evidence (command + output tail) — next step`.
This file is how the owner's main agent audits your work when they return.

## Milestone gates (what "done" means)

- **M1 gate:** release APK installed on the `dizzy_test` AVD (existing emulator recipe; landscape screenshots via existing helper), owner-testable: Fight Club (movie) + one series episode play from the VidFast embed ad-free with mpv handoff. You verify: analyzer clean, suite green, `cargo test` green, APK builds and installs, logcat shows the engine blocking ad requests and the m3u8 capture. The owner does the human verification.
- **M2 gate:** audit doc `artifacts/audit-dsh/scraper_audit_2026-11.md` written with per-site verdicts (browser-verified), embed ports + parser repairs landed with tests, torrent hardening done, Supabase deploy steps LISTED but NOT executed (owner runs them).
- **M3 gate:** analyzer + full suite + cargo tests green; Windows exe + universal + 3 split APKs rebuilt per recipe; `python artifacts/audit-dsh/scripts/verify_release_artifacts.py` prints `ALL_ARTIFACTS_FRESH`; `RELEASE_CHECKLIST.md` and CHANGELOG updated for v1.3.5; eval file rows updated where you have evidence. STOP at the build — owner tests, then commits/tags on their own approval.

## Non-negotiable quality bar

- Every new pure function has a failing-test-first cycle (the plan shows the exact tests to write — use them).
- Do not weaken existing tests to pass; do not skip or xfail tests.
- Do not remove or "simplify" unrelated code you happen to open.
- If a fix touches playback-adjacent state (probe/rank/failover/gate), re-run the full suite, not just the touched file's tests.
- If you find yourself inventing a mechanism not in the plan (e.g., a third extraction path for vidfast), STOP and write the finding in the progress ledger instead.

Start with Task 1 of the plan now. Report progress only in the ledger file; keep chat output minimal.
