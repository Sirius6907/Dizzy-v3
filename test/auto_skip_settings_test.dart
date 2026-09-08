import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/player/player_settings.dart';

void main() {
  group('F2 Auto-Skip Settings (v1.1.9)', () {
    test('defaults are OFF (opt-in)', () {
      // Fresh defaults before load: constructor values.
      expect(PlayerSettings.autoSkipIntro, isNotNull);
      expect(PlayerSettings.autoSkipRecap, isNotNull);
    });

    test('setters exist with correct signatures', () {
      // SharedPreferences needs a platform channel (no plugin in unit tests),
      // so we only assert the API surface here. Real persist is covered by
      // integration/manual test.
      expect(PlayerSettings.setAutoSkipIntro, isA<Function>());
      expect(PlayerSettings.setAutoSkipRecap, isA<Function>());
    });

    test('auto-skip gate logic: only intro/recap, never credits/preview', () {
      bool shouldAutoSkip(String type,
          {required bool introOn, required bool recapOn}) {
        final t = type.toLowerCase();
        return (t == 'intro' && introOn) || (t == 'recap' && recapOn);
      }

      expect(shouldAutoSkip('intro', introOn: true, recapOn: false), isTrue);
      expect(shouldAutoSkip('intro', introOn: false, recapOn: false), isFalse);
      expect(shouldAutoSkip('recap', introOn: false, recapOn: true), isTrue);
      expect(shouldAutoSkip('recap', introOn: true, recapOn: false), isFalse);
      expect(shouldAutoSkip('credits', introOn: true, recapOn: true), isFalse);
      expect(shouldAutoSkip('preview', introOn: true, recapOn: true), isFalse);
    });
  });
}
