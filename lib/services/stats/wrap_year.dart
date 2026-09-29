/// F5 — Yearly Wrapped: the numbers, then the words.
///
/// [WatchStats] already answers "how much" over whatever list it is handed.
/// This file answers the two questions that only make sense for a *year*:
///
///   1. Which year are we wrapping?
///   2. What is the one sentence a person would actually want to send?
///
/// The share line is built here, not in the widget, so the exact text a
/// person pastes into a chat is unit tested. A share card whose words drift
/// between builds is a card nobody screenshots twice.
///
/// Pure — no Flutter, no storage, no network.
library;

import '../../models/continue_watching/continue_watching_item.dart';
import 'watch_stats.dart';

/// A flattened watch item, so this file stays free of the player model.
class WrapFact {
  final String title;
  final String type;
  final int minutes;
  final DateTime watchedAt;

  /// The whole title was watched (90% or more).
  final bool finished;

  const WrapFact({
    required this.title,
    required this.type,
    required this.minutes,
    required this.watchedAt,
    this.finished = false,
  });

  bool get isUsable => title.trim().isNotEmpty;
}

/// The finished numbers for one year.
class YearlyWrap {
  /// The year these numbers belong to.
  final int year;

  final int minutesWatched;
  final int titlesFinished;
  final int titlesStarted;

  /// Longest run of consecutive days with any watch time in the year.
  final int longestStreakDays;

  /// Longest single sitting, in minutes.
  final int longestSessionMinutes;

  /// Most-watched type: `'movie'` or `'series'`. Empty when nothing watched.
  final String topType;

  /// Busiest calendar day, `null` when nothing watched.
  final DateTime? busiestDay;
  final int busiestDayMinutes;

  const YearlyWrap({
    required this.year,
    required this.minutesWatched,
    required this.titlesFinished,
    required this.titlesStarted,
    required this.longestStreakDays,
    required this.longestSessionMinutes,
    required this.topType,
    required this.busiestDay,
    required this.busiestDayMinutes,
  });

  static YearlyWrap empty(int year) => YearlyWrap(
        year: year,
        minutesWatched: 0,
        titlesFinished: 0,
        titlesStarted: 0,
        longestStreakDays: 0,
        longestSessionMinutes: 0,
        topType: '',
        busiestDay: null,
        busiestDayMinutes: 0,
      );

  bool get hasAnything => minutesWatched > 0 || titlesStarted > 0;

  /// `12h 30m`
  String get hoursLabel {
    if (minutesWatched < 60) return '${minutesWatched}m';
    final h = minutesWatched ~/ 60;
    final m = minutesWatched % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  /// Aggregate one year of facts.
  ///
  /// `year` is injectable so a test can pin the calendar and so the wrap for
  /// last year can be opened later without changing any other call site.
  static YearlyWrap fromFacts(
    List<WrapFact> facts, {
    int year = 0,
  }) {
    final usable = facts.where((f) => f.isUsable && f.minutes > 0).toList();
    if (usable.isEmpty) return empty(year);

    final targetYear = year != 0
        ? year
        : usable
            .map((f) => f.watchedAt.year)
            .reduce((a, b) => a > b ? a : b);

    final inYear = usable
        .where((f) => f.watchedAt.year == targetYear)
        .toList();
    if (inYear.isEmpty) return empty(targetYear);

    var minutes = 0;
    var longestSession = 0;
    final days = <DateTime, int>{};
    final titles = <String>{};
    var finished = 0;
    var seriesMinutes = 0;
    var movieMinutes = 0;

    for (final f in inYear) {
      minutes += f.minutes;
      if (f.minutes > longestSession) longestSession = f.minutes;
      final key = DateTime(f.watchedAt.year, f.watchedAt.month, f.watchedAt.day);
      days[key] = (days[key] ?? 0) + f.minutes;
      titles.add(f.title);
      if (f.finished) finished++;
      if (f.type.trim().toLowerCase() == 'series') {
        seriesMinutes += f.minutes;
      } else {
        movieMinutes += f.minutes;
      }
    }

    DateTime? busiest;
    var busiestMinutes = 0;
    days.forEach((day, mins) {
      // Strictly greater wins; the map is walked in insertion order and ties
      // keep the first day seen, so the answer never depends on hash order.
      if (mins > busiestMinutes) {
        busiest = day;
        busiestMinutes = mins;
      }
    });

    return YearlyWrap(
      year: targetYear,
      minutesWatched: minutes,
      titlesFinished: finished,
      titlesStarted: titles.length,
      longestStreakDays: _longestStreak(days.keys.toList()),
      longestSessionMinutes: longestSession,
      topType: seriesMinutes == movieMinutes
          ? ''
          : (seriesMinutes > movieMinutes ? 'series' : 'movie'),
      busiestDay: busiest,
      busiestDayMinutes: busiestMinutes,
    );
  }

  /// Longest run of consecutive days in [days].
  static int _longestStreak(List<DateTime> days) {
    if (days.isEmpty) return 0;
    final sorted = days.toList()..sort();
    var best = 1;
    var run = 1;
    for (var i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1];
      final cur = sorted[i];
      final gapDays = DateTime(cur.year, cur.month, cur.day)
          .difference(DateTime(prev.year, prev.month, prev.day))
          .inDays;
      if (gapDays == 1) {
        run++;
        if (run > best) best = run;
      } else if (gapDays > 1) {
        run = 1;
      }
    }
    return best;
  }

  /// Build from the live continue-watching list. Same rows the stats page
  /// reads, so the wrap never invents a total of its own.
  static YearlyWrap fromItems(
    List<ContinueWatchingItem> items, {
    int year = 0,
  }) =>
      fromFacts(
        items
            .map((i) => WrapFact(
                  title: i.title,
                  type: i.type,
                  minutes: i.positionSeconds ~/ 60,
                  watchedAt: i.lastWatchedAt,
                  // Same completion rule the stats page uses.
                  finished: i.isCompleted,
                ))
            .toList(),
        year: year,
      );

  /// The existing aggregate, for the tiles that already have a shape.
  WatchStats toWatchStats() => WatchStats(
        titlesCount: titlesStarted,
        episodesFinished: titlesFinished,
        minutesWatched: minutesWatched,
        currentStreakDays: longestStreakDays,
        typeCounts: topType.isEmpty
            ? const {}
            : {topType: titlesStarted},
      );
}

/// The words on the card, and the one line a person shares.
abstract final class WrapShareCopy {
  const WrapShareCopy._();

  /// Headline above the big number.
  static String title(YearlyWrap w) => 'Your ${w.year} in stories';

  /// One short line under the number. Never an empty string — an empty card
  /// reads as broken.
  static String hoursLine(YearlyWrap w) {
    if (w.minutesWatched <= 0) return 'Your story starts with one tap.';
    return 'You watched ${w.hoursLabel} of stories this year.';
  }

  /// Streak tile label.
  static String streakLine(YearlyWrap w) {
    if (w.longestStreakDays <= 0) return 'Watch daily to start a streak';
    if (w.longestStreakDays == 1) return '1 day in a row — streak lit!';
    return '${w.longestStreakDays} days in a row — keep it burning!';
  }

  /// What the person watched most.
  static String topTypeLine(YearlyWrap w) {
    if (w.topType.isEmpty) return 'You mixed movies and shows.';
    return w.topType == 'series'
        ? 'Shows carried your year.'
        : 'Movies carried your year.';
  }

  /// The shareable line. Short on purpose: it is read in a chat, next to
  /// other messages, on a small screen.
  static String shareText(YearlyWrap w) {
    if (!w.hasAnything) {
      return 'My Dizzy ${w.year}: the year starts now.';
    }
    final buf = StringBuffer();
    buf.write('My Dizzy ${w.year}: ${w.hoursLabel} watched');
    if (w.titlesStarted > 0) buf.write(', ${w.titlesStarted} titles');
    if (w.longestStreakDays > 0) {
      buf.write(', ${w.longestStreakDays}-day streak');
    }
    buf.write('.');
    return buf.toString();
  }

  /// The headline of an empty wrap. Same function as `shareText`, so the two
  /// can never say different things about a fresh install.
  static String emptyLine(int year) => 'My Dizzy $year: the year starts now.';
}
