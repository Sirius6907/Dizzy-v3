import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dizzy/services/music/music_settings.dart';
import 'package:dizzy/services/music/music_mood_filter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('selectedMood defaults to any with no stored preference', () async {
    SharedPreferences.setMockInitialValues({});
    await MusicSettings.initialize();
    expect(MusicSettings.selectedMood.value, MusicMood.any);
  });

  test('setSelectedMood persists and survives re-initialization', () async {
    SharedPreferences.setMockInitialValues({});
    await MusicSettings.initialize();
    await MusicSettings.setSelectedMood(MusicMood.focus);
    expect(MusicSettings.selectedMood.value, MusicMood.focus);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('music_selected_mood'), 'focus');

    // A fresh initialize (simulated app restart) reads the persisted mood.
    await MusicSettings.initialize();
    expect(MusicSettings.selectedMood.value, MusicMood.focus);
  });

  test('resetToDefaults restores the any mood and clears the key', () async {
    SharedPreferences.setMockInitialValues({
      'music_selected_mood': 'romance',
    });
    await MusicSettings.initialize();
    expect(MusicSettings.selectedMood.value, MusicMood.romance);

    await MusicSettings.resetToDefaults();
    expect(MusicSettings.selectedMood.value, MusicMood.any);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('music_selected_mood'), isNull);
  });
}
