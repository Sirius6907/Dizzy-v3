import 'package:dizzy/models/music/music_track.dart';
import 'package:dizzy/services/music/music_engagement_service.dart';
import 'package:dizzy/services/music/music_mood_filter.dart';
import 'package:dizzy/services/music/music_onboarding_service.dart';
import 'package:dizzy/services/music/music_radio_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Part C (2026-11-12) — the vibe engine: onboarding-derived vibe
/// profile, vibe-seeded daily mixes with human titles and ~1-in-4
/// favorite accents, and the vibe-first radio pool stage.
MusicTrack _t(String id, String artist, String title,
    {int duration = 200}) => MusicTrack(
      id: id,
      title: title,
      artist: artist,
      album: 'Album $id',
      coverUrl: '',
      durationSeconds: duration,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    addTearDown(() {
      MusicRadioService.instance.searchSeam = null;
      // Restore pristine onboarding notifiers so other tests in this
      // file and future files start from a no-signal state.
      MusicOnboardingService.isDone.value = false;
      MusicOnboardingService.favoriteArtists.value = const [];
      MusicOnboardingService.selectedStyles.value = const [];
      MusicOnboardingService.defaultMood.value = MusicMood.any;
      MusicOnboardingService.changeNotifier.value = 0;
    });
  });

  group('Vibe profile derivation', () {
    test('empty onboarding = no signal, empty weights, empty profKey body',
        () {
      final vibe = MusicVibeProfile.fromOnboarding();
      expect(vibe.hasSignal, isFalse);
      expect(vibe.moodWeights, isEmpty);
      expect(vibe.styleTitles, isEmpty);
    });

    test('styles map 1.0 onto their mood, default mood adds 1.5', () {
      final vibe = MusicEngagementCore.vibeProfile(
        styles: [MusicStyle.lofi, MusicStyle.romantic],
        defaultMood: MusicMood.night,
      );
      expect(vibe.hasSignal, isTrue);
      // lofi → night 1.0 + romantic → romance 1.0 + default night 1.5.
      expect(vibe.moodWeights[MusicMood.night], closeTo(2.5, 1e-9));
      expect(vibe.moodWeights[MusicMood.romance], closeTo(1.0, 1e-9));
      expect(vibe.styleTitles, ['Lo-fi Evenings', 'Romantic Golden Hour']);
      expect(vibe.styleQueries, contains('lofi chill beats'));
    });

    test('devotional style carries its query but no mood weight', () {
      final vibe = MusicEngagementCore.vibeProfile(
        styles: [MusicStyle.devotional],
      );
      expect(vibe.moodWeights, isEmpty);
      expect(vibe.styleQueries, contains('devotional bhajan mantra peaceful'));
      expect(vibe.hasSignal, isTrue); // still a style title signal
    });

    test('profile key changes when favorites change (caches refresh)', () {
      final before = MusicEngagementCore.vibeProfile(
        favoriteArtists: ['Arijit Singh'],
        styles: [MusicStyle.lofi],
      );
      final after = MusicEngagementCore.vibeProfile(
        favoriteArtists: ['Arijit Singh', 'Shreya Ghoshal'],
        styles: [MusicStyle.lofi],
      );
      final same = MusicEngagementCore.vibeProfile(
        favoriteArtists: ['arijit singh'], // normalized → same key
        styles: [MusicStyle.lofi],
      );
      expect(after.profKey, isNot(before.profKey));
      expect(same.profKey, before.profKey);
    });

    test('favorite artists are normalized (lowercase, trimmed)', () {
      final vibe = MusicEngagementCore.vibeProfile(
        favoriteArtists: ['  ARIJIT Singh ', '', '   '],
      );
      expect(vibe.favoriteArtists, ['arijit singh']);
    });
  });

  group('Vibe scoring', () {
    test('favorite artist track outscores a stranger with equal mood fit',
        () {
      final vibe = MusicEngagementCore.vibeProfile(
        favoriteArtists: ['Arijit Singh'],
        defaultMood: MusicMood.night,
      );
      final fav = _t('f1', 'Arijit Singh', 'Plain Title');
      final stranger = _t('s1', 'Random Face', 'Plain Title');
      expect(MusicEngagementCore.vibeScore(fav, vibe),
          greaterThan(MusicEngagementCore.vibeScore(stranger, vibe)));
      // Exactly the favorite bonus when neither has keyword hits.
      expect(
        MusicEngagementCore.vibeScore(fav, vibe) -
            MusicEngagementCore.vibeScore(stranger, vibe),
        closeTo(MusicEngagementCore.favoriteArtistBonus, 1e-9),
      );
    });

    test('mood keywords score through the weights (night lofi track)', () {
      final vibe = MusicEngagementCore.vibeProfile(
        styles: [MusicStyle.lofi],
        defaultMood: MusicMood.night,
      );
      // 'lofi' keyword hit ×2.0 × weight 2.5 + duration band 200s ∈
      // night band (200..480) ×1.0 × 2.5.
      final lofi = _t('l1', 'Anyone', 'Lofi Night Drive', duration: 220);
      expect(MusicEngagementCore.vibeScore(lofi, vibe), greaterThan(0));
      // Same track scores 0 under a profile with no mood signal.
      final empty = MusicEngagementCore.vibeProfile(
        favoriteArtists: ['Someone Else'],
      );
      expect(MusicEngagementCore.vibeScore(lofi, empty), 0.0);
    });
  });

  group('Daily mixes with a vibe', () {
    test('titles come from the user’s own style titles, never artists', () {
      final pool = List.generate(
        30,
        (i) => _t('m$i', 'Mixer Artist $i', 'Song $i'),
      );
      final vibe = MusicEngagementCore.vibeProfile(
        styles: [MusicStyle.lofi, MusicStyle.romantic],
      );
      final mixes = MusicEngagementCore.generateDailyMixes(
        pool: pool,
        date: DateTime(2026, 11, 10),
        vibe: vibe,
      );
      expect(mixes, isNotEmpty);
      for (final mix in mixes) {
        expect(
          vibe.styleTitles.any((t) => mix.title.startsWith(t)),
          isTrue,
          reason: 'title "${mix.title}" must come from the chosen styles',
        );
        expect(mix.title.contains('·'), isFalse);
        expect(mix.title.contains(' — '), isFalse);
      }
    });

    test('without a vibe the titles stay human (time-of-day themes)', () {
      final pool = List.generate(
        30,
        (i) => _t('n$i', 'No Vibe Artist $i', 'Song $i'),
      );
      final mixes = MusicEngagementCore.generateDailyMixes(
        pool: pool,
        date: DateTime(2026, 11, 10),
      );
      expect(mixes, isNotEmpty);
      const themes = {'Midday', 'Workday', 'Easy', 'Pump', 'Deep', 'Radar'};
      for (final mix in mixes) {
        expect(
          themes.any((t) => mix.title.startsWith(t)),
          isTrue,
          reason: 'title "${mix.title}" must be a human theme',
        );
        expect(mix.title.contains('Mixer'), isFalse);
      }
    });

    test('favorite accents: ~1-in-4 slots, pool coverage preserved', () {
      // 30-track pool; tracks 0..7 by 'Arijit Singh' are the favorites.
      final pool = <MusicTrack>[
        for (var i = 0; i < 30; i++)
          _t('a$i', i < 8 ? 'Arijit Singh' : 'Filler Artist $i', 'Song $i'),
      ];
      final vibe = MusicEngagementCore.vibeProfile(
        favoriteArtists: ['Arijit Singh'],
      );
      final favTracks = pool.take(8).toList();
      final mixes = MusicEngagementCore.generateDailyMixes(
        pool: pool,
        date: DateTime(2026, 11, 10),
        vibe: vibe,
        favoriteTracks: favTracks,
      );
      expect(mixes, isNotEmpty);

      // Every accent slot (index 3, 7, ...) holds a favorite.
      for (final mix in mixes) {
        for (var i = 3; i < mix.tracks.length; i += 4) {
          expect(mix.tracks[i].artist, 'Arijit Singh',
              reason: 'every 4th slot must be a favorite accent');
        }
      }

      // Global uniqueness + full coverage: nothing invented, nothing lost.
      final ids = mixes.expand((m) => m.tracks.map((t) => t.id)).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids.length, 30, reason: 'the whole pool is distributed');
    });

    test('same vibe + same day is stable, day flip rotates titles', () {
      final pool = List.generate(
        30,
        (i) => _t('r$i', 'Rota Artist $i', 'Song $i'),
      );
      final vibe = MusicEngagementCore.vibeProfile(
        styles: [MusicStyle.lofi],
      );
      final today = MusicEngagementCore.generateDailyMixes(
        pool: pool,
        date: DateTime(2026, 11, 10),
        vibe: vibe,
      );
      final again = MusicEngagementCore.generateDailyMixes(
        pool: pool,
        date: DateTime(2026, 11, 10, 22),
        vibe: vibe,
      );
      expect(today.map((m) => m.title).join(','),
          again.map((m) => m.title).join(','));
      expect(
        today.expand((m) => m.tracks).map((t) => t.id).join('|'),
        again.expand((m) => m.tracks).map((t) => t.id).join('|'),
      );
      final tomorrow = MusicEngagementCore.generateDailyMixes(
        pool: pool,
        date: DateTime(2026, 11, 11),
        vibe: vibe,
      );
      expect(
        tomorrow.expand((m) => m.tracks).map((t) => t.id).join('|'),
        isNot(today.expand((m) => m.tracks).map((t) => t.id).join('|')),
      );
    });
  });

  group('Radio vibe-first pool stage', () {
    test('vibe searches enter the seam when onboarding has signal', () async {
      final queried = <String>[];
      MusicRadioService.instance.searchSeam = (query) async {
        queried.add(query);
        return <MusicTrack>[
          _t('radio_${query.hashCode}', 'Seam Artist', 'Seam Song $query'),
        ];
      };
      MusicOnboardingService.selectedStyles.value = [MusicStyle.lofi];
      MusicOnboardingService.favoriteArtists.value = ['Arijit Singh'];

      final seed = _t('seed', 'Seed Artist', 'Seed Song');
      final queue = await MusicRadioService.instance.generateSongRadio(seed);

      expect(queried, contains('lofi chill beats'));
      expect(queried, contains('arijit singh'));
      // Vibe candidates made it into the queue after the seed.
      expect(queue.any((t) => t.id == 'radio_${'lofi chill beats'.hashCode}'),
          isTrue);
    });

    test('no onboarding signal = no vibe searches (legacy radio intact)',
        () async {
      final queried = <String>[];
      MusicRadioService.instance.searchSeam = (query) async {
        queried.add(query);
        return <MusicTrack>[];
      };
      MusicOnboardingService.favoriteArtists.value = const [];
      MusicOnboardingService.selectedStyles.value = const [];

      final seed = _t('seed2', 'Seed Artist', 'Seed Song Two');
      await MusicRadioService.instance.generateSongRadio(seed);

      expect(queried, isNot(contains('lofi chill beats')));
      expect(queried, everyElement(isNot('lofi chill beats')));
    });
  });

  group('India-first rail helpers', () {
    MusicTrack tr(String id, String artist, String album,
            {String cover = 'c.jpg'}) =>
        MusicTrack(
          id: id,
          title: 'T $id',
          artist: artist,
          album: album,
          coverUrl: cover,
          durationSeconds: 200,
        );

    test('albumCardsFromTracks groups trending tracks in first-seen order',
        () {
      final tracks = [
        tr('a1', 'A', 'Album One'),
        tr('a2', 'A', 'Album One'),
        tr('b1', 'B', 'Album Two'),
        tr('c1', 'C', ''), // no album name → skipped
      ];
      final albums = MusicEngagementCore.albumCardsFromTracks(tracks);
      expect(albums, hasLength(2));
      expect(albums[0].title, 'Album One');
      expect(albums[0].artistName, 'A');
      expect(albums[0].trackCount, 2);
      expect(albums[0].tracks, hasLength(2));
      expect(albums[1].title, 'Album Two');
    });

    test('albumCardsFromTracks caps and dedupes album names', () {
      final tracks = [
        for (var i = 0; i < 20; i++) tr('t$i', 'A$i', 'Al $i'),
        tr('dup', 'Again', 'Al 0'), // same album as t0 → folded, not new card
      ];
      final albums =
          MusicEngagementCore.albumCardsFromTracks(tracks, cap: 25);
      expect(albums.length, 20);
      expect(albums.first.trackCount, 2);
    });

    test('stationPlaylist builds a card only from enough covered tracks',
        () {
      final few = [tr('p1', 'X', 'al')];
      expect(
        MusicEngagementCore.stationPlaylist(
          id: 's1',
          title: 'Punjabi Heat',
          tracks: few,
        ),
        isNull,
      );
      final many = [for (var i = 0; i < 6; i++) tr('p$i', 'X', 'al')];
      final pl = MusicEngagementCore.stationPlaylist(
        id: 's1',
        title: 'Punjabi Heat',
        tracks: many,
      );
      expect(pl, isNotNull);
      expect(pl!.id, 's1');
      expect(pl.title, 'Punjabi Heat');
      expect(pl.trackCount, 6);
      expect(pl.coverUrl, 'c.jpg');
    });

    test('stationPlaylist rejects a coverless station', () {
      final many = [
        for (var i = 0; i < 6; i++) tr('p$i', 'X', 'al', cover: ''),
      ];
      expect(
        MusicEngagementCore.stationPlaylist(id: 's1', title: 'T', tracks: many),
        isNull,
      );
    });
  });
}
