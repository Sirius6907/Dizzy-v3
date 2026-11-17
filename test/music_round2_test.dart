import 'dart:async';
import 'dart:io';

import 'package:dizzy/models/music/music_track.dart';
import 'package:dizzy/services/music/music_engagement_service.dart';
import 'package:dizzy/services/music/music_mood_filter.dart';
import 'package:dizzy/services/music/music_radio_service.dart';
import 'package:dizzy/services/music/music_service.dart';
import 'package:dizzy/services/music/music_trend_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round 2 verification — album completeness gate, taste-driven up-next,
/// date-seeded daily mixes, trend rotation, and the no-hardcode audit
/// (grep-as-test) demanded by MUSIC_CREATOR_ROUND2.md.
MusicTrack _t(String id) => MusicTrack(
  id: id,
  title: 'Track $id',
  artist: 'Artist $id',
  album: 'Album $id',
  coverUrl: '',
  durationSeconds: 200,
);

/// Generic latin-bucket track so language scores are uniform (both
/// providers share the latin bucket — keeps steering math disjoint).
MusicTrack _by(String id, String artist, String title) => MusicTrack(
  id: id,
  title: title,
  artist: artist,
  album: 'Common Stage',
  coverUrl: '',
  durationSeconds: 200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'music home source contract excludes geo-dependent global artist charts',
    () {
      final source = File(
        'lib/services/music/music_service.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('_deezer.getChartArtists(')));
    },
  );

  // Reset all seams + session state after every test (addTearDown must be
  // registered inside setUp, which runs within a test scope).
  setUp(() {
    addTearDown(() {
      MusicRadioService.instance.searchSeam = null;
      MusicEngagementService.instance.candidateSeam = null;
      MusicEngagementService.instance.resetSessionForTest();
    });
  });

  group('Round 2 — album completeness gate (Complaint 1)', () {
    test('declared trackCount >= 5 makes a card album-worthy', () {
      const album = MusicAlbum(
        id: 'alb1',
        title: 'Some Album',
        artistName: 'Someone',
        coverUrl: '',
        trackCount: 9,
        tracks: [],
      );
      expect(MusicService.isAlbumCardComplete(album), isTrue);
    });

    test('resolved tracks >= 5 make a card album-worthy even with count 0', () {
      final album = MusicAlbum(
        id: 'alb2',
        title: 'Resolved Album',
        artistName: 'Someone',
        coverUrl: '',
        trackCount: 0,
        tracks: List.generate(5, (i) => _t('r$i')),
      );
      expect(MusicService.isAlbumCardComplete(album), isTrue);
    });

    test('1-2-track bodies can never present themselves as albums', () {
      final thinCard = MusicAlbum(
        id: 'alb3',
        title: 'Thin Card',
        artistName: 'Someone',
        coverUrl: '',
        trackCount: 2,
        tracks: [_t('x1'), _t('x2')],
      );
      expect(MusicService.isAlbumCardComplete(thinCard), isFalse);

      const empty = MusicAlbum(
        id: 'alb4',
        title: 'Empty Card',
        artistName: 'Someone',
        coverUrl: '',
      );
      expect(MusicService.isAlbumCardComplete(empty), isFalse);
    });
  });

  group('Round 2 — day seed and time buckets (Complaints 3/4/5)', () {
    test('daySeed is stable across the same day and flips across days', () {
      final d1 = DateTime(2026, 11, 10);
      final d1Again = DateTime(2026, 11, 10, 18, 30);
      final d2 = DateTime(2026, 11, 11);
      expect(
        MusicEngagementCore.daySeed(d1),
        MusicEngagementCore.daySeed(d1Again),
        reason: 'same-day properties must hold',
      );
      expect(
        MusicEngagementCore.daySeed(d1),
        isNot(MusicEngagementCore.daySeed(d2)),
        reason: 'next-day properties must rotate (proven with fake dates)',
      );
    });

    test('timeBucket boundaries: <6 and 22+ are late night', () {
      const table = <int, MusicTimeBucket>{
        5: MusicTimeBucket.lateNight,
        6: MusicTimeBucket.morning,
        11: MusicTimeBucket.morning,
        12: MusicTimeBucket.afternoon,
        16: MusicTimeBucket.afternoon,
        17: MusicTimeBucket.evening,
        21: MusicTimeBucket.evening,
        22: MusicTimeBucket.lateNight,
      };
      table.forEach((hour, bucket) {
        expect(
          MusicEngagementCore.timeBucket(DateTime(2026, 11, 10, hour)),
          bucket,
          reason: 'hour $hour should be $bucket',
        );
      });
    });

    test('moodOrder is a complete permutation and is bucket-aware', () {
      const firstByBucket = <MusicTimeBucket, MusicMood>{
        MusicTimeBucket.morning: MusicMood.focus,
        MusicTimeBucket.afternoon: MusicMood.happy,
        MusicTimeBucket.evening: MusicMood.energetic,
        MusicTimeBucket.lateNight: MusicMood.chill,
      };
      firstByBucket.forEach((bucket, expectedFirst) {
        final order = MusicEngagementCore.moodOrder(bucket);
        expect(
          order.toSet().length,
          order.length,
          reason: 'no duplicated moods for $bucket',
        );
        expect(
          order.length,
          MusicMood.values.length - 1,
          reason: 'every real mood ordered once (any excluded)',
        );
        expect(order.first, expectedFirst);
        expect(order.contains(MusicMood.any), isFalse);
      });
    });
  });

  group('Round 2 — up-next taste engine (Complaint 2)', () {
    test('rankUpNext: seed artist block always outranks the rest', () {
      final seed = _by('seed-a', 'Atra Vibe', 'Seed Anthem A');
      final candidates = [
        _by('a1', 'Atra Vibe', 'Track A1'),
        _by('be1', 'Bora Lane', 'Track B1'),
        _by('a2', 'Atra Vibe', 'Track A2'),
        _by('be2', 'Bora Lane', 'Track B2'),
        _by('a3', 'Atra Vibe', 'Track A3'),
        _by('be3', 'Bora Lane', 'Track B3'),
      ];
      final ranked = MusicEngagementCore.rankUpNext(
        seed: seed,
        candidates: candidates,
        daySeed: MusicEngagementCore.daySeed(DateTime(2026, 11, 10)),
        limit: 6,
      );
      expect(ranked.length, 6);
      expect(
        ranked.take(3).every((t) => t.artist == 'Atra Vibe'),
        isTrue,
        reason: 'same-artist block (+30) dominates (+8 pool)',
      );
    });

    test('seed-change flips up-next even with identical candidates', () {
      final candidates = [
        _by('a1', 'Atra Vibe', 'Track A1'),
        _by('be1', 'Bora Lane', 'Track B1'),
        _by('a2', 'Atra Vibe', 'Track A2'),
        _by('be2', 'Bora Lane', 'Track B2'),
      ];
      final seedA = _by('seed-a', 'Atra Vibe', 'Seed Anthem A');
      final seedB = _by('seed-b', 'Bora Lane', 'Seed Anthem B');
      final day = MusicEngagementCore.daySeed(DateTime(2026, 11, 10));
      final forA = MusicEngagementCore.rankUpNext(
        seed: seedA,
        candidates: candidates,
        daySeed: day,
        limit: 4,
      );
      final forB = MusicEngagementCore.rankUpNext(
        seed: seedB,
        candidates: candidates,
        daySeed: day,
        limit: 4,
      );
      expect(forA.first.artist, 'Atra Vibe');
      expect(forB.first.artist, 'Bora Lane');
      expect(
        forA.map((t) => t.id).join(','),
        isNot(forB.map((t) => t.id).join(',')),
        reason: 'different playing song → visibly different up-next',
      );
    });

    test(
      'cold start: empty candidates produces an empty rail (no fallback)',
      () {
        final seed = _by('s', 'Atra Vibe', 'Seed Anthem A');
        final ranked = MusicEngagementCore.rankUpNext(
          seed: seed,
          candidates: const [],
          daySeed: MusicEngagementCore.daySeed(DateTime(2026, 11, 10)),
        );
        expect(ranked, isEmpty);
      },
    );

    test('session skip signal steers candidates away (order change)', () {
      final seed = _by('seed-n', 'Neutral Base', 'Seed Anthem');
      final candidates = [
        _by('au1', 'Aurora Kin', 'Track U1'),
        _by('ba1', 'Bastille Nine', 'Track N1'),
        _by('au2', 'Aurora Kin', 'Track U2'),
        _by('ba2', 'Bastille Nine', 'Track N2'),
        _by('au3', 'Aurora Kin', 'Track U3'),
        _by('ba3', 'Bastille Nine', 'Track N3'),
      ];
      final day = MusicEngagementCore.daySeed(DateTime(2026, 11, 10));
      final withoutSkip = MusicEngagementCore.rankUpNext(
        seed: seed,
        candidates: candidates,
        daySeed: day,
        limit: 6,
      );
      final withSkip = MusicEngagementCore.rankUpNext(
        seed: seed,
        candidates: candidates,
        skips: const {'aurora kin': 2},
        daySeed: day,
        limit: 6,
      );
      expect(
        withoutSkip.map((t) => t.id).join(','),
        isNot(withSkip.map((t) => t.id).join(',')),
        reason: 'signal must be observable as an order change',
      );
      final skipPositions = withSkip
          .where((t) => t.artist == 'Aurora Kin')
          .length;
      expect(
        withSkip
            .sublist(withSkip.length - skipPositions)
            .every((t) => t.artist == 'Aurora Kin'),
        isTrue,
        reason: 'every skipped-artist track sinks below the rest (-50)',
      );
    });

    test('session like/boost signal lifts candidates (order change)', () {
      final seed = _by('seed-n', 'Neutral Base', 'Seed Anthem');
      final candidates = [
        _by('au1', 'Aurora Kin', 'Track U1'),
        _by('ba1', 'Bastille Nine', 'Track N1'),
        _by('au2', 'Aurora Kin', 'Track U2'),
        _by('ba2', 'Bastille Nine', 'Track N2'),
      ];
      final day = MusicEngagementCore.daySeed(DateTime(2026, 11, 10));
      final withBoost = MusicEngagementCore.rankUpNext(
        seed: seed,
        candidates: candidates,
        boosts: const {'bastille nine': 2},
        daySeed: day,
        limit: 4,
      );
      final boostCount = withBoost
          .where((t) => t.artist == 'Bastille Nine')
          .length;
      expect(
        withBoost
            .sublist(0, boostCount)
            .every((t) => t.artist == 'Bastille Nine'),
        isTrue,
        reason: 'boosted artist (+12) dominates the unboosted pool (+8)',
      );
    });
  });

  group('Round 2 — next-up via service seam (session learning observable)', () {
    test(
      'recordSkip through the singleton changes the produced up-next',
      () async {
        final svc = MusicEngagementService.instance;
        svc.resetSessionForTest();
        final seed = _by('seed-n', 'Neutral Base', 'Seed Anthem');
        final candidates = [
          _by('au1', 'Aurora Kin', 'Track U1'),
          _by('ba1', 'Bastille Nine', 'Track N1'),
          _by('au2', 'Aurora Kin', 'Track U2'),
          _by('ba2', 'Bastille Nine', 'Track N2'),
          _by('au3', 'Aurora Kin', 'Track U3'),
          _by('ba3', 'Bastille Nine', 'Track N3'),
        ];
        svc.candidateSeam = (q) async => List.of(candidates);
        final when = DateTime(2026, 11, 10, 10, 30);

        final before = await svc.nextUpForPlaying(
          seed: seed,
          exclude: const [],
          now: when,
        );
        expect(before, hasLength(6));
        expect(
          before.any((t) => t.id == seed.id),
          isFalse,
          reason: 'seed never self-searches into its own up-next',
        );

        // Skip two Aurora Kin tracks this session (simulate = signal against).
        svc.recordSkip(candidates[0]);
        svc.recordSkip(candidates[2]);
        final after = await svc.nextUpForPlaying(
          seed: seed,
          exclude: const [],
          now: when,
        );

        expect(
          before.map((t) => t.id).join(','),
          isNot(after.map((t) => t.id).join(',')),
          reason: 'session learning must be observable: signal → order change',
        );
        final skippedCount = after
            .where((t) => t.artist == 'Aurora Kin')
            .length;
        expect(
          after
              .sublist(after.length - skippedCount)
              .every((t) => t.artist == 'Aurora Kin'),
          isTrue,
          reason: 'skipped artist ranks strictly below every other candidate',
        );

        // exclude list is honored: queue-reviewed tracks never re-appear.
        final excluded = await svc.nextUpForPlaying(
          seed: seed,
          exclude: candidates.take(3).toList(),
          now: when,
        );
        expect(
          excluded.any((t) => candidates.take(3).any((c) => c.id == t.id)),
          isFalse,
        );
      },
    );
  });

  group('Round 2 — daily mix generator (Complaint 4)', () {
    test(
      'tiny pool (8) yields at least one mix with the full deduped pool',
      () {
        final pool = List.generate(
          8,
          (i) => _by('p$i', 'Zed Rand $i', 'Song $i'),
        );
        final mixes = MusicEngagementCore.generateDailyMixes(
          pool: pool,
          date: DateTime(2026, 11, 10),
        );
        expect(mixes, isNotEmpty);
        final total = mixes.fold<int>(0, (n, m) => n + m.tracks.length);
        expect(
          total,
          8,
          reason: 'dedup pool fully distributed, nothing invented',
        );
      },
    );

    test('30-track pool yields 4 mixes totalling 30 (spec floor 30+)', () {
      final pool = List.generate(
        30,
        (i) => _by('q$i', 'Mera Hart $i', 'Jam $i'),
      );
      final mixes = MusicEngagementCore.generateDailyMixes(
        pool: pool,
        date: DateTime(2026, 11, 10),
      );
      expect(mixes.length, 4);
      final total = mixes.fold<int>(0, (n, m) => n + m.tracks.length);
      expect(total, 30);
      for (final m in mixes) {
        expect(m.tracks, isNotEmpty);
        expect(m.tracks.length, lessThanOrEqualTo(25));
      }
    });

    test('120-track pool yields 6 mega-mixes covering every track', () {
      final pool = List.generate(
        120,
        (i) => _by('b$i', 'Cora Pride $i', 'Pulse $i'),
      );
      final mixes = MusicEngagementCore.generateDailyMixes(
        pool: pool,
        date: DateTime(2026, 11, 10),
      );
      expect(mixes.length, 6, reason: 'big pool earns the 6-mix layout');
      final total = mixes.fold<int>(0, (n, m) => n + m.tracks.length);
      expect(total, 120, reason: 'mega-mixes must cover the whole pool');
      // Global uniqueness: no track appears in two mixes on the same day.
      final ids = mixes.expand((m) => m.tracks.map((t) => t.id)).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('same day is stable, next day rotates (fake dates, no waiting)', () {
      final pool = List.generate(
        40,
        (i) => _by('c$i', 'Delta Nine $i', 'Wave $i'),
      );
      final today = MusicEngagementCore.generateDailyMixes(
        pool: pool,
        date: DateTime(2026, 11, 10),
      );
      final todayAgain = MusicEngagementCore.generateDailyMixes(
        pool: pool,
        date: DateTime(2026, 11, 10, 21, 45),
      );
      expect(
        today.map((m) => m.id).join(','),
        todayAgain.map((m) => m.id).join(','),
      );
      expect(
        today.expand((m) => m.tracks).map((t) => t.id).join('|'),
        todayAgain.expand((m) => m.tracks).map((t) => t.id).join('|'),
      );

      final tomorrow = MusicEngagementCore.generateDailyMixes(
        pool: pool,
        date: DateTime(2026, 11, 11),
      );
      expect(
        tomorrow.first.tracks.map((t) => t.id).join('|'),
        isNot(today.first.tracks.map((t) => t.id).join('|')),
        reason: 'day flip → rotated pool start (+1) → visibly different mixes',
      );
    });

    test('mix titles are human theme labels, never artist concatenation', () {
      final pool = List.generate(
        24,
        (i) => _by('d$i', 'Era Skye $i', 'Glow $i'),
      );
      final mixes = MusicEngagementCore.generateDailyMixes(
        pool: pool,
        date: DateTime(2026, 11, 10),
      );
      expect(mixes, isNotEmpty);
      for (final mix in mixes) {
        final lead = mix.tracks.first.artist;
        expect(
          mix.title.contains(' — '),
          isFalse,
          reason: 'title "${mix.title}" must not use the artist-dash form',
        );
        expect(
          mix.title.contains('·'),
          isFalse,
          reason: 'title "${mix.title}" must not mash artist names together',
        );
        expect(
          mix.title.contains(lead),
          isFalse,
          reason: 'title "${mix.title}" must not carry artist "$lead"',
        );
        expect(mix.title.trim(), isNotEmpty);
      }
    });

    test('undersized pool fabricates nothing', () {
      final pool = List.generate(5, (i) => _t('tiny$i'));
      final mixes = MusicEngagementCore.generateDailyMixes(
        pool: pool,
        date: DateTime(2026, 11, 10),
      );
      expect(mixes, isEmpty);
    });
  });

  group('Round 2 — rail rotation (Complaint 3)', () {
    test('rotateRail windows vary across consecutive days', () {
      final items = List.generate(30, (i) => _t('g$i'));
      final serials = <String>{};
      var base = MusicEngagementCore.daySeed(DateTime(2026, 11, 10));
      for (var d = 0; d < 12; d++) {
        final window = MusicEngagementCore.rotateRail(
          items,
          daySeed: base + d,
          take: 10,
        );
        expect(window, hasLength(10));
        serials.add(window.map((t) => t.id).join(','));
      }
      expect(
        serials.length,
        greaterThanOrEqualTo(5),
        reason: '12 days cannot all render the identical 10 items',
      );
    });
  });

  group('Round 2 — trend cache (24h TTL, dedupe, expiry)', () {
    test('concurrent getOr callers share one in-flight load', () async {
      final ts = MusicTrendService.instance;
      ts.clear();
      var calls = 0;
      final gate = Completer<void>();
      Future<List<String>> loader() async {
        calls++;
        await gate.future;
        return const ['shared-a', 'shared-b'];
      }

      final f1 = ts.getOr<List<String>>('std-share', loader);
      final f2 = ts.getOr<List<String>>('std-share', loader);
      gate.complete();
      final r1 = await f1;
      final r2 = await f2;
      expect(calls, 1);
      expect(r1, r2);
    });

    test('an expired entry reloads instead of serving stale', () async {
      final ts = MusicTrendService.instance;
      ts.clear();
      var calls = 0;
      Future<List<String>> loader() async {
        calls++;
        return ['fresh-$calls'];
      }

      await ts.getOr<List<String>>('std-exp', loader, ttl: Duration.zero);
      final second = await ts.getOr<List<String>>(
        'std-exp',
        loader,
        ttl: Duration.zero,
      );
      expect(calls, 2);
      expect(second, ['fresh-2']);
    });
  });

  group('Round 2 — song radio via searchSeam (no fixed fallbacks)', () {
    test(
      'radio is seed-led, artist-preferred, and lacks the seed twice',
      () async {
        final radio = MusicRadioService.instance;
        final queries = <String>[];

        List<MusicTrack> fixture() => [
          _by('rr-a1', 'Nova Strait', 'Track NA1'),
          _by('rr-o1', 'Oro Pines', 'Track OP1'),
          _by('rr-a2', 'Nova Strait', 'Track NA2'),
          _by('rr-o2', 'Oro Pines', 'Track OP2'),
          _by('rr-a3', 'Nova Strait', 'Track NA3'),
          _by('rr-o3', 'Oro Pines', 'Track OP3'),
          _by('rr-a4', 'Nova Strait', 'Track NA4'),
          _by('rr-o4', 'Oro Pines', 'Track OP4'),
          _by('rr-a5', 'Nova Strait', 'Track NA5'),
          _by('rr-o5', 'Oro Pines', 'Track OP5'),
          _by('rr-a6', 'Nova Strait', 'Track NA6'),
          _by('rr-o6', 'Oro Pines', 'Track OP6'),
          _by('rr-a7', 'Nova Strait', 'Track NA7'),
          _by('rr-o7', 'Oro Pines', 'Track OP7'),
          _by('rr-a8', 'Nova Strait', 'Track NA8'),
        ];

        radio.searchSeam = (q) async {
          queries.add(q);
          return fixture();
        };

        final seed = _by('rr-seed', 'Nova Strait', 'Seed Anthem One');
        final queue = await radio.generateSongRadio(seed);

        // Contract: [seed, ...extension] — seed first, exactly once.
        expect(queue.first.id, 'rr-seed');
        expect(queue.where((t) => t.id == 'rr-seed').length, 1);
        // A ≥15-candidate sheet must not trigger the featured backfill —
        // candidates come only from seed metadata through search.
        expect(queries, ['Nova Strait']);
        // Extension order: same-artist block (+30) above the rest (+8).
        final bout = queue.sublist(1);
        final novaCount = bout.where((t) => t.artist == 'Nova Strait').length;
        expect(novaCount, 8);
        expect(
          bout.sublist(0, novaCount).every((t) => t.artist == 'Nova Strait'),
          isTrue,
        );

        // A different seed changes the order — up-next is seed-driven.
        final seedB = _by('rr-seed2', 'Oro Pines', 'Seed Anthem Two');
        final queueB = await radio.generateSongRadio(seedB);
        expect(queueB.first.id, 'rr-seed2');
        final bStarts = queueB.sublist(1);
        final oroCount = bStarts.where((t) => t.artist == 'Oro Pines').length;
        expect(oroCount, 7, reason: 'seedB + 7 remaining Oro tracks');
        expect(
          bStarts.sublist(0, oroCount).every((t) => t.artist == 'Oro Pines'),
          isTrue,
        );
        expect(
          bout.map((t) => t.id).join(','),
          isNot(bStarts.map((t) => t.id).join(',')),
        );
      },
    );
  });

  group('Round 2 — no-hardcode audit (grep-as-test)', () {
    test('banned content literals are absent from music services + pages', () {
      const banned = <String>[
        // Fixed artist seeds removed in Round 2.
        'Arijit Singh',
        'AP Dhillon',
        'Pritam',
        'Diljit Dosanjh',
        'Badshah',
        'Shreya Ghoshal',
        'Anuv Jain',
        'Honey Singh',
        // Curated playlist cards that used to be hardcoded data.
        'Bollywood Love Songs',
        'Punjabi Bhangra',
        'Bollywood Remix',
        'Night Drive',
        'Sad Lofi',
        'Phonk Hits',
        'Bollywood Romance Essentials',
        'Bollywood Dance & Party',
        'Mashup & Remix Lab',
        'Punjabi Party Hits',
        'Desi Hip-Hop — Gully Vibes',
        'Indie & Acoustic Feels',
        'Ollywood DJ & Sambalpuri Mashups',
        'Lofi & Slowed-Reverb Nights',
        'Sambalpuri DJ',
      ];
      final dirs = ['lib/services/music', 'lib/pages/music'];
      // Sanctioned exception (product override, 2026-11-12): the owner
      // explicitly specified the default artist row. default_artists.dart
      // is the ONE file those names may live in, and every name is only
      // ever a search query resolved to live catalog data — never fixed
      // tracks or playlists.
      final exemptPaths = ['default_artists.dart'];
      final offenders = <String>[];
      for (final dir in dirs) {
        final dartFiles = Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'));
        for (final file in dartFiles) {
          final exempt = exemptPaths.any(file.path.contains);
          if (exempt) continue;
          final text = file.readAsStringSync();
          for (final b in banned) {
            if (text.contains(b)) {
              offenders.add('${file.path} → "$b"');
            }
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'hardcoded content literals found: ${offenders.join("; ")}',
      );
    });

    test('scan actually swept both target directories', () {
      var files = 0;
      for (final dir in ['lib/services/music', 'lib/pages/music']) {
        files += Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .length;
      }
      expect(
        files,
        greaterThan(20),
        reason: 'audit must scan real surface area, not an empty glob',
      );
    });
  });
}
