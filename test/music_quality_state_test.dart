import 'package:dizzy/services/music/music_player_controller.dart';
import 'package:dizzy/services/music/music_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'choosing lossless preference does not certify an unresolved stream',
    () async {
      SharedPreferences.setMockInitialValues({});
      final controller = MusicPlayerController.instance;
      await Future<void>.delayed(Duration.zero);
      await controller.setAudioSource(MusicAudioSource.youtube);
      await controller.setAudioSource(MusicAudioSource.flac);
      expect(controller.isCurrentTrackLossless, isFalse);
      expect(
        controller.currentQualityLabel.toLowerCase(),
        isNot(contains('flac')),
      );
    },
  );
}
