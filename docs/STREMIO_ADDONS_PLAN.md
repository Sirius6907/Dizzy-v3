# Stremio Addons for the Indian Audience — Phase 8 Plan

**Date:** 2026-10-06 · **Status:** Approved to build (phased, ship each phase independently)
**Owner:** Sirius · **Rule set:** Easy English only, anonymous-first, defaults ON, budgets ≤3GB RAM / ≤2.5GB VRAM / ≤20% CPU, no tag without a "kar de".

---

## 1. Audit — what already works (verified in code, 2026-10-06)

| Capability | Status | Evidence |
|---|---|---|
| Manifest parsing (meta / catalog / stream / subtitles) | ✅ live | `lib/models/addon/addon.dart:26-29`, `InstalledAddon.is*Active` `:154-163` |
| Install by pasting a `manifest.json` URL | ✅ live | `lib/pages/settings/addons_settings_page.dart:29-40` |
| Per-feature toggles (catalog / search / subtitles / streams) | ✅ live | `addons_settings_page.dart:677-704` + `AddonManager.updateAddonFeature` |
| Reorder / enable / remove, persisted (`installed_addons_v4`) | ✅ live | `addon_manager.dart:204-304` |
| Home rails aggregated across active catalog addons | ✅ live | `fetchAllHomeSections` `addon_manager.dart:339` |
| Search across addons + genre browse | ✅ live | `searchAll:431`, `fetchByGenre:492` |
| **Stream addons actually resolve playback** | ✅ live | `stream_service.dart:134`, `:356` via `activeStreamAddons` |
| **Subtitle addons feed the player** | ✅ live | `stremio_subtitle_provider.dart:163` |
| Built-ins: TorrServer P2P engine + HTTP scraper pack (as stream addons) | ✅ live | `addon_manager.dart:119`, `:138` |
| First-launch default: Cinemeta installed | ✅ live | class doc `addon_manager.dart:16` |
| Backup/restore of the addon list | ✅ live | Settings → Backup & Restore (JSON) |

**Verdict:** the *engine* is production-ready. What's missing is everything around it that makes it usable by a non-technical Indian user.

## 2. Gaps (why a non-tech user still can't use this)

1. **No directory.** Users must paste a raw `manifest.json` URL — 99% of the audience will never have one. This is the single biggest blocker.
2. **No India-relevant curation.** Out of the box a user gets Cinemeta (global) — nothing tuned for Hindi/Tamil/Telugu/Malayalam/Bengali content, Indian subs, or Indian catalog rails.
3. **No addon health signal.** A dead addon fails silently in the background; user just sees "no results" with no idea which addon broke.
4. **No safety gate for a public/family product.** Stremio's public directory contains adult and dubious addons; a public Indian launch must default to a vetted, SFW set.
5. **No share/QR install.** Sending a friend an addon today means sending a URL they must paste — friction the Watch Together flow already solved for rooms.
6. **Discoverability.** Nothing in Home/Discover tells the user more content is one tap away.

## 3. Build plan

### A — Curated Addon Store (the flagship, ship first)
- New `lib/services/addon/addon_directory.dart`: a **data-only list** (JSON asset, updated by release) of vetted addons: `{id, name, oneLine (Easy English), category, languages[], sFW: bool, manifestUrl, icon}`.
- New page `lib/pages/addons/addon_store_page.dart`: grid/list by category — *Subtitles*, *Indian Cinema*, *Anime*, *Music/TV*, *Debrid & P2P* — each card = name + one line + **Install** button (one tap, calls existing `AddonManager.addAddon(url)`), installed state flips to "Added ✓" + toggle.
- Entry points: Settings → Addons gets a **"Browse addons"** hero row; Discover page gets a small "More sources" card after first empty result.
- **Acceptance:** fresh install → Discover → tap → install → home rail appears, ≤3 taps, zero typing.

### B — India pack (languages + catalogs)
- Seed the directory with India-relevant entries (Hindi/Tamil/Telugu/Malayalam/Bengali subtitle providers, Indian catalog/meta addons, fanart), each verified by a real manifest fetch before it ships.
- Language preference row in the store ("Hindi / Tamil / …") that sorts + auto-suggests; wired to the existing subtitle provider ordering (`subtitle_service.dart`).
- **Acceptance:** a Hindi movie search shows Hindi subtitle addons suggested first; no manual URL ever typed.

### C — Health + trust
- `AddonHealthService`: every 6h + on app resume, ping active addons' `manifest.json` (through DizzyNet — retry/breaker for free), record last-ok/last-fail.
- Show per-addon chip in Settings → Addons: green "working" / amber "slow" / red "not responding", with Easy English helper ("This one is down — Dizzy is skipping it").
- Dead-addon auto-skip is already implicit (scrapers/quarantine pattern) — expose it, don't invent new behavior.
- **Acceptance:** kill a network path for one addon → chip turns red within one refresh → user sees an Easy English line, never a stack trace.

### D — Share install (QR + link)
- "Share this addon" → native share sheet with `dizzy://addon/<encoded manifest url>` deep link; receiver's Dizzy opens a confirm sheet → installs. QR rendering for in-person sharing (reuse `RepaintBoundary` share-card machinery from Wrapped).
- **Acceptance:** two phones, zero typing, install in <10s.

### E — Public/family defaults (launch guard)
- Directory entries ship `sFW`-flagged; public build defaults to SFW-only listing (adult/dubious entries hidden unless Settings → Privacy → "Show all addons" is flipped — mirrors the existing adult-first/PIN posture).
- Rate-limit manifest fetches through DizzyNet (no burst on small addon hosts), and never log addon URLs into `device_logs` (privacy contract in `AppErrorLog`).

## 4. Sequencing & effort

| Phase | Effort | Ship gate |
|---|---|---|
| A — Store | ~1 day | 3-tap install on a fresh install |
| B — India pack | ~0.5 day | manifest-verified entries only |
| C — Health | ~0.5 day | red chip + Easy English line proven offline |
| D — Share/QR | ~1 day | phone-to-phone install |
| E — SFW defaults | ~0.5 day | launch checklist item |

All phases ride on existing code (`AddonManager`, `DizzyNet`, guide cards, share sheet) — no backend changes required; the directory ships as a JSON asset so it can be updated without an app release.

## 5. Risks

- **Directory staleness** → JSON asset shipped in-app; entries verified by CI job (manifest fetch) before release.
- **Third-party addon hosts dying** → Phase C makes it visible instead of silent; Dizzy's own scrapers/TorrServer remain the fallback.
- **Legal/ToS posture** → same as today: Dizzy ships no pirated content and no addon URLs; users install what they choose from the store we curate. Keep the existing "no API keys in APK" and privacy rules.
