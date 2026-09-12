import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/guide/guide_service.dart';

/// Polish P9 — skip persistence audit: zero nag after skip,
/// replay entry works via resetAll.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Guide skip persistence (P9 audit)', () {
    test('fresh user sees the guide', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await GuideService.shouldShow('downloads'), isTrue);
    });

    test('skip once = never again (zero nag)', () async {
      SharedPreferences.setMockInitialValues({});
      await GuideService.markSeen('downloads');
      expect(await GuideService.shouldShow('downloads'), isFalse);
      // Second check still hidden — no nag on later opens.
      expect(await GuideService.shouldShow('downloads'), isFalse);
    });

    test('resetAll replays (Settings entry works)', () async {
      SharedPreferences.setMockInitialValues(
          {'guide_seen_downloads': true});
      await GuideService.resetAll(['downloads']);
      expect(await GuideService.shouldShow('downloads'), isTrue);
    });

    test('reset is scoped — other guides stay hidden', () async {
      SharedPreferences.setMockInitialValues({
        'guide_seen_downloads': true,
        'guide_seen_party_v2': true,
      });
      await GuideService.resetAll(['downloads']);
      expect(await GuideService.shouldShow('downloads'), isTrue);
      expect(await GuideService.shouldShow('party_v2'), isFalse);
    });
  });
}
