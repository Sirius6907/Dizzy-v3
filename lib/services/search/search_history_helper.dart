/// Polish P6 — search history rules in ONE place (pure, testable).
///
/// Rule (v1.2.0-T2.3, unchanged): 50 stored, last 10 shown,
/// re-search bumps to top, empty ignored.
abstract final class SearchHistoryHelper {
  static const int maxStored = 50;
  static const int maxShown = 10;

  /// Returns a NEW list with [query] bumped to top (dedupe + cap).
  /// Empty/blank queries return the list unchanged.
  static List<String> add(List<String> history, String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return List<String>.from(history);
    final next = List<String>.from(history)..remove(trimmed);
    next.insert(0, trimmed);
    while (next.length > maxStored) {
      next.removeLast();
    }
    return next;
  }

  /// First [maxShown] entries for chips.
  static List<String> shown(List<String> history) =>
      history.take(maxShown).toList();

  static List<String> remove(List<String> history, String query) {
    final next = List<String>.from(history)..remove(query);
    return next;
  }
}
