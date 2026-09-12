import 'package:dizzy/services/cloud/cloud_client.dart';
import 'package:dizzy/services/scraper/sites/tmdb_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P14: keyless-first chain', () {
    test('edge always first; direct only with key; keyless always last', () {
      expect(TmdbHelper.resolveChain(edgeReady: true, key: true),
          ['resolve', 'edge', 'direct', 'keyless']);
      expect(TmdbHelper.resolveChain(edgeReady: true, key: false),
          ['resolve', 'edge', 'keyless']);
      expect(TmdbHelper.resolveChain(edgeReady: false, key: true),
          ['direct', 'keyless']);
      expect(TmdbHelper.resolveChain(edgeReady: false, key: false),
          ['keyless'],
          reason: 'cloud-off survival via third-party proxy, never preferred');
    });

    test('test env ships no TMDB key (APK carries none)', () {
      // No --dart-define + no .env in CI/test → keyless path only.
      expect(TmdbHelper.hasKey, isFalse);
    });

    test('functionUrl empty when cloud unconfigured (fail-soft)', () {
      // No SUPABASE_URL in test env → '' → edge skipped, no crash.
      expect(CloudClient.functionUrl('tmdb-proxy'), isEmpty);
    });

    test('numeric ids resolve offline (no network touched)', () async {
      expect(
        await TmdbHelper.resolveTmdbId(
            imdbId: 'tmdb:12345', title: 'X', type: 'movie'),
        12345,
      );
    });

    test('garbage resolves null, never throws', () async {
      expect(
        await TmdbHelper.resolveTmdbId(title: '', type: 'movie'),
        isNull,
      );
    });
  });
}
