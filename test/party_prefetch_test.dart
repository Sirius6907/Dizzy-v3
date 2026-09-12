import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/movie/movie_detail.dart';
import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/stream/next_episode_engine.dart';
import 'package:dizzy/services/watchparty/guest_auto_open.dart';
import 'package:dizzy/services/watchparty/watch_sync_engine.dart';

const _master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720
720p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080
1080p/index.m3u8
''';

MovieDetail _detail(String id) =>
    MovieDetail(id: id, type: 'movie', name: 'N $id');

void main() {
  group('P10: ready-hint message channel', () {
    test('round-trips true; defaults false; old JSON → false', () {
      const m = WatchSyncMessage(
        mediaRef: 'tmdb:movie:550',
        positionMs: 0,
        playing: true,
        hostSentAtMs: 1,
        prefetchReady: true,
      );
      final back = WatchSyncMessage.fromJson(
          Map<String, dynamic>.from(m.toJson()));
      expect(back.prefetchReady, isTrue);
      expect(back.isUsable, isTrue);

      const plain = WatchSyncMessage(
        mediaRef: 'tmdb:movie:550',
        positionMs: 0,
        playing: true,
        hostSentAtMs: 1,
      );
      expect(plain.prefetchReady, isFalse);

      final old = WatchSyncMessage.fromJson({'media_ref': 'x', 'v': 1});
      expect(old.prefetchReady, isFalse);
      expect(old.isUsable, isTrue);
    });
  });

  group('P10: prefetch carries renditions', () {
    test('HLS master + fake fetch → ladder attached best-first', () async {
      final src =
          StreamSource(url: 'https://cdn/x/master.m3u8', addonName: 'a');
      final out = await NextEpisodeEngine.withRenditions(src,
          fetchBody: (_, __) async => _master);
      expect(out.renditions.map((e) => e.label), ['1080p', '720p']);
    });

    test('non-HLS untouched; failure → same source; existing kept', () async {
      final mp4 = StreamSource(url: 'https://c/f.mp4', addonName: 'a');
      expect(await NextEpisodeEngine.withRenditions(mp4), same(mp4));

      final hls =
          StreamSource(url: 'https://cdn/x/master.m3u8', addonName: 'a');
      final failed = await NextEpisodeEngine.withRenditions(hls,
          fetchBody: (_, __) async => throw Exception('offline'));
      expect(failed.renditions, isEmpty);

      final garbage = await NextEpisodeEngine.withRenditions(hls,
          fetchBody: (_, __) async => 'not a playlist');
      expect(garbage.renditions, isEmpty);

      final rich = StreamSource(
        url: 'https://cdn/x/master.m3u8',
        addonName: 'a',
        renditions: const [Rendition(label: '480p', url: 'u')],
      );
      var fetched = false;
      final kept = await NextEpisodeEngine.withRenditions(rich,
          fetchBody: (_, __) async {
        fetched = true;
        return _master;
      });
      expect(kept, same(rich)); // no refetch when ladder exists
      expect(fetched, isFalse);
    });
  });

  group('P10: guest prewarm cache', () {
    setUp(GuestAutoOpen.clearCache);

    test('miss → null; seed → hit; bounded at 8 (oldest evicted)', () {
      expect(GuestAutoOpen.cachedDetail('tmdb:movie:1'), isNull);
      GuestAutoOpen.cacheDetail('tmdb:movie:1', _detail('tt1'));
      expect(GuestAutoOpen.cachedDetail('tmdb:movie:1')?.name, 'N tt1');

      for (var i = 2; i <= 10; i++) {
        GuestAutoOpen.cacheDetail('tmdb:movie:$i', _detail('tt$i'));
      }
      expect(GuestAutoOpen.cachedDetail('tmdb:movie:1'), isNull,
          reason: 'oldest evicted past bound');
      expect(GuestAutoOpen.cachedDetail('tmdb:movie:10')?.name, 'N tt10');

      GuestAutoOpen.clearCache();
      expect(GuestAutoOpen.cachedDetail('tmdb:movie:10'), isNull);
    });
  });
}
