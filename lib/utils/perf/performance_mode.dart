import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// P2/P9/UX3 — single switchboard for every visual & buffer cost in the app.
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

/// UX3: Adaptive device tiers
enum DeviceTier { budget, midTier, flagship }

abstract final class PerformanceMode {
  /// Current mitigation level. Written by ResourceGovernor, read by UI/player.
  static final ValueNotifier<PerfLevel> level =
      ValueNotifier<PerfLevel>(PerfLevel.normal);

  /// Master kill-switch for the animated ambient background + blur wallpaper.
  /// P2: OFF on caution+, or when the user enables Smooth Mode / Low-End Mode.
  static final ValueNotifier<bool> ambientAllowed =
      ValueNotifier<bool>(true);

  /// Master kill-switch for liquid-glass lenses. OFF on critical, or when
  /// the screen already hosts too many lenses (P2 cap), or Smooth Mode / Low-End Mode.
  static final ValueNotifier<bool> glassAllowed =
      ValueNotifier<bool>(true);

  /// User-facing Smooth Mode (defaults ON on ≤3GB-RAM phones, P17).
  /// Forces ambient OFF + glass OFF + eco player buffers.
  static final ValueNotifier<bool> smoothMode =
      ValueNotifier<bool>(false);

  /// UX3: Adaptive Device Tier detected at runtime.
  static final ValueNotifier<DeviceTier> deviceTier =
      ValueNotifier<DeviceTier>(DeviceTier.flagship);

  /// UX3: Low-End Device Mode toggle.
  /// Disables heavy Gaussian blurs (solid acrylic fallback) and clamps decode caps.
  static final ValueNotifier<bool> lowEndDeviceMode =
      ValueNotifier<bool>(false);

  /// True on phones with ≤3GB total RAM (set once at startup from
  /// DeviceInfo / /proc/meminfo; defaults to false on unknown).
  static bool isLowRamDevice = false;

  /// Detects and sets the device tier based on platform and RAM.
  static void detectDeviceTier({required bool isMobile, int? totalRamMb}) {
    if (!isMobile) {
      deviceTier.value = DeviceTier.flagship;
      return;
    }
    if ((totalRamMb != null && totalRamMb <= 3072) || isLowRamDevice) {
      deviceTier.value = DeviceTier.budget;
    } else if (totalRamMb != null && totalRamMb <= 6144) {
      deviceTier.value = DeviceTier.midTier;
    } else {
      deviceTier.value = DeviceTier.flagship;
    }
  }

  /// Applies a governor level to the visual switches. Idempotent.
  static void applyLevel(PerfLevel next) {
    level.value = next;
    final forceOff = smoothMode.value || lowEndDeviceMode.value;
    switch (next) {
      case PerfLevel.normal:
        ambientAllowed.value = !forceOff;
        glassAllowed.value = !forceOff;
        break;
      case PerfLevel.caution:
        // Freeze ambient (static gradient frame stays), glass → fallback.
        ambientAllowed.value = false;
        glassAllowed.value = !forceOff;
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

  /// UX3: Low-End Device Mode toggle.
  /// Enforces solid acrylic fallback and tighter image cache caps.
  static void setLowEndDeviceMode(bool on) {
    lowEndDeviceMode.value = on;
    if (on) {
      setSmoothMode(true);
      try {
        PaintingBinding.instance.imageCache.maximumSize = 100;
        PaintingBinding.instance.imageCache.maximumSizeBytes = 80 << 20;
      } catch (_) {}
    }
    applyLevel(level.value);
  }

  @visibleForTesting
  static void resetForTest() {
    level.value = PerfLevel.normal;
    ambientAllowed.value = true;
    glassAllowed.value = true;
    smoothMode.value = false;
    lowEndDeviceMode.value = false;
    deviceTier.value = DeviceTier.flagship;
    isLowRamDevice = false;
  }
}
