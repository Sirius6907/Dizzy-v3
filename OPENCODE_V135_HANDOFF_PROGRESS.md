# v1.3.5 handoff — progress ledger

Branch `prism/v2-reskin`, Windows, Git Bash. Plan:
`docs/superpowers/plans/2026-11-16-v135-playback-milestones.md`.
One line per task, evidence first. Commit checkpoints are owner-gated; nothing
was committed, pushed, tagged or deployed.

## Task 1 — Rust toolchain + bridge scaffold — DONE

- `rust/dizzy_adblock/{Cargo.toml,src/lib.rs,src/api.rs}` created;
  `flutter_rust_bridge 2.9.0` added to `pubspec.yaml`; Android targets
  (`aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android`)
  and `x86_64-pc-windows-msvc` installed.
- Codegen 2.9.0 installed (`cargo install flutter_rust_bridge_codegen
  --version 2.9.0`), generated `lib/rust/{api.dart,frb_generated*.dart}` and
  `rust/dizzy_adblock/src/frb_generated.rs`.
- Windows DLL: `cargo build --release --target x86_64-pc-windows-msvc` →
  `rust/dizzy_adblock/target/x86_64-pc-windows-msvc/release/dizzy_adblock.dll`
  (3.5 MB). A copy also sits at `rust/dizzy_adblock/target/release/`, which is
  the path FRB's generated loader reads in dev.
- Android: `cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o
  android/app/src/main/jniLibs build --release` →
  `libdizzy_adblock.so` (3.7 MB / 2.5 MB / 3.9 MB).
- `windows/CMakeLists.txt` installs the DLL next to `dizzy.exe` when it exists
  (warning, not failure, when absent).
- `lib/main.dart`: `_safeInit('adblock_bridge', RustLib.init)` — a missing or
  incompatible native library disables embed ad-blocking only.
- **Dependency fix (required):** `adblock 0.8.12` pulls `rmp-serde 0.15.5`,
  which does not compile against `rmp 0.8.15`. Pinned `rmp 0.8.11`
  (`cargo update -p rmp --precise 0.8.11`, recorded in `Cargo.lock`).
- **Design note:** `adblock::Engine` is `!Send + !Sync` (internal `Rc`/
  `RefCell`) and FRB opaque handles require both. Rather than `unsafe impl`,
  the engine owns a dedicated worker thread and every query is a channel
  round-trip — serialized by construction, and filter-list compilation stays
  off the caller's thread.

## Task 2 — DizzyEngine match API — DONE

- `rust/dizzy_adblock/src/api.rs`: `DizzyEngine::from_rules` /
  `match_request` + the FRB surface `new_engine` / `engine_match`; parse errors
  answer "allow" (never block on a parse failure); a dead worker answers
  "allow".
- `cargo test` → `4 passed; 0 failed` (`blocks_known_ad_hosts`,
  `blocks_third_party_tag_manager`, `allows_media_and_site_traffic`,
  `unparseable_request_is_allowed`).
- `test/adblock_engine_test.dart` (Dart → FFI → Rust round-trip):
  `flutter test --no-pub test/adblock_engine_test.dart` → `All tests passed!`
  (2 cases; skipped automatically on a machine without the native build).
- `flutter analyze --no-pub` → **No issues found!** (97.9 s).

## Task 3 — FilterListService + supplemental list — DONE

- `lib/services/adblock/filter_list_service.dart` — merge cached EasyList +
  uBlock filters + shipped supplemental; 7-day refresh; stale cache survives a
  network failure; injectable client/dir/asset loader.
- `assets/adblock/dizzy_supplemental.txt` — measured VidFast ad/tracker hosts;
  registered under `assets/adblock/` in `pubspec.yaml`.
- `test/filter_list_service_test.dart` → `4 passed` (fresh merge, stale-cache
  survival, refresh writes disk, shipped asset content).

## Task 4 — VidFast embed scraper — DONE

- `lib/services/scraper/sites/vidfast.dart` rewritten: official embed URL
  (`/movie/{id}?autoPlay=true`, `/tv/{id}/{s}/{e}?autoPlay=true`), `url: null`,
  `behaviorHints['dizzyEmbed']=true`, IMDb-id fallback when TMDB resolution
  fails. The enc-dec chain and its network/parse code are gone.
- `test/vidfast_embed_scraper_test.dart` → `5 passed` (movie, tv, IMDb
  fallback, throwing resolver, no-id).

## Task 5 — EmbedWebviewPlayer — DONE

- `lib/pages/player/embed_webview_player.dart`: `flutter_inappwebview` surface
  with `useShouldInterceptRequest`, a single process-wide engine + list cache,
  pure `resourceTypeFor` / `isMediaUrl` / `shouldBlock` helpers, media capture
  with `Referer`/UA, blocked-request logcat lines, 30 s no-capture fallback to
  in-webview playback, page-error Retry, and `onGiveUp` for failover.
- Page document is never blocked; `.ts`/`.m4s`/`.vtt` are never captured.
- `test/embed_adblock_decision_test.dart` → `3 passed`.

## Task 6 — Player + probe + ranker wiring — DONE

- `StreamSource.isEmbedSource` getter; health checker returns alive without a
  probe for embeds; `SourceRanker.buildFailoverChain` tiers
  **direct → embed → torrent**.
- `PlayerScreen`: `_embedActive` / captured-URL-by-source-fingerprint state,
  `_initStream` opens the webview instead of mpv until capture, then reopens
  mpv with the captured URL + headers; `onGiveUp` fails over only when a ranked
  backup exists.
- `test/embed_source_pipeline_test.dart` → `4 passed`.

## Gates after Task 6

- `flutter analyze --no-pub` (whole app, after Task 2) → **No issues found!**
- `flutter test --no-pub --name '^(?!bulk corpus probe$)'` → **1663 passed,
  26 skipped, 0 failed** (baseline 1645 + 18 new tests; log
  `artifacts/v135/full-suite-1.log`).
- `cargo test` → 4 passed.

## Task 6 device evidence — VERIFIED ON ANDROID

`integration_test/vidfast_embed_test.dart` on `emulator-5554` (x86_64,
`--dart-define-from-file=.env`), log
`artifacts/v135/m1-embed-integration-2.log`: **All tests passed**, and the log
shows the whole M1 chain happening for real:

```
[Embed] block static.cloudflareinsights.com (xhr)
[Embed] block www.googletagmanager.com (xhr)
[Embed] block flagsapi.com (image)
[Embed] block umami.vidfast.vc (script)
[Embed] block o.2oznbwwxbwxlhb8o2tzizevu6uffxuvrp6948b.cfd (xhr)
[Embed] media captured from moon.goldenkite.top
[M1] captured media from moon.goldenkite.top
[Embed] session blocked 6 ad/tracker requests
```

That answers the plan's biggest open risk: **VidFast's protection gate does not
block Android WebView**, the Rust engine blocks its ads, and the embed really
does issue a capturable media URL (12 s), with the `Referer` header attached.

`[boot] adblock_bridge ok 18ms` also appears in the app's own logcat, so the
native library loads on device outside the test harness.

### Defect found by this device run and fixed

An embed source is "alive" with zero latency (there is nothing to probe), so
offering it to the instant-play race immediately made autoplay prefer a webview
over a direct stream that answered 200 ms later. `WatchResolveController` now
gives direct sources a 3 s head start (`embedRaceHeadStart`) before the embed is
offered to the race; if no direct source is alive, the embed still opens.

## Task 6 device evidence — (superseded) IN PROGRESS

- Emulator `dizzy_test` booted (`emulator-5554`, x86_64).
- `flutter build apk --debug` log: `artifacts/v135/apk-debug-build.log`.
  Release APK cannot replace the emulator's debug-signed install without an
  uninstall (forbidden), so device runs use the debug build of the same source
  — the same precedent recorded in `RELEASE_CHECKLIST.md`.
- **Verify on logcat:** `[boot] adblock_bridge ok`, `[Embed] block …` lines and
  `[Embed] media captured from …`.

## Environment notes for the next agent

- `export PATH="/c/Users/opcha/flutter/bin:$PATH"` before every flutter
  command. `flutter_rust_bridge_codegen` and `cargo-ndk` live in
  `~/.cargo/bin` (not on PATH).
- Codegen command that works on this machine (FRB 2.9 has a Windows
  `\\?\`-prefix bug with absolute paths): run from `rust/dizzy_adblock` —
  `flutter_rust_bridge_codegen generate --rust-input crate::api --rust-root .
  --dart-output ../../lib/rust --dart-root ../..`
  (`lib/rust` must already exist; Flutter must be on PATH).
- NDK: `ANDROID_NDK_HOME='C:\tools\ndk\28.2.13676358'`.

## Task 6 device evidence — mpv handoff PROVEN (main-agent re-run, 2026-11-16)

Fresh emulator run of `integration_test/vidfast_embed_test.dart` on
`emulator-5554` (`--dart-define-from-file=.env`) completes the M1 gate. The
mpv-handoff assertion (added at 12:14, unexecuted by the Freebuff run) now ran:

```
[Embed] block static.cloudflareinsights.com (xhr)
[Embed] block www.googletagmanager.com (xhr)
[Embed] block umami.vidfast.vc (script)
[Embed] block flagsapi.com (image)
[Embed] block o.2oznbwwxbwxlhb8o2tzizevu6uffxuvrp6948b.cfd (xhr)
[Embed] media captured from moon.goldenkite.top
[M1] mpv position after handoff: 2s
[Embed] session blocked 6 ad/tracker requests
All tests passed!
```

`mpv position after handoff: 2s` = bytes actually decoded in mpv from the
captured CDN URL with the captured Referer. Full M1 chain proven on device:
embed webview → Rust engine blocks ads → media capture (12 s) → mpv playback.

Fresh gates at handoff (main agent, 2026-11-16): `cargo test` 4 passed;
`flutter analyze --no-pub` No issues found!; full suite 1663 passed / 26 skip /
0 failed.

**M1 COMPLETE. Remaining: owner manual test (M1 UX), M2 (Tasks 7—11), M3 (Task 12).**

## v1.3.5 second wave — scraper isolation, probe .exe, ranker refactor (2026-11-16)

### Scraper isolation — DONE
- `lib/services/stream/stream_service.dart`: added
  `appActiveScrapers = {'rivestream', 'flaxmovies'}`; `_reg()` now checks
  retiredScrapers (blocklist) AND appActiveScrapers (allowlist). Knaben +
  TorrentGalaxy registration routed through `_reg()` too, so torrents are
  gated by the same switch. Nothing deleted — re-enabling is a one-line edit.
- Probe (`tool/player_probe`) still iterates all 45 built-ins on purpose.

### Probe .exe — DONE (build: `flutter build windows --release -t tool/player_probe/main.dart`)
- `probe_engine.dart`: new `SourceShape.file` → label 'FILE' for
  extension-less direct links (worker `/d/…` hosts, signed CDN tokens);
  `unknown` ('???') stays reserved for empty/unsupported. `opensInMpv`
  already true for `file`.
- `probe_screen.dart`: embed rows now PLAY, reusing the app's own
  `EmbedWebviewPlayer` verbatim (webview + Rust adblock + capture → mpv).
  Shared `_openMediaUrl(index, url, {headers, shapeLabel, isLive})` core for
  direct sources + captured embed media; `_openEmbed`/`_onEmbedCaptured`/
  `_onEmbedGiveUp`; `_embedActive` state; webview stacks on top of mpv Video.
  Torrents remain labelled-not-played (TorrServer is app-only).
- `main.dart`: boots Rust engine — `_ensureAdblockDllNextToExe()` copies
  `dizzy_adblock.dll` next to the exe (cwd first, then walk up 6 dirs) then
  `RustLib.init()`; soft-fail (unblocked ads, logged).
- Exe at `build\windows\x64\runner\Release\dizzy.exe`. CMake warns "dll not
  built" — expected; the runtime bootstrap covers it.

### Ranker refactor — DONE (behavior preserved, tests are the spec)
- `lib/services/stream/source_ranker.dart` rewritten:
  - single `isTorrent(StreamSource)` predicate (was duplicated 3×:
    tierOf / score / buildFailoverChain),
  - one `_searchableText` helper (was 4 copies of the same concatenation),
  - named size constants `_sizeTwoGb/_sizeOneGb/_sizeSevenHundredMb`,
  - precompiled regexes (`_reHeavyCodec/_reAv1/_reAdaptiveLabel/_reSeeders`),
  - new `explain(s, ctx)` → Map<String,int> of every additive score
    component; `score()` is exactly its sum (debug API, additive-neutral).
- Public API unchanged: buildFailoverChain / fingerprint / order / score /
  tierOf / promotedProviders / isPromoted (+ new isTorrent, explain).
- Gates: `flutter analyze --no-pub` No issues; 63 tests passed across
  source_ranker / promoted_source_priority / playback_source_selection /
  embed_source_pipeline / probe_engine / rendition_contract.

### APKs — rebuilt WITH the ranker refactor (2026-11-16 21:25)
- `build/app/outputs/flutter-apk/`: app-arm64-v8a (61.1MB), app-armeabi-v7a
  (58.7MB), app-x86_64 (64.4MB), universal app-release.apk (171.4MB).
  Split + universal built after the ranker refactor (analyze + 63 tests
  green beforehand).
- NOTE (PowerShell): `flutter build` exit code 1 = stderr
  NativeCommandError artifact; success shows as "√ Built ..." lines.

