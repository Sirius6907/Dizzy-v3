import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/ai/mood_quiz_policy.dart';
import 'package:dizzy/services/calendar/reminder_schedule.dart';
import 'package:dizzy/services/discover/discover_copy.dart';
import 'package:dizzy/services/discover/history_rail_policy.dart';
import 'package:dizzy/services/stats/wrap_year.dart';

/// F5 — Discover Daily proofs.
///
/// Everything here is pure policy: no player, no network, no login. If a
/// test in this file needs a platform channel, the policy leaked I/O and the
/// policy is what gets fixed — not the test.
void main() {
  // ── Shared fixtures ──────────────────────────────────────────────────────
  // Not const: DateTime literals are not constant expressions.
  final seed = WatchSignal(
    mediaId: 'fc',
    title: 'Fight Club',
    type: 'movie',
    genres: const ['Drama', 'Thriller'],
    watchedAt: DateTime(2026, 9, 1),
    progress: 1.0,
  );

  const candidates = [
    RailCandidate(
      id: 'c1',
      title: 'Se7en',
      type: 'movie',
      genres: ['Drama', 'Thriller', 'Crime'],
      rating: 8.6,
    ),
    RailCandidate(
      id: 'c2',
      title: 'The Machinist',
      type: 'movie',
      genres: ['Drama', 'Thriller'],
      rating: 7.7,
    ),
    RailCandidate(
      id: 'c3',
      title: 'Bluey',
      type: 'series',
      genres: ['Animation', 'Family'],
      rating: 9.1,
    ),
    RailCandidate(
      id: 'fc',
      title: 'Fight Club',
      type: 'movie',
      genres: ['Drama', 'Thriller'],
      rating: 8.8,
    ),
  ];

  // Not const: tests mutate a copy to change one answer at a time.
  Map<String, String?> complete() => <String, String?>{
        'mood': 'chill',
        'budget': 'oneNight',
        'company': 'alone',
      };

  group('F5 rails — a rail is caused by something real', () {
    test('history seed produces a rail that names its cause', () {
      final rails = HistoryRailPolicy.railsFrom(
        [seed],
        candidates: candidates,
      );

      expect(rails, hasLength(1));
      expect(rails.first.title, 'Because you watched Fight Club');
      expect(rails.first.picks, isNotEmpty);
      expect(rails.first.picks.first.because, 'Fight Club');
    });

    test('a title never re-suggests itself', () {
      final rails = HistoryRailPolicy.railsFrom(
        [seed],
        candidates: candidates,
      );

      expect(rails.first.picks.map((p) => p.id), isNot(contains('fc')));
    });

    test('no title appears on two rails', () {
      final other = WatchSignal(
        mediaId: 'se7en',
        title: 'Se7en',
        type: 'movie',
        genres: const ['Crime', 'Thriller'],
        watchedAt: DateTime(2026, 8, 20),
        progress: 1.0,
      );

      final rails = HistoryRailPolicy.railsFrom(
        [seed, other],
        candidates: candidates,
      );

      final seen = <String>{};
      for (final rail in rails) {
        for (final pick in rail.picks) {
          expect(
            seen.add(pick.id),
            isTrue,
            reason: '${pick.id} appeared on more than one rail',
          );
        }
      }
    });

    test('genre overlap beats a genre mismatch', () {
      final rails = HistoryRailPolicy.railsFrom(
        [seed],
        candidates: candidates,
      );

      final ids = rails.first.picks.map((p) => p.id).toList();
      // c1 and c2 share Drama+Thriller with the seed; c3 shares nothing.
      expect(ids.indexOf('c1'), lessThan(ids.indexOf('c3')));
      expect(ids.indexOf('c2'), lessThan(ids.indexOf('c3')));
    });

    test('the same history builds the same rails every time', () {
      final a = HistoryRailPolicy.railsFrom([seed], candidates: candidates);
      final b = HistoryRailPolicy.railsFrom([seed], candidates: candidates);

      expect(
        a.first.picks.map((p) => p.id).toList(),
        b.first.picks.map((p) => p.id).toList(),
      );
    });

    test('empty history gets the honest start-anywhere rail', () {
      final rails = HistoryRailPolicy.discoverRails(
        signals: const [],
        candidates: candidates,
      );

      expect(rails, hasLength(1));
      expect(rails.first.id, 'rail:start-anywhere');
      expect(rails.first.title, RailCopy.fallbackTitle);
      expect(rails.first.picks, isNotEmpty);
      // Nothing caused it, so it must not claim a cause.
      expect(rails.first.picks.every((p) => p.because.isEmpty), isTrue);
    });

    test('unusable history rows are skipped, not crashed on', () {
      final broken = WatchSignal(
        mediaId: '  ',
        title: '',
        type: 'movie',
        watchedAt: DateTime(2026, 9, 1),
      );

      final rails = HistoryRailPolicy.discoverRails(
        signals: [broken],
        candidates: candidates,
      );

      expect(rails, hasLength(1));
      expect(rails.first.id, 'rail:start-anywhere');
    });
  });

  group('F5 mood quiz — three taps, then tonight is sorted', () {
    test('three answers build a profile, missing answers do not', () {
      expect(MoodQuizPolicy.isComplete(complete()), isTrue);
      expect(MoodQuizPolicy.profileFrom(const {}), isNull);

      final twoAnswers = <String, String?>{
        'mood': 'chill',
        'budget': 'quick',
      };
      expect(MoodQuizPolicy.profileFrom(twoAnswers), isNull);
      expect(MoodQuizPolicy.unanswered(twoAnswers), hasLength(1));
    });

    test('an unknown answer id is refused instead of guessed', () {
      final answers = <String, String?>{
        'mood': 'manic',
        'budget': 'oneNight',
        'company': 'alone',
      };
      expect(MoodQuizPolicy.profileFrom(answers), isNull);
    });

    test('every option id the sheet shows round-trips into a profile', () {
      // Regression: 'oneNight' is camelCase, and fromId used to lowercase
      // only the input — so the middle time option could never complete the
      // quiz. Every option in the question sheet must resolve.
      for (final q in MoodQuizPolicy.questions) {
        for (final option in q.options) {
          final answers = complete();
          answers[q.id] = option;
          expect(
            MoodQuizPolicy.isComplete(answers),
            isTrue,
            reason: 'option "${q.id}:$option" never completed the quiz',
          );
        }
      }
    });

    test('picks are local, in order, and each carries a reason', () {
      final profile = MoodQuizPolicy.profileFrom(complete())!;
      final picks = MoodQuizPolicy.localPicksFor(profile);

      expect(picks, hasLength(3));
      expect(picks.every((p) => p.reason.trim().isNotEmpty), isTrue);
      expect(
        picks.map((p) => MoodQuizPolicy.pickLine(p)).toList(),
        MoodQuizPolicy.pickLines(picks),
      );

      final again = MoodQuizPolicy.localPicksFor(profile);
      expect(
        picks.map((p) => p.title).toList(),
        again.map((p) => p.title).toList(),
      );
    });

    test('guidance is the string the existing quiz pipeline already takes', () {
      final profile = MoodQuizPolicy.profileFrom(complete())!;
      final guidance = MoodQuizPolicy.guidanceFor(profile);

      expect(guidance, contains('Mood: Chill'));
      expect(guidance, contains('Time: One evening'));
      expect(guidance, contains('Watching with: Just me'));
    });
  });

  group('F5 reminders — a nudge with no account', () {
    final now = DateTime(2026, 9, 10, 8);
    final airsAt = DateTime(2026, 9, 12, 21);

    ReminderRequest request({int lead = 30}) => ReminderRequest(
          showTitle: 'The Bear',
          season: 4,
          episode: 2,
          leadMinutes: lead,
        );

    test('a follow becomes one slot that fires before air time', () {
      final slots = ReminderSchedule.build(
        [request()],
        [
          CalendarAiring(
            showTitle: 'The Bear',
            season: 4,
            episode: 2,
            episodeTitle: 'Next',
            airsAt: DateTime(2026, 9, 12, 21),
          ),
        ],
        now: now,
      );

      expect(slots, hasLength(1));
      expect(slots.first.episodeCode, 'S04E02');
      expect(slots.first.remindAt.isBefore(airsAt), isTrue);
      expect(slots.first.remindAt.isAfter(now), isTrue);
    });

    test('a past fire time is pulled to now, never dropped', () {
      final fired = ReminderSchedule.remindAtFor(
        now.subtract(const Duration(minutes: 10)),
        30,
        now,
      );
      expect(fired, now);
    });

    test('lead minutes are clamped into the honoured range', () {
      expect(ReminderSchedule.clampLead(-5), ReminderSchedule.minLeadMinutes);
      expect(
        ReminderSchedule.clampLead(100000),
        ReminderSchedule.maxLeadMinutes,
      );
      expect(ReminderSchedule.clampLead(45), 45);
    });

    test('the same episode followed twice fires once', () {
      final airing = CalendarAiring(
        showTitle: 'The Bear',
        season: 4,
        episode: 2,
        episodeTitle: 'Next',
        airsAt: DateTime(2026, 9, 12, 21),
      );

      final slots = ReminderSchedule.build(
        [request(), request()],
        [airing, airing],
        now: now,
      );

      expect(slots, hasLength(1));
    });

    test('stopping a follow actually silences its alerts', () {
      final airing = CalendarAiring(
        showTitle: 'The Bear',
        season: 4,
        episode: 2,
        episodeTitle: 'Next',
        airsAt: DateTime(2026, 9, 12, 21),
      );
      final slots = ReminderSchedule.build(
        [request()],
        [airing],
        now: now,
      );

      final silenced = ReminderSchedule.without(slots, {'the bear'});
      expect(silenced, isEmpty);
      expect(ReminderSchedule.next(slots), isNotNull);
      expect(ReminderSchedule.next(const []), isNull);
    });

    test('an episode outside the horizon is left unscheduled', () {
      final slots = ReminderSchedule.build(
        [request()],
        [
          CalendarAiring(
            showTitle: 'The Bear',
            season: 4,
            episode: 2,
            episodeTitle: 'Next',
            airsAt: DateTime(2027, 1, 1, 21),
          ),
        ],
        now: now,
      );

      expect(slots, isEmpty);
    });
  });

  group('F5 wrap — the numbers, then the words', () {
    test('a year of facts aggregates to the right totals', () {
      final facts = [
        WrapFact(
          title: 'Dune',
          type: 'movie',
          minutes: 155,
          watchedAt: DateTime(2026, 2, 1),
          finished: true,
        ),
        WrapFact(
          title: 'The Bear',
          type: 'series',
          minutes: 30,
          watchedAt: DateTime(2026, 2, 2),
        ),
        WrapFact(
          title: 'The Bear',
          type: 'series',
          minutes: 30,
          watchedAt: DateTime(2026, 2, 3),
        ),
        // Wrong year — must not leak into the 2026 totals.
        WrapFact(
          title: 'Old Film',
          type: 'movie',
          minutes: 90,
          watchedAt: DateTime(2025, 6, 1),
        ),
        // Unusable row — dropped, not counted.
        WrapFact(
          title: '   ',
          type: 'movie',
          minutes: 60,
          watchedAt: DateTime(2026, 3, 1),
        ),
      ];

      final wrap = YearlyWrap.fromFacts(facts, year: 2026);

      expect(wrap.year, 2026);
      expect(wrap.minutesWatched, 215);
      expect(wrap.titlesStarted, 2);
      expect(wrap.titlesFinished, 1);
      expect(wrap.busiestDay, DateTime(2026, 2, 1));
      expect(wrap.busiestDayMinutes, 155);
      // 155 movie minutes vs 60 series minutes.
      expect(wrap.topType, 'movie');
    });

    test('a year with nothing watched says so instead of showing zeros', () {
      final wrap = YearlyWrap.fromFacts(const [], year: 2026);

      expect(wrap.hasAnything, isFalse);
      expect(WrapShareCopy.hoursLine(wrap), 'Your story starts with one tap.');
      expect(WrapShareCopy.shareText(wrap), WrapShareCopy.emptyLine(2026));
      expect(WrapShareCopy.streakLine(wrap), 'Watch daily to start a streak');
    });

    test('the share line is short, Easy English, and factually its own', () {
      final facts = [
        for (var d = 1; d <= 3; d++)
          WrapFact(
            title: 'Title $d',
            type: 'series',
            minutes: 45,
            watchedAt: DateTime(2026, 5, d),
            finished: true,
          ),
      ];

      final wrap = YearlyWrap.fromFacts(facts, year: 2026);
      final share = WrapShareCopy.shareText(wrap);

      expect(share, startsWith('My Dizzy 2026:'));
      expect(share.length, lessThan(90));
      expect(share, contains('2h 15m'));
      expect(share, contains('3 titles'));
      expect(share, contains('3-day streak'));
      expect(WrapShareCopy.title(wrap), 'Your 2026 in stories');
      expect(WrapShareCopy.topTypeLine(wrap), 'Shows carried your year.');
    });
  });

  group('F5 copy — Easy English, no tech words leak', () {
    const banned = [
      'exception',
      'stacktrace',
      'stack trace',
      'nullptr',
      'nullpointer',
      'e_net_',
      'e_http_',
      'e_unknown',
      'socketexception',
      'timeoutexception',
      'httpexception',
      'formatexception',
    ];

    test('every discover line reads as plain English', () {
      final lines = <String>[
        DiscoverCopy.title,
        DiscoverCopy.tagline,
        DiscoverCopy.loading,
        DiscoverCopy.emptyTitle,
        DiscoverCopy.emptyLine,
        DiscoverCopy.musicRailTitle,
        DiscoverCopy.quizRailTitle,
        DiscoverCopy.remindersTitle,
        DiscoverCopy.wrapTitle,
        DiscoverCopy.railsSection,
        DiscoverCopy.railError('E_UNKNOWN: boom'),
        DiscoverCopy.railCount(0),
        DiscoverCopy.railCount(1),
        DiscoverCopy.railCount(7),
        RailCopy.railTitle('Fight Club'),
        RailCopy.railSubtitle(7),
        RailCopy.fallbackTitle,
        RailCopy.fallbackSubtitle,
        ReminderCopy.title,
        ReminderCopy.empty,
        ReminderCopy.following(0),
        ReminderCopy.following(1),
        ReminderCopy.following(4),
        ReminderCopy.nextLine(null),
      ];

      for (final line in lines) {
        expect(line.trim(), isNotEmpty);
        for (final bad in banned) {
          expect(
            line.toLowerCase().contains(bad),
            isFalse,
            reason: 'copy leaked a tech word: "$line"',
          );
        }
      }

      // The error line never echoes the raw failure back at a person.
      expect(DiscoverCopy.railError('E_HLS_403 from player'), isNot(contains('403')));
    });

    test('counts read naturally at 0, 1 and many', () {
      expect(DiscoverCopy.railCount(0), 'No picks yet');
      expect(DiscoverCopy.railCount(1), '1 pick for you');
      expect(DiscoverCopy.railCount(12), '12 picks for you');
      expect(ReminderCopy.following(1), 'Following 1 show');
      expect(ReminderCopy.following(3), 'Following 3 shows');
    });
  });
}