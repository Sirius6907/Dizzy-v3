import '../../models/continue_watching/continue_watching_item.dart';

/// F5 (v1.1.9): "My Dizzy Wrap" aggregates. Pure functions over
/// ContinueWatching items — fully unit-testable, zero UI.
class WatchStats {
  final int titlesCount;
  final int episodesFinished;
  final int minutesWatched;
  final int currentStreakDays;
  final Map<String, int> typeCounts; // movie / series

  const WatchStats({
    required this.titlesCount,
    required this.episodesFinished,
    required this.minutesWatched,
    required this.currentStreakDays,
    required this.typeCounts,
  });

  static const empty = WatchStats(
    titlesCount: 0,
    episodesFinished: 0,
    minutesWatched: 0,
    currentStreakDays: 0,
    typeCounts: {},
  );

  /// Aggregate from CW items. `now` injectable for tests.
  static WatchStats aggregate(
    List<ContinueWatchingItem> items, {
    DateTime? now,
  }) {
    if (items.isEmpty) return empty;
    final today = now ?? DateTime.now();

    var minutes = 0;
    var episodes = 0;
    final types = <String, int>{};
    final days = <String>{};

    for (final it in items) {
      minutes += (it.positionSeconds ~/ 60);
      if (it.isCompleted) episodes++;
      types[it.type] = (types[it.type] ?? 0) + 1;
      final d = it.lastWatchedAt;
      days.add('${d.year}-${d.month}-${d.day}');
    }

    // Streak: consecutive days ending today/yesterday.
    var streak = 0;
    var cursor = DateTime(today.year, today.month, today.day);
    // Allow "today not yet watched" — start from yesterday if needed.
    String key(DateTime d) => '${d.year}-${d.month}-${d.day}';
    if (!days.contains(key(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (days.contains(key(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return WatchStats(
      titlesCount: items.length,
      episodesFinished: episodes,
      minutesWatched: minutes,
      currentStreakDays: streak,
      typeCounts: types,
    );
  }

  String get hoursLabel {
    if (minutesWatched < 60) return '$minutesWatched min';
    final h = minutesWatched ~/ 60;
    final m = minutesWatched % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
