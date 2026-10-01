/// Phase E1 — smart force-update gate. Pure, no I/O, fully testable.
///
/// Decision (plan §0): server never bricks an offline client — the gate only
/// activates when remote config actually carries `min_app_version`. Deadline
/// semantics:
///   * below min, no force_after  → advisory banner (never blocking)
///   * below min, before force_after → banner with countdown
///   * below min, after force_after → blocking screen
enum UpdateGateLevel { none, banner, blocking }

class UpdateGateResult {
  final UpdateGateLevel level;
  final String minVersion;
  final DateTime? forceAfter;

  const UpdateGateResult(this.level, {this.minVersion = '', this.forceAfter});

  bool get isBlocking => level == UpdateGateLevel.blocking;
  bool get isBanner => level == UpdateGateLevel.banner;

  /// Milliseconds until the blocking deadline (0 when none/passed).
  Duration untilForced(DateTime now) {
    if (forceAfter == null) return Duration.zero;
    final d = forceAfter!.difference(now);
    return d.isNegative ? Duration.zero : d;
  }
}

class UpdateGate {
  /// Compare dotted numeric versions ("1.10.0" > "1.2.9"). Non-numeric
  /// suffixes ("1.2.1-beta") are ignored per segment.
  static int compareVersions(String a, String b) {
    final pa = _parts(a), pb = _parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static List<int> _parts(String v) => v
      .split('.')
      .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();

  static UpdateGateResult evaluate({
    required String currentVersion,
    required String minVersion,
    String forceAfter = '',
    required DateTime now,
  }) {
    final min = minVersion.trim();
    if (min.isEmpty) {
      return const UpdateGateResult(UpdateGateLevel.none); // no server data
    }
    if (compareVersions(currentVersion, min) >= 0) {
      return UpdateGateResult(UpdateGateLevel.none, minVersion: min);
    }
    final faRaw = forceAfter.trim();
    if (faRaw.isEmpty) {
      // Advisory only until the admin sets a deadline.
      return UpdateGateResult(UpdateGateLevel.banner, minVersion: min);
    }
    final fa = DateTime.tryParse(faRaw);
    if (fa == null) {
      return UpdateGateResult(UpdateGateLevel.banner, minVersion: min);
    }
    return UpdateGateResult(
      now.isAfter(fa) ? UpdateGateLevel.blocking : UpdateGateLevel.banner,
      minVersion: min,
      forceAfter: fa,
    );
  }
}
