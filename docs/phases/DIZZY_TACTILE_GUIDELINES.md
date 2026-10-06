# Dizzy Tactile Guidelines — Hardware UI Design System

**Status:** Frozen with the 40-phase blueprint (Block 4, Phase 40).
**Scope:** Every screen, card, button, dock, dialog and banner in Dizzy-v3.
**References:** `lib/design/dizzy_tokens.dart`, `lib/design/dizzy_tactile.dart`,
`lib/widgets/tactile/`, `DIZZY_40_PHASE_IMPLEMENTATION_REPORT.md`.

---

## 1. Core principle

Dizzy looks like studio hardware (Boss Pocket GT / EQ-200): anodized metal,
extruded cards, LED digits, physical knobs and stomp pads. Depth comes from
**static gradients + static shadows**. Never from GPU blur shaders.

## 2. Hard bans (app chrome)

| Banned | Why | Use instead |
|---|---|---|
| `BackdropFilter` / `ImageFilter.blur` | GPU shader cost, violates OLED budget | `Container` + `LinearGradient` + 1px hairline border |
| `liquid_glass_easy` (`Glass`, lenses) | Same as above | `DizzyTactileCard` / `DizzyGradients.surface` |
| `ShaderMask` for chrome | Same as above | Pre-baked `LinearGradient` in `DizzyGradients` |
| Aurora / mesh / ambient shader backgrounds | Same as above | `Ticker`-driven `AnimatedPositioned` overlay shifts (gated by `PerformanceMode.ambientAllowed`) |
| `InkWell` splash on tactile pads | Wrong feel (ink vs hardware) | `GestureDetector` + gradient swap + haptic |

`CustomPainter` with `Paint` + `Rect` + `Path` is the only allowed custom
rendering path (rotary dial, EQ faders, 7-segment, dot-matrix, page curl).

## 3. Tokens (single source of truth)

- **Void (dark surfaces):** `DizzyVoid` — scaffold, surface1–3. Black
  backgrounds stay true black for OLED (off pixels).
- **Light (anodized aluminum):** `DizzyLight` — `boneDark` text
  (`0xFF1A1D26`), ash secondary, inverted surface1–3. Every widget with a
  hardcoded dark color must have a light-mode branch.
- **Glow (accents):** `DizzyGlow.red` (primary action), `ember`, `beam`
  (info/degraded), `volt` (healthy/online). Status colors are fixed:
  healthy = volt, error = red, degraded = beam.
- **Edges:** `DizzyEdge.hairline` (1px dividers), `DizzyEdge.neon`
  (focused/active borders, e.g. search field, online avatar ring).
- **Shadows:** `DizzyShadow.card` (sections), `.dock` (dock bar).
  Card depth tiers — small (list rows, 1px / blur 4), medium (cards, 2px /
  blur 10), large (modals, 4px / blur 20). On press: `Transform.translate`
  2px up + brighter gradient, never a blur change.
- **Gradients:** `DizzyGradients.surface` (cards), `.raised` (floating),
  `.silver` (light anodized), `.darkMetal` (dark metallic), `.accent`
  (primary actions). All `const` where possible.

## 4. Widget catalogue (`lib/widgets/tactile/`)

| Widget | File | Notes |
|---|---|---|
| Rotary dial | `dizzy_rotary_dial.dart` | `atan2` touch angle, detents, `lightImpact` ticks |
| EQ fader + panel | `dizzy_eq_fader.dart`, `dizzy_eq_panel.dart` | Wired to `MusicEqualizerService.bandGains`, presets in `SharedPreferences` |
| 7-segment display | `dizzy_7segment.dart` | Red-on-black digits (resolve countdown, counters) |
| Dot-matrix display | `dizzy_dotmatrix.dart` | Beam/volt 5×7 dots, `Offset`-only scroll animation |
| Stomp pad + grid | `dizzy_stomp_pad.dart`, `dizzy_stomp_grid.dart` | `mediumImpact`, pressed = red @ 20% |
| Button / Card / Dock | `dizzy_tactile_button.dart`, `dizzy_tactile_card.dart`, `dizzy_tactile_dock.dart` | Theme-aware, tiered elevation |

## 5. Theme switching

`AppThemeService.currentThemeId` (`ValueNotifier`) drives everything via
`ValueListenableBuilder` — no `setState` full rebuilds. Dark Studio Obsidian
OLED ↔ Light Anodized Aluminum must switch all screens without lag.
`DizzyShadow` values swap with theme (dark shadows on light bg and vice versa).

## 6. Motion & haptics

- Haptic on every tactile interaction: buttons/cards `lightImpact`,
  dock/stomp/long-press `mediumImpact`, fader/dial detents click/light.
- 120 FPS budget: `RepaintBoundary` around animated islands only (vinyl
  spin, progress bars, EQ faders). `PerformanceMode.targetFrameRate`
  60/90/120; low-end devices lock 60 FPS.
- Offline banner: `OfflineAwareScaffold` wraps every `Scaffold`;
  "No internet. Waiting…" slides away on reconnect (no shader).

## 7. Copy

All user-facing copy is Easy English (enforced by
`test/copy/easy_english_test.dart`). Forbidden in UI strings:
authentication, authorization, endpoint, payload, API, token,
cache invalidation, middleware, deprecated. Replacements: login, permission,
connection, data, access key / connection, key, clear old data, controller,
outdated. Error states never surface stack traces — one plain line + retry.

## 8. Contributor checklist (tactile freeze)

1. No new `BackdropFilter`, `ImageFilter.blur`, `ShaderMask`,
   `liquid_glass_easy` imports in `lib/` (chrome).
2. New surfaces use `DizzyGradients` + `DizzyShadow` tier + `DizzyEdge`.
3. New pressables have haptic feedback and a pressed gradient state.
4. Light + dark palettes both render (no hardcoded single-theme colors).
5. User-facing strings pass `test/copy/easy_english_test.dart`.
6. Animated widgets are `RepaintBoundary`-wrapped islands.
