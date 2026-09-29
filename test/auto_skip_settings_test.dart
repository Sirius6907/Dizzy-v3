import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/player/auto_skip_policy.dart';
import 'package:dizzy/services/player/player_settings.dart';

/// F1 moved the auto-skip rule out of the player widget and into
/// `AutoSkipPolicy`, so it can be tested without a BuildContext. The real
/// policy is covered in `test/player/instant_play_test.dart`; this file
/// keeps the settings-surface half (notifiers + setter signatures).
void main() {
  group('F1 Auto-Skip settings', () {
    test('defaults are ON (press once, watch the whole thing)', () {
      // Fresh defaults before load: constructor values.
      expect(PlayerSettings.autoSkipIntro.value, isTrue);
      expect(PlayerSettings.autoSkipRecap.value, isTrue);
      // Credits ride the existing user-facing "Skip Intro (Smart)" switch.
      expect(PlayerSettings.skipIntroHeuristics.value, isTrue);
    });

    test('setters exist with correct signatures', () {
      // SharedPreferences needs a platform channel (no plugin in unit tests),
      // so we only assert the API surface here. Real persist is covered by
      // integration/manual test.
      expect(PlayerSettings.setAutoSkipIntro, isA<Function>());
      expect(PlayerSettings.setAutoSkipRecap, isA<Function>());
    });

    test('auto-skip gate: intro/recap/credits yes, preview never', () {
      bool shouldAutoSkip(String type,
          {required bool introOn,
          required bool recapOn,
          required bool creditsOn}) =>
          AutoSkipPolicy.shouldAutoSkip(type,
              autoSkipIntro: introOn,
              autoSkipRecap: recapOn,
              autoSkipCredits: creditsOn);

      expect(shouldAutoSkip('intro',
          introOn: true, recapOn: false, creditsOn: false), isTrue);
      expect(shouldAutoSkip('intro',
          introOn: false, recapOn: false, creditsOn: false), isFalse);
      expect(shouldAutoSkip('recap',
          introOn: false, recapOn: true, creditsOn: false), isTrue);
      expect(shouldAutoSkip('recap',
          introOn: true, recapOn: false, creditsOn: false), isFalse);
      expect(shouldAutoSkip('credits',
          introOn: false, recapOn: false, creditsOn: true), isTrue);
      expect(shouldAutoSkip('credits',
          introOn: true, recapOn: true, creditsOn: false), isFalse);
      // A preview is the tail of a movie — never yanked automatically.
      expect(shouldAutoSkip('preview',
          introOn: true, recapOn: true, creditsOn: true), isFalse);
    });
  });
}
