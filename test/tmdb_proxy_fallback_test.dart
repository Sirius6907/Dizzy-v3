import 'package:dizzy/services/cloud/cloud_client.dart';
import 'package:dizzy/services/scraper/sites/tmdb_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// P18: proxy fallback — cloud-off devices (and CI) still resolve through
/// the keyless last resort; edge stays first wherever it exists.
void main() {
  group('P18: proxy fallback', () {
    test('unconfigured cloud yields no edge URL (callers fail soft)', () {
      expect(CloudClient.functionUrl('tmdb-proxy'), isEmpty);
    });

    test('edge first when ready, keyless always last', () {
      for (final entry in [
        (true, true),
        (true, false),
        (false, true),
        (false, false),
      ]) {
        final chain = TmdbHelper.resolveChain(
            edgeReady: entry.$1, key: entry.$2);
        expect(chain.last, 'keyless');
        if (entry.$1) expect(chain.first, 'edge');
      }
    });
  });
}
