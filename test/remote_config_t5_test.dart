import 'package:dizzy/services/cloud/remote_config_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => RemoteConfigService.debugSeed({}));

  group('v1.3.3-T5 typed hot-fix accessors (fail-closed)', () {
    test('missing keys fall back to safe defaults', () {
      expect(RemoteConfigService.typedValue('nope', fallback: 'd'), 'd');
      expect(RemoteConfigService.typedNamespace('scraper_urls'), isEmpty);
      expect(RemoteConfigService.typedJson('ranking_weights'), isEmpty);
      expect(RemoteConfigService.musicShelvesLayout, isEmpty);
      expect(RemoteConfigService.musicEndpoints, isEmpty);
      expect(RemoteConfigService.minSupportedBuild, isEmpty);
    });

    test('bad JSON never grants — returns empty map', () {
      RemoteConfigService.debugSeed({'ranking_weights': '{broken'});
      expect(RemoteConfigService.typedJson('ranking_weights'), isEmpty);
    });

    test('namespaced keys scope correctly, empty values dropped', () {
      RemoteConfigService.debugSeed({
        'music_endpoints.jiosaavn': 'https://edge.example/saavn',
        'music_endpoints.ytmusic': '',
        'scraper_kill': '{}',
      });
      final ep = RemoteConfigService.musicEndpoints;
      expect(ep, {'jiosaavn': 'https://edge.example/saavn'});
      expect(RemoteConfigService.scopedSnapshot('scraper'), isEmpty);
    });

    test('music shelves layout parses, unknown keys stay out of scope', () {
      RemoteConfigService.debugSeed({
        'music_shelves_layout':
            '{"order":["trending","moods"],"hidden":["charts"]}',
        'min_supported_build': '1033',
      });
      final layout = RemoteConfigService.musicShelvesLayout;
      expect(layout['order'], ['trending', 'moods']);
      expect(RemoteConfigService.minSupportedBuild, '1033');
    });
  });
}
