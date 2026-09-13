import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/music/music_track.dart';
import 'package:dizzy/services/music/music_equalizer_service.dart';
import 'package:dizzy/services/music/music_playlist_sharing_service.dart';

void main() {
  group('Music M1-M20 Services Tests', () {
    test('MusicEqualizerService presets have 5 valid frequency bands', () {
      for (final preset in MusicEqPreset.values) {
        final gains = MusicEqualizerService.presetGains[preset];
        expect(gains, isNotNull);
        expect(gains!.length, 5);
        for (final g in gains) {
          expect(g >= -12.0 && g <= 12.0, isTrue);
        }
      }
    });

    test('MusicPlaylistSharingService exports to M3U correctly', () {
      final playlist = UserPlaylist(
        id: 'test-p1',
        title: 'Chill Lo-Fi Vibes',
        createdAt: '2026-09-13T12:00:00Z',
        tracks: [
          const MusicTrack(
            id: 't1',
            title: 'Midnight City',
            artist: 'M83',
            album: 'Hurry Up',
            coverUrl: 'https://example.com/cover1.jpg',
            durationSeconds: 243,
          ),
          const MusicTrack(
            id: 't2',
            title: 'Resonance',
            artist: 'HOME',
            album: 'Odyssey',
            coverUrl: 'https://example.com/cover2.jpg',
            durationSeconds: 212,
          ),
        ],
      );

      final m3u = MusicPlaylistSharingService.instance.exportToM3U(playlist);
      expect(m3u.contains('#EXTM3U'), isTrue);
      expect(m3u.contains('#PLAYLIST:Chill Lo-Fi Vibes'), isTrue);
      expect(m3u.contains('#EXTINF:243,M83 - Midnight City'), isTrue);
      expect(m3u.contains('https://music.youtube.com/watch?v=t1'), isTrue);
      expect(m3u.contains('#EXTINF:212,HOME - Resonance'), isTrue);
      expect(m3u.contains('https://music.youtube.com/watch?v=t2'), isTrue);
    });

    test('MusicPlaylistSharingService exports to JSON correctly', () {
      final playlist = UserPlaylist(
        id: 'test-p2',
        title: 'Synthwave Neon',
        createdAt: '2026-09-13T12:00:00Z',
        tracks: [
          const MusicTrack(
            id: 'trk1',
            title: 'Turbo Killer',
            artist: 'Carpenter Brut',
            album: 'Trilogy',
            coverUrl: 'https://example.com/cover3.jpg',
            durationSeconds: 208,
          ),
        ],
      );

      final jsonStr = MusicPlaylistSharingService.instance.exportToJson(playlist);
      expect(jsonStr.contains('dizzy_playlist_v3'), isTrue);
      expect(jsonStr.contains('Synthwave Neon'), isTrue);
      expect(jsonStr.contains('Turbo Killer'), isTrue);
    });
  });
}
