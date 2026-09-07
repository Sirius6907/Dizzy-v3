import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dizzy/services/player/dub_mode_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DubModeService.resetForTest();
  });

  group('DubModeService', () {
    test('default mode is english', () {
      expect(DubModeService.mode.value, AudioDubMode.english);
      expect(DubModeService.isHindi, isFalse);
    });

    test('setMode(hindi) toggles + persists to prefs', () async {
      await DubModeService.setMode(AudioDubMode.hindi);
      expect(DubModeService.mode.value, AudioDubMode.hindi);
      expect(DubModeService.isHindi, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('audio_dub_mode'), 'hindi');
    });

    test('setMode(english) persists english and isHindi false', () async {
      await DubModeService.setMode(AudioDubMode.hindi);
      await DubModeService.setMode(AudioDubMode.english);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('audio_dub_mode'), 'english');
      expect(DubModeService.isHindi, isFalse);
    });

    test('initialize() restores hindi from prefs', () async {
      SharedPreferences.setMockInitialValues({'audio_dub_mode': 'hindi'});
      await DubModeService.initialize();
      expect(DubModeService.mode.value, AudioDubMode.hindi);
      expect(DubModeService.isHindi, isTrue);
    });

    test('initialize() is idempotent (safe to call twice)', () async {
      SharedPreferences.setMockInitialValues({'audio_dub_mode': 'english'});
      await DubModeService.initialize();
      await DubModeService.initialize();
      expect(DubModeService.mode.value, AudioDubMode.english);
    });

    test('mode notifier notifies listeners on change', () async {
      var notifications = 0;
      void listener() => notifications++;
      DubModeService.mode.addListener(listener);
      await DubModeService.setMode(AudioDubMode.hindi);
      await DubModeService.setMode(AudioDubMode.english);
      DubModeService.mode.removeListener(listener);
      expect(notifications, 2);
    });
  });
}
