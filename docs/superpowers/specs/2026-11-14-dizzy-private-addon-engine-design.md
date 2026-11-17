# Dizzy private add-on engine — design spec (2026-11-14)

Owner decision (this round): **hybrid engine — edge resolver + in-app scrapers**,
**catalog ids stay IMDb/TMDB**, and the **torrent engine choice is presented with
outcomes** below (Phase 0 must close it).

Problem being solved: every user of Dizzy currently gets the *same* sources,
because the app force-installs the public Stremio add-ons
(`torrentio.strem.fun`, `torrentsdb.com`, `acuanime.pages.dev` —
`lib/services/addon/addon_manager.dart:28-32`) and because the built-in HTTP
scrapers target the same popular sites that every public resolver targets. The
owner wants Dizzy to run **its own** add-on/scraper engine that provides
(a) P2P/torrent sources served as playable HTTP, (b) HTTP provider streams and
(c) catalogs — used only inside the Dizzy app, **never published** to the
Stremio community catalogue.

This engine is private by construction: the Stremio publish API is a separate
`POST https://api.strem.io/api/addonPublish` call
(https://github.com/Stremio/stremio-addon-sdk/blob/master/src/publishToCentral.js)
and the docs state local add-ons "cannot be used by other Stremio users"
(https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/README.md).
Nothing in this design calls that API.

---

## 1. What already exists (reuse, do not rebuild)

| Area | Today | File:line |
|---|---|---|
| Add-on registry | `AddonManager` singleton, prefs key `installed_addons_v4`, manifest parse, per-resource toggles, `activeStreamAddons` | `lib/services/addon/addon_manager.dart:20,24,82,97,309` |
| Pseudo add-ons | `builtin:dizzy` (TorrServer P2P) and `builtin:dizzyhttp` (HTTP scraper pack) already exist | `addon_manager.dart:147,167` |
| Stream contract | `StreamSource{name,title,url,infoHash,fileIdx,addonName,behaviorHints,headers,renditions}` | `lib/models/stream/stream_model.dart:33` |
| Scraper contract | `StreamScraper{name,isTorrentScraper,indexesNewReleases,priority,scrapeStream(...)}` | `lib/services/scraper/stream_scraper.dart:9` |
| Scraper pool | `ScraperManager.scrapeAll` — bounded pool (10 parallel / 20 queued), dedupe by infohash+URL, quarantine + remote kill map | `lib/services/scraper/stream_scraper.dart:100,161,305` |
| Built-in providers | ~47 HTTP site scrapers + 2 torrent indexers (`knaben.dart`, `torrent_galaxy.dart`) | `lib/services/scraper/sites/*` |
| Torrent playback | TorrServer sidecar (`torrserver_flutter ^0.0.6`), magnet → `addTorrent` → `streamUrl(hash,index)` → loopback HTTP | `lib/services/stream/torrent_stream_service.dart:51,123,149,205` |
| Torrent readiness | `TorrentWarmupPolicy.evaluate` (2 MB target, 512 KB floor, 14 s ceiling, peer grace) | `lib/services/stream/torrent_warmup_policy.dart:39` |
| Catalog today | Cinemeta via `MetadataService` (`https://v3-cinemeta.strem.io`), plus Dizzy rails from the `catalog` edge (TMDB) | `lib/services/metadata/metadata_service.dart:77,84` |
| Player consumption | magnet assembly from `infoHash`+`sources`, headers merge (`resolveStreamHeaders` + `behaviorHints.proxyHeaders`), mpv open | `lib/pages/player/player_screen_part_stream.dart:54,113,136,227` |
| Net layer | `DizzyNet.instance` (never throws, synthetic 504), `CircuitBreaker` 5-fail/60 s, retry policy, offline replay | `lib/services/net/dizzy_net.dart:47,106` |
| Health/quarantine | `ScraperQuarantineService` (7-day quarantine), `RemoteConfigService.killedScrapers` | `lib/services/scraper/scraper_quarantine_service.dart:10`, `lib/services/cloud/remote_config_service.dart:76` |
| Edge functions | `supabase/functions/catalog`, `resolve`, `tmdb-proxy`, `scraper-ingest` (crowd votes) | `supabase/functions/*` |

**Gaps that this engine must close** (from the codebase map):
1. No first-party catalog provider — rows still come from Cinemeta/TMDB.
2. No first-party torrent indexer beyond 2 sites; `knaben.dart` uses raw
   `http.get` outside `DizzyNet` (no breaker, no retry policy).
3. Public add-on URL list is hardcoded in Dart and force-installed — no
   env/remote-config control, no way to route to our own engine.
4. Torrent bytes can only become HTTP via the bundled TorrServer process; no
   abstraction to swap engines later.
5. `StreamScraper` has no introspection contract (no manifest-like description
   of a provider: types, idPrefixes, quality, supported sites).
6. No provider latency/yield telemetry — only dead/not-dead quarantine.
7. Add-on protocol only partially modelled; `behaviorHints` read in two places.

---

## 2. Verified research (2026-11-14)

### 2.1 Protocol facts

- Canonical spec is the SDK repo docs (the old wiki 404s):
  https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md
- Manifest fields: `id,name,description,version,resources,types,idPrefixes,
  catalogs,behaviorHints{adult,p2p,configurable,configurationRequired,epgProvider}` —
  https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/manifest.md
- Resources/routes: `/manifest.json`, `/{resource}/{type}/{id}.json`,
  `/{resource}/{type}/{id}/{extraArgs}.json`; CORS `*` required on every route.
- Stream object: `url` | `ytId` | `infoHash`+`fileIdx` | `nzbUrl`+`servers` |
  `externalUrl`, plus `name,title,subtitles[],sources[]` (trackers/DHT) and
  `behaviorHints{countryWhitelist,notWebReady,bingeGroup,proxyHeaders,videoHash,videoSize,filename}`
  — https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/stream.md
- `stremio-addon-sdk` npm is 1.6.10 (2022-10-30) while the docs moved on; the
  community TS SDK `@stremio-addon/sdk` exists since 2025-09 —
  https://www.npmjs.com/package/stremio-addon-sdk , https://github.com/Stremio-Community/stremio-addon-sdk
- 2026 additions worth knowing: native EPG (`behaviorHints.epgProvider`,
  `tv` catalogs, `date` extra) landed 2026-09-13 —
  https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/epg.md ;
  `player`/`library` event resources —
  https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md
- Cinemeta shape we must be able to answer: catalog `{metas[],hasMore,cacheMaxAge}`;
  meta for movie `{meta{id,type,name,poster,background,logo,description,
  releaseInfo,imdbRating,released,runtime,genres,cast,director,trailers,links,videos[]}}`
  with IMDb ids `tt…`; series video ids `tt0386676:5:18` —
  https://v3-cinemeta.strem.io/meta/movie/tt0111161.json ,
  https://v3-cinemeta.strem.io/meta/series/tt0386676.json
- Cinemeta traps: catalog and meta now live on **different hosts**
  (`cinemeta-catalogs.strem.io` vs `v3-cinemeta.strem.io`) and query-string
  extras are dropped by its 307 redirect — use path-style
  `/catalog/movie/top/search=x.json`.

### 2.2 Torrent engine facts

- libtorrent is **BSD-3** (GPL only for historic rasterbar releases) and ships
  a documented streaming implementation —
  https://github.com/arvidn/libtorrent/blob/master/COPYING ,
  https://libtorrent.org/streaming.html
- The only Flutter libtorrent FFI package is **GPL-3.0**
  (`libtorrent_flutter` 2.0.0, 2026-08-12, includes a built-in range-capable
  HTTP server) — https://pub.dev/packages/libtorrent_flutter
- Pure-Dart option: `dtorrent_task_v2` (BSD-3, 2026-10-23) — tracker + DHT +
  magnet + sequential download "optimized for video/audio streaming"; browser
  WebRTC transport is a separate future layer —
  https://github.com/atlet99/dtorrent_task_v2
- Sidecar servers: TorrServer (Go, GPL-3.0, already in the app),
  FluxTorrent (Go, Apache-2.0, TorrServer/Stremio-compatible API) —
  https://github.com/jodacame/FluxTorrent ; `torrent2http` (GPL-3.0);
  `torrent-stream-server` (MIT) — https://github.com/KiraLT/torrent-stream-server
- Node/WebTorrent path: `torrent-stream` (MIT) + `peerflix` (MIT) expose torrent
  files over HTTP with `range-parser` — https://github.com/mafintosh/torrent-stream ;
  `webtorrent-hybrid` (MIT) bridges WebTorrent and classic BT.
- Torrentio is a **relay**, not P2P: its repo contains only debrid adapters
  (alldebrid, realdebrid, torbox, …) behind a `Moch` trait —
  https://github.com/TheBeastLT/torrentio-scraper/blob/master/addon/README.md ;
  TorBox seeds on its side — https://github.com/devblaze/torbox-client/blob/main/README.md
- Jackett/Prowlarr are indexers only (metadata + magnets, no bytes) —
  https://github.com/Jackett/Jackett , https://github.com/Prowlarr/Prowlarr
- qBittorrent WebUI API has no endpoint that serves file bytes over HTTP —
  https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-5.0) ;
  MediaFusion reaches bytes through qBittorrent + WebDAV —
  https://github.com/mhdzumair/MediaFusion/blob/main/backend/src/providers/torrents/qbittorrent.rs
- Real-Debrid links are IP-locked to one public IP —
  https://api.real-debrid.com/ (error 22 "IP Address not allowed");
  Comet exists partly to proxy around that —
  https://github.com/g0ldyy/comet

### 2.3 HTTP provider facts

- A provider = site + parser. MediaFusion ships a static registry with URL
  templates and per-site row/title/detail/magnet/size/seeder selectors, plus
  `supports_movie/series/anime`, `solve_cloudflare`, `http_fallback` and handler
  types `Html | Rss | SubsPleaseJson | KnabenJson` —
  https://github.com/mhdzumair/MediaFusion/blob/main/backend/src/scrapers/public_indexer_registry.rs
- That registry's 2026 provider set: Knaben, TorrentFunk, Il Corsaro Nero,
  Comando, BluDV, 1337x, BT4G, Nyaa, SubsPlease, AnimeTosho, EZTV, YTS,
  The Pirate Bay, LimeTorrents, UIndex, Rutor, OxTorrent, Torlock, TheRARBG,
  TorrentDownloads, YourBittorrent, TorrentDownload, BitSearch.
- Name matching uses metadata modules (IMDb/TMDB/TVDB/AniList/Kitsu/Trakt) to
  build queries like `Title (Year)`, `SxxExx` —
  https://github.com/mhdzumair/MediaFusion/blob/main/backend/src/scrapers/title_queries.rs
- Health gating is a Redis-backed source-health gate (success rate, timeout
  rate, decay, recovery streak, 7-day TTL) —
  https://github.com/mhdzumair/MediaFusion/blob/main/backend/src/scrapers/source_health.rs ;
  Torrentio drops zero-seeder streams and uses 30 s availability / 120 s resolve
  timeouts.
- AIOStreams (AGPL-3.0) aggregates add-ons; it does not scrape —
  https://github.com/Viren070/AIOStreams ; Knightcrawler (Apache-2.0) is
  self-hosted but **debrid mandatory** — https://github.com/knightcrawler-stremio/knightcrawler

### 2.4 Hard constraints for true P2P from a phone

- iOS allows no generic torrent background mode —
  https://developer.apple.com/documentation/xcode/configuring-background-execution-modes
- Android UIDT jobs need a visible app + notification and are killed for
  thermal/memory reasons; >10 min background work is "highly likely to be
  interrupted" — https://developer.android.com/develop/background-work/background-tasks/uidt
- DHT needs bootstrap nodes and is useless for private torrents —
  https://libtorrent.org/reference-Settings.html
- CGNAT breaks port forwarding; consumer NAT tables fill under BitTorrent's
  connection rate — https://en.wikipedia.org/wiki/BitTorrent
- ISPs block BitTorrent (measured: https://people.mpi-sws.org/~mdischin/papers/08_imc_blocking.pdf);
  ~39 countries block pirate sites —
  https://itif.org/publications/2025/06/09/blocking-access-to-foreign-pirate-sites-a-long-overdue-task-for-congress/
- Zero-seeder torrents are common and get filtered before playback —
  https://github.com/TheBeastLT/torrentio-scraper/blob/master/addon/crates/addon/src/providers/mod.rs

### 2.5 Measured truth about the owner's Odia seed list (2026-11-14)

The owner's 50-title Odia list was verified title-by-title against TMDB
through Dizzy's own edge proxy (`artifacts/audit-dsh/scripts/verify_catalog_seed.py`,
evidence `artifacts/audit-dsh/odia_seed_verification.txt`):

- **21 VERIFIED** — title present with `original_language='or'`
  (e.g. *Maliput Melodies* 2025, *Jadi: The Untold Side of If* 2026).
- **11 WRONG_LANGUAGE** — a same-title film in another language:
  *Game Over* → 1996 German, *Monster* → 2003 English, *Midnight* → 1982,
  *Vaastav* → 1999, *Misiri* → *Kid Millions* 1934, *Angel* → 1984.
- **18 unresolved** — TMDB 429 (the edge rate-limits bursts; 6 workers hit 429
  after ~10 titles, hence the paced script) or genuinely absent.

Consequences for the design: (a) a pasted title list may never enter the
catalog unverified — title-only matching demonstrably admits the wrong film;
(b) TMDB's Odia coverage is thin (21/50), so regional catalogs beyond TMDB
need a second metadata source before they can be complete; (c) the ingestion
must be batched server-side (one `discover` call per language), not per-title
from the app.

---

## 3. Torrent engine decision (owner call required — Phase 0)

| Option | What the user gets | Cost / risk | Outcome summary |
|---|---|---|---|
| **A. Keep TorrServer (bundled sidecar) + own indexers/providers** — *recommended* | Real P2P: the phone/desktop seeds and plays; our own indexers decide *what* to fetch. Works today on Windows + Android. | Provider-scraping maintenance; TorrServer is GPL-3.0 (already shipped inside the app binary today, so no new exposure); no relay cost. | Most "own engine" character, zero new binary work, keeps the existing warm-up policy. Risk: seeding from a phone is bandwidth-heavy and ISP-blocked. |
| **B. Embed libtorrent in-app (FFI)** | True P2P with no sidecar process; `libtorrent_flutter` even ships a range-capable HTTP server. | The only FFI package is **GPL-3.0** → copyleft obligation on the shipped app; libtorrent itself is BSD but binding is not; iOS background limits + Android foreground-service rules; untested on this device class. | Highest technical risk, changes the app's licence posture. Only pick if the sidecar is dropped entirely. |
| **C. Debrid relay for torrent bytes (our indexers, their servers)** | Our resolver picks the torrent; a debrid service fetches and serves it. Most reliable playback, best seed selection. | Recurring cost per GB; not P2P from the user; links are IP-locked (needs the Comet-style proxy). | Best reliability, least "own engine". Use only as a fallback tier behind A. |

**Recommendation: Option A, with C as an optional later tier.** Phase 0 = a
one-day spike that measures, on the real device, (a) TorrServer magnet→bytes
time for the titles that currently fail, (b) whether the failing titles have
zero-seeders or 403s, and (c) how many alternative candidates our own indexers
return for the same title. Those three numbers decide A vs B vs C without
speculation. If A's numbers are good, no engine change is needed at all.

---

## 4. Controlled P2P usage (Option A — the owner's chosen engine)

Option A keeps TorrServer as the seeder/player, so the product now owes the
user a **usage contract**: the phone must stay cool and cheap, playback must
stay fast, and the household IP must not get flagged.

### 7.1 What TorrServer actually exposes (verified 2026-11-14)

TorrServer does **not** embed libtorrent; it embeds `anacrolix/torrent`
(v1.59.1) through the `tsynik/torrent` fork
(https://github.com/YouROK/TorrServer/blob/master/server/go.mod). Every knob
lives in one **global** struct `BTSets`
(https://github.com/YouROK/TorrServer/blob/master/server/settings/btsets.go)
and is written with `POST /settings` `{action:"set", sets:{…}}`
(https://github.com/YouROK/TorrServer/blob/master/server/web/api/settings.go):

| Knob | Effect |
|---|---|
| `DownloadRateLimit` / `UploadRateLimit` | kb/s, `0` = unlimited |
| `ConnectionsLimit` | established peers per torrent (default 25) |
| `DisableDHT` / `DisablePEX` / `EnableLPD` | peer-discovery channels off |
| `DisableUPNP` | no port forwarding → no inbound exposure |
| `ForceEncrypt` | MSE (MS obfuscated) encryption |
| `CacheSize`, `UseDisk`, `PreloadCache`, `ReaderReadAHead`, `ResponsiveMode` | cache + read-ahead behaviour |
| `TorrentDisconnectTimeout` | idle torrents are dropped |
| `DefaultTrackers`, `RetrackersMode` | tracker list |

Hard limits that shape the design:

- `addTorrent` accepts only `link, hash, title, poster, data, category,
  save_to_db` (https://github.com/YouROK/TorrServer/blob/master/server/web/api/torrents.go)
  — **no per-torrent speed limit, no per-file priority, no per-torrent
  timeout**.
- Changing `BTSets` **drops every torrent and restarts the BT client**
  (https://github.com/YouROK/TorrServer/blob/master/server/torr/apihelper.go).
  Policy must therefore be applied **once per session**, never mid-playback.
- The stream endpoint is `http.ServeContent` — range/seek capable, 1 MiB
  buffered reader, `Accept-Ranges: bytes`
  (https://github.com/YouROK/TorrServer/blob/master/server/torr/stream.go) —
  but the **HTTP path is not throttled**; throttling is BT-side only, so a
  global download cap also starves the pieces feeding playback.
- Proxy support is **CLI-only**: `-proxy` + `-proxy-mode tracker|peers|full`
  (https://github.com/YouROK/TorrServer/blob/master/server/cmd/main.go). The
  app already launches the sidecar with `extraArgs`
  (`lib/services/stream/torrent_stream_service.dart:103`), so the proxy can be
  passed at start.
- The peer identity is hard-coded to qBittorrent 4.3.9
  (https://github.com/YouROK/TorrServer/blob/master/server/torr/btserver.go) and
  cannot be changed per instance.
- Played-file piece priority exists in the library but TorrServer never calls
  it (https://github.com/anacrolix/torrent/blob/v1.59.1/file.go).

### 7.2 The usage contract (what Dizzy promises)

1. **Playback first.** The download cap stays `0` (unlimited) so playback
   pieces are never starved; the read-ahead knobs (`ReaderReadAHead`,
   `PreloadCache`, `ResponsiveMode`) buy fast start.
2. **Seeding is a budget, not a default.** Upload is capped to a small
   fraction of the measured uplink, seeding happens only inside an explicit
   window after playback, and the torrent is deleted when the window ends —
   so the household IP is not a permanent peer.
3. **Metered / background / not charging → no seeding.** TorrServer cannot
   throttle per torrent, so the app enforces this by *removing* torrents
   instead of changing settings.
4. **One active torrent at a time.**
5. **IP-hygiene defaults on:** DHT/PEX/LSD off, UPnP off, encryption forced,
   low connection count, no continuous seeding.
6. **Optional peer traffic through a proxy** (`-proxy -proxy-mode peers`),
   so the ISP sees the proxy's traffic rather than the household IP.

### 7.3 Policy model (pure Dart, testable)

```dart
class TorrentUsageProfile {
  final int uploadRateLimitKb;   // 0 = unlimited
  final int downloadRateLimitKb; // always 0 in v1
  final int connectionsLimit;
  final int seedWindowMinutes;
  final int maxSeedBytes;
  final bool allowSeeding;
  final bool proxyPeers;
}
```

`TorrentUsagePolicy.profileFor({required bool metered, required bool charging,
required bool playbackActive, required int? uplinkKbps, required bool proxyConfigured})`
returns the profile. Rules (v1):

- `metered` → `allowSeeding = false`, `uploadRateLimitKb = 0`.
- `!charging && playbackActive` → upload cap = 32 kb/s (playback-safe floor).
- otherwise `uploadRateLimitKb = clamp(uplinkKbps * 0.15, 32, 512)`; when
  `uplinkKbps` is unknown → 64 kb/s.
- `connectionsLimit = 12` (playback-first, less swarm visibility).
- `seedWindowMinutes = 10`, `maxSeedBytes = 256 MB` after playback ends.
- `proxyPeers` = the user's own setting.

### 7.4 Sensing layer

`connectivity_plus ^7.3.1` is already a dependency (pubspec.yaml:90) but
exposes connectivity **type**, not metered state or bandwidth. Android's
`NET_CAPABILITY_NOT_METERED`, `getLinkUpstreamBandwidthKbps()` and charging
state need a small platform channel
(https://developer.android.com/reference/android/net/ConnectivityManager ,
https://developer.android.com/reference/android/net/NetworkCapabilities).
One Kotlin `MethodChannel` returning one JSON map
(`metered`, `uplinkKbps`, `downlinkKbps`, `charging`) is enough.

### 7.5 Honest limits (must appear in the report)

- No knob prevents DPI detection: libtorrent's maintainer states there is "no
  way to 'hide' from your ISP"
  (https://github.com/arvidn/libtorrent/issues/5222). Encryption helps against
  *filtering* (https://github.com/transmission/transmission/blob/main/docs/Editing-Configuration-Files.md),
  not against detection.
- The claim that per-IP peer counts trigger ISP blocks is **unverified**; the
  measured problem is protocol detection and behavioural shaping
  (https://people.mpi-sws.org/~mdischin/papers/08_imc_blocking.pdf).
- Android bandwidth numbers are first-hop *estimates*, not measured
  throughput, and are wrong after a handover or VPN change.
- The global download cap cannot be separated from the playback lane.
- The strongest mitigation for the household IP is running the seeder on a
  VPS instead of the phone; that is a product decision, not a knob.

---

## 5. Target architecture (hybrid, per owner decision)

```
┌──────────────────────────── DIZZY APP (device) ─────────────────────────────┐
│  Home rails / Browse / Search                                               │
│        │                                                                   │
│        ▼                                                                   │
│  CatalogService  ── IMDb/TMDB ids (unchanged) ──►  catalog edge (TMDB)       │
│        │                                                                   │
│        ▼                                                                   │
│  WatchResolveController ──► DizzyResolver (Dart, in-process)                 │
│        │                     ├─ InAppProviderScraper  (our HTTP parsers,      │
│        │                     │    user's own IP, no IP-lock problem)          │
│        │                     ├─ DizzyTorrentIndexers  (our indexers →        │
│        │                     │    magnet/infohash)                            │
│        │                     └─ EdgeResolverClient  (Supabase edge: ranking,  │
│                          │     catalog, cross-user dedupe, health)            │
│        ▼                                                                     │
│  TorrServer sidecar ── magnet ──► ranged HTTP on 127.0.0.1 ──► mpv          │
└──────────────────────────────────────────────────────────────────────────────┘
                                      ▲
┌──────────────── SUPABASE (owner-controlled, never published) ────────────────┐
│  /functions/dizzy-resolver  → Stremio-shaped /manifest.json, /catalog,       │
│                               /meta, /stream over the Dizzy edge URL         │
│  /functions/catalog        → TMDB-backed catalog rows (today)                │
│  remote_config             → provider registry + kill switches + quality    │
│                               ranking weights                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

Key properties:
- **The app consumes our engine exactly like an add-on.** No new UI concept,
  no parallel player path: our engine exposes the same `StreamSource`
  contract the player already consumes.
- **The edge is the brain; the device is the hands.** Ranking, dedupe,
  catalog freshness, per-provider health and the provider registry live on the
  edge (one place to fix, one place to roll back). Provider scraping that
  benefits from the user's IP (or that must not hit our server IP) stays in
  the app.
- **IMDb/TMDB ids stay the currency.** Provider queries and the player keep
  using `tt…` / `tmdb:` ids; our catalog service mints no new id space, so
  nothing in Home/Browse/Search has to change.
- **Nothing is published.** The engine URL is private config; the
  `addonPublish` API is never called.

### 4.1 Components

| Component | New/Changed | Responsibility |
|---|---|---|
| `ProviderRegistry` (edge) | new | Data-driven provider list (id, site, parser id, capabilities, quality bias, enabled flag) served from `remote_config`/a table. Replaces hardcoded lists. |
| `ProviderHealth` (edge + app) | new | Per-provider success/timeout/yield counters with decay; feeds the ranking and the kill switch. Replaces the dead/not-dead quarantine with numbers. |
| `EdgeResolverClient` (app) | new | Calls the edge resolver, caches results (TTL + LRU), degrades to in-app resolution when the edge is unreachable. |
| `InAppProviderScraper` (app) | new | Runs our HTTP provider parsers from the device IP; parses are table/selector-driven, not copy-pasted per site. |
| `DizzyTorrentIndexer` (app) | new | Our torrent indexers behind one interface (magnet + infohash + trackers + size + seeders), replacing the 2 hardcoded sites. |
| `StreamRanker` (edge) | new | One ranking rule set (resolution, codec, seeders, provider health, India relevance, freshness) so Home/Search/Player agree on order. |
| `DizzyCatalogService` (edge) | modified | Keeps IMDb/TMDB ids; adds `dizzy` catalog feed, episode lists, and "where to watch" rows. |
| `AddonManager` | modified | Stop force-installing the public stream add-ons; install our engine as `builtin:dizzyown` and keep the public ones opt-in. |
| `ScraperManager` | modified | Consume the registry + health instead of the hardcoded 47-site list; keep the same `StreamScraper` interface so existing scrapers still work. |
| `TorrServer` binding | modified | Wrap behind a `TorrentEngine` interface so Phase 0's spike can swap A→B→C without touching the player. |

### 4.2 Data flow (one title, start to finish)

1. User taps a rail card → `WatchResolveController` opens a 400 ms window.
2. `DizzyResolver.resolve(type, id, title, year, season, episode)` runs:
   a. edge resolver call (cache hit → return immediately);
   b. on cache miss: in-app providers + torrent indexers run in parallel
      (bounded pool, per-provider timeout);
   c. edge merges both halves, ranks, dedupes by infohash/URL/fingerprint, and
      returns Stremio-shaped streams.
3. Player receives `StreamSource` exactly as today.
4. For a torrent stream: `TorrentEngine.resolve(magnet)` → TorrServer
   `addTorrent` → warm-up policy → loopback URL → mpv opens it.
5. Health counters are reported back (edge `scraper-ingest` already exists for
   crowd votes) and feed the next ranking.

### 4.3 Error handling (no dead ends)

- Edge unreachable → in-app resolution continues (the app never blocks on the
  edge).
- Provider down → health score decays, provider is skipped, the UI shows the
  remaining candidates; no "no streams" dead end while another provider works.
- Torrent has zero seeders → not offered; if all torrent candidates are dead,
  HTTP candidates still play.
- TorrServer fails to start → torrent tier is disabled for that session and
  the UI says so plainly; HTTP tier keeps working.

### 4.4 Testing

- Dart unit tests: provider registry parsing, ranking function, magnet parsing,
  health decay, cache TTL, id translation.
- Edge function tests: manifest/catalog/meta/stream shapes match the protocol
  (Deno test).
- Golden tests: provider HTML fixtures → parsed `StreamSource` (fixtures
  committed, so selector drift shows up as a failing test, not a silent
  regression).
- Device test: one title resolves to ≥1 HTTP candidate and ≥1 torrent
  candidate on the real device, and the torrent candidate actually plays.

---

## 6. Phasing (each phase ships something usable)

| Phase | Deliverable | Gate |
|---|---|---|
| 0 | Torrent engine spike (measure A vs B vs C) + `TorrentEngine` interface | Numbers decide the engine; no user-visible change |
| 1 | `builtin:dizzyown` pseudo add-on serving our own providers via the existing `StreamSource` contract; public add-ons become opt-in | Our own provider returns a playable stream on device |
| 2 | Provider registry + health in `remote_config`; existing 47 scrapers registered through it | A provider can be disabled remotely and the UI reflects it |
| 3 | Edge resolver + `EdgeResolverClient` (ranking, dedupe, cache) | Same title returns the same order on two devices |
| 4 | Own catalog feed on the edge (IMDb/TMDB ids, episodes, India-first ordering) | Home rails and Search read from our catalog |
| 5 | Own torrent indexers behind `DizzyTorrentIndexer`; magnet hygiene + warm-up tuning | A title that previously failed plays from our indexer |
| 6 | Cleanup: retire the public add-on default, harden the honest-state UI, audit notes | No public add-on is force-installed; audit updated |

## 7. Explicit non-goals

- Not published to any Stremio catalogue or community list.
- No debrid subscription in the core path (Option C stays optional).
- No new id space (IMDb/TMDB ids stay).
- No third-party service the user did not choose (no scraping-as-a-service SaaS).
- No scraping of Cloudflare-protected providers from Dart — those need a
  headless browser and stay out of scope until a provider decision is made.
