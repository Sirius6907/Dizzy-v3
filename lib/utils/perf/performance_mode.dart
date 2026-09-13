import 'package:flutter/foundation.dart';

/// P2/P9 — single switchboard for every visual & buffer cost in the app.
///
/// The [ResourceGovernor] samples RAM/CPU/GPU and writes [level] here;
/// widgets (ambient background, glass lenses) and the player read these
/// notifiers and shed load immediately. Pure ValueNotifiers — no timers,
/// no platform calls — so this file is unit-testable and never crashes.
///
/// Levels:
/// - normal   → full visuals, full buffers
/// - caution  → ambient frozen, glass → flat fallback, torrent buffer trimmed
/// - critical → ambient OFF, all glass OFF, shaders stripped, eco buffers
enum PerfLevel { normal, caution, critical }

abstract final class PerformanceMode {
  /// Current mitigation level. Written by ResourceGovernor, read by UI/player.
  static final ValueNotifier<PerfLevel> level =
      ValueNotifier<PerfLevel>(PerfLevel.normal);

  /// Master kill-switch for the animated ambient background + blur wallpaper.
  /// P2: OFF on caution+, or when the user enables Smooth Mode.
  static final ValueNotifier<bool> ambientAllowed =
      ValueNotifier<bool>(true);

  /// Master kill-switch for liquid-glass lenses. OFF on critical, or when
  /// the screen already hosts too many lenses (P2 cap), or Smooth Mode.
  static final ValueNotifier<bool> glassAllowed =
      ValueNotifier<bool>(true);

  /// User-facing Smooth Mode (defaults ON on ≤3GB-RAM phones, P17).
  /// Forces ambient OFF + glass OFF + eco player buffers.
  static final ValueNotifier<bool> smoothMode =
      ValueNotifier<bool>(false);

  /// True on phones with ≤3GB total RAM (set once at startup from
  /// DeviceInfo / /proc/meminfo; defaults to false on unknown).
  static bool isLowRamDevice = false;

  /// Applies a governor level to the visual switches. Idempotent.
  static void applyLevel(PerfLevel next) {
    level.value = next;
    final smooth = smoothMode.value;
    switch (next) {
      case PerfLevel.normal:
        ambientAllowed.value = !smooth;
        glassAllowed.value = !smooth;
        break;
      case PerfLevel.caution:
        // Freeze ambient (static gradient frame stays), glass → fallback.
        ambientAllowed.value = false;
        glassAllowed.value = !smooth;
        break;
      case PerfLevel.critical:
        ambientAllowed.value = false;
        glassAllowed.value = false;
        break;
    }
  }

  /// Called once when Smooth Mode toggles — re-applies current level.
  static void setSmoothMode(bool on) {
    smoothMode.value = on;
    applyLevel(level.value);
  }

  @visibleForTesting
  static void resetForTest() {
    level.value = PerfLevel.normal;
    ambientAllowed.value = true;
    glassAllowed.value = true;
    smoothMode.value = false;
    isLowRamDevice = false;
  }
}
