# v1.3.5 Playback Milestones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make VidFast the first fully-working ad-free source (official embed + Brave's open-source adblock-rust engine in an in-app webview, handing off to mpv), then repair/retire every remaining source and the torrent tier, and ship v1.3.5.

**Architecture:** Three milestones. M1 = one source, end-to-end: Rust adblock engine (adblock-rust via flutter_rust_bridge) + filter-list cache + webview embed surface + VidFast scraper rewrite + player handoff. M2 = breadth: liveness-audit every scraper, port embed-style sites to the same webview pattern, retire the dead, harden the torrent tier, deploy the pending Supabase functions. M3 = release: full gates, artifacts, eval, checklist.

**Tech Stack:** Flutter 3.47.2 / Dart 3.13.2, media_kit (mpv), flutter_inappwebview (Android + Windows WebView2), adblock-rust 0.8 via flutter_rust_bridge v2 (Rust cdylib), EasyList + uBlock filter lists, TorrServer (existing Go sidecar), Supabase edge functions.

**Spec:** `docs/superpowers/specs/2026-11-14-dizzy-private-addon-engine-design.md` (engine context) + this plan. VidFast decision record: use the site's OWN documented embed (`https://vidfast.vc/movie/{imdbOrTmdbId}?autoPlay=true`, `https://vidfast.vc/tv/{id}/{season}/{episode}?autoPlay=true`) — never enc-dec chains (root-cause evidence in `artifacts/audit-dsh/vidfast/`: site is now Next.js RSC + VF1 protection VM + TLS-fingerprint gate; Dart http gets a token-less page, Chrome-UA curl gets 403).

## Global Constraints

- Exactly Light Clay and Dark Clay; semantic palette tokens only, no raw white/black.
- No commit, push, tag, or release without the owner's explicit approval; commit checkpoints below are owner-gated.
- No Supabase deploy or schema/data change without separate owner approval; never `db push --include-all`.
- No adb uninstall or clear-data on the test device.
- Secrets only in gitignored `.env`; never print signed URLs/tokens.
- Ad/tracker blocklists are DATA (open-source lists: EasyList `https://easylist.to/easylist/easylist.txt`, uBlock filters `https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt`, plus a shipped supplemental list of VidFast-observed domains). Blocking decisions never hardcode per-site logic in UI code.
- The owner runs manual/UI/UX/device verification; agent verification = analyzer + `flutter test --no-pub` + build + logs.
- **"Source dead" ≠ "no content" — and user reports of unavailable content are an app-code suspect FIRST.** When a user reports "content not available / not playing", the default hypothesis is OUR pipeline (parser stale, id mismatch, probe false-negative, gate bug) — not the source. A site that "yields 0 sources" is verified against its live site in a real browser BEFORE any dead verdict; most 0-yields are stale parsers chasing an updated site layout (VidFast was exactly this: alive and playing while our parser saw nothing). Only a site that is truly gone (DNS dead / service shut down) gets retired.
- Build gates unchanged: `flutter analyze --no-pub` → "No issues found!"; full suite green; artifact freshness via `artifacts/audit-dsh/scripts/verify_release_artifacts.py`.
- Windows build needs `TORRSERVER_FLUTTER_LOCAL_BINARIES` exported (see `project-release-build-recipe` memory).

---

# MILESTONE 1 — First success playback: VidFast, ad-free, in-app (owner-verified)

Success = owner taps a movie/series → VidFast embed opens in-app → zero ad requests (engine log proves it) → m3u8 hands off to mpv → plays, seeks, fails over normally. If the webview fingerprint check blocks playback, fall back to in-webview playback (still ad-free) and log the handoff failure.

### Task 1: Rust toolchain + bridge scaffold

**Files:**
- Create: `rust/dizzy_adblock/Cargo.toml`, `rust/dizzy_adblock/src/api.rs`, `rust/dizzy_adblock/src/lib.rs`
- Modify: `pubspec.yaml` (add `flutter_rust_bridge: ^2.9.0`), `lib/main.dart` (bridge init), `android/app/build.gradle` (jniLibs srcDirs for `rust/target/cargo-ndk output`), `windows/CMakeLists.txt` (copy cdylib)

**Interfaces:**
- Produces: Rust functions visible to Dart via flutter_rust_bridge codegen:
  `RustOpaque<DizzyEngine> newEngine(List<String> rules)` and `bool engineMatch(DizzyEngine e, String url, String sourceHost, String resourceType)`. Dart import: `package:dizzy/rust/api.dart` (codegen output lives in `lib/rust/`).

- [ ] **Step 1: Install rustup (no admin needed — user-local)**

Run: `curl -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable` (Windows: `winget install Rustlang.Rustup` or the rustup-init.exe user install), then `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android`.
Expected: `cargo --version` works in a fresh shell; MSVC linker comes from the existing VS C++ toolchain (Flutter Windows builds already use it).

- [ ] **Step 2: Scaffold the crate**

`rust/dizzy_adblock/Cargo.toml`:
```toml
[package]
name = "dizzy_adblock"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "staticlib", "rlib"]

[dependencies]
adblock = "0.8"
flutter_rust_bridge = "=2.9.0"

[profile.release]
lto = true
strip = true
```

`rust/dizzy_adblock/src/lib.rs`:
```rust
pub mod api;
```

- [ ] **Step 3: Verify a Windows cdylib builds**

Run: `cd rust/dizzy_adblock && cargo build --release`
Expected: `target/release/dizzy_adblock.dll` exists. If linking fails on `C:` disk pressure (<5 GB free), STOP and report to the owner before freeing anything.

- [ ] **Step 4: flutter_rust_bridge codegen + Dart wiring**

Run: `flutter_rust_bridge_codegen generate --rust-input rust/dizzy_adblock/src/api.rs --rust-output-dir lib/rust --dart-output-dir lib/rust --class-name-filter Dizzy*`
Add to `pubspec.yaml`: `flutter_rust_bridge: ^2.9.0`. Init the bridge once at app startup (`RustLib.init()`) inside a guarded `try/catch` so the app still boots if the native lib is missing (webview sources then fail over like dead ones — never crash the app).

- [ ] **Step 5: Android NDK build**

Run: `cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o ../../android/app/src/main/jniLibs build --release`
Expected: three `libdizzy_adblock.so` files under `android/app/src/main/jniLibs/`.

- [ ] **Step 6: Owner checkpoint — commit scaffold**

Owner-approved commit: `feat(adblock): scaffold dizzy_adblock rust crate + flutter_rust_bridge wiring`.

### Task 2: DizzyEngine — the adblock match API

**Files:**
- Modify: `rust/dizzy_adblock/src/api.rs`
- Test: `rust/dizzy_adblock/tests/match_test.rs`

**Interfaces:**
- Produces: `pub struct DizzyEngine(Engine)` with `DizzyEngine::from_rules(rules: Vec<String>)` and `fn match_request(&self, url: &str, source_host: &str, resource_type: &str) -> bool` (true = block). Dart side sees `newEngine(rules)` / `engineMatch(...)` from Task 1 codegen.

- [ ] **Step 1: Write the failing Rust test**

`rust/dizzy_adblock/tests/match_test.rs`:
```rust
use dizzy_adblock::api::DizzyEngine;

const RULES: &str = "\
||vinnyvower.cfd^\n\
||contain.remanpurflertawneys.cyou^\n\
||googletagmanager.com^$third-party\n\
@@||vidfast.vc^$document\n";

#[test]
fn blocks_known_ad_hosts() {
    let e = DizzyEngine::from_rules(RULES.lines().map(String::from).collect());
    assert!(e.match_request(
        "https://vinnyvower.cfd/cuid/?f=https%3A%2F%2Fvidfast.vc",
        "vidfast.vc",
        "xmlhttprequest",
    ));
    assert!(e.match_request(
        "https://contain.remanpurflertawneys.cyou/gd/137978?md=abc",
        "vidfast.vc",
        "xmlhttprequest",
    ));
}

#[test]
fn allows_media_and_site_traffic() {
    let e = DizzyEngine::from_rules(RULES.lines().map(String::from).collect());
    assert!(!e.match_request("https://vidfast.vc/movie/550", "vidfast.vc", "document"));
    // A CDN m3u8 from a random media host must never be blocked.
    assert!(!e.match_request(
        "https://some-cdn.example.net/hls/550/index.m3u8",
        "vidfast.vc",
        "xhr",
    ));
}
```

- [ ] **Step 2: Run test, watch it fail**

Run: `cd rust/dizzy_adblock && cargo test`
Expected: FAIL (DizzyEngine not defined).

- [ ] **Step 3: Implement with adblock-rust**

`rust/dizzy_adblock/src/api.rs`:
```rust
use adblock::engine::Engine;
use adblock::lists::ParseOptions;
use adblock::request::Request;
use std::collections::HashSet;

pub struct DizzyEngine {
    engine: Engine,
}

impl DizzyEngine {
    pub fn from_rules(rules: Vec<String>) -> Self {
        let mut set = adblock::lists::FilterSet::default();
        for r in rules {
            set.add_filter(r);
        }
        let engine = Engine::from_filter_set(set, true);
        Self { engine }
    }

    pub fn match_request(&self, url: &str, source_host: &str, resource_type: &str) -> bool {
        let req = match Request::new(url, source_host, resource_type) {
            Ok(r) => r,
            Err(_) => return false,
        };
        self.engine.check_network_request(&req)
    }
}
```
(If `Engine::from_filter_set(set, true)` / `FilterSet::add_filter` differ in the installed 0.8.x, follow that crate's docs — the observable API above stays identical. `ParseOptions` import is only needed if the strictness flag requires it; delete if unused.)

- [ ] **Step 4: Run test, watch it pass**

Run: `cd rust/dizzy_adblock && cargo test`
Expected: both tests PASS.

- [ ] **Step 5: Regenerate Dart bridge + smoke it from a Dart test**

Run: `flutter_rust_bridge_codegen generate ...` (same args as Task 1), then a `test/` smoke test that builds `DizzyEngine` from 4 rules and asserts the same two outcomes. Run: `flutter test test/adblock_engine_test.dart` (skip-marker the test `@Skip('needs native lib')`-style only if the lib is absent on the runner — CI must stay green).

### Task 3: FilterListService — fetch, cache, refresh the open-source lists

**Files:**
- Create: `lib/services/adblock/filter_list_service.dart`
- Create: `assets/adblock/dizzy_supplemental.txt` (shipped rules below)
- Test: `test/filter_list_service_test.dart`

**Interfaces:**
- Consumes: nothing network-y in tests (HTTP injected).
- Produces: `class FilterListService` with
  `static Future<List<String>> loadRules({http.Client? client})` — returns merged lines from cached EasyList + uBlock + supplemental, refreshing any cache older than 7 days; and `static const supplementalAssetPath = 'assets/adblock/dizzy_supplemental.txt'`.

- [ ] **Step 1: Write the failing test**

```dart
test('merges cached lists + supplemental and skips stale refresh on error', () async {
  final dir = await ApplicationPaths.temporary; // project's existing temp dir helper
  File(p.join(dir.path, 'easylist.txt')).writeAsStringSync('||ads.example^\n');
  File(p.join(dir.path, 'ublock.txt')).writeAsStringSync('||track.example^\n');
  final rules = await FilterListService.loadRules(client: _FailingClient());
  expect(rules, contains('||ads.example^'));
  expect(rules, contains('||track.example^'));
  expect(rules, contains('||vinnyvower.cfd^')); // from supplemental asset
});
```

- [ ] **Step 2: Run to verify it fails** (`flutter test test/filter_list_service_test.dart`)

- [ ] **Step 3: Implement**

```dart
class FilterListService {
  static const _easylistUrl = 'https://easylist.to/easylist/easylist.txt';
  static const _ublockUrl =
      'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt';
  static const supplementalAssetPath = 'assets/adblock/dizzy_supplemental.txt';
  static const _refreshAfter = Duration(days: 7);

  static Future<List<String>> loadRules({http.Client? client}) async {
    final rules = <String>{};
    rules.addAll(await _listFromCacheOrNet(
      name: 'easylist.txt', url: _easylistUrl, client: client));
    rules.addAll(await _listFromCacheOrNet(
      name: 'ublock.txt', url: _ublockUrl, client: client));
    rules.addAll(await _supplemental());
    return rules.where((r) => r.isNotEmpty && !r.startsWith('!')).toList();
  }
  // _listFromCacheOrNet: read cache if fresher than _refreshAfter, else GET
  // (10 s timeout); on network error with stale cache, keep the stale cache.
  // _supplemental: rootBundle.loadString(supplementalAssetPath), split lines.
}
```

`assets/adblock/dizzy_supplemental.txt` (observed live on vidfast 2026-11-16, see `artifacts/audit-dsh/vidfast/`):
```
! Dizzy supplemental — measured on vidfast.vc 2026-11-16
||vinnyvower.cfd^
||contain.remanpurflertawneys.cyou^
||lpxu3ovf7r.fipjmbp8j2l9lf9he8e6y9oukzfg.cfd^
googletagmanager.com$third-party
google-analytics.com$third-party
umami.vidfast.vc^
cloudflareinsights.com$third-party
flagsapi.com$third-party
```

- [ ] **Step 4: Verify green + register the asset** in `pubspec.yaml` (`assets: [assets/adblock/]`), run full analyzer.

- [ ] **Step 5: Owner checkpoint — commit** `feat(adblock): filter list service + supplemental measured rules`.

### Task 4: VidFast scraper rewrite → embed source

**Files:**
- Modify: `lib/services/scraper/sites/vidfast.dart` (full rewrite, ~70 lines)
- Test: `test/vidfast_embed_scraper_test.dart`

**Interfaces:**
- Consumes: `TmdbHelper.resolveTmdbId` (existing), `StreamSource` (existing; uses `externalUrl` + `behaviorHints`).
- Produces: `VidFastScraper` yields exactly one `StreamSource` per title with
  `externalUrl = 'https://vidfast.vc/movie/{tmdbId}?autoPlay=true'` or `'https://vidfast.vc/tv/{tmdbId}/{s}/{e}?autoPlay=true'`,
  `url = null`, `behaviorHints['dizzyEmbed'] = true`, `name/addonName = 'vidfast'`, `title = 'VidFast · Embed'`. Falls back to the IMDb id DIRECTLY when `imdbId` is present and TMDB resolution fails (the site accepts IMDb ids).

- [ ] **Step 1: Write the failing test**

```dart
test('yields embed source with tmdb id', () async {
  final s = VidFastScraper();
  final out = await s.scrape(
    type: 'movie', title: 'Fight Club', year: 1999, imdbId: 'tt0137523',
  ).then((l) => l.toList());
  expect(out, hasLength(1));
  expect(out.single.externalUrl, 'https://vidfast.vc/movie/550?autoPlay=true');
  expect(out.single.behaviorHints?['dizzyEmbed'], true);
  expect(out.single.url, isNull);
});

test('tv embed carries season/episode', () async {
  final out = await VidFastScraper().scrape(
    type: 'series', title: 'Game of Thrones', imdbId: 'tt0944947',
    season: 1, episode: 3,
  ).then((l) => l.toList());
  expect(out.single.externalUrl, contains('/tv/1399/1/3?autoPlay=true'));
});
```
(TMDB stub: the existing `TmdbHelper` test seam — follow how `test/playback_source_selection_test.dart` stubs network dependencies; if TmdbHelper has no injectable client, resolve via the real cached helper only in live-probe tests and use the IMDb-direct path for the unit test.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/vidfast_embed_scraper_test.dart`
Expected: FAIL (old scraper still enc-dec based / yields nothing).

- [ ] **Step 3: Rewrite the scraper**

```dart
class VidFastScraper extends StreamScraper {
  @override
  String get name => 'vidfast';
  @override
  bool get indexesNewReleases => true; // embed resolves any TMDB id instantly

  @override
  Stream<StreamSource> scrapeStream({
    required String type, required String title,
    int? year, int? season, int? episode, String? imdbId,
  }) async* {
    final isTv = (type == 'tv' || type == 'series');
    // The site accepts IMDb OR TMDB ids; prefer TMDB, fall back to IMDb.
    final id = await TmdbHelper.resolveTmdbId(
          imdbId: imdbId, title: title, type: isTv ? 'tv' : 'movie', year: year,
        ) ?? imdbId;
    if (id == null || id.isEmpty) return;
    final embed = isTv
        ? 'https://vidfast.vc/tv/$id/${season ?? 1}/${episode ?? 1}?autoPlay=true'
        : 'https://vidfast.vc/movie/$id?autoPlay=true';
    yield StreamSource(
      name: 'VidFast', addonName: 'vidfast',
      title: 'VidFast · Embed', description: 'VidFast embed player',
      externalUrl: embed, url: null,
      behaviorHints: {'dizzyEmbed': true},
    );
  }
}
```

- [ ] **Step 4: Verify green + analyzer + full suite** (scraper registration unchanged — it was never retired).

- [ ] **Step 5: Owner checkpoint — commit** `feat(scraper): vidfast via official embed, enc-dec chain removed`.

### Task 5: EmbedWebviewPlayer — adblocked webview surface + mpv handoff

**Files:**
- Create: `lib/pages/player/embed_webview_player.dart`
- Modify: `pubspec.yaml` (`flutter_inappwebview: ^6.1.5`), `lib/models/stream/stream_model.dart` (nothing if behaviorHints key is enough — prefer NO new field)
- Test: `test/embed_adblock_decision_test.dart` (pure part), `test/vidfast_embed_scraper_test.dart` (already covers source shape)

**Interfaces:**
- Consumes: `DizzyEngine` (Task 2), `FilterListService.loadRules()` (Task 3), `StreamSource` with `behaviorHints['dizzyEmbed']`.
- Produces: `EmbedWebviewPlayer(source, onMediaCaptured: (CapturedMedia m) -> void, onGiveUp: () -> void)` where `class CapturedMedia { final String url; final Map<String,String> headers; }`. Blocking decision is a pure static for testability:
  `static bool shouldBlock(DizzyEngine engine, String url, String pageHost, String type)`.

- [ ] **Step 1: Write the failing decision test**

```dart
test('blocks ads/trackers, allows site + media', () {
  final engine = newEngine(sampleRules); // 4-rule sample from Task 2
  expect(EmbedWebviewPlayer.shouldBlock(
      engine, 'https://vinnyvower.cfd/x', 'vidfast.vc', 'xmlhttprequest'), true);
  expect(EmbedWebviewPlayer.shouldBlock(
      engine, 'https://cdn.example/hls/i.m3u8', 'vidfast.vc', 'xhr'), false);
  expect(EmbedWebviewPlayer.shouldBlock(
      engine, 'https://vidfast.vc/movie/550', 'vidfast.vc', 'document'), false);
});
```

- [ ] **Step 2: Verify fail → implement the widget**

```dart
class EmbedWebviewPlayer extends StatefulWidget { ... }
class _EmbedWebviewPlayerState extends State<EmbedWebviewPlayer> {
  DizzyEngine? _engine;
  static const _mediaTypes = ['.m3u8', '.mp4', '.mkv', '/hls/'];

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final rules = await FilterListService.loadRules();
    _engine = newEngine(rules);
    if (mounted) setState(() {});
  }

  bool shouldBlock(DizzyEngine engine, String url, String pageHost, String type) =>
      engineMatch(engine, url, pageHost, type);

  // flutter_inappwebview settings: useShouldInterceptRequest = true.
  // In the interception callback:
  //   1. shouldBlock(engine, url, sourceHost, resourceType) → return the
  //      empty WebResourceResponse (blocked) and count it in _blockedCount.
  //   2. else if url ends with a _mediaTypes entry and host != vidfast.vc →
  //      capture CapturedMedia(url, {'Referer': 'https://vidfast.vc/'})
  //      → widget.onMediaCaptured(m) ONCE (guard with _captured flag).
  //   3. else → null (allow).
  // Fallback timer: if no media captured within 30 s, stay in webview
  // (playback continues inside) and log; user keeps an ad-free player.
}
```

- [ ] **Step 3: Verify green + analyzer.**

- [ ] **Step 4: Owner checkpoint — commit** `feat(player): adblocked embed webview surface`.

### Task 6: Player wiring + health/ranker integration

**Files:**
- Modify: `lib/pages/player/player_screen.dart` (open path) and `lib/pages/player/player_screen_part_playback.dart` (the `_initStream` entry — route embed sources)
- Modify: `lib/services/stream/stream_health_checker.dart` (skip probe for embeds), `lib/services/stream/source_ranker.dart` (tier: verified-direct > embed-webview > torrents)
- Test: `test/playback_source_selection_test.dart` (extend)

**Interfaces:**
- Consumes: `behaviorHints['dizzyEmbed']`, `EmbedWebviewPlayer`, existing `InstantPlayGate`/failover (`kTryingNextSourceMessage` unchanged).
- Produces: `static bool isEmbedSource(StreamSource s) => s.behaviorHints?['dizzyEmbed'] == true;` (put it on `StreamSource` as a getter `bool get isEmbedSource`).

- [ ] **Step 1: Write failing tests** — (a) health checker: an embed source returns alive WITHOUT any network call; (b) ranker: embed sources sort after verified direct HTTP, before torrents.

```dart
test('embed sources are alive without probing', () async {
  final s = StreamSource(name: 'VidFast', addonName: 'vidfast')
    ..externalUrl = 'https://vidfast.vc/movie/550'
    ..behaviorHints = {'dizzyEmbed': true};
  final alive = await StreamHealthChecker.isAlive(s);
  expect(alive, true);
  expect(s.probeDead, false);
});

test('ranker: direct first, embed second, torrent last', () {
  final ctx = RankerContext(/* existing fixture */);
  final chain = SourceRanker.buildFailoverChain([torrent, embed, direct], ctx);
  expect(chain.indexOf(direct), lessThan(chain.indexOf(embed)));
  expect(chain.indexOf(embed), lessThan(chain.indexOf(torrent)));
});
```

- [ ] **Step 2: Verify fail → implement:**
  - `StreamSource.isEmbedSource` getter; health checker returns `true` early for embeds (no probe — the webview is the probe).
  - Ranker: embed tier between `alive` and `torrents` in `buildFailoverChain`.
  - Player: in `_initStream`, if `_currentSource.isEmbedSource` → show `EmbedWebviewPlayer(source, onMediaCaptured: (m) { /* stop webview, set headers, open mpv with m.url — reuses the existing atomic open path */ }, onGiveUp: () => _requestFailover('embed gave up'))`; mpv open uses `headers: {'Referer': 'https://vidfast.vc/', 'User-Agent': <existing UA>}`.

- [ ] **Step 3: Full suite + analyzer green.**

- [ ] **Step 4: Build + install on emulator, owner tests (M1 GATE):**
  `flutter build apk --release` → install on `dizzy_test` AVD (existing recipe) → owner plays Fight Club (movie) and one series episode:
  - [ ] plays from VidFast embed
  - [ ] no ad redirect/popup (engine block-count logged in logcat)
  - [ ] mpv handoff happens (logcat shows the captured m3u8)
  - [ ] seek/quality/failover UX unchanged
  - [ ] Windows exe: same flow via WebView2 (may be M2 — Android first)
  - [ ] eval row updated in `docs/superpowers/evals/2026-11-12-dizzy-eval.md`
  - [ ] Owner checkpoint — commit `feat(player): vidfast embed playback end-to-end (M1)`.

---

# MILESTONE 2 — All sources + torrent engine

### Task 7: Liveness audit of every active scraper (evidence first)

**Files:**
- Reuse: `test/live_probe_bulk_test.dart` harness patterns, `artifacts/audit/bulk_probe.log`
- Create: `artifacts/audit-dsh/scraper_audit_2026-11.md` (the verdict table)

- [ ] **Step 1: Live-probe the 13 active HTTP scrapers + Knaben over a fixed corpus (10 new + 10 old mainstream titles — Odia/regional titles are EXCLUDED from this plan's corpus and metrics entirely; they get their own scraper and plan later).**
- [ ] **Step 2: For every 0-yield site, verify the site itself in a real browser first** (does vidfast-style playback work there today?). A 0-yield against a live site = PARSER-BROKEN, not dead.
- [ ] **Step 3: Record verdict per site:** ALIVE-direct (yields byte-verified media), EMBED-PORTABLE (site offers a documented embed), PARSER-BROKEN (site alive, our code stale → repair), TRULY-DEAD (site gone: DNS dead or service shut). Known going in: lmscript/vidlink/a111477 alive; vadapav/vidapi unverified against their live sites.
- [ ] **Step 4: Owner reviews the verdict table (this decides repair-vs-port-vs-retire, no agent discretion).**

### Task 8: Port embed-portable sites to the webview pattern

**Files (expected, per audit):** `lib/services/scraper/sites/vidlink.dart`, `vidup.dart`, `kisskh.dart`, `meowtv.dart` — same shape as Task 4 (each becomes an externalUrl embed source with `dizzyEmbed`); their enc-dec chains get deleted. Sites already yielding direct URLs (lmscript, a111477, rivestream) stay parser-based untouched.

- [ ] Per site: failing test (embed URL shape) → rewrite → green → retire its enc-dec usage.
- [ ] One shared engine, one list cache — nothing per-site except the embed URL template and a supplemental rule line if the site has its own ad domains (add to `dizzy_supplemental.txt` with a dated comment).

### Task 9: Repair parser-broken sites, retire only the truly dead

**Files:** `lib/services/scraper/sites/<parser-broken>.dart`, `lib/services/stream/stream_service.dart` (`retiredScrapers` set)

- [ ] **PARSER-BROKEN sites get repaired, not retired:** re-read the live site's current flow (the Task 4 method: fetch page, inspect JS/API shape, follow the real request chain) and update the parser with a failing-test-first cycle. The "0 sources in bulk probe" history was recorded against stale parsers — VidFast proved sites can be alive while our code sees nothing.
- [ ] **Only TRULY-DEAD verdicts** (browser-verified gone) move into `retiredScrapers` with the audit doc as evidence; remove enc-dec imports that no longer have consumers (`hexa.dart` decision follows the audit).
- [ ] Full suite green (no test references removed scrapers).

### Task 10: Torrent engine hardening

**Files:** `lib/services/stream/torrent_stream_service.dart`, `torrent_warmup_policy.dart`, `lib/utils/torrent/torrent_trackers.dart`, `lib/services/scraper/sites/knaben.dart`

- [ ] Verify Knaben core-title matching on 10 regional titles (the `TitleCoreMatch` path) — add fixtures for any miss.
- [ ] Refresh the tracker list (announce endpoints rotate; re-run the tracker health snippet, keep the top ~15).
- [ ] Confirm warm-up gate + stall watchdog behavior on a cold torrent end-to-end on the emulator (owner test, per existing division).
- [ ] Controlled P2P usage guard rails from the private-engine plan Phase 0b (seed window / metered no-seed) — implement ONLY the flags, not the full phase.

### Task 11: Supabase deploys (owner-acked)

- [ ] `supabase functions deploy resolve` (IMDb+OMDb fallback), `catalog`, `tmdb-proxy` (owner reviews allowlist change), corpus-sync migrations `20261114`/`20261115` via `db query -f` + history INSERT, `migration repair --status applied 20261113`, `OMDB_API_KEY` secret. Each step is a separate owner-approved command.

---

# MILESTONE 3 — Release v1.3.5

### Task 12: Release gates

- [ ] `flutter analyze --no-pub` → No issues found!
- [ ] `flutter test --no-pub` full suite green (exclude bulk live probes)
- [ ] `cargo test` (rust crate) green; NDK libs rebuilt fresh
- [ ] Rebuild artifacts per recipe (Windows + 4 APKs, TorrServer payload verified) → `ALL_ARTIFACTS_FRESH`
- [ ] Eval re-scored with owner device rows
- [ ] `RELEASE_CHECKLIST.md` + CHANGELOG v1.3.5 entries (embed playback, adblock engine, retired scrapers, torrent hardening)
- [ ] Owner approves final commit + tag `v1.3.5`

## Verification gates (every task)

`flutter analyze --no-pub` clean → touched-area tests green → full suite green at task end → owner-gated commit. No "should work": every claim carries the command output that proves it.

## Open items (tracked, not blockers for M1)

- **Odia/regional movies are OUT OF SCOPE for v1.3.5 entirely** — they need their own scraper and a separate plan (owner decision 2026-11-16); this plan's corpus, audit, and success metrics exclude them by definition.
- WebView2 runtime presence on end-user Windows machines (WebView2 ships with Win11/Edge; Win10 may need the Evergreen runtime — check and document in RELEASE_CHECKLIST).
- VidFast fingerprint check inside Android WebView — first thing M1's device test proves.
- Windows WebView2 handoff may land in M2 if the Android path needs iteration first.
