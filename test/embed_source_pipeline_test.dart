import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/stream/source_ranker.dart';
import 'package:dizzy/services/stream/stream_health_checker.dart';

StreamSource _direct() => StreamSource(
  name: 'lmscript',
  addonName: 'lmscript',
  url: 'https://cdn.example/hls/550/index.m3u8',
  title: '1080p direct',
);

StreamSource _embed() => StreamSource(
  name: 'VidFast',
  addonName: 'vidfast',
  externalUrl: 'https://vidfast.vc/movie/550?autoPlay=true',
  title: 'VidFast · Embed',
  behaviorHints: const {'dizzyEmbed': true},
);

StreamSource _torrent() => StreamSource(
  name: 'Knaben',
  addonName: 'knaben',
  infoHash: 'abc123',
  title: '1080p torrent',
);

void main() {
  test('an embed source is alive without any network probe', () async {
    final source = _embed();
    final alive = await StreamHealthChecker.isAlive(source);
    expect(alive, isTrue);
    expect(source.probeDead, isFalse);
  });

  test('failover order: direct first, embed second, torrent last', () {
    final chain = SourceRanker.buildFailoverChain(
      [_torrent(), _embed(), _direct()],
      const RankerContext(),
    );

    final direct = chain.indexWhere((s) => s.addonName == 'lmscript');
    final embed = chain.indexWhere((s) => s.addonName == 'vidfast');
    final torrent = chain.indexWhere((s) => s.addonName == 'knaben');

    expect(direct, 0);
    expect(embed, 1);
    expect(torrent, 2);
  });

  test('a probe-dead source never survives in the chain', () {
    final dead = _direct()..probeDead = true;
    final chain = SourceRanker.buildFailoverChain(
      [dead, _embed()],
      const RankerContext(),
    );
    expect(chain.any((s) => s.addonName == 'lmscript'), isFalse);
    expect(chain.single.addonName, 'vidfast');
  });

  test('isEmbedSource only reads the explicit hint', () {
    expect(_embed().isEmbedSource, isTrue);
    expect(_direct().isEmbedSource, isFalse);
    expect(_torrent().isEmbedSource, isFalse);
  });
}
