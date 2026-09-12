/// Polish P19 — Wrap editorial voice in ONE place.
///
/// Done rule: "mere liye bana hai" feel.
/// Cheer tiers by watch time + streak — Easy English, zero tech.
abstract final class WrapCopy {
  const WrapCopy._();

  /// Cheer line under the big hours number.
  static String hoursCheer(int minutesWatched) {
    if (minutesWatched <= 0) return 'Your story starts with one tap.';
    if (minutesWatched < 60) return 'Warming up — every minute counts.';
    if (minutesWatched < 600) return 'Getting cozy with stories.';
    if (minutesWatched < 3000) return 'Certified binge legend.';
    return 'Cinema lives in your pocket.';
  }

  /// Streak tile label.
  static String streakLine(int days) {
    if (days <= 0) return 'Watch daily to start a streak';
    if (days == 1) return 'Day 1 — streak lit!';
    return '$days-day streak — keep it burning!';
  }

  /// Empty taste-profile line.
  static String emptyTaste() =>
      'Watch something and your taste profile builds here.';
}
