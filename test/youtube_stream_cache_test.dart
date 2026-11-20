import 'package:dizzy/models/music/music_track.dart';
import 'package:dizzy/services/music/youtube_audio_extractor.dart';
import 'package:dizzy/services/music/youtube_rate_limit_guard.dart';
import 'package:dizzy/services/music/youtube_stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

class _Extractor extends Fake implements YoutubeAudioExtractor {
  var refreshed = false;

  @override
  Future<({String videoId, String audioUrl, String userAgent})?> extract(
    String title,
    String artist, {
    Duration? targetDuration,
    String? titleVersion,
    bool verifyStream = true,
    Duration budget = const Duration(seconds: 10),
  }) async => (
    videoId: 'test-video',
    audioUrl: refreshed
        ? 'https://audio-test.invalid/fresh.m4a'
        : 'https://audio-test.invalid/rejected.m4a',
    userAgent: 'test-agent',
  );

  @override
  void invalidate(String videoId) {
    if (videoId == 'test-video') refreshed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const track = MusicTrack(
    id: 'cache-test',
    title: 'Test track',
    artist: 'Test artist',
    album: 'Test album',
    coverUrl: '',
    durationSeconds: 200,
  );

  test(
    'rejected audio evicts both resolver and extractor stream caches',
    () async {
      YoutubeRateLimitGuard.clear();
      final resolver = YoutubeStreamResolver(extractor: _Extractor());
      expect(
        (await resolver.resolveUrl(track))?.url,
        'https://audio-test.invalid/rejected.m4a',
      );
      resolver.invalidate(track.id);
      expect(
        (await resolver.resolveUrl(track))?.url,
        'https://audio-test.invalid/fresh.m4a',
      );
    },
  );
}
