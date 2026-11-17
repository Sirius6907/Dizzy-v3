# Dizzy private add-on engine — implementation plan (2026-11-14)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the public Stremio add-ons with Dizzy's own provider + catalog + resolver engine (hybrid: edge resolver + in-app scrapers), keeping IMDb/TMDB ids, with a private torrent-to-HTTP tier that Dizzy owns.

**Architecture:** A new edge function `dizzy-resolver` (Supabase, owner-controlled) serves a Stremio-shaped manifest/catalog/meta/stream API and owns ranking, dedupe, provider health and catalog freshness. The app keeps a local tier: our own HTTP provider parsers and torrent indexers run on the device (user's own IP), so provider IP-lock is not a problem. The player consumes the same `StreamSource` contract it consumes today; torrents are played through a `TorrentEngine` interface whose default implementation is the already-bundled TorrServer sidecar.

**Tech stack:** Flutter/Dart, Supabase Edge Functions (Deno), Postgres, `http`/`DizzyNet`, media_kit + `torrserver_flutter`, Stremio add-on protocol.

**Spec:** `docs/superpowers/specs/2026-11-14-dizzy-private-addon-engine-design.md`

## Global Constraints

- Never call `POST https://api.strem.io/api/addonPublish`; never submit to stremio-addons.net. The engine is private to Dizzy.
- No git commit, push, tag, release or deploy without the owner's explicit go-ahead. If a task ends with a commit step, stop and ask first.
- No Supabase schema/permission change without the owner's explicit approval; apply migrations with `supabase db query --linked -f <file>` and record the history row manually (never `db push --include-all`).
- Catalog ids stay IMDb (`tt…`) / TMDB (`tmdb:`). Do not mint a new id space in this plan.
- Exactly two themes (Light Clay / Dark Clay); use semantic palette tokens, no raw `Colors.white/black` in new UI.
- Secrets only in the gitignored `.env`; never print keys, signed stream URLs or tokens.
- Never `adb uninstall` / `adb shell pm clear`; install with `adb install -r`.
- No hardcoded provider/track lists in Dart: providers live in the registry (edge `remote_config` / table), titles live in the catalog tables.
- Every new behaviour needs a failing test first (TDD), and every fix needs a regression test.
- Do not repeat long device interaction loops: the owner runs manual UI/UX verification.

---

## File Structure

**New — edge (`supabase/functions/dizzy-resolver/`)**
- `index.ts` — HTTP entry: `manifest.json`, `catalog`, `meta`, `stream`, `health`.
- `providers.ts` — provider registry loader (from `remote_config` + table).
- `rank.ts` — one ranking function (resolution, codec, seeders, provider health, India relevance).
- `dedupe.ts` — dedupe by infohash, URL, filename fingerprint.
- `catalog_store.ts` — read/write of `dizzy_catalog` rows.

**New — app (`lib/services/engine/`)**
- `provider_registry.dart` — typed registry + `ProviderSpec` (id, site, parser id, capabilities, enabled).
- `provider_health.dart` — success/timeout/yield counters with decay, persisted locally, synced to the edge.
- `edge_resolver_client.dart` — calls the edge resolver; TTL + LRU cache; soft-fails.
- `in_app_provider_scraper.dart` — runs our HTTP provider parsers from the device IP.
- `dizzy_torrent_indexer.dart` — our torrent indexers behind one interface (magnet, infohash, trackers, size, seeders).
- `torrent_engine.dart` — `TorrentEngine` interface + `TorrServerEngine` implementation.
- `catalog_service_v2.dart` — reads our catalog rows, keeps IMDb/TMDB ids.

**New — controlled P2P usage (Phase 0b)**
- `lib/services/stream/torrent_usage_policy.dart` — pure policy → `TorrentUsageProfile`.
- `lib/services/stream/torrserver_settings_builder.dart` — profile → TorrServer `BTSets` JSON.
- `lib/services/stream/torrent_seeding_governor.dart` — bounded seed window, byte cap, torrent removal.
- `lib/services/net/network_state_service.dart` — Dart side of the Android sensing channel.
- `android/app/src/main/kotlin/<package>/DizzyNetworkChannel.kt` — metered / uplink / charging state.

**New — data**
- `supabase/migrations/20261115_dizzy_catalog.sql` — `dizzy_catalog`, `dizzy_providers`, `dizzy_provider_health` tables + RLS + admin RPCs.
- `supabase/functions/catalog-ingest/index.ts` — scheduled ingestion of regional catalogs (TMDB discover per language).
- `artifacts/audit-dsh/scripts/verify_catalog_seed.py` — already written: verifies a seed title list against TMDB through the edge.

**Modified**
- `lib/services/addon/addon_manager.dart:28-32` — stop force-installing public stream add-ons; install `builtin:dizzyown`.
- `lib/services/scraper/stream_scraper.dart:9` — add the provider-introspection contract to `StreamScraper`.
- `lib/services/scraper/stream_scraper.dart:100` — `ScraperManager` consumes the registry + health.
- `lib/services/stream/torrent_stream_service.dart:51` — implement `TorrServerEngine` behind `TorrentEngine`.
- `lib/pages/player/player_screen_part_stream.dart:113` — call `TorrentEngine`, not the singleton directly.
- `lib/services/metadata/metadata_service.dart:77` — serve our catalog first, Cinemeta as fallback.
- `supabase/functions/tmdb-proxy/index.ts:13` — allow `/discover/movie` and `/discover/tv`.

---

## Phase 0 — Torrent engine spike (decides A vs B vs C)

- [ ] **Step 1: Write the spike script** — `artifacts/audit-dsh/scripts/torrent_engine_spike.dart` resolves five known-failing titles ("Blinding Lights", "Krishna Trance", "Paani Waala Dance", "Bara Badhu", "Madhumallati") through `YoutubeStreamResolver` + `TorrentStreamService` and writes, per title: candidate count, infohash, tracker count, TorrServer metadata-wait seconds, first-byte seconds, peak bytes, and whether mpv produced audio output. It must print the magnet **without** the `dn=`/`xt=` payload beyond the infohash, and never print trackers.

- [ ] **Step 2: Run the spike on the device** — `flutter run -d emulator-5554` is not needed; run the script through a `flutter test` that talks to the real device? No: the spike must run inside the app, so instead build the spike as a **debug-only screen route** `/dev/torrent-spike` behind `kDebugMode`, then:
  ```bash
  /c/tools/platform-tools/adb.exe -s emulator-5554 shell am start -n com.sirius6907.dizzyv3/.MainActivity
  ```
  and navigate to it. Record the numbers in `artifacts/audit-dsh/torrent-spike.md`.

- [ ] **Step 3: Decide the engine from the numbers**
  - TorrServer resolves ≥1 candidate with audio for ≥4 of 5 titles → **Option A** (keep TorrServer).
  - TorrServer resolves but frequently hits "no peers / 0 seeders" → **Option A + Option C** (our indexers + a debrid fallback tier).
  - TorrServer cannot start or cannot serve bytes on Android → **Option B** spike (libtorrent FFI) before any code lands.
  Write the decision + numbers into `artifacts/audit-dsh/torrent-spike.md` and append a short section to the spec. **Do not proceed past Phase 0 without the owner's confirmation of the chosen engine.**

---

## Phase 0b — Controlled P2P usage (Option A usage contract)

Owner chose **Option A** (keep TorrServer). This phase makes the seeder a
*budgeted* citizen: playback first, seeding in a bounded window, metered and
background devices never seed, and the household IP carries as little
BitTorrent traffic as possible.

Design basis: spec section "Controlled P2P usage". Facts that constrain the
implementation: `BTSets` is global and **any change drops all torrents and
restarts the BT client**; `addTorrent` has no per-torrent limits; the HTTP
stream path is unthrottled; the proxy is CLI-only; Android bandwidth numbers
are first-hop estimates.

- [ ] **Step 1: Write the failing policy test** — `test/torrent_usage_policy_test.dart`:
  ```dart
  test('a metered network never seeds', () {
    final profile = TorrentUsagePolicy.profileFor(
      metered: true, charging: false, playbackActive: true,
      uplinkKbps: 2000, proxyConfigured: false,
    );
    expect(profile.allowSeeding, isFalse);
  });

  test('upload stays a small fraction of the measured uplink', () {
    final profile = TorrentUsagePolicy.profileFor(
      metered: false, charging: true, playbackActive: false,
      uplinkKbps: 1000, proxyConfigured: false,
    );
    expect(profile.uploadRateLimitKb, 150);
    expect(profile.connectionsLimit, 12);
  });

  test('an unknown uplink falls back to a conservative cap', () {
    final profile = TorrentUsagePolicy.profileFor(
      metered: false, charging: true, playbackActive: false,
      uplinkKbps: null, proxyConfigured: false,
    );
    expect(profile.uploadRateLimitKb, 64);
  });

  test('playback keeps the download lane unlimited', () {
    final profile = TorrentUsagePolicy.profileFor(
      metered: false, charging: false, playbackActive: true,
      uplinkKbps: 5000, proxyConfigured: false,
    );
    expect(profile.downloadRateLimitKb, 0);
  });
  ```

- [ ] **Step 2: Watch it fail** — `flutter test --no-pub test/torrent_usage_policy_test.dart` → FAIL (no `TorrentUsagePolicy`).

- [ ] **Step 3: Implement `lib/services/stream/torrent_usage_policy.dart`** — pure Dart, no I/O:
  ```dart
  class TorrentUsageProfile {
    const TorrentUsageProfile({
      required this.uploadRateLimitKb, required this.downloadRateLimitKb,
      required this.connectionsLimit, required this.seedWindowMinutes,
      required this.maxSeedBytes, required this.allowSeeding,
      required this.proxyPeers,
    });
    final int uploadRateLimitKb, downloadRateLimitKb, connectionsLimit;
    final int seedWindowMinutes, maxSeedBytes;
    final bool allowSeeding, proxyPeers;
  }

  abstract final class TorrentUsagePolicy {
    static TorrentUsageProfile profileFor({
      required bool metered, required bool charging, required bool playbackActive,
      required int? uplinkKbps, required bool proxyConfigured,
    }) {
      if (metered) {
        return const TorrentUsageProfile(
          uploadRateLimitKb: 0, downloadRateLimitKb: 0, connectionsLimit: 12,
          seedWindowMinutes: 0, maxSeedBytes: 0,
          allowSeeding: false, proxyPeers: false,
        );
      }
      final upload = playbackActive && !charging
          ? 32
          : ((uplinkKbps ?? 0) * 0.15).round().clamp(32, 512);
      return TorrentUsageProfile(
        uploadRateLimitKb: upload,
        downloadRateLimitKb: 0,
        connectionsLimit: 12,
        seedWindowMinutes: 10,
        maxSeedBytes: 256 * 1024 * 1024,
        allowSeeding: true,
        proxyPeers: proxyConfigured,
      );
    }
  }
  ```

- [ ] **Step 4: Write the failing settings-builder test** — `test/torrserver_settings_builder_test.dart`: the builder must emit the **exact** `BTSets` field names (Go struct names, no json tags):
  ```dart
  test('settings payload uses the exact BTSets field names', () {
    final payload = TorrServerSettingsBuilder.build(
      const TorrentUsageProfile(
        uploadRateLimitKb: 150, downloadRateLimitKb: 0, connectionsLimit: 12,
        seedWindowMinutes: 10, maxSeedBytes: 268435456,
        allowSeeding: true, proxyPeers: false,
      ),
    );
    expect(payload['UploadRateLimit'], 150);
    expect(payload['DownloadRateLimit'], 0);
    expect(payload['ConnectionsLimit'], 12);
    expect(payload['DisableDHT'], isTrue);
    expect(payload['DisablePEX'], isTrue);
    expect(payload['EnableLPD'], isFalse);
    expect(payload['DisableUPNP'], isTrue);
    expect(payload['ForceEncrypt'], isTrue);
    expect(payload['CacheSize'], 64);
    expect(payload['UseDisk'], isFalse);
    expect(payload['PreloadCache'], isTrue);
    expect(payload['ReaderReadAHead'], 80);
    expect(payload['ResponsiveMode'], isTrue);
    expect(payload['TorrentDisconnectTimeout'], 120);
  });
  ```

- [ ] **Step 5: Watch it fail, then implement `lib/services/stream/torrserver_settings_builder.dart`** — `static Map<String, Object> build(TorrentUsageProfile profile)` returning exactly the keys above (plus `DisableUpload: !profile.allowSeeding`). Field names come from https://github.com/YouROK/TorrServer/blob/master/server/settings/btsets.go.

- [ ] **Step 6: Add the Android sensing channel** — `android/app/src/main/kotlin/.../DizzyNetworkChannel.kt` (new file, package path per the existing MainActivity) exposing `MethodChannel('dizzy/network')` with method `getNetworkState` returning
  `{metered: bool, uplinkKbps: int, downlinkKbps: int, charging: bool}`
  from `ConnectivityManager.getLinkProperties` / `NetworkCapabilities`
  (https://developer.android.com/reference/android/net/ConnectivityManager ,
  https://developer.android.com/reference/android/net/NetworkCapabilities) and
  `BatteryManager`/sticky `ACTION_BATTERY_CHANGED` for charging.
  Register it in `MainActivity.configureFlutterEngine`.
  Dart side: `lib/services/net/network_state_service.dart` — `MethodChannel('dizzy/network')`, `Future<NetworkState> current()` returning `metered`, `uplinkKbps`, `downlinkKbps`, `charging`, and failing soft (all-false/0) when the channel is missing (desktop build).

- [ ] **Step 7: Apply the profile exactly once per session** — in `lib/services/stream/torrent_stream_service.dart:103` (sidecar start), when `TorrServerSettingsBuilder` is available, call `POST /settings {action:"set", sets:{…}}` **before** any torrent is added, and persist the applied profile so it is never re-applied mid-session (re-applying drops torrents and restarts the BT client).
  Add `TorrentSettingsApplier.applyOnce(profile)` with a persisted flag in SharedPreferences.

- [ ] **Step 8: Seed window governor** — `lib/services/stream/torrent_seeding_governor.dart`:
  - Starts a window when playback of a torrent ends: keep the torrent alive for `seedWindowMinutes`, stop uploading when the window closes or `maxSeedBytes` is reached (read the uploaded bytes from TorrServer `torrents/info`), then **remove the torrent** from TorrServer so the IP stops appearing in the swarm.
  - Cancels the window immediately when the device becomes metered, the app goes to background for > 5 minutes, or a second torrent starts (one active torrent at a time).
  - Expose `Stream<TorrentUsageState>` so the player can show "Seeding for 6 more minutes (cap 64 kb/s)" and the UI can offer "Stop seeding now".

- [ ] **Step 9: Optional peer proxy** — when the user configures a SOCKS5/HTTP proxy for peers, start the sidecar with
  `extraArgs: ['-i','127.0.0.1','-proxy',proxy,'-proxy-mode','peers']`
  (TorrServer CLI flags, https://github.com/YouROK/TorrServer/blob/master/server/cmd/main.go).
  The proxy setting lives in the app's network settings; it is never enabled silently.

- [ ] **Step 10: Playback-lane protection** — keep `DownloadRateLimit = 0`; rely on `ReaderReadAHead` + `PreloadCache` + `ResponsiveMode` for start latency, and keep the existing `TorrentWarmupPolicy` (2 MB target / 14 s ceiling / hopeless detection) as the gate before playback starts.

- [ ] **Step 11: Verify** — `flutter test --no-pub test/torrent_usage_policy_test.dart test/torrserver_settings_builder_test.dart` PASS; `flutter analyze --no-pub` clean; on the emulator, play a torrent and confirm the log line "Seeding window: N min, cap X kb/s" appears and that the torrent is removed after the window.

- [ ] **Step 12: Report the honest limits** — add a "Controlled P2P usage" section to `docs/audit/2026-11-09-music-creator.md` stating: no knob prevents DPI detection
  (https://github.com/arvidn/libtorrent/issues/5222); "per-IP peer counts cause blocks" is unverified; Android bandwidth numbers are estimates; the global download cap cannot be separated from the playback lane; the strongest protection for the household IP is seeding from a VPS, which is a product decision for the owner.

---

## Phase 1 — `builtin:dizzyown`: our providers behind the existing contract

- [ ] **Step 1: Write the failing test** — `test/provider_registry_test.dart`:
  ```dart
  test('registry parses the provider spec list and honours the enabled flag', () {
    final registry = ProviderRegistry.fromJson(const {
      'providers': [
        {'id': 'dizzy_knaben', 'site': 'knaben', 'parser': 'knaben_json',
         'supports': ['movie', 'series'], 'enabled': true, 'priority': 10},
        {'id': 'dizzy_off', 'site': 'example', 'parser': 'html',
         'supports': ['movie'], 'enabled': false, 'priority': 1},
      ],
    });
    expect(registry.enabledIds, ['dizzy_knaben']);
    expect(registry.byId('dizzy_off')!.enabled, isFalse);
  });
  ```

- [ ] **Step 2: Run it and watch it fail** — `flutter test --no-pub test/provider_registry_test.dart` → FAIL (`ProviderRegistry` undefined).

- [ ] **Step 3: Implement `lib/services/engine/provider_registry.dart`** — `ProviderSpec{id, site, parser, supports, enabled, priority}`; `ProviderRegistry.fromJson(Map)`; `List<String> get enabledIds`; `ProviderSpec? byId(String)`; `ProviderRegistry fromRemoteConfig(String? json)`.

- [ ] **Step 4: Add the provider-introspection contract to `StreamScraper`** — in `lib/services/scraper/stream_scraper.dart:9` add:
  ```dart
  ProviderSpec describe() => ProviderSpec(
    id: 'builtin_$name', site: name, parser: 'legacy',
    supports: const ['movie', 'series'], enabled: true, priority: priority,
  );
  ```
  Existing scrapers then appear in the registry without being rewritten.

- [ ] **Step 5: Register our scrapers through the registry** — in `lib/services/scraper/stream_scraper.dart:111` (`_registerBuiltInScrapers`) keep the existing 47 registrations, but derive the registry list from `describe()` instead of a second hardcoded list.

- [ ] **Step 5b: Wire the two names so they are not confused** — `builtin:dizzyown` is the **in-app pseudo add-on** that `AddonManager` knows about; `com.dizzy.resolver` is the **edge function's protocol manifest** (Phase 3). Dizzy itself reaches the edge through `EdgeResolverClient` (Phase 4), not by fetching a manifest over the network. Keep the two ids distinct in code and in logs.

- [ ] **Step 6: Verify** — `flutter test --no-pub test/provider_registry_test.dart test/stream_scraper_test.dart` (or the closest existing scraper test) → PASS; `flutter analyze --no-pub` → "No issues found!".

- [ ] **Step 7: Stop for the owner's commit approval** (no commit without a go-ahead).

---

## Phase 2 — Provider health with numbers

- [ ] **Step 1: Write the failing test** — `test/provider_health_test.dart`:
  ```dart
  test('a failing provider is skipped until its score recovers', () {
    final health = ProviderHealthStore();
    health.record('dizzy_a', ProviderOutcome.success);
    health.record('dizzy_b', ProviderOutcome.timeout);
    expect(health.rankFor('dizzy_a'), greaterThan(health.rankFor('dizzy_b')));
    expect(health.shouldSkip('dizzy_b'), isTrue);
  });
  ```

- [ ] **Step 2: Watch it fail** — `flutter test --no-pub test/provider_health_test.dart` → FAIL.

- [ ] **Step 3: Implement `lib/services/engine/provider_health.dart`** — per-provider counters (success, timeout, error, yield) persisted in SharedPreferences, decayed over a 24 h window; `rankFor(id)` = weighted success ratio minus penalty; `shouldSkip(id)` = true when 3 consecutive failures or a decayed score below 0.2; `record(id, outcome)`.

- [ ] **Step 4: Wire it into `ScraperManager.scrapeAll`** (`lib/services/scraper/stream_scraper.dart:100`) — skip providers where `shouldSkip(id)`; record the outcome of each provider; keep the existing quarantine service as the second line of defence.

- [ ] **Step 5: Verify** — targeted test PASS + `flutter analyze --no-pub` clean.

---

## Phase 3 — Edge resolver (`dizzy-resolver`)

- [ ] **Step 1: Write the failing edge test** — `supabase/functions/dizzy-resolver/index_test.ts` (Deno test) asserts the manifest shape:
  ```ts
  Deno.test('manifest advertises our catalog and stream resources', async () => {
    const res = await handler(new Request('http://x/manifest.json'));
    const manifest = await res.json();
    expect(manifest.id).toBe('com.dizzy.resolver');
    expect(manifest.resources).toContain('catalog');
    expect(manifest.resources).toContain('stream');
    expect(manifest.idPrefixes).toContain('tt');
  });
  ```

- [ ] **Step 2: Watch it fail** — `deno test supabase/functions/dizzy-resolver/` → FAIL (module missing).

- [ ] **Step 3: Implement `index.ts`** — routes:
  - `GET /manifest.json` → `{id:'com.dizzy.resolver', version, name, description, resources:['catalog','meta','stream'], types:['movie','series'], idPrefixes:['tt','tmdb:'], catalogs:[{type:'movie',id:'dizzy_recent',name:'Dizzy Recent',extra:[{name:'genre',options:[...]}]}], behaviorHints:{p2p:true}}`
  - `GET /catalog/{type}/{id}.json` → `{metas:[…], hasMore}` from `dizzy_catalog`
  - `GET /meta/{type}/{id}.json` → `{meta:{id,type,name,poster,releaseInfo,imdbRating,videos:[{id:'tt…:S:E',season,episode}]}}`
  - `GET /stream/{type}/{id}.json` → `{streams:[…]}` merged from the provider registry + health + ranking
  - CORS `*` on every route.

- [ ] **Step 4: Implement `rank.ts`** — score = resolution weight + codec weight + seeders weight + provider health + India relevance + freshness; deterministic order for equal scores.

- [ ] **Step 5: Implement `dedupe.ts`** — dedupe by infohash, then by normalized URL, then by filename fingerprint (size + cleaned name).

- [ ] **Step 6: Deno tests pass** — `deno test supabase/functions/dizzy-resolver/` → PASS, including a ranking test (720p < 1080p < 4K, a higher-seed torrent outranks a lower-seed one at equal quality) and a dedupe test (same infohash from two providers appears once).

- [ ] **Step 7: Deploy the edge function** — `supabase functions deploy dizzy-resolver` (ask the owner first: this is a deployment).

---

## Phase 4 — App-side edge client with graceful degradation

- [ ] **Step 1: Write the failing test** — `test/edge_resolver_client_test.dart` with a fake `http.Client`: a successful response yields parsed streams; a 500 yields an empty list and no exception; a second call for the same key hits the cache.

- [ ] **Step 2: Watch it fail** — `flutter test --no-pub test/edge_resolver_client_test.dart` → FAIL.

- [ ] **Step 3: Implement `lib/services/engine/edge_resolver_client.dart`** — `Future<List<StreamSource>> streamsFor({required String type, required String id, String? title, int? year, int? season, int? episode})`; TTL 5 min + LRU 100; on error returns `const []` and logs via `AppLog.d`.

- [ ] **Step 4: Wire it into `WatchResolveController`** (`lib/pages/player/watch_resolve_controller.dart:160`) — the edge result is merged with the local scraper result; the local tier runs when the edge returned nothing.

- [ ] **Step 5: Verify** — targeted test PASS + `flutter analyze --no-pub` clean.

---

## Phase 5 — Own catalog with IMDb/TMDB ids (India-first, incl. Odia)

- [ ] **Step 1: Extend the TMDB proxy allowlist** — `supabase/functions/tmdb-proxy/index.ts:13`: add `/^\/discover\/(movie|tv)$/` so regional slates can be pulled in one call instead of 50 searches. Deploy with the owner's approval.

- [ ] **Step 2: Write the migration** — `supabase/migrations/20261115_dizzy_catalog.sql`:
  ```sql
  create table if not exists public.dizzy_catalog (
    id uuid primary key default gen_random_uuid(),
    content_id text not null,          -- 'tt0111161' or 'tmdb:12345'
    tmdb_id integer,
    type text not null check (type in ('movie','series')),
    title text not null,
    original_title text,
    year integer,
    language text,                    -- TMDB original_language, e.g. 'or'
    region text default 'IN',
    synopsis text,
    poster_url text,
    imdb_rating numeric,
    season_count integer,
    episode_count integer,
    verified boolean not null default false,
    source text not null default 'tmdb',
    fetched_at timestamptz not null default now(),
    unique (content_id, type)
  );
  create index if not exists idx_dizzy_catalog_lang_year
    on public.dizzy_catalog (language, year desc);
  create table if not exists public.dizzy_providers (
    id text primary key,
    site text not null,
    parser text not null,
    supports text[] not null default '{}',
    enabled boolean not null default true,
    priority integer not null default 0,
    config jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now()
  );
  create table if not exists public.dizzy_provider_health (
    provider_id text primary key references public.dizzy_providers(id) on delete cascade,
    success integer not null default 0,
    timeout integer not null default 0,
    error integer not null default 0,
    yield_count integer not null default 0,
    updated_at timestamptz not null default now()
  );
  ```
  Plus RLS: `authenticated` may read `dizzy_catalog` and `dizzy_providers`; writes only through `security definer` functions (ingestion + admin RPCs).

- [ ] **Step 3: Write the ingestion function** — `supabase/functions/catalog-ingest/index.ts`: for each configured language (`or`, `hi`, `ml`, `ta`, `te`, `bn`, `mr`, `kn`, `gu`, `pa`, `mr`), call `/discover/movie?with_original_language=<lang>&region=IN&sort_by=release_date.desc`, upsert into `dizzy_catalog` with `verified = true` (the row came from TMDB itself), and store `content_id` as the IMDb id when TMDB returns `imdb_id`, else `tmdb:<id>`. Schedule it with `pg_cron` (or a Supabase scheduled function) **daily**.

- [ ] **Step 4: Prove the Odia seed list before admitting it** — the owner's 50-title Odia list must be verified, never pasted blindly:
  ```bash
  python artifacts/audit-dsh/scripts/verify_catalog_seed.py artifacts/audit-dsh/odia_seed_titles.txt or
  ```
  Rules the script enforces (already implemented): a title is admitted only when TMDB returns it **with the intended original language**; a same-title film in another language is rejected as `WRONG_LANGUAGE`; TMDB 429s are reported as unresolved, never as "missing".
  Measured on 2026-11-14 over the full 50-title list: **21 VERIFIED** (title
  present in TMDB with `original_language='or'`), **11 WRONG_LANGUAGE** (a
  same-title film in another language — e.g. "Game Over" → 1996 German,
  "Monster" → 2003 English, "Midnight" → 1982, "Misiri" → "Kid Millions"
  1934), **18 unresolved** (TMDB 429 or absent). Evidence:
  `artifacts/audit-dsh/odia_seed_verification.txt`. The language check is
  deliberately conservative — "Murabi" (2026) is flagged only because TMDB
  tags it differently — so a rejected row may still be a real film; admitted
  rows are always real.

- [ ] **Step 5: Serve our catalog** — `lib/services/catalog/catalog_service_v2.dart` reads `dizzy_catalog` (through the `catalog` edge or a new `dizzy-catalog` edge route) and returns rows with IMDb/TMDB ids; `lib/services/metadata/metadata_service.dart:77` tries our catalog **first** and falls back to Cinemeta.

- [ ] **Step 6: Add the language chip to Home** — `lib/pages/home/home_rails.dart` gains an "Odia" (and other languages) chip sourced from `dizzy_catalog` with `language='or'`.

- [ ] **Step 7: Verify** — `flutter test --no-pub test/home_rails_test.dart` and a new `test/dizzy_catalog_test.dart` (rows keep `tt…`/`tmdb:` ids) PASS; analyzer clean.

- [ ] **Step 8: Apply the migration and deploy the ingestion function** — ask the owner first; apply with `supabase db query --linked -f supabase/migrations/20261115_dizzy_catalog.sql` and record the history row (`version = '20261115'`).

---

## Phase 6 — Own torrent indexers behind `TorrentEngine`

- [ ] **Step 1: Write the failing test** — `test/dizzy_torrent_indexer_test.dart` with a fake HTTP client: the indexer returns `TorrentCandidate{infoHash, magnet, trackers, sizeBytes, seeders, title}` for a known query and an empty list when nothing matches.

- [ ] **Step 2: Watch it fail** — `flutter test --no-pub test/dizzy_torrent_indexer_test.dart` → FAIL.

- [ ] **Step 3: Implement `lib/services/engine/dizzy_torrent_indexer.dart`** — `abstract class DizzyTorrentIndexer { String id; Future<List<TorrentCandidate>> search({required String title, int? year, int? season, int? episode}); }`, plus one implementation per indexer we operate. Use `DizzyNet` (not raw `http.get`) so the circuit breaker and retry policy apply — the current `knaben.dart:38` bypasses them and must be migrated.

- [ ] **Step 4: Implement `lib/services/engine/torrent_engine.dart`** — `abstract class TorrentEngine { Future<String?> resolvePlayableUrl({required String magnet, required String title, int? season, int? episode, int? fileIdx}); }` with `TorrServerEngine` wrapping `TorrentStreamService` (magnet → `addTorrent` → warm-up → `streamUrl`), preserving the existing `TorrentWarmupPolicy` behaviour.

- [ ] **Step 5: Switch the player** — `lib/pages/player/player_screen_part_stream.dart:113` calls `TorrentEngine.instance.resolvePlayableUrl(...)` instead of `TorrentStreamService().streamTorrent(...)`; the existing decoy-`.exe` guard (`TorrentFileGuard.isVideo`) and warm-up stay in place.

- [ ] **Step 6: Verify** — new tests PASS, `test/music_playback_retry_test.dart` and `test/torrent_warmup_policy_test.dart` still PASS, analyzer clean.

- [ ] **Step 7: Check the seeds** — reject candidates with `seeders == 0` and prefer candidates whose file matches the requested episode.

---

## Phase 7 — Retire the public add-ons and harden the honest states

- [ ] **Step 1: Change the default add-on set** — `lib/services/addon/addon_manager.dart:28-32`: remove `torrentio.strem.fun`, `torrentsdb.com`, `acuanime.pages.dev` from the force-installed list; keep them as **opt-in** entries the user can add manually; install our `builtin:dizzyown` instead.

- [ ] **Step 2: Write the failing test** — `test/addon_defaults_test.dart`: after `AddonManager.initialize()` with empty prefs, the installed set contains `builtin:dizzyown` and contains no public stream add-on URL.

- [ ] **Step 3: Watch it fail, then fix `addon_manager.dart`** so the defaults come from the registry/remote config.

- [ ] **Step 4: Honest states** — when the resolver returns nothing: say *which* tiers were tried (our providers / our indexers / TorrServer) instead of a generic "no streams". When the torrent tier is unavailable because TorrServer did not start, say so plainly. Reuse the existing "Audio unavailable" pattern in `lib/pages/music/widgets/music_expanded_player.dart` and the player's error copy.

- [ ] **Step 5: Verify on device** — one title plays from our own provider on the emulator; the UI shows the new tier names when a tier fails. Capture the screenshot to `artifacts/audit-dsh/engine-01-*.jpg`.

- [ ] **Step 6: Report** — append a "Private add-on engine" section to `docs/audit/2026-11-09-music-creator.md` with what is VERIFIED (device evidence) and what is UNVERIFIED. Update `docs/superpowers/evals/2026-11-12-dizzy-eval.md` only for checks that actually changed.

---

## Verification Gate (end of plan)

- [ ] `flutter analyze --no-pub` → "No issues found!"
- [ ] `flutter test --no-pub --name '^(?!bulk corpus probe$)'` → 0 failures (report the excluded live-network test and the skips honestly).
- [ ] `deno test supabase/functions/dizzy-resolver/` → PASS.
- [ ] `python artifacts/audit-dsh/scripts/verify_catalog_seed.py artifacts/audit-dsh/odia_seed_titles.txt or` → every admitted row is VERIFIED, no WRONG_LANGUAGE row admitted.
- [ ] Device: one title resolves and plays through our own tier.
- [ ] `artifacts/audit-dsh/final-artifacts.json` regenerated after the last build; Windows bundle, universal APK and three split APKs present.
- [ ] No public add-on is force-installed; nothing was published to any Stremio catalogue.

## Open items for the owner

1. **Torrent engine — DECIDED: Option A** (keep TorrServer + our own
   indexers/providers). Phase 0b then implements the usage contract
   (upload budget, seed window, metered/background no-seed, peer proxy
   option). If Phase 0's spike shows TorrServer cannot serve bytes on
   Android, revisit (Option B) before Phase 6.
2. **Provider set** — which sites we operate as first-party. Recommend starting with the JSON-friendly ones already in the codebase (`knaben`) plus the indexers that need no JS rendering; Cloudflare-protected providers stay out of scope for a Dart-only parser.
3. **Catalog seed** — the 50-title Odia list needs verification before it enters the catalog; the script does that, and the first run showed title-only matching admitting wrong-language films.
4. **Deployment approvals** — edge function deploys, migrations and the admin dashboard publish each need a separate go-ahead.
5. **Where the seeder runs long-term** — the household IP still carries the swarm. If the owner wants the IP fully protected, the seeder must move to a VPS; that is a product decision, not a knob (spec section 4.5).
6. **Concurrency with the other agent** — the OpenCode session
   `ses_e2f5fdc86ffeKjcaP4FKH5mzV5` is currently running the
   `OPENCODE_NEXT_STEPS.md` tasks (settings layout + audit round, updated
   2026-11-14 09:41). Phases 0b/1–7 of this plan touch different files
   (torrent policy, provider registry, edge resolver, catalog), but
   `lib/services/stream/torrent_stream_service.dart` and
   `lib/services/addon/addon_manager.dart` are shared with that session —
   re-read them before editing, and do not run two agents in the same
   file at the same time.
