/// F1 — smart quality: one policy the player asks, no math in the widget.
///
/// Three rules, in priority order:
///  1. **Data Saver caps auto at 720p.** Always, even on fibre. The user
///     said "save my data"; the ladder must not argue.
///  2. **Weak / straining devices prefer H.264.** AV1 decode is the most
///     expensive thing in the pipeline — on a budget phone or a machine
///     already over its RAM/VRAM budget it melts playback. AV1 is still
///     allowed as a *fallback* when nothing else matches, because a worse
///     picture that plays beats a great picture that stutters.
///  3. **Manual choice always wins.** Auto mode is the only thing this
///     policy is allowed to move.
///
/// Pure Dart (no Flutter widgets) so the boundaries are unit-tested. The
/// player widget owns mpv; this only decides *what* to aim for.
library;

import '../../models/stream/stream_model.dart';
import '../../utils/perf/performance_mode.dart';
import '../system/resource_governor.dart';
import 'quality_service.dart';

/// Device capability signal, decoupled from the live services so the
/// policy can be exercised without a running governor.
enum DeviceCapability {
  /// Plenty of headroom — every codec, every rung.
  strong,

  /// Budget phone / low-RAM device, or the machine is over budget right
  /// now (caution+). Prefer H.264, dodge AV1.
  strained,
}

abstract final class SmartQualityPolicy {
  /// Data Saver never goes past this rung, however fast the link is.
  static const QualityChoice dataSaverCeiling = QualityChoice.q720;

  /// Collapse the live signals into a single capability signal.
  ///
  /// "Strained" is sticky in the safe direction: a budget-tier device or
  /// a ≤3GB phone counts as strained even while the governor is calm,
  /// because the governor only notices *after* playback has already hurt.
  static DeviceCapability capability({
    required bool lowEndDeviceMode,
    required DeviceTier deviceTier,
    required bool lowRamDevice,
    required ResourceLevel resourceLevel,
  }) {
    if (resourceLevel != ResourceLevel.normal) return DeviceCapability.strained;
    if (lowEndDeviceMode) return DeviceCapability.strained;
    if (lowRamDevice) return DeviceCapability.strained;
    if (deviceTier == DeviceTier.budget) return DeviceCapability.strained;
    return DeviceCapability.strong;
  }

  /// Convenience read of the live app state (player hot path).
  static DeviceCapability liveCapability() => capability(
        lowEndDeviceMode: PerformanceMode.lowEndDeviceMode.value,
        deviceTier: PerformanceMode.deviceTier.value,
        lowRamDevice: PerformanceMode.isLowRamDevice,
        resourceLevel: ResourceGovernor.instance.level.value,
      );

  /// Whether AV1 files should be passed over when picking a rendition.
  static bool shouldAvoidAv1(DeviceCapability cap) =>
      cap == DeviceCapability.strained;

  /// Apply the Data Saver ceiling to an auto-mode target.
  ///
  /// Only ever *lowers* a real rung; Auto is returned untouched.
  static QualityChoice applyDataSaverCeiling(
    QualityChoice target, {
    required bool dataSaver,
  }) {
    if (!dataSaver) return target;
    if (target == QualityChoice.auto) return target;
    if (target.index > dataSaverCeiling.index) return dataSaverCeiling;
    return target;
  }

  /// The auto-mode ladder step: bandwidth verdict → Data Saver ceiling.
  ///
  /// [bandwidthTarget] is `BandwidthMeter.stableTarget`'s verdict, which
  /// is null while the window is still thin — the caller then keeps the
  /// current rung rather than flip-flopping on one noisy sample.
  static QualityChoice? autoLadderStep({
    required QualityChoice? bandwidthTarget,
    required bool dataSaver,
  }) {
    if (bandwidthTarget == null) return null;
    return applyDataSaverCeiling(bandwidthTarget, dataSaver: dataSaver);
  }

  /// Pick the progressive file for [choice] on this device.
  ///
  /// Delegates matching to [QualityService] and supplies only the AV1-dodge
  /// intent, so the two can never disagree about what "720p" means. AV1 is
  /// returned as a last resort (see [QualityService.matchProgressive]).
  /// Null means nothing matches — the caller toasts, never dead-ends.
  static StreamSource? pickProgressive({
    required List<StreamSource> ranked,
    required QualityChoice choice,
    required DeviceCapability capability,
  }) {
    if (choice == QualityChoice.auto) return null;
    return QualityService.matchProgressive(
      ranked,
      choice,
      avoidAv1: shouldAvoidAv1(capability),
    );
  }
}
