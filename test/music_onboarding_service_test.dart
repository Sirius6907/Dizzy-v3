import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/music/music_mood_filter.dart';
import 'package:dizzy/services/music/music_onboarding_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    MusicOnboardingService.resetForTest();
    await MusicOnboardingService.initialize();
  });

  group('MusicOnboardingService (Part B)', () {
    test('fresh state: wizard not done, no signal', () async {
      expect(MusicOnboardingService.isDone.value, isFalse);
      expect(MusicOnboardingService.favoriteArtists.value, isEmpty);
      expect(MusicOnboardingService.selectedStyles.value, isEmpty);
      expect(MusicOnboardingService.defaultMood.value, MusicMood.any);
      expect(MusicOnboardingService.hasSignal, isFalse);
    });

    test('complete persists all picks and sets the done flag', () async {
      await MusicOnboardingService.complete(
        artists: ['Arijit Singh', ' Shreya Ghoshal ', ''],
        styles: [MusicStyle.lofi, MusicStyle.devotional],
        mood: MusicMood.night,
      );

      expect(MusicOnboardingService.isDone.value, isTrue);
      expect(MusicOnboardingService.favoriteArtists.value,
          ['Arijit Singh', 'Shreya Ghoshal']);
      expect(MusicOnboardingService.selectedStyles.value,
          [MusicStyle.lofi, MusicStyle.devotional]);
      expect(MusicOnboardingService.defaultMood.value, MusicMood.night);
      expect(MusicOnboardingService.hasSignal, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(MusicOnboardingService.doneKey), isTrue);
      expect(prefs.getStringList('music_onboarding_favorites'),
          ['Arijit Singh', 'Shreya Ghoshal']);
    });

    test('complete with empty picks still marks done (steps skippable)',
        () async {
      await MusicOnboardingService.complete();
      expect(MusicOnboardingService.isDone.value, isTrue);
      expect(MusicOnboardingService.hasSignal, isFalse);
    });

    test('skip sets done and never wipes existing preferences', () async {
      await MusicOnboardingService.complete(
        artists: ['Arijit Singh'],
        styles: [MusicStyle.romantic],
        mood: MusicMood.romance,
      );

      // Simulate a fresh session re-read.
      MusicOnboardingService.resetForTest();
      await MusicOnboardingService.initialize();
      expect(MusicOnboardingService.isDone.value, isTrue);
      expect(MusicOnboardingService.favoriteArtists.value, ['Arijit Singh']);

      // A later wizard visit skips instead of completing.
      await MusicOnboardingService.skip();
      expect(MusicOnboardingService.isDone.value, isTrue);
      expect(MusicOnboardingService.favoriteArtists.value, ['Arijit Singh']);
      expect(MusicOnboardingService.selectedStyles.value,
          [MusicStyle.romantic]);
      expect(MusicOnboardingService.defaultMood.value, MusicMood.romance);
    });

    test('updatePreferences changes fields without ever un-setting done',
        () async {
      await MusicOnboardingService.complete(
        artists: ['Old Artist'],
        styles: [MusicStyle.lofi],
        mood: MusicMood.chill,
      );

      await MusicOnboardingService.updatePreferences(
        artists: ['New Artist'],
        styles: [MusicStyle.party, MusicStyle.focus],
        mood: MusicMood.energetic,
      );

      expect(MusicOnboardingService.isDone.value, isTrue);
      expect(MusicOnboardingService.favoriteArtists.value, ['New Artist']);
      expect(MusicOnboardingService.selectedStyles.value,
          [MusicStyle.party, MusicStyle.focus]);
      expect(MusicOnboardingService.defaultMood.value, MusicMood.energetic);
    });

    test('updatePreferences works with partial updates', () async {
      await MusicOnboardingService.complete(
        artists: ['Arijit Singh'],
        styles: [MusicStyle.lofi],
        mood: MusicMood.chill,
      );

      await MusicOnboardingService.updatePreferences(mood: MusicMood.focus);

      expect(MusicOnboardingService.favoriteArtists.value, ['Arijit Singh']);
      expect(MusicOnboardingService.selectedStyles.value, [MusicStyle.lofi]);
      expect(MusicOnboardingService.defaultMood.value, MusicMood.focus);
    });

    test('state survives a fresh session re-read', () async {
      await MusicOnboardingService.complete(
        artists: ['Diljit Dosanjh'],
        styles: [MusicStyle.energetic, MusicStyle.devotional],
        mood: MusicMood.happy,
      );

      MusicOnboardingService.resetForTest();
      await MusicOnboardingService.initialize();

      expect(MusicOnboardingService.isDone.value, isTrue);
      expect(MusicOnboardingService.favoriteArtists.value,
          ['Diljit Dosanjh']);
      expect(MusicOnboardingService.selectedStyles.value,
          [MusicStyle.energetic, MusicStyle.devotional]);
      expect(MusicOnboardingService.defaultMood.value, MusicMood.happy);
    });

    test('sanitizeArtists trims, dedups and caps entries', () {
      final out = MusicOnboardingService.sanitizeArtists(
        ['  Arijit Singh ', 'Arijit Singh', '', 'x' * 100],
      );
      expect(out, ['Arijit Singh']);
    });

    test('sanitizeStyles drops unknown names and dedups', () {
      final out = MusicOnboardingService.sanitizeStyles(
        ['lofi', 'bogus', 'lofi', 'focus'],
      );
      expect(out, [MusicStyle.lofi, MusicStyle.focus]);
    });

    test('sanitizeStyles tolerates free-text artist names from search',
        () => expect(MusicOnboardingService.sanitizeStyles([]), isEmpty));
  });

  group('MusicStyle (Part B vibe mapping)', () {
    test('each style maps onto the existing MusicMood system', () {
      for (final s in MusicStyle.values) {
        expect(MusicMood.values.contains(s.mood), isTrue,
            reason: '${s.name} must map to a real MusicMood');
      }
    });

    test('vibe titles are human, never artist mashups', () {
      for (final s in MusicStyle.values) {
        expect(s.vibeTitle, isNotEmpty);
        expect(s.vibeTitle.contains('\${artist.name}'), isFalse,
            reason: 'titles must be vibe words, not artist names');
      }
    });

    test('devotional carries its own live search phrase (mood can\'t express it)',
        () {
      expect(MusicStyle.devotional.mood, MusicMood.any);
      expect(MusicStyle.devotional.searchQuery, contains('devotional'));
    });

    test('fromName round-trips every style', () {
      for (final s in MusicStyle.values) {
        expect(MusicStyle.fromName(s.name), s);
      }
      expect(MusicStyle.fromName('bogus'), isNull);
    });
  });
}
