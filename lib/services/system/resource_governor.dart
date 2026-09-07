import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// How aggressively the app must shed resources.
enum ResourceLevel {
  /// Normal operation — full quality, full buffers.
  normal,

  /// Over ~75% of budget: trim caches & demuxer buffers.
  caution,

  /// Over ~90% of budget: drop Anime4K shaders, skip loop filters,
  /// minimal demuxer. Anything to stay inside the budget.
  critical,
}

/// Immutable snapshot of one sampling tick.
class ResourceSample {
  final int rssMb;
  final double cpuPercent; // % of ALL cores combined (machine-wide share)
  final int? gpuTotalMb; // total GPU memory used, if queryable

  const ResourceSample({
    required this.rssMb,
    required this.cpuPercent,
    this.gpuTotalMb,
  });
}

/// Platform-aware resource budgets & live sampler.
///
/// **PC budgets (user-set):** ≤ 3 GB RAM, ≤ 2.5 GB VRAM (total GPU),
/// ≤ 20% CPU. **Android:** tighter (phones share everything).
///
/// The governor samples every 10 s and escalates through
/// [ResourceLevel]s with hysteresis (2 bad samples to escalate,
/// 6 calm samples to de-escalate) so playback never flickers quality.
class ResourceGovernor {
  ResourceGovernor._();

  static final ResourceGovernor instance = ResourceGovernor._();

  /// Current mitigation level (listened to by PlayerScreen).
  final ValueNotifier<ResourceLevel> level =
      ValueNotifier<ResourceLevel>(ResourceLevel.normal);

  /// True while the video player is actively playing (gates CPU/VRAM
  /// mitigation — no point dropping quality when nothing plays).
  bool playbackActive = false;

  /// Anime4K currently enabled (VRAM mitigation knows what to shed).
  bool anime4kActive = false;

  // ── Budgets ────────────────────────────────────────────────────────────
  int get ramBudgetMb =>
      Platform.isAndroid ? (Platform.isLinux ? 2800 : 1800) : 2800;
  static const double cpuBudgetPercent = 20.0;
  static const int gpuBudgetMb = 2560; // 2.5 GB total GPU

  // ── Sampling state ────────────────────────────────────────────────────
  Timer? _sampleTimer;
  Timer? _gpuTimer;
  double _lastCpuSeconds = 0;
  DateTime _lastCpuAt = DateTime.now();
  int _overStreak = 0;
  int _calmStreak = 0;

  /// Starts the periodic sampler (idempotent).
  void start() {
    _sampleTimer ??= Timer.periodic(
      const Duration(seconds: 10),
      (_) => _sampleOnce(),
    );
    // GPU memory is the slowest-moving metric — sample every 20 s.
    if (!Platform.isAndroid) {
      _gpuTimer ??= Timer.periodic(
        const Duration(seconds: 20),
        (_) => _sampleGpu(),
      );
    }
  }

  /// Latest measured sample (for logging / debug displays).
  ResourceSample? lastSample;

  Future<void> _sampleOnce() async {
    try {
      final sample = await _measure();
      lastSample = sample;
      _evaluate(sample);
    } catch (_) {
      // Monitoring must never crash the app.
    }
  }

  Future<void> _sampleGpu() async {
    try {
      final gpuMb = await _queryGpuTotalMb();
      if (gpuMb == null) return;
      final base = lastSample ??
          ResourceSample(rssMb: 0, cpuPercent: 0, gpuTotalMb: gpuMb);
      final merged = ResourceSample(
        rssMb: base.rssMb,
        cpuPercent: base.cpuPercent,
        gpuTotalMb: gpuMb,
      );
      lastSample = merged;
      _evaluate(merged);
    } catch (_) {}
  }

  // ── Measurement (per platform) ─────────────────────────────────────────

  Future<ResourceSample> _measure() async {
    if (Platform.isWindows) {
      // One PowerShell call: WorkingSet64 + TotalProcessorTime.
      final cmdline =
          r'$p = Get-Process -Id ' + pid.toString() + r'; ' +
          r'"{0} {1}" -f $p.WorkingSet64, ' +
          r'[double]$p.TotalProcessorTime.TotalSeconds';
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        cmdline,
      ]);
      final parts = (result.stdout as String).trim().split(RegExp(r'\s+'));
      if (parts.length < 2) {
        return const ResourceSample(rssMb: 0, cpuPercent: 0);
      }
      final rssBytes = int.tryParse(parts[0]) ?? 0;
      final cpuSecs = double.tryParse(parts[1]) ?? _lastCpuSeconds;
      return _buildSample(
        rssMb: rssBytes ~/ (1024 * 1024),
        cpuSeconds: cpuSecs,
      );
    }
    // Linux / Android: pure /proc reads (self is always readable).
    final rssMb = await _readProcRssMb();
    final cpuSecs = _readProcCpuSeconds();
    if (rssMb == null || cpuSecs == null) {
      return const ResourceSample(rssMb: 0, cpuPercent: 0);
    }
    return _buildSample(rssMb: rssMb, cpuSeconds: cpuSecs);
  }

  ResourceSample _buildSample({required int rssMb, required double cpuSeconds}) {
    final now = DateTime.now();
    final wall = now.difference(_lastCpuAt).inMicroseconds / 1e6;
    double cpuPercent = 0;
    if (wall > 0.5) {
      final cores = Platform.numberOfProcessors <= 0
          ? 1
          : Platform.numberOfProcessors;
      final deltaCpu = (cpuSeconds - _lastCpuSeconds).clamp(0, wall * cores);
      // Normalize to machine-wide share: 100% = all cores fully busy.
      cpuPercent = (deltaCpu / (wall * cores)) * 100.0;
    }
    _lastCpuSeconds = cpuSeconds;
    _lastCpuAt = now;
    final gpu = lastSample?.gpuTotalMb;
    return ResourceSample(
      rssMb: rssMb,
      cpuPercent: cpuPercent,
      gpuTotalMb: gpu,
    );
  }

  Future<int?> _readProcRssMb() async {
    try {
      final lines = await File('/proc/self/status').readAsLines();
      for (final l in lines) {
        if (l.startsWith('VmRSS:')) {
          final kb = int.tryParse(l.split(RegExp(r'\s+'))[1]);
          return kb == null ? null : kb ~/ 1024;
        }
      }
    } catch (_) {}
    return null;
  }

  double? _readProcCpuSeconds() {
    try {
      final stat = File('/proc/self/stat').readAsStringSync();
      // Fields after the last ')' start at 'state' = field 3.
      final afterComm = stat.substring(stat.lastIndexOf(')') + 2);
      final fields = afterComm.split(' ');
      // utime = field 14, stime = field 15 → indices 11, 12 in `fields`.
      final utime = int.tryParse(fields[11]);
      final stime = int.tryParse(fields[12]);
      if (utime == null || stime == null) return null;
      const userHz = 100.0; // USER_HZ on Linux & Android
      return (utime + stime) / userHz;
    } catch (_) {
      return null;
    }
  }

  /// Total GPU memory in use (MB), or null when not queryable.
  Future<int?> _queryGpuTotalMb() async {
    try {
      final r = await Process.run('nvidia-smi', [
        '--query-gpu=memory.used',
        '--format=csv,noheader,nounits',
      ]);
      if (r.exitCode != 0) return null;
      return int.tryParse((r.stdout as String).trim().split(RegExp(r'\s+')).first);
    } catch (_) {
      return null;
    }
  }

  // ── Policy: escalation ladder with hysteresis ──────────────────────────

  void _evaluate(ResourceSample s) {
    final ram = s.rssMb > 0.75 * ramBudgetMb;
    final cpu = s.cpuPercent > cpuBudgetPercent;
    final gpu = (playbackActive && anime4kActive)
        ? (s.gpuTotalMb != null && s.gpuTotalMb! > gpuBudgetMb)
        : (s.gpuTotalMb != null && s.gpuTotalMb! > gpuBudgetMb * 1.2);

    final bad = ram || cpu || gpu;
    if (bad) {
      _overStreak++;
      _calmStreak = 0;
    } else {
      _calmStreak++;
      _overStreak = 0;
    }

    final current = level.value;
    if (current != ResourceLevel.critical &&
        (_overStreak >= 3 || s.rssMb > 0.92 * ramBudgetMb)) {
      level.value = ResourceLevel.critical;
      debugPrint('[ResourceGovernor] CRITICAL ram=${s.rssMb}MB '
          'cpu=${s.cpuPercent.toStringAsFixed(1)}% gpu=${s.gpuTotalMb}MB');
    } else if (current == ResourceLevel.normal &&
        _overStreak >= 2) {
      level.value = ResourceLevel.caution;
      debugPrint('[ResourceGovernor] CAUTION ram=${s.rssMb}MB '
          'cpu=${s.cpuPercent.toStringAsFixed(1)}% gpu=${s.gpuTotalMb}MB');
    } else if (current != ResourceLevel.normal &&
        _calmStreak >= 6 &&
        s.rssMb < 0.6 * ramBudgetMb &&
        s.cpuPercent < cpuBudgetPercent * 0.7) {
      level.value = ResourceLevel.normal;
      debugPrint('[ResourceGovernor] back to NORMAL ram=${s.rssMb}MB');
    }
  }

  void dispose() {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    _gpuTimer?.cancel();
    _gpuTimer = null;
    playbackActive = false;
  }
}

/// Pure level-decision helper (kept separate for tests).
class ResourcePolicy {
  /// Returns the desired level given the current one and streak counters.
  ///
  /// Escalation: 3 bad samples (or 92%+ RAM burst) → critical;
  /// 2 bad samples → caution. De-escalation: 6 calm samples AND
  /// RAM < 60% budget AND CPU < 70% budget → normal.
  static ResourceLevel decide({
    required ResourceLevel current,
    required int overStreak,
    required int calmStreak,
    required int rssMb,
    required double cpuPercent,
    required int ramBudgetMb,
    required double cpuBudgetPercent,
  }) {
    final badRam = rssMb > 0.75 * ramBudgetMb;
    final badCpu = cpuPercent > cpuBudgetPercent;
    final burstRam = rssMb > 0.92 * ramBudgetMb;

    if (current != ResourceLevel.critical && (overStreak >= 3 || burstRam)) {
      return ResourceLevel.critical;
    }
    if (current == ResourceLevel.normal && overStreak >= 2) {
      return ResourceLevel.caution;
    }
    if (current != ResourceLevel.normal &&
        calmStreak >= 6 &&
        rssMb < 0.6 * ramBudgetMb &&
        cpuPercent < cpuBudgetPercent * 0.7) {
      return ResourceLevel.normal;
    }
    if (current == ResourceLevel.caution && (badRam || badCpu)) {
      // Hold caution; critical requires the streak above.
      return ResourceLevel.caution;
    }
    return current;
  }
}
