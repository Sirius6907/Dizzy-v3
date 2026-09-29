# PHASE P6 — UI/UX 50x (complete)

**Date:** 2026-09-29
**Base:** `065a855` (P6-hex2, 931 legacy hex remaining)
**Commits:** `4b26058` (hex3) · `232cb51` (narrow bars) · `21d23d2` (music proofs)

---

## 1. Legacy hex sweep — 931 → 871 (pre-merge measurement)

Only `Color(0xFF…)` literals under `lib/pages` + `lib/widgets` were in scope.

**Swapped (53 sites, 28 files) — flat dark surfaces → the frozen `DizzyVoid` tiers**

| Legacy literal | Count | Token |
|---|---|---|
| `0xFF161A26`, `0xFF12151E`, `0xFF171B26`, `0xFF141926`, `0xFF151822`, `0xFF161927`, `0xFF141A26` | 36 | `DizzyVoid.surface1` |
| `0xFF1E2235`, `0xFF1E2336`, `0xFF1A1F2C`, `0xFF1B2030`, `0xFF1C2130` | 17 | `DizzyVoid.surface2` |
| `0xFF0D1017`, `0xFF0B0E15`, `0xFF0E1017`, `0xFF131826` | 4 | `DizzyVoid.voidB` |
| `0xFF0F1117` | 2 | `DizzyVoid.voidA` |
| `0xFF080A0F`, `0xFF0A0C11` | 2 | `DizzyVoid.obsidian` |
| `0xFF242A3D` | 1 | `DizzyVoid.surface3` |
| `0xFFFFFFFF` (pure white) | 7 | `Colors.white` |
| exact-token values (`0xFF8B5CF6`, `0xFF0C0E15`, `0xFF14161E`, …) | 3 | matching `DizzyVoid` / `DizzyGlow` |

All replacements are nearest-tier swaps; dark values come from `dizzy_tactile.dart`
(`DizzyVoid`), never `DizzyLight`, which stays reserved for light-OLED modes.

**Deliberately left literal (documented in code)**

| Literal | Count | Why it stays |
|---|---|---|
| `0xFF7C5CFF` | 293 | Amethyst brand purple — the `amethyst` palette primary. It is a per-feature identity colour and the gradient stop of several hero washes; `DizzyGlow.violet` (`0xFF8B5CF6`) is a *different* colour, so swapping would change the look. |
| `0xFF10B981` | 88 | Emerald palette primary — same reasoning (success / credits identity). |
| `0xFF00D2EF`, `0xFF00E5FF`, `0xFF00ADFF`, `0xFF00B4DB` | 155 | Cyan gradient family — the stops of the ambient canvas and the IPTV brand wash. |
| `0xFFEF4444`, `0xFF3B82F6`, `0xFFF59E0B`, `0xFFFF3366`, `0xFFED1C24` | 81 | Remaining palette primaries (sapphire / metallic / sunset / vampire) plus the YouTube source red. |
| alpha-tinted glows and shadows (`…withValues(alpha: …)`) | — | Glow and shadow tint is derived from the base colour; keeping the literal keeps the alpha maths exact. |

The two places that *define* these pairs (not merely consume them) now carry a
comment saying so:
- `lib/pages/iptv/iptv_channel_sheet.dart:99`
- `lib/widgets/player/player_skip_button.dart:69`

`lib/pages/discover/**` was skipped — it is F-worker owned.

---

## 2. Narrow-screen audit — 40 `AppBar` owners

Real `AppBar`s are **already safe**: `NavigationToolbar` constrains the middle
slot, so a long title ellipsizes instead of overflowing. The real risk is in
hand-rolled bars built as `Positioned` + `Row`. Verified every file rather than
trusting the handoff note (the previous run had added no new narrow logic).

**Fixed (3) — real overflow at 360px**

| File | Problem | Fix |
|---|---|---|
| `lib/pages/iptv/iptv_page.dart` `_IptvGlassAppBar` | two info pills + three glass buttons ≈ 356px | `width < 420` hides the `60+ CHANNELS` pill, tightens padding 28→12 and button gaps 10→6 |
| `lib/pages/ai/wewatch_quiz_page.dart` `_buildAppBar` | back + AI pill + title ≈ 361px, plus `Retake` once results exist | `width < 420` hides the AI pill, shortens the title to `Taste Quiz`, wraps it in `Expanded` + ellipsis, back button gains a tooltip |
| `lib/pages/social/direct_message_page.dart` | unbounded `@username` overflowed with a long handle | `Expanded` + ellipsis on both title lines |

**Already correct, left alone:** home (`<420`), anime (`<430`), manga (`<600`),
party (`<420`), audiobook studio (`<420`), music studio (`<600`), downloads
(short title + one action), and every settings page except the two above.
`epub_content_view` and the photo page have no actions.

New user copy (`Taste Quiz`, `Go back`) went into the copy-deck pool.

---

## 3. Music verify — 22 proofs, `test/music_p6_verify_test.dart`

All four features already existed; this phase made their contracts testable
and fixed the one real defect the tests exposed.

- **Ambient canvas black-flash guard.** `MusicTrackPalette.isAmbientSafe` +
  `MusicTrackPalette.minBackgroundLuminance`, and `_liftUntilVisible()` walks
  the HSL lightness up until the background clears the floor. The canvas paints
  `getFastPalette()` synchronously in `initState` and swaps in the extracted
  palette a moment later, so that first frame must never be black. Proven
  across 200 hue buckets plus the no-artwork fallback path.
- **Queue reorder mapping.** Extracted the pure upcoming→absolute math into
  `lib/services/music/music_queue_ops.dart`; `MusicPlayerController` delegates
  to it, so the mapping is testable without booting the media backend.
  Out-of-range drags are now ignored instead of clamped into a surprise
  position. Proven up / down / no-op / history-safe / out-of-range / empty.
- **Quality hot-swap keeps position.** `debugSeedPlaybackState()` seeds queue +
  position, then `setAudioSource` is asserted to preserve the position, the
  track and flip the FLAC/HQ badge polarity.
- **Song Radio + Smart Mix.** Seed-first ordering, ID dedupe, and fail-soft
  when nothing can be fetched; `SmartMixPlaylist.primaryCoverUrl` is safe on an
  empty mix.

---

## Gates

| Gate | Result |
|---|---|
| `flutter analyze` on every touched file | 0 issues |
| `test/music_p6_verify_test.dart` | 22 new tests, green |
| `test/copy_deck_test.dart`, `design_tokens_test.dart`, `design_contract_test.dart`, `music_smoke_test.dart`, `music_m1_m20_test.dart` | green |
| **Full suite** | **701 passed / 24 skipped / 0 failed** (baseline 679 / 24 / 0 — +22, exactly the new music tests) |

P7–P10 are tracked separately; see `PHASE_P9_PERF.md` for the budget numbers.
