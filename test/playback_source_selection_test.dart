import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/stream/source_ranker.dart';
import 'package:dizzy/services/stream/stream_health_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

StreamSource _torrent({
  String name = 'MobLand 1080p BluRay HEVC x265 5.1',
  String? desc,
  int? seeders,
  String? infoHash,
  int? fileIdx,
}) {
  return StreamSource(
    addonName: 'Torrentio',
    infoHash: infoHash ?? 'abcaa28b7d8c96562e8c43d21cfb4693ed89e139',
    fileIdx: fileIdx,
    name: name,
    description:
        desc ??
        (seeders == null ? null : '👤 $seeders 💾 1.1 GB ⚙️ TorrentGalaxy'),
  );
}

StreamSource _http({String name = 'Bypass', String? url}) {
  return StreamSource(
    addonName: 'VidLink',
    url: url ?? 'https://vidlink.example/stream/movie.mkv',
    name: name,
  );
}

void main() {
  group('torrent candidates survive the liveness probe', () {
    test('a torrent with peers is a candidate even when nothing is cached', () {
      expect(
        StreamHealthChecker.isTorrentCandidateViable(seeders: 1095),
        isTrue,
      );
    });

    test('an unknown peer count is not treated as a dead source', () {
      expect(
        StreamHealthChecker.isTorrentCandidateViable(seeders: null),
        isTrue,
      );
    });

    test('a torrent without peers is dead', () {
      expect(StreamHealthChecker.isTorrentCandidateViable(seeders: 0), isFalse);
    });
  });

  group('http probe verifies before dropping', () {
    test('an HTML answer to HEAD is confirmed with a ranged GET', () async {
      var headAnswered = false;
      final client = MockClient((request) async {
        if (request.method == 'HEAD') {
          headAnswered = true;
          return http.Response('', 200, headers: {'content-type': 'text/html'});
        }
        return http.Response.bytes(
          List<int>.filled(64, 0),
          206,
          headers: {'content-type': 'video/mp4'},
        );
      });
      final alive = await StreamHealthChecker.isAlive(
        _http(),
        clientFactory: () => client,
      );
      expect(headAnswered, isTrue);
      expect(alive, isTrue);
    });

    test('an error page for both HEAD and GET is a dead source', () async {
      final client = MockClient((request) async {
        return http.Response(
          '<html>not found</html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      });
      final alive = await StreamHealthChecker.isAlive(
        _http(),
        clientFactory: () => client,
      );
      expect(alive, isFalse);
    });
  });

  group('instant-play ranking', () {
    const ctx = RankerContext();

    test('a small x264 file beats a huge HEVC file of the same kind', () {
      final heavy = _torrent(
        name: 'MobLand 1080p BluRay HEVC x265 5.1',
        desc: '👤 1095 💾 1.1 GB ⚙️ TorrentGalaxy',
      );
      final light = _torrent(
        name: 'MobLand S01E01 480p x264',
        desc: '👤 1095 💾 0.4 GB ⚙️ TorrentGalaxy',
        infoHash: 'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd',
      );
      final ordered = SourceRanker.order([heavy, light], ctx);
      expect(ordered.first, light);
    });

    test('a decode-friendly http source beats a 4K HEVC one', () {
      final heavy = _http(
        name: 'Movie 2160p HEVC DolbyVision',
        url: 'https://a.example/4k.mkv',
      );
      final light = _http(
        name: 'Movie 720p x264',
        url: 'https://b.example/720.mkv',
      );
      final ordered = SourceRanker.order([heavy, light], ctx);
      expect(ordered.first, light);
    });

    test('a plain 1080p x264 source is not penalised', () {
      final plain = _http(name: 'Movie 1080p x264');
      final score = SourceRanker.score(plain, ctx);
      expect(score, greaterThan(0));
    });

    test('a direct http source outranks a cold torrent', () {
      final direct = _http(name: 'Movie 1080p x264');
      final torrent = _torrent(
        name: 'MobLand 1080p BluRay HEVC x265 5.1',
        desc: '👤 1095 💾 1.1 GB ⚙️ TorrentGalaxy',
      );
      final ordered = SourceRanker.order([torrent, direct], ctx);
      expect(ordered.first, direct);
    });

    test('the failover chain skips sources the probe proved dead', () {
      final dead = _http(name: 'Dead 1080p', url: 'https://dead.example/a.mkv')
        ..probeDead = true;
      final alive = _http(
        name: 'Alive 720p',
        url: 'https://alive.example/b.mkv',
      );
      final chain = SourceRanker.buildFailoverChain([dead, alive], ctx);
      expect(chain.length, 1);
      expect(chain.first, alive);
    });

    test('a direct link is tried before a torrent that needs a swarm', () {
      final direct = _http(name: 'Direct 1080p x264');
      final torrent = _torrent(
        name: 'VisionQuest 480p H.264',
        desc: '👤 1 💾 750 MB ⚙️ BestTorrents',
      );
      final chain = SourceRanker.buildFailoverChain([torrent, direct], ctx);
      expect(chain.first, direct);
    });
  });
}
