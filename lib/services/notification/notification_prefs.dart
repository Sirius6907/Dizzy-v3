/// Phase J1 — pure notification gating: per-type prefs + quiet hours.
///
/// Everything here is deterministic and I/O free so tests can pin the
/// policy without a platform channel. The service layer feeds these
/// values in; nothing here can fail.
library;

/// The four channels the plan calls for (§2e).
enum NotificationKind {
  update('updates'),
  download('downloads'),
  social('social'),
  announcement('announcements');

  const NotificationKind(this.key);
  final String key;

  static NotificationKind? fromKey(String? key) {
    for (final k in NotificationKind.values) {
      if (k.key == key) return k;
    }
    return null;
  }
}

class NotificationGate {
  const NotificationGate({
    this.off = const <String>{},
    this.quietEnabled = false,
    this.quietStartMinute = 22 * 60,
    this.quietEndMinute = 7 * 60,
  });

  /// Keys of the kinds the user switched OFF (everything else defaults on).
  final Set<String> off;

  final bool quietEnabled;
  final int quietStartMinute;
  final int quietEndMinute;

  /// Pure: is `at` inside the quiet window? Handles a window that wraps
  /// midnight (22:00 → 07:00) without any date arithmetic.
  static bool isQuietAt(
    DateTime at, {
    required int startMinute,
    required int endMinute,
  }) {
    final m = at.hour * 60 + at.minute;
    final s = startMinute.clamp(0, 1439);
    final e = endMinute.clamp(0, 1439);
    if (s == e) return false; // zero-length window is not a window
    if (s < e) return m >= s && m < e;
    return m >= s || m < e; // wraps midnight
  }

  bool kindEnabled(NotificationKind kind) => !off.contains(kind.key);

  /// The one call the service makes before showing a system banner.
  /// Quiet hours and per-type prefs both have to pass.
  bool allows(NotificationKind kind, DateTime at) {
    if (!kindEnabled(kind)) return false;
    if (quietEnabled &&
        isQuietAt(
          at,
          startMinute: quietStartMinute,
          endMinute: quietEndMinute,
        )) {
      return false;
    }
    return true;
  }

  NotificationGate copyWith({
    Set<String>? off,
    bool? quietEnabled,
    int? quietStartMinute,
    int? quietEndMinute,
  }) {
    return NotificationGate(
      off: off ?? this.off,
      quietEnabled: quietEnabled ?? this.quietEnabled,
      quietStartMinute: quietStartMinute ?? this.quietStartMinute,
      quietEndMinute: quietEndMinute ?? this.quietEndMinute,
    );
  }

  Map<String, dynamic> toJson() => {
    'off': off.toList(),
    'quietEnabled': quietEnabled,
    'quietStartMinute': quietStartMinute,
    'quietEndMinute': quietEndMinute,
  };

  factory NotificationGate.fromJson(Map<String, dynamic> json) {
    return NotificationGate(
      off: ((json['off'] as List?) ?? const [])
          .map((e) => e.toString())
          .toSet(),
      quietEnabled: json['quietEnabled'] == true,
      quietStartMinute: (json['quietStartMinute'] as num?)?.toInt() ?? 22 * 60,
      quietEndMinute: (json['quietEndMinute'] as num?)?.toInt() ?? 7 * 60,
    );
  }

  static String hhmm(int minuteOfDay) {
    final m = minuteOfDay.clamp(0, 1439);
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    return '$h:$mm';
  }

  /// Parse "22:30" → minutes. Returns null when unparsable.
  static int? parseHhMm(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
    if (match == null) return null;
    final h = int.tryParse(match.group(1)!);
    final m = int.tryParse(match.group(2)!);
    if (h == null || m == null || h > 23 || m > 59) return null;
    return h * 60 + m;
  }
}
