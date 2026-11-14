import 'package:dizzy/services/cloud/cloud_client.dart';
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
      expect(await CloudResolveService.resolveIds(title: 'Fight Club'), isNull);
      expect(
        await CloudResolveService.resolveIds(title: '', imdbId: 'tt0137523'),
        isNull,
      );
    });

    test('titlesMatch: exact, case/punct-insensitive; mismatch rejected', () {
      expect(CloudResolveService.titlesMatch('Inception', 'Inception'), isTrue);
      expect(
        CloudResolveService.titlesMatch('The Dark Knight', 'the dark knight!'),
        isTrue,
      );
      expect(
        CloudResolveService.titlesMatch('Dune: Part Two', 'dune part 2'),
        isFalse,
      );
      // THE regression: server echoing a DIFFERENT video must not resolve.
      expect(CloudResolveService.titlesMatch('The', 'The Odyssey'), isFalse);
      expect(
        CloudResolveService.titlesMatch('Janam Janam', 'The Odyssey'),
        isFalse,
      );
    });
  });

  group('v1.3.5: the resolver actually reaches the edge function', () {
    test('the request carries a bearer token, not only apikey', () {
      // THE 401 regression: the `resolve` function is deployed with JWT
      // verification ON, so an apikey-only request comes back
      // 401 UNAUTHORIZED_NO_AUTH_HEADER and the app silently lost its
      // best resolver rung (measured live, every single call).
      final h = CloudResolveService.buildHeaders();
      expect(h.containsKey('Authorization'), isTrue);
      expect(h['Authorization'], 'Bearer ${CloudClient.anonKey}');
      expect(h.containsKey('apikey'), isTrue);
      expect(h['apikey'], CloudClient.anonKey);
    });

    test('acceptsEcho: a plain mismatch is still rejected', () {
      expect(
        CloudResolveService.acceptsEcho(
          requested: 'Inception',
          echoed: 'The Odyssey',
        ),
        isFalse,
      );
      // A server answer with no provenance info stays rejected.
      expect(
        CloudResolveService.acceptsEcho(
          requested: 'Dahaan: The Evil Within',
          echoed: 'Dahaan',
          payload: const {'tmdbId': 1},
        ),
        isFalse,
      );
    });

    test('acceptsEcho: an exact echo always passes', () {
      expect(
        CloudResolveService.acceptsEcho(
          requested: 'Dahaan',
          echoed: 'dahaan',
        ),
        isTrue,
      );
    });

    test('acceptsEcho: a corpus alias is accepted (server-guarded)', () {
      expect(
        CloudResolveService.acceptsEcho(
          requested: 'Dahaan: The Evil Within',
          echoed: 'Dahaan',
          payload: const {
            'tmdbId': 1157265,
            'source': 'corpus',
            'matchQuality': 'alias',
          },
        ),
        isTrue,
      );
    });

    test('acceptsEcho: a corpus fuzzy match is accepted', () {
      expect(
        CloudResolveService.acceptsEcho(
          requested: 'AWM (Agney Weds Minall)',
          echoed: 'AWM (Agney Weds Minal)',
          payload: const {
            'tmdbId': 1133036,
            'source': 'corpus',
            'matchQuality': 'fuzzy',
          },
        ),
        isTrue,
      );
    });

    test('acceptsEcho: a tmdb fuzzy match is accepted', () {
      expect(
        CloudResolveService.acceptsEcho(
          requested: 'Minall',
          echoed: 'Minal',
          payload: const {
            'tmdbId': 1133036,
            'source': 'tmdb',
            'matchQuality': 'fuzzy',
          },
        ),
        isTrue,
      );
    });

    test('acceptsEcho: an unknown source is never accepted', () {
      expect(
        CloudResolveService.acceptsEcho(
          requested: 'Dahaan: The Evil Within',
          echoed: 'Dahaan',
          payload: const {'source': 'guess', 'matchQuality': 'exact'},
        ),
        isFalse,
      );
    });
  });
}
