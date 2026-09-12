import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dizzy/services/guide/guide_service.dart';
import 'package:dizzy/widgets/guide/guide_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P13: party_v2 guides', () {
    test('exactly 3 cards: create → join → host plays', () {
      expect(AppGuides.partyV2.length, 3);
      expect(AppGuides.partyV2[0].title, contains('Create'));
      expect(AppGuides.partyV2[1].title, contains('join'));
      expect(AppGuides.partyV2[2].line, contains('follows'));
    });

    test('allKeys retired watch_party, carries party_v2', () {
      expect(GuideService.allKeys, contains('party_v2'));
      expect(GuideService.allKeys, isNot(contains('watch_party')));
    });

    test('migration: old seen → new hidden (no re-nag)', () async {
      SharedPreferences.setMockInitialValues(
          {'guide_seen_watch_party': true});
      await GuideService.migrateLegacyPartyKey();
      expect(await GuideService.shouldShow('party_v2'), isFalse);
    });

    test('migration: fresh user still sees the new guide', () async {
      SharedPreferences.setMockInitialValues({});
      await GuideService.migrateLegacyPartyKey();
      expect(await GuideService.shouldShow('party_v2'), isTrue);
    });

    test('migration: already-migrated stays put', () async {
      SharedPreferences.setMockInitialValues({
        'guide_seen_watch_party': true,
        'guide_seen_party_v2': true,
      });
      await GuideService.migrateLegacyPartyKey();
      expect(await GuideService.shouldShow('party_v2'), isFalse);
    });
  });
}
