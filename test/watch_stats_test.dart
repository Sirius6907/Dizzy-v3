import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/continue_watching/continue_watching_item.dart';
import 'package:dizzy/services/stats/watch_stats.dart';

ContinueWatchingItem item({
  required String id,
  required int pos,
  required int total,
  required DateTime at,
  String type = 'movie',
}) => ContinueWatchingItem(
  id: id,
  title: id,
  type: type,
  positionSeconds: pos,
  totalDurationSeconds: total,
  lastWatchedAt: at,
  isTorrent: false,
);

void main() {
  group('F5 WatchStats.aggregate (v1.1.9)', () {
    test('empty list returns empty', () {
      expect(WatchStats.aggregate([]), WatchStats.empty);
    });

    test('minutes + finished counting', () {
      final now = DateTime(2026, 9, 8, 12);
      final items = [
        // 60/120 min → 60 min watched, not finished (50%)
        item(id: 'a', pos: 3600, total: 7200, at: now),
        // 108/120 min → 108 min, finished (90%)
        item(id: 'b', pos: 6480, total: 7200, at: now),
      ];
      final s = WatchStats.aggregate(items, now: now);
      expect(s.titlesCount, 2);
      expect(s.minutesWatched, 168);
      expect(s.episodesFinished, 1);
      expect(s.hoursLabel, '2h 48m');
    });

    test('streak counts consecutive days ending today', () {
      final now = DateTime(2026, 9, 8, 12);
      final items = [
        item(id: 'a', pos: 60, total: 600, at: now),
        item(
          id: 'b',
          pos: 60,
          total: 600,
          at: now.subtract(const Duration(days: 1)),
        ),
        item(
          id: 'c',
          pos: 60,
          total: 600,
          at: now.subtract(const Duration(days: 2)),
        ),
        // gap, then older — streak stops at 3
        item(
          id: 'd',
          pos: 60,
          total: 600,
          at: now.subtract(const Duration(days: 4)),
        ),
      ];
      final s = WatchStats.aggregate(items, now: now);
      expect(s.currentStreakDays, 3);
    });

    test('streak tolerates today-not-yet-watched', () {
      final now = DateTime(2026, 9, 8, 12);
      final items = [
        item(
          id: 'a',
          pos: 60,
          total: 600,
          at: now.subtract(const Duration(days: 1)),
        ),
      ];
      final s = WatchStats.aggregate(items, now: now);
      expect(s.currentStreakDays, 1);
    });

    test('type counts split series/movies', () {
      final now = DateTime(2026, 9, 8, 12);
      final items = [
        item(id: 'a', pos: 60, total: 600, at: now, type: 'series'),
        item(id: 'b', pos: 60, total: 600, at: now, type: 'series'),
        item(id: 'c', pos: 60, total: 600, at: now, type: 'movie'),
      ];
      final s = WatchStats.aggregate(items, now: now);
      expect(s.typeCounts['series'], 2);
      expect(s.typeCounts['movie'], 1);
    });
  });

  group('WatchStats.weekly (v1.3.3 Phase 5)', () {
    test('only counts the last seven days', () {
      final now = DateTime(2026, 10, 31, 20);
      final items = [
        item(id: 'today', pos: 1200, total: 6000, at: now),
        item(
          id: 'three',
          pos: 600,
          total: 6000,
          at: now.subtract(const Duration(days: 3)),
        ),
        item(
          id: 'eight',
          pos: 6000,
          total: 6000,
          at: now.subtract(const Duration(days: 8)),
        ),
      ];

      final w = WatchStats.weekly(items, now: now);

      expect(w.titlesCount, 2);
      expect(w.minutesWatched, 30);
      expect(w.episodesFinished, 0);
    });

    test('finished inside the window still counts', () {
      final now = DateTime(2026, 10, 31, 20);
      final items = [
        item(
          id: 'done',
          pos: 6480,
          total: 7200,
          at: now.subtract(const Duration(days: 2)),
        ),
      ];

      expect(WatchStats.weekly(items, now: now).episodesFinished, 1);
    });

    test('an old-only list returns empty', () {
      final now = DateTime(2026, 10, 31, 20);
      final items = [
        item(
          id: 'old',
          pos: 600,
          total: 6000,
          at: now.subtract(const Duration(days: 30)),
        ),
      ];

      final w = WatchStats.weekly(items, now: now);

      expect(w.titlesCount, 0);
      expect(w.minutesWatched, 0);
      expect(w.hoursLabel, '0 min');
    });
  });
}
