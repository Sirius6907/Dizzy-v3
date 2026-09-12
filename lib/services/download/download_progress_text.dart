/// Polish P7 — download progress honesty in ONE voice (Easy English).
///
/// Pure formatter so the line never drifts between cards:
/// - failed → `Failed: <easy line>`
/// - paused → `Paused at 42%`
/// - active → `42% • 2.10 MB/s • 3m 10s left`
///
/// Whole % on purpose (non-tech-first: 42% beats 42.3%).
abstract final class DownloadProgressText {
  const DownloadProgressText._();

  static int wholePercent(double progress) =>
      (progress * 100).round().clamp(0, 100);

  static String line({
    required double progress,
    required String speedLabel,
    required String etaLabel,
    required bool isPaused,
    required bool isFailed,
    String? error,
  }) {
    if (isFailed) return 'Failed: ${error ?? 'Unknown error'}';
    final pct = wholePercent(progress);
    if (isPaused) return 'Paused at $pct%';
    return '$pct% • $speedLabel • $etaLabel left';
  }
}
