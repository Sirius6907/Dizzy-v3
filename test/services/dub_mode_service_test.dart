import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dizzy/services/player/dub_mode_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('initial preference selects Hindi before loading prefs', () {
    expect(DubModeService.mode.value, AudioDubMode.hindi);
    expect(DubModeService.isHindi, isTrue);
  });

  group('DubModeService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DubModeService.resetForTest();
    });

    test('reset restores the Hindi default', () async {
      await DubModeService.setMode(AudioDubMode.english);
      DubModeService.resetForTest();
      expect(DubModeService.mode.value, AudioDubMode.hindi);
      expect(DubModeService.isHindi, isTrue);
    });

    test('missing saved preference selects Hindi', () async {
      DubModeService.mode.value = AudioDubMode.english;
      await DubModeService.initialize();
      expect(DubModeService.isHindi, isTrue);
    });

    for (final invalid in <Object>['', 'unknown', 'dual', 'HINDI', 42, true]) {
      test('invalid saved preference $invalid selects Hindi', () async {
        SharedPreferences.setMockInitialValues({'audio_dub_mode': invalid});
        DubModeService.mode.value = AudioDubMode.english;
        await DubModeService.initialize();
        expect(DubModeService.isHindi, isTrue);
      });
    }

    test('initialize() restores explicitly saved English', () async {
      SharedPreferences.setMockInitialValues({'audio_dub_mode': 'english'});
      DubModeService.mode.value = AudioDubMode.hindi;
      await DubModeService.initialize();
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
      await DubModeService.setMode(AudioDubMode.english);
      await DubModeService.setMode(AudioDubMode.hindi);
      DubModeService.mode.removeListener(listener);
      expect(notifications, 2);
    });
  });
}
