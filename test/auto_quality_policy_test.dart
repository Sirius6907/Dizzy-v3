// Regression: the AUTO quality ladder must never re-open a torrent.
//
// Device evidence (2026-11-16, emulator-5554, VisionQuest S01E02):
//   13:16:38  TorrentsDB 1080p torrent opened successfully, 1920x1080,
//             hindi audio track selected -> PLAYING
//   13:16:50  "[Quality] torrent swarm 4.0 Mbps cannot feed 1080p -> auto
//             480p"  -> the player was stopped, a DIFFERENT torrent was
//             opened, that swarm starved, and the session ended with
//             "Stream URL is null" - the working 1080p was thrown away.
//
// A torrent has one file, so "a different quality" is a different SOURCE.
// That decision belongs to the start/failover path (StartupBandwidthPolicy
// and the torrent failure path), never to a mid-playback switch.
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/player/auto_quality_policy.dart';

void main() {
  group('AutoQualityPolicy.supportsQualitySwitch', () {
    test('a torrent source is not quality-switchable', () {
      final torrent = StreamSource(
        name: 'TorrentsDB',
        addonName: 'torrentsdb',
        title: 'VisionQuest S01E02 1080p',
        infoHash: '13f69c7025c388c22210c7d9ef8fb401f8bdbdff',
        sources: const ['tracker:udp://tracker.example:1337'],
      );
      expect(AutoQualityPolicy.supportsQualitySwitch(torrent), isFalse);
    });

    test('a magnet URL is not quality-switchable', () {
      final magnet = StreamSource(
        name: 'Torrentio',
        addonName: 'torrentio',
        title: 'VisionQuest S01E02 1080p',
        url: 'magnet:?xt=urn:btih:13f69c7025c388c22210c7d9ef8fb401f8bdbdff',
        infoHash: '13f69c7025c388c22210c7d9ef8fb401f8bdbdff',
      );
      expect(AutoQualityPolicy.supportsQualitySwitch(magnet), isFalse);
    });

    test('a progressive HTTP source is quality-switchable', () {
      final http = StreamSource(
        name: 'VidLink',
        addonName: 'vidlink',
        title: 'VidLink - 1080p',
        url: 'https://cdn.example.net/movie/550.mp4',
      );
      expect(AutoQualityPolicy.supportsQualitySwitch(http), isTrue);
    });
  });
}
