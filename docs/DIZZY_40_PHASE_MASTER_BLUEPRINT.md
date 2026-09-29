# Dizzy-v3: 40-Phase Master Blueprint
## Studio-Grade Industrial Tactile Hardware UI
### Boss Pocket GT / EQ-200 Inspired — Dual Light (Anodized Aluminum) & Dark (Studio Obsidian OLED)

**Generated:** Session analysis of `C:/Users/opcha/Downloads/Dizzy-v3`
**Repository State:** Branch `main`, clean working tree
**Constraint Checklist:** Zero GPU shader blurs for chrome, <=3GB RAM, <=20% CPU, Easy English copy, anonymous-first, tactile OLED design rules.

---

## PART A — CURRENT ARCHITECTURE MAP

### Existing Subsystems (verified)

| Layer | Key Files | Status |
|-------|-----------|--------|
| **Design Tokens** | `lib/design/dizzy_tokens.dart`, `lib/design/dizzy_tactile.dart` | ✅ Exists — `DizzyVoid`, `DizzyGlow`, `DizzyShadow`, `DizzyEdge` color/constants defined |
| **Theme Service** | `lib/services/theme/app_theme_service.dart` | ⚠️ Partial — 6 palettes exist but no true OLED Silver/Aluminum light theme |
| **Tactile Widgets** | `dizzy_tactile_button.dart`, `dizzy_tactile_card.dart`, `dizzy_tactile_dock.dart` | ✅ Exists — invert-gradient on press, haptic feedback, static shadows |
| **Home Hub** | `lib/pages/home/home_page.dart` (2000 lines) | ⚠️ Uses `liquid_glass_easy` package + `AnimatedAmbientBackground` (shader-based) |
| **Watch Party** | `party_session.dart`, `watch_sync_engine.dart`, `guest_auto_open.dart` | ✅ Core exists — host sync math, guest auto-open, prewarm cache all wired |
| **Music Player** | `music_player_controller.dart` (594 lines) | ✅ Full — play/pause/seek/shuffle/repeat/crossfade/Discord RPC |
| **Music EQ** | `music_equalizer_service.dart` | ✅ Exists — 5-band EQ + bass boost + spatializer + dynaudnorm |
| **Video Player** | `lib/pages/player/watch_screen.dart` (3554 lines), `WatchResolveController` | ⚠️ Complex but lacks explicit audio conflict resolution |
| **Torrent Stream** | `lib/services/stream/torrent_stream_service.dart` | ✅ TorrServer engine, port allocation, swarm stats |
| **Download Service** | `lib/services/download/download_service.dart` (804 lines) | ✅ TorrServer + HTTP Range + HLS, connectivity auto-pause/resume |
| **Media Coordinator** | `lib/services/media/global_media_coordinator.dart` | ✅ Exists — resolves music+video conflicts |
| **Scraper Quarantine** | `lib/services/scraper/scraper_quarantine_service.dart` | ⚠️ Exists but no UI integration in settings |
| **Social** | `dizzy_identity_service.dart`, `dizzy_social_service.dart`, `dizzy_friend_service.dart` | ✅ Anonymous-first, friend graph CRUD |
| **Profiles** | `lib/models/profiles/dizzy_profile.dart`, `profile_service.dart` | ✅ Multi-profile with PIN |
| **Anime** | `lib/pages/anime/anime_page.dart` (1259 lines) | ⚠️ Uses `liquid_glass_easy` |
| **Manga** | `lib/pages/manga/manga_page.dart` (1082 lines) | ⚠️ Uses `liquid_glass_easy` |
| **Discover** | `lib/pages/discover/discover_page.dart` | ❌ Uses `BackdropFilter(ImageFilter.blur())` at line 100 — **violates OLED rules** |
| **Settings** | `lib/pages/settings/settings_page.dart` (1091 lines) | ⚠️ Has `LiquidGlassSettingsPage` which exposes glass shaders |
| **Dock** | `lib/widgets/common/app_liquid_dock.dart` | ⚠️ Uses `liquid_glass_easy` package |
| **Main** | `lib/main.dart` (280 lines) | ✅ ResourceGovernor, PerformanceMode, image caps all wired |

### Confirmed GPU Shader Violations (must replace per OLED rules)

1. **`lib/pages/discover/discover_page.dart:100`** — `BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15))` on app bar
2. **`lib/widgets/common/app_liquid_dock.dart`** — uses `liquid_glass_easy` package (GPU blur shaders)
3. **`lib/widgets/common/performance_liquid_lens.dart`** — uses `liquid_glass_easy` as fallback when glass enabled + perf allows
4. **`lib/widgets/common/animated_ambient_background.dart`** — "aurora waves, gradient meshes" (shader-based animated background)
5. **`lib/pages/anime/anime_page.dart`** — imports `liquid_glass_easy`
6. **`lib/pages/manga/manga_page.dart`** — imports `liquid_glass_easy`
7. **`lib/pages/home/home_page.dart`** — imports `liquid_glass_easy` and `animated_ambient_background`
8. **`lib/pages/settings/appearance/liquid_glass_settings_page.dart`** — entire page is about enabling/disabling GPU glass shaders
9. **`lib/services/theme/glass_settings.dart`** — settings engine for GPU shader parameters (should be deprecated)

### Confirmed Missing Wirings

1. **Watch Together guest autoplay**: Core logic works (GuestAutoOpen, GuestFollowService) but no integration test verifying actual video playback sync. Also: no UI progress indicator during 20s resolve timeout — user sees toast only.
2. **Audio/video conflict resolution**: `GlobalMediaCoordinator` exists and `MusicPlayerController` has `onPauseVideoRequest` callback, but the actual wiring from `WatchScreen` to `GlobalMediaCoordinator.notifyVideoStarted()` is unclear. Need verification.
3. **Scraper health monitoring**: `scraper_quarantine_service.dart` exists but `settings_page.dart` imports `scraper_health_page.dart` — need to verify it has functional UI.
4. **Download resume**: Both HLS and torrent download engines support resume, but no explicit test verifying partial download recovery.
5. **Light theme (Anodized Aluminum)**: `AppThemePalette` has `isMetallic` flag but all 6 palettes use dark `scaffoldBackgroundColor` (`0xFF090A0D`). No true light OLED mode exists.
6. **7-segment / dot-matrix displays**: No widgets exist for hardware-style numeric displays.
7. **Rotary dial / EQ fader / tactile stomp pad**: No widget primitives for these hardware controls.

---

## PART B — THE 40 PHASES

---

### PHASES 1–10: DESIGN SYSTEM & CORE HARDWARE SKEUOMORPHIC PRIMITIVES

#### Phase 1: Kill All GPU Shader Blur Shaders (Critical Path)
**Goal:** Replace every `BackdropFilter`, `ImageFilter.blur`, and `liquid_glass_easy` usage in app chrome with pure `BoxDecoration` + `LinearGradient` + static `BoxShadow`.
**Files to modify:**
- `lib/pages/discover/discover_page.dart` — Replace `BackdropFilter` app bar with `Container` + `LinearGradient` + static border (1px hairline). Use `DizzyShadow.card` for depth.
- `lib/widgets/common/app_liquid_dock.dart` — Replace `liquid_glass_easy` `Glass` widget with `Container` + `LinearGradient` from `DizzyGradients.surface` + `DizzyShadow.dock` box shadows.
- `lib/widgets/common/performance_liquid_lens.dart` — Remove `liquid_glass_easy` dependency entirely. Fallback decoration already exists — make it the ONLY rendering path. Delete the conditional that enables glass when perf allows.
- `lib/widgets/common/animated_ambient_background.dart` — Replace shader-based "aurora waves / gradient meshes" with a `Ticker`-driven `AnimationController` that animates a set of `Container` overlays with `AnimatedPositioned` + `LinearGradient` shifts (no shader blurs). Keep the `PerformanceMode.ambientAllowed` gate.
- `lib/pages/anime/anime_page.dart` — Remove `liquid_glass_easy` import, replace any `Glass` widgets with tactile `Container` equivalents.
- `lib/pages/manga/manga_page.dart` — Same treatment as anime.
- `lib/pages/home/home_page.dart` — Remove `liquid_glass_easy` and `animated_ambient_background` imports. Replace glass widgets.
- `lib/pages/settings/appearance/liquid_glass_settings_page.dart` — Deprecate. Replace with `Tactile Theme Settings` page that controls OLED palette, accent color, and tactile depth (no shader parameters).
**Verification:** Run `flutter analyze` (zero issues), search repo for `BackdropFilter`, `ImageFilter.blur`, `liquid_glass_easy` (zero results).

#### Phase 2: True Light Theme — Anodized Aluminum OLED
**Goal:** Add a fully-realized Light Mode palette pair that matches the Dark Studio Obsidian OLED.
**Files to modify:**
- `lib/services/theme/app_theme_service.dart` — Add `AppThemePalette` entries:
  - `anodized_aluminum` (id: `'light_aluminum'`): primary `0xFFB0B8C8`, accent `0xFFE50914`, scaffold `0xFFE8EAED`, card `0xFFFFFFFF`, appBar `0xFFD8DADF`, silverAccent `0xFF1A1D26`, amberAccent `0xFFFFC107`, isMetallic `true`
  - `polished_silver` (id: `'light_silver'`): primary `0xFF8A93A3`, accent `0xFFE50914`, scaffold `0xFFF5F5F7`, card `0xFFFFFFFF`, appBar `0xFFE0E2E6`, silverAccent `0xFF0A0C10`, amberAccent `0xFFFFC107`, isMetallic `true`
- Add `isLight` getter to `AppThemePalette`.
- `lib/design/dizzy_tokens.dart` — Add `DizzyLight` abstract class with `boneDark` (`0xFF1A1D26`), `ashDark` (`0xFF66666B`), `surfaceLight1-3` inverted tokens.
- `lib/widgets/tactile/dizzy_tactile_card.dart` — Make `DizzyShadow` values swap based on theme (dark shadows on light bg, light shadows on dark bg).
- `lib/widgets/tactile/dizzy_tactile_button.dart` — Make invert-gradient logic aware of light/dark context.
**Verification:** Test both palettes render correctly (analyze passes, widget tests check color values).

#### Phase 3: Rotary Dial Widget
**Goal:** Build a tactile rotary dial (like Boss Pocket GT knob) using pure `CustomPainter` — zero shaders.
**Files to create:** `lib/widgets/tactile/dizzy_rotary_dial.dart`
**Spec:**
- `CustomPainter` that draws concentric circles with `Paint` + `Rect` gradients (anodized metal look).
- Tick marks at 0°, 90°, 180°, 270° using `canvas.drawLine`.
- Knob position calculated from touch angle via `atan2`.
- `ValueListenableBuilder` for value changes, no `AnimationController`.
- Haptic feedback on tick detents (use `HapticFeedback.lightImpact`).
- Supports `min`, `max`, `value`, `onChanged`, `segments` (e.g., 12 detents for volume).
**Constraints:** < 200 lines, no `BackdropFilter`, no `ShaderMask`, `Paint` + `Rect` + `Path` only.

#### Phase 4: EQ Fader Widget (7-Band Hardware Equalizer)
**Goal:** Build vertical faders for music EQ visualization (like Boss EQ-200 sliders).
**Files to create:** `lib/widgets/tactile/dizzy_eq_fader.dart`, `lib/widgets/tactile/dizzy_eq_panel.dart`
**Spec:**
- `dizzy_eq_fader.dart`: Vertical slider with tactile groove (drawn via `CustomPaint`), colored fill bar (`DizzyGlow.red` → `DizzyGlow.beam` gradient), knob with static shadow.
- `dizzy_eq_panel.dart`: 5-7 `dizzy_eq_fader` widgets in a row with labels (60Hz, 250Hz, 1kHz, 4kHz, 16kHz), plus `MusicEqualizerService` integration.
- Ties into `MusicEqualizerService.instance.bandGains` via `ValueListenableBuilder`.
- No GPU shaders — all drawing via `CustomPainter` with `LinearGradient` + `BoxShadow`.
**Constraints:** Each fader < 150 lines, panel < 200 lines.

#### Phase 5: 7-Segment & Dot-Matrix Display Widgets
**Goal:** Build hardware-style number displays (like LED/LCD on Boss pedals).
**Files to create:** `lib/widgets/tactile/dizzy_7segment.dart`, `lib/widgets/tactile/dizzy_dotmatrix.dart`
**Spec:**
- `dizzy_7_segment.dart`: Custom painter that draws a 7-segment digit display (a,b,c,d,e,f,g segments) for any 0-9 digit. Color: `DizzyGlow.red` (active) / `DizzyVoid.surface3` (off). Supports multi-digit via `digits` parameter.
- `dizzy_dot_matrix.dart`: Custom painter that renders text/numbers via a 5x7 dot grid. Color: `DizzyGlow.beam` (cyan) or `DizzyGlow.volt` (green). Supports scrolling text animation (via `AnimationController`, no shader — just `Offset` animation).
- Both support dark mode only (OLED — black background = off pixels).
**Constraints:** Pure `CustomPainter` + `Path` + `Paint`. No text rendering via `Text` widget (draw segments/dots manually for authentic look).

#### Phase 6: Tactile Stomp Pad Widget
**Goal:** Build a grid of pressable tiles (like Boss footswitch array).
**Files to create:** `lib/widgets/tactile/dizzy_stomp_pad.dart`, `lib/widgets/tactile/dizzy_stomp_grid.dart`
**Spec:**
- `dizzy_stomp_pad.dart`: Single tile with `BoxDecoration` (gradient from `DizzyVoid.surface3` to `DizzyVoid.surface2`), static `BoxShadow` for depth, pressed state swaps gradient to `DizzyGlow.red` at 20% opacity.
- Haptic feedback on tap (`HapticFeedback.mediumImpact`).
- `dizzy_stomp_grid.dart`: Grid of pads (2x6 or 4x4) with optional labels.
- Each pad is a `GestureDetector` (not `InkWell`) for raw press handling.
**Constraints:** < 150 lines per file. No `Material` widget with default ink effects.

#### Phase 7: Theme Switch Controller (Light ↔ Dark OLED)
**Goal:** Build a global theme switch that toggles between Dark Studio Obsidian OLED and Light Anodized Aluminum, propagating through all widgets.
**Files to modify:**
- `lib/services/theme/app_theme_service.dart` — Add `currentThemeId` `ValueNotifier<String>`, `switchTheme(String id)` method.
- `lib/main.dart` — Wrap `MaterialApp` with `ValueListenableBuilder` on theme id, set `brightness` and `colorScheme` accordingly.
- `lib/design/dizzy_tactile.dart` — Make all token classes respond to `AppThemeService.currentThemeId`.
- `lib/widgets/tactile/dizzy_tactile_button.dart`, `dizzy_tactile_card.dart` — Theme-aware rendering.
**Verification:** Theme toggle switches ALL screens without rebuild lag (use `ValueListenableBuilder`, not `setState`).

#### Phase 8: DizzyGradients — Static Gradient Library
**Goal:** Centralize all gradient definitions for tactile surfaces.
**Files to modify:** `lib/design/dizzy_tactile.dart` (add to existing)
**Add:**
- `DizzyGradients.surface`: Linear gradient `DizzyVoid.surface2` → `DizzyVoid.surface1` (top → bottom) for cards
- `DizzyGradients.raised`: `DizzyVoid.surface3` → `DizzyVoid.surface2` for floating elements
- `DizzyGradients.silver`: `Color(0xFFFFFFFF)` → `Color(0xFFC0C8D4)` (light mode anodized)
- `DizzyGradients.darkMetal`: `Color(0xFF3A3E4A)` → `Color(0xFF1C202C)` (dark mode metallic)
- `DizzyGradients.accent`: `DizzyGlow.red` → `DizzyGlow.ember` for primary actions
**Constraint:** All gradients are `const` where possible. No `ShaderMask` usage.

#### Phase 9: Tactile Card 2.0 — Extruded Depth System
**Goal:** Upgrade tactile cards with multi-tier depth system (3 levels).
**Files to modify:** `lib/widgets/tactile/dizzy_tactile_card.dart`
**Add:**
- `DizzyCardTier.small` (1px shadow offset, `blurRadius: 4`) — for list items
- `DizzyCardTier.medium` (2px shadow offset, `blurRadius: 10`) — for cards
- `DizzyCardTier.large` (4px shadow offset, `blurRadius: 20`) — for modals/dialogs
- `elevation` parameter maps to tiers. Each tier has a static `BoxDecoration` + `BoxShadow` definition.
- On press: card shifts 2px up (use `Transform.translate`) + brighter gradient (not shader).
**Verification:** Analyze passes, widget test checks 3 tiers render distinct shadows.

#### Phase 10: Audio/Video Conflict Resolution Wiring Verification
**Goal:** Verify and harden the `GlobalMediaCoordinator` ↔ `WatchScreen` ↔ `MusicPlayerController` conflict resolution chain.
**Files to inspect:** `lib/pages/player/watch_screen.dart`, `lib/services/media/global_media_coordinator.dart`, `lib/services/music/music_player_controller.dart`
**Actions:**
- Verify `WatchScreen` calls `GlobalMediaCoordinator.instance.notifyVideoStarted()` when playback starts.
- Verify `WatchScreen` calls `.notifyVideoStopped()` or `.notifyVideoMinimized()` when navigating away.
- Verify `MusicPlayerController` registers `onPauseVideoRequest` callback from `GlobalMediaCoordinator`.
- If any link is missing, add the wiring. Add comment markers `// WIRED: conflict resolution` at each link.
- Write a test that music pauses when video starts and resumes when video stops.
**Deliverable:** Verified wiring + test in `test/media/conflict_resolution_test.dart`.

---

### PHASES 11–20: MEDIA PLAYBACK, INSTANT SYNC & FLAGSHIP ENGINES

#### Phase 11: Watch Together — Guest Sync Integration Test
**Goal:** End-to-end test verifying host→guest sync works with real video playback.
**Files:** `test/watchparty/watch_together_integration_test.dart` (new)
**Actions:**
- Mock `WatchPartyService` events.
- Host sends `WatchSyncMessage` via `party_session`.
- Guest receives via `GuestFollowService` → `GuestAutoOpen.handle()`.
- Verify guest `PartySession` updates `mediaRef`, `chapterIndex`, `pageIndex`.
- Verify `WatchSyncEngine.targetPosition()` computes correct position within <50ms drift.
- Verify `GuestAutoOpen.prewarm()` caches metadata in ≤2 seconds.
- Verify timeout toast displays correctly (20s resolve timeout).

#### Phase 12: Watch Together — Resolve Timeout UX Fix
**Goal:** Replace the raw 20s `TimeoutException` toast with a graceful countdown UI.
**Files to modify:** `lib/services/watchparty/guest_auto_open.dart`
**Actions:**
- Add `ResolveTimeoutWidget` (uses `CountdownTimer`-style `AnimationController`, 20 seconds) showing remaining resolve time.
- On timeout, show "Ask host to pick a popular title" with a retry button.
- The prewarm cache should show a "Resolving..." indicator using `dizzy_7segment` (Phase 5 widget).

#### Phase 13: Music M1 — M3U/PLS Playlist Import
**Goal:** Import local M3U/PLS playlists into the music library.
**Files to create:** `lib/services/music/music_playlist_import_service.dart`
**Actions:** Parse M3U/PLS format, extract track metadata (title, artist, duration, URL), create `MusicTrack` objects, persist via `MusicLibraryService`. Add UI entry point in music page.

#### Phase 14: Music M2 — Hardware EQ Visual Mapping
**Goal:** Map the existing `MusicEqualizerService` (5-band + bass boost + spatializer) to Phase 4 EQ faders.
**Files to modify:** `lib/widgets/tactile/dizzy_eq_panel.dart` (from Phase 4)
**Actions:** Wire `MusicEqualizerService.instance.bandGains` to Phase 4 fader widgets. Save/restore presets via `SharedPreferences`. Add `DizzyGlow.volt` active indicator on each fader.

#### Phase 15: Music M3 — Crossfade Engine Refinement
**Goal:** The existing crossfade (`_executeCrossfadeNext` in music player) works but has hardcoded timing. Make it configurable and visually show the crossfade progress.
**Files to modify:** `lib/services/music/music_player_controller.dart`
**Actions:** Make crossfade duration configurable (default 6s). Add a `ValueNotifier<double>` for crossfade progress (0.0 → 1.0) for UI visualization.

#### Phase 16: Music M4 — Chromecast / Cast Discovery (Fallback)
**Goal:** Add Simplecast/Chromecast device discovery as a secondary audio output.
**Files to create:** `lib/services/music/music_cast_service.dart`
**Actions:** Simplecast protocol discovery via UDP (mDNS), cast audio stream URL to discovered device. Fail-soft: if no device found, play locally. No external packages — pure Dart socket + XML parsing.

#### Phase 17: Manga Discrete Page Turn Sync
**Goal:** Implement discrete page turn sync for manga reader (already partially in PartySession with `pageIndex`).
**Files to modify:** `lib/pages/manga/manga_reader_page.dart`, `lib/services/watchparty/party_session.dart`
**Actions:** When in a "Read Together" party, sync `pageIndex` events via `PartySession.updateCoExperience()`. Add `pageIndex` parameter to `WatchSyncMessage` (already exists in model). Add discrete page turn events in manga reader.

#### Phase 18: Manga Reader — Tactile Page Flip Animation
**Goal:** Replace manga page transitions with tactile hardware page flip animation.
**Files to modify:** `lib/pages/manga/manga_reader_page.dart`
**Actions:** Use `AnimatedBuilder` with `PageFlipPainter` (CustomPainter) that draws a "paper curl" effect using gradients and static shadows only. No shader blurs. Page direction (left/right) determined by gesture.

#### Phase 19: Torrent/Debrid Streaming — Resume Verification
**Goal:** Verify and document download resume for both HLS and torrent engines.
**Files to inspect:** `lib/services/download/hls_download_engine.dart`, `lib/services/download/download_service.dart`
**Actions:**
- Test: Start download → kill app → restart → verify download resumes from `.part` file.
- Test: Pause → resume → verify byte range continues from last position.
- Add `download_resume_test.dart` with these tests.
- Fix any resume bugs found.

#### Phase 20: Scrapers — Health Dashboard UI
**Goal:** Wire `scraper_quarantine_service.dart` into settings UI with a functional health dashboard.
**Files to modify:** `lib/pages/settings/scraper_health_page.dart`
**Actions:**
- Display all scrapers (from `scraper_quarantine_service`) with status: Healthy / Quarantined / Degraded.
- Show error counts, last failure reason, average response time.
- "Restore All" button (calls quarantine service reset).
- "Test" button per scraper (runs single check).
- Use `DizzyGlow.volt` for healthy, `DizzyGlow.red` for errors, `DizzyGlow.beam` for degraded.

---

### PHASES 21–30: ALL MAIN SCREENS & HUBS END-TO-END OVERHAUL

#### Phase 21: Home — Remove All Shader Elements + Tactile Cards
**Goal:** Home page uses zero GPU blur shaders, all tactile cards and gradients.
**Files to modify:** `lib/pages/home/home_page.dart`
**Actions:**
- Remove `liquid_glass_easy` import.
- Replace `AnimatedAmbientBackground` with a static `TiledBackground` widget (uses `GridTile` with `LinearGradient` patterns, animated via `AnimationController` that shifts `Alignment` not `Filter`).
- Replace movie/show cards with `DizzyTactileCard` (Phase 9).
- Replace `continue_watching_slider` with `DizzyStompGrid` (Phase 6) or `DizzyTactileButton` array.
- Use `DizzyGradients.surface` for all section containers.

#### Phase 22: Home — Trending Now Section (Pure Pull)
**Goal:** Home Trending section is pure-pull, cached 30min, never throws.
**Files to modify:** `lib/pages/home/home_page.dart` (already has `buildTrendingSection`)
**Actions:** Verify the trending section: (1) pulls from `AddonManager`, (2) maps to `Movie` via `tmdb:${c.id}`, (3) has 30-min cache, (4) shows nothing (not error) when empty/offline. Add widget test verifying empty → no section.

#### Phase 23: Discover — Remove BackdropFilter
**Goal:** Fix the confirmed `BackdropFilter` violation on Discover page.
**Files to modify:** `lib/pages/discover/discover_page.dart`
**Actions:** Replace the `BackdropFilter` app bar (line 100) with `Container` + `LinearGradient` + static border + `DizzyShadow.card`. The app bar uses `Color(0xFF0A0C16).withValues(alpha: 0.6)` which becomes a static gradient. Verify no `BackdropFilter` remains.

#### Phase 24: Search — Universal Spotlight Modal Tactile Treatment
**Goal:** Upgrade search modal to tactile design.
**Files to modify:** `lib/pages/search/universal_spotlight_modal.dart`
**Actions:** Replace glass/blur elements with `DizzyTactileCard`. Use `DizzyEdge.neon` for active/focused search field border. Use `DizzyGlow.beam` for search icon active state.

#### Phase 25: Movies/TV — Movie Card Tactile Upgrade
**Goal:** All movie/TV cards use tactile design with hover/press states.
**Files to modify:** `lib/widgets/movie/movie_card.dart`
**Actions:** Replace default `Material` card with `DizzyTactileCard`. Add hover effect via `MouseRegion` + `onEnter`/`onExit` changing the card gradient (not shader). Press effect uses `DizzyGradients.accent` overlay at 15% opacity.

#### Phase 26: Anime — Liquid Glass Removal + Section Tactile Treatment
**Goal:** Anime page removes `liquid_glass_easy`, all sections use tactile cards.
**Files to modify:** `lib/pages/anime/anime_page.dart`
**Actions:** Remove `liquid_glass_easy` import. Replace `Glass` widgets with `DizzyTactileCard`. Update section sliders to use `DizzyEdge.neon` borders. Anime detail modal uses `DizzyGradients.surface` background.

#### Phase 27: Music — Tactile Treatment for All Music Screens
**Goal:** Music page (1252 lines) fully tactile.
**Files to modify:** `lib/pages/music/music_page.dart`, `lib/pages/music/widgets/music_*`
**Actions:**
- Remove all `liquid_glass_easy` references in music page.
- Sidebar uses `DizzyTactileCard` for section list items.
- Top header uses `DizzyGradients.surface` + `DizzyShadow.card`.
- Bottom player bar uses `DizzyTactileCard` with play/pause stomp pad buttons (Phase 6).
- Album art card uses `DizzyTactileCard` with hover lift.
- Search bar uses `DizzyEdge.hairline` border, `DizzyVoid.voidB` background.

#### Phase 28: Books — E-Reader Page Turn Tactile Animation
**Goal:** Book reader page turn uses tactile animation.
**Files to modify:** `lib/pages/books/epub_reader_page.dart`, `lib/widgets/books/`
**Actions:** Add `PageFlipPainter` CustomPainter (shared with manga Phase 18). Animate via `AnimationController` with `CurvedAnimation` (ease-out). Gradient + shadow for page curl. No shaders.

#### Phase 29: Settings — Theme/Appearance Overhaul
**Goal:** Settings page fully tactile, Liquid Glass settings deprecated.
**Files to modify:** `lib/pages/settings/settings_page.dart`, `lib/pages/settings/appearance_settings_page.dart`, `lib/pages/settings/appearance/liquid_glass_settings_page.dart`
**Actions:**
- Replace `LiquidGlassSettingsPage` with `TactileThemeSettingsPage` (Phase 7 + Phase 8).
- Settings tiles use `DizzyTactileCard` with switch/toggle.
- Section headers use `DizzyEdge.hairline` divider.
- Deprecate `glass_settings.dart` (mark with `@Deprecated` annotation).

#### Phase 30: Social — DMs, Profiles, Friends Full Tactile
**Goal:** Social screens (DMs, profiles, friend list) fully tactile.
**Files to modify:** `lib/pages/social/direct_message_page.dart`, `lib/pages/social/instagram_profile_page.dart`
**Actions:**
- DM message bubbles: `DizzyTactileCard` (sent: `DizzyGlow.red` at 10%, received: `DizzyVoid.surface3`).
- Profile avatar ring uses `DizzyEdge.neon` (online=green, offline=ash).
- Friend cards use `DizzyTactileCard` with status indicator dot (`DizzyGlow.volt` for online).
- Send button uses `DizzyGradients.accent`.

---

### PHASES 31–40: HARDWARE EDGE CASES, SETTINGS, MICRO-INTERACTIONS, 120 FPS, SECURITY & RELEASE

#### Phase 31: Offline Banner — Universal Offline Fail-Soft
**Goal:** Add offline banner to every page automatically.
**Files to create:** `lib/widgets/common/offline_banner_connectivity.dart` (upgraded)
**Actions:**
- Listen to `Connectivity().onConnectivityChanged`.
- When offline: show `DizzyTactileCard` banner at top of every `Scaffold` with "No internet. Waiting…" in Easy English.
- When back online: banner slides away (animated `Positioned` + `AnimationController`, no shader).
- Auto-pauses active downloads (already in DownloadService).
- Auto-resumes net-paused downloads (already in DownloadService).
- All pages wrap `Scaffold` with banner via a `OfflineAwareScaffold` widget.

#### Phase 32: Resource Governor Integration — Perf Mode UI
**Goal:** Show current performance mode (Smooth/Low-End/Normal) in settings and respond to resource governor events.
**Files to modify:** `lib/pages/settings/appearance_settings_page.dart`, `lib/services/system/resource_governor.dart`
**Actions:**
- Display current mode: Normal / Smooth Mode (≤3GB RAM) / Low-End Mode (tight resources).
- User can override: Normal → Smooth → Low-End (one-way downgrade).
- When ResourceGovernor triggers GPU breach: auto-enable Smooth Mode + kill ambient background.
- Show RAM/CPU usage indicator in developer settings (sampled, not polling).

#### Phase 33: 120 FPS Lock — Targeted Frame Rate Governance
**Goal:** Ensure 60-120 FPS on budget phones through targeted optimizations.
**Files to modify:** `lib/utils/perf/performance_mode.dart`, `lib/services/system/resource_governor.dart`
**Actions:**
- `PerformanceMode` already exists — add `targetFrameRate` `ValueNotifier<int>` (60, 90, 120).
- On low-end devices: force 60 FPS (lower refresh rate saves battery AND prevents thermal throttling).
- Add `RepaintBoundary` wrapping around animated islands only (vinyl spin, progress bars, EQ faders).
- Verify no `BackdropFilter` in the widget tree during normal operation (only in fully-deprecated settings preview).
- Run `flutter analyze` on all files.

#### Phase 34: Micro-Interactions — Haptic Feedback Everywhere
**Goal:** Add haptic feedback to all tactile interactions.
**Files to modify:** `lib/widgets/tactile/dizzy_tactile_button.dart`, `dizzy_tactile_card.dart`, `dizzy_tactile_dock.dart`, `dizzy_stomp_pad.dart` (from Phases 6, 9)
**Actions:**
- `DizzyTactileButton`: `HapticFeedback.lightImpact` on tap, `HapticFeedback.mediumImpact` on long-press.
- `DizzyTactileCard`: `HapticFeedback.lightImpact` on press.
- `DizzyTactileDock`: `HapticFeedback.mediumImpact` on tab switch.
- `DizzyStompPad`: `HapticFeedback.mediumImpact` on tap.
- EQ Fader (Phase 4): `HapticFeedback.click` on detent snap.
- Rotary Dial (Phase 3): `HapticFeedback.lightImpact` on tick detent.

#### Phase 35: Settings — Comprehensive Audit & Fix
**Goal:** Verify all settings sub-pages are wired correctly and use tactile design.
**Files to audit:** All `lib/pages/settings/**/*.dart`
**Actions:**
- Check each settings page: does it use tactile cards? No glass blur? Easy English copy?
- Add missing settings entries from spec:
  - Download settings (pause/resume/location)
  - Scraper health (Phase 20)
  - Watch party settings (create/join/leave room)
  - Privacy settings (friend visibility, profile visibility)
- Ensure all settings tiles use `DizzyTactileCard` or `DizzyTactileButton`.

#### Phase 36: Security Hardening — Anonymous-First Verification
**Goal:** Verify anonymous-first architecture is intact and cannot be bypassed.
**Files to inspect:** `lib/main.dart`, `lib/services/social/dizzy_identity_service.dart`, `lib/pages/home/home_page.dart`
**Actions:**
- Verify app launches without any auth dialog.
- Verify `DizzyIdentityService` creates anonymous ID on first boot.
- Verify no route in `nav_key.dart` requires login.
- Add `test/security/anonymous_first_test.dart` verifying:
  - App starts without cloud connection.
  - No auth screen is the initial route.
  - User ID is generated from HWID hash + 7-digit DIZ code.
- Verify `CloudAuthService` is non-blocking in `main()`.

#### Phase 37: Security — RLS Policy Verification
**Goal:** Verify all Supabase RLS policies are correctly enforced.
**Files to inspect:** `supabase/migrations/` (all SQL migration files)
**Actions:**
- Verify `friendships` table has INSERT/UPDATE/DELETE policies (added in earlier Phase 2 work).
- Verify `dm_messages` table has proper RLS policies.
- Verify `profiles` table policies.
- Add a check script (Dart test or shell script) that verifies migration SQL contains RLS policies for all write-enabled tables.

#### Phase 38: Easy English Audit — All User-Facing Copy
**Goal:** Scan all user-facing strings for technical jargon.
**Files to scan:** All `*.dart` in `lib/`
**Actions:**
- Search for forbidden terms in strings/literals: `socket`, `timeout`, `debrid`, `scraper`, `RPC`, `exception`, `null`, `nil`, `Error`, `Failed`, `Crash`.
- Replace with Easy English equivalents: "Connection problem", "Took too long", "Content source", "Search tool", "Message", "Problem", "Something went wrong".
- Fix any found violations. Add automated test that fails if forbidden terms appear in user-visible strings.

#### Phase 39: Production Release Hardening — Build Artifact Verification
**Goal:** Verify all release artifacts build cleanly.
**Files:** Build scripts and configs
**Actions:**
- Run `flutter build apk --split-per-abi` (verify 3 APKs: arm64-v8a, armeabi-v7a, x86_64).
- Run `flutter build windows` (verify EXE builds).
- Verify artifact sizes are reasonable (no debug symbols in release).
- Run `flutter analyze` on entire project one final time.
- Run full test suite one final time.
- Note: do NOT push or tag — user tests first per standing rules.

#### Phase 40: Documentation & Blueprint Finalization
**Goal:** Document all architectural decisions, wire up remaining gaps.
**Files to create:** `docs/DIZZY_40_PHASE_IMPLEMENTATION_REPORT.md`, `docs/DIZZY_TACTILE_GUIDELINES.md`
**Actions:**
- Document which phases are complete, which are in progress, which are blocked.
- Record all files modified per phase.
- Document all "broken wiring" found and how it was fixed.
- Create `TACTILE_CHECKLIST.md` — a checklist for future contributors to verify OLED/tactile rules are maintained.
- Archive deprecated files (`glass_settings.dart`, `LiquidGlassSettingsPage`) with `@Deprecated` annotations and migration notes.

---

## PART C — CRITICAL DEPENDENCY GRAPH

```
Phase 1 (Kill Shaders) ──────────┐
    │                            ▼
    ├─→ Phase 7 (Theme Switch) → Phase 2 (Light Theme)
    │                           ▼
    └─→ Phase 8 (Gradients) ──→ Phase 9 (Card 2.0) ──→ Phase 21 (Home overhaul)
Phase 3 (Rotary Dial) ────→ Phase 4 (EQ Fader) ────→ Phase 14 (EQ Mapping)
Phase 5 (7-Segment/Matrix) → Phase 12 (Resolve Timeout UI)
Phase 6 (Stomp Pad) ──────→ Phase 34 (Haptics)
Phase 10 (AV Conflict) ────→ Phase 36 (Security audit)
Phase 11 (Guest Sync Test) → Phase 19 (Resume Verification)
Phase 23 (Discover fix) ───→ Phase 1 (Kill Shaders) [dependency]
Phase 20 (Scraper Health)  → Phase 35 (Settings audit)
Phase 25 (Movie Cards) ────→ Phase 21 (Home)
Phase 26 (Anime) ──────────→ Phase 1 (Kill Shaders)
Phase 27 (Music) ──────────→ Phase 14 (EQ), Phase 34 (Haptics)
Phase 28 (Books) ──────────→ Phase 18 (Manga page flip)
Phase 29 (Settings) ───────→ Phase 35 (Settings audit)
Phase 30 (Social) ─────────→ Phase 27 (Music - DM)
Phase 31 (Offline) ────────→ Phase 32 (Perf Mode UI)
Phase 33 (120FPS) ─────────→ Phase 1 (Kill Shaders)
Phase 36 (Security) ───────→ Phase 37 (RLS Verify)
Phase 38 (Easy English) ───→ ALL
Phase 39 (Build) ──────────→ Phase 38 (Easy English)
Phase 40 (Docs) ───────────→ ALL completed phases
```

---

## PART D — CONFIRMED BLOCKERS & UNRESOLVED ITEMS

1. **`liquid_glass_easy` package dependency**: This package is imported by ~15 files. Complete removal (Phase 1) requires replacing every usage. The package itself will still be in `pubspec.yaml` until all imports are gone. **Risk:** Some usages may be deeply nested in widget trees and require significant refactoring.

2. **`AnimatedAmbientBackground`**: This widget uses shader-based animations. It's used in HomePage, AnimePage, MusicPage. Replacement (Phase 1) requires building a new animated background that uses only `AnimationController` + `Alignment` shifts on `Container` overlays. **Risk:** The current visual effect (aurora, gradient meshes) may not be fully reproducible without shaders.

3. **`glass_settings.dart`**: This entire service drives GPU shader parameters. Marking it `@Deprecated` (Phase 29) but existing code references it in ~20 places. **Risk:** Need to update all callers before deprecation.

4. **Watch Together guest autoplay integration**: Core logic is tested in isolation but not integrated with the actual video player. **Risk:** `GuestAutoOpen.handle()` opens `WatchScreen` via `navigatorKey` which might not work in all navigation contexts.

5. **Download resume verification**: Need to actually test the `.part` file resume mechanism. **Risk:** HLS and torrent engines may have different resume behaviors.

6. **Light theme (Anodized Aluminum)**: No light palette exists. Adding one (Phase 2) requires checking every widget for hardcoded dark-mode colors. **Risk:** Many widgets have `const Color(0xFF000000)` or similar dark colors that won't look right in light mode.

---

## PART E — RECOMMENDED EXECUTION ORDER

**Start here:** Phase 1 (Kill Shaders) — this unlocks everything else. Without it, all UI work violates the core OLED rule.

**Then parallelize:**
- Phases 3-6 (hardware primitives) — independent of each other, all pure CustomPainter widgets
- Phase 2 (Light Theme) — depends on Phase 1 completing for gradient tokens
- Phase 8 (Gradients) — depends on Phase 1, feeds Phase 9

**Then sequentially:**
- Phase 7 (Theme Switch) ← needs Phase 2 + Phase 8
- Phase 9 (Card 2.0) ← needs Phase 8
- Phase 10 (AV Conflict wiring) ← independent, verify + fix
- Phase 11 (Guest Sync test) ← verify existing logic
- Phases 21-30 (Screen overhauls) ← each depends on Phase 1 + relevant primitive

**End with:**
- Phase 38 (Easy English audit) ← last before release
- Phase 39 (Build artifacts) ← final verification
- Phase 40 (Documentation) ← last

---

## PART F — BLOCK 4 COMPLETION RECORD (2026-09-20, Phase 40)

**Scope:** Phases 36, 37, 38, 40. No new features — verification + docs only.
Full detail: `DIZZY_40_PHASE_IMPLEMENTATION_REPORT.md` (repo root).

- **Phase 36 (anonymous-first): COMPLETE.** Verified, no code changes.
  `main.dart` boots `HomePage` with cloud last + non-blocking;
  `DeviceIdService` mints the random 7-digit DIZ code; HWID hash is computed
  in `DizzyIdentityService.bootDevice()` only after the `CloudClient.isReady`
  guard; auth-flow files contain no OAuth/redirect code
  (`signInAnonymously` only). Test:
  `test/security/anonymous_first_test.dart` (4/4 pass). Note: no file named
  `AnonymousFirstService` exists — equivalents are `DeviceIdService` +
  `CloudAuthService` + `DizzyIdentityService` + `CloudClient`.
- **Phase 37 (RLS hardening): COMPLETE.** Verified, no migration changes.
  `profiles` owner-scoped; `rooms`/`room_messages` membership-gated with
  writes via `send_room_message`/`join_watch_room` RPCs; `friendships`
  INSERT requires `requester = auth.uid()` and forbids self-friend; all 11
  protected tables RLS-enabled with authenticated/`auth.uid()`-scoped
  policies. Test: `test/security/rls_policy_verification_test.dart`
  (5/5 pass).
- **Phase 38 (Easy English): COMPLETE.** 14 user-facing strings fixed
  (API→access key, token→key, authorization→permission, plus two error
  rewrites). Test: `test/copy/easy_english_test.dart` (passes; negative
  control verified).
- **Phase 39 (build artifacts): NOT RUN** — out of scope for this block;
  no push/tag per standing rules. Left for the user.
- **Phase 40 (docs): COMPLETE.** `DIZZY_40_PHASE_IMPLEMENTATION_REPORT.md`,
  `DIZZY_TACTILE_GUIDELINES.md` (repo root), and this record.

**Blueprint freeze:** Parts A–E above remain the normative spec; this Part F
is the append-only completion log. Do not edit A–E without opening a new
phase.
