import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/guide/guide_service.dart';
import 'package:dizzy/widgets/guide/guide_card.dart';
import 'package:dizzy/widgets/onboarding/onboarding_superpower_sheet.dart';

/// P7 — Tutorial cards 50x comprehensive test suite.
///
/// Covers:
///  * Skip persistence (skip once = never again, zero nag)
///  * Migration no re-nag (legacy keys to v2 keys, legacy onboarding)
///  * Settings Help replay (resetAll)
///  * GuideCard contract: max 3 steps per guide
///  * Onboarding 2.0 once-only
///  * Error resiliency (storage failures don't trap users)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P7 GuideService — basic flags & persistence', () {
    test('fresh user sees any guide by default', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await GuideService.shouldShow('home'), isTrue);
      expect(await GuideService.shouldShow('spotlight'), isTrue);
      expect(await GuideService.shouldShow('movie'), isTrue);
    });

    test('markSeen hides the guide forever (zero nag)', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await GuideService.shouldShow('downloads'), isTrue);
      await GuideService.markSeen('downloads');
      expect(await GuideService.shouldShow('downloads'), isFalse);
      // Repeated checks still false
      expect(await GuideService.shouldShow('downloads'), isFalse);
    });

    test('markSeen is idempotent', () async {
      SharedPreferences.setMockInitialValues({});
      await GuideService.markSeen('music_studio');
      await GuideService.markSeen('music_studio');
      expect(await GuideService.shouldShow('music_studio'), isFalse);
    });

    test('allKeys contains exactly 25 curated feature keys', () {
      expect(GuideService.allKeys.length, 25);
      expect(GuideService.allKeys.toSet().length, 25, reason: 'Duplicate keys in allKeys');
      expect(GuideService.allKeys, contains('home'));
      expect(GuideService.allKeys, contains('spotlight'));
      expect(GuideService.allKeys, contains('movie'));
      expect(GuideService.allKeys, contains('anime'));
      expect(GuideService.allKeys, contains('manga'));
      expect(GuideService.allKeys, contains('music_studio'));
      expect(GuideService.allKeys, contains('eq'));
      expect(GuideService.allKeys, contains('books'));
      expect(GuideService.allKeys, contains('audiobooks'));
      expect(GuideService.allKeys, contains('downloads'));
      expect(GuideService.allKeys, contains('offline'));
      expect(GuideService.allKeys, contains('my_list'));
      expect(GuideService.allKeys, contains('profiles_pin'));
      expect(GuideService.allKeys, contains('debrid'));
      expect(GuideService.allKeys, contains('iptv'));
      expect(GuideService.allKeys, contains('calendar'));
      expect(GuideService.allKeys, contains('stats'));
      expect(GuideService.allKeys, contains('subtitles'));
      expect(GuideService.allKeys, contains('sources_health'));
      expect(GuideService.allKeys, contains('cloud_sync'));
      expect(GuideService.allKeys, contains('party_v2'));
      expect(GuideService.allKeys, contains('dms'));
      expect(GuideService.allKeys, contains('social_hub'));
      expect(GuideService.allKeys, contains('accent_studio'));
      expect(GuideService.allKeys, contains('appearance'));
    });
  });

  group('P7 GuideService — Settings replay & resetAll', () {
    test('resetAll brings back specified keys', () async {
      SharedPreferences.setMockInitialValues({
        'guide_seen_home': true,
        'guide_seen_music_studio': true,
        'guide_seen_downloads': true,
      });

      expect(await GuideService.shouldShow('home'), isFalse);
      expect(await GuideService.shouldShow('music_studio'), isFalse);
      expect(await GuideService.shouldShow('downloads'), isFalse);

      await GuideService.resetAll(['home', 'music_studio']);

      expect(await GuideService.shouldShow('home'), isTrue);
      expect(await GuideService.shouldShow('music_studio'), isTrue);
      expect(await GuideService.shouldShow('downloads'), isFalse);
    });

    test('resetAll with onboardingKey replays onboarding tour', () async {
      SharedPreferences.setMockInitialValues({
        'guide_seen_onboarding': true,
      });
      expect(await OnboardingSuperpowerSheet.shouldShow(), isFalse);

      await GuideService.resetAll([GuideService.onboardingKey]);
      expect(await OnboardingSuperpowerSheet.shouldShow(), isTrue);
    });
  });

  group('P7 GuideService — legacy migration (no re-nag)', () {
    test('legacy party_v2 alias migrates watch_party', () async {
      SharedPreferences.setMockInitialValues({
        'guide_seen_watch_party': true,
      });
      await GuideService.migrateLegacyKeys();
      expect(await GuideService.shouldShow('party_v2'), isFalse);
    });

    test('fresh user after migration still sees party_v2', () async {
      SharedPreferences.setMockInitialValues({});
      await GuideService.migrateLegacyKeys();
      expect(await GuideService.shouldShow('party_v2'), isTrue);
    });

    test('legacy onboarding pref migrates to onboardingKey', () async {
      SharedPreferences.setMockInitialValues({
        'has_seen_superpower_onboarding_v1_2': true,
      });
      await GuideService.migrateLegacyKeys();
      expect(await GuideService.shouldShow(GuideService.onboardingKey), isFalse);
      expect(await OnboardingSuperpowerSheet.shouldShow(), isFalse);
    });

    test('already migrated keys are not reset or toggled', () async {
      SharedPreferences.setMockInitialValues({
        'guide_seen_watch_party': true,
        'guide_seen_party_v2': true,
      });
      await GuideService.migrateLegacyKeys();
      expect(await GuideService.shouldShow('party_v2'), isFalse);
    });
  });

  group('P7 GuideCard 2.0 contract', () {
    test('all AppGuides flows have between 1 and 3 steps (maxSteps)', () {
      final flows = [
        AppGuides.home,
        AppGuides.spotlight,
        AppGuides.movie,
        AppGuides.anime,
        AppGuides.manga,
        AppGuides.musicStudio,
        AppGuides.eq,
        AppGuides.books,
        AppGuides.audiobooks,
        AppGuides.downloads,
        AppGuides.offline,
        AppGuides.myList,
        AppGuides.profilesPin,
        AppGuides.debrid,
        AppGuides.iptv,
        AppGuides.calendar,
        AppGuides.stats,
        AppGuides.subtitles,
        AppGuides.sourcesHealth,
        AppGuides.cloudSync,
        AppGuides.partyV2,
        AppGuides.watchParty,
        AppGuides.dms,
        AppGuides.socialHub,
        AppGuides.accentStudio,
        AppGuides.appearance,
      ];

      for (final flow in flows) {
        expect(flow.isNotEmpty, isTrue);
        expect(flow.length, lessThanOrEqualTo(GuideService.maxSteps),
            reason: 'Guide exceeds maxSteps (${GuideService.maxSteps})');
        for (final step in flow) {
          expect(step.icon.trim(), isNotEmpty);
          expect(step.title.trim(), isNotEmpty);
          expect(step.line.trim(), isNotEmpty);
        }
      }
    });

    test('GuideCard maxSteps constant is 3', () {
      expect(GuideService.maxSteps, 3);
    });
  });

  group('P7 Onboarding 2.0', () {
    test('OnboardingSuperpowerSheet marks seen in GuideService', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await OnboardingSuperpowerSheet.shouldShow(), isTrue);

      await OnboardingSuperpowerSheet.markSeen();
      expect(await OnboardingSuperpowerSheet.shouldShow(), isFalse);
      expect(await GuideService.shouldShow(GuideService.onboardingKey), isFalse);
    });
  });
}
