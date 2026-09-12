import 'package:dizzy/services/cloud/cloud_resolve_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// P21: Cloud resolve API — every fail-soft path returns null (never throws,
/// never blocks the chain). Live edge calls need Supabase + deploy, so unit
/// tests pin the guard rails.
void main() {
  group('P21: cloud resolve guards', () {
    test('empty title + empty imdb → null without touching network', () async {
      expect(await CloudResolveService.resolveIds(title: '   '), isNull);
      expect(await CloudResolveService.resolveIds(title: ''), isNull);
    });

    test('unconfigured cloud → null (fail-soft to next chain rung)', () async {
      // Test env ships no Supabase URL → CloudClient.isReady is false.
      expect(await CloudResolveService.resolveIds(title: 'Fight Club'),
          isNull);
      expect(
          await CloudResolveService.resolveIds(
              title: '', imdbId: 'tt0137523'),
          isNull);
    });
  });
}
