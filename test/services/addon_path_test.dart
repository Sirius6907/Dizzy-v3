import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/stream/stream_service.dart';

void main() {
  group('addon stream path', () {
    test('movie keeps a bare id', () {
      expect(
        StreamService.buildAddonStreamPath(type: 'movie', id: 'tt1375666'),
        'movie/tt1375666',
      );
    });

    test('series appends season and episode', () {
      expect(
        StreamService.buildAddonStreamPath(
          type: 'series',
          id: 'tt26598805',
          season: 1,
          episode: 2,
        ),
        'series/tt26598805:1:2',
      );
    });

    test('series without an episode stays unsuffixed', () {
      expect(
        StreamService.buildAddonStreamPath(type: 'series', id: 'tt26598805'),
        'series/tt26598805',
      );
    });

    test('anime appends the absolute episode to a kitsu id', () {
      expect(
        StreamService.buildAddonStreamPath(
          type: 'anime',
          id: 'kitsu:13209',
          season: 2,
          episode: 53,
        ),
        'anime/kitsu:13209:53',
      );
    });

    test('an already scoped id is not suffixed twice', () {
      expect(
        StreamService.buildAddonStreamPath(
          type: 'series',
          id: 'tt26598805:1:2',
          season: 1,
          episode: 2,
        ),
        'series/tt26598805:1:2',
      );
    });

    test('percent-encodes each id segment but keeps the colons', () {
      expect(
        StreamService.buildAddonStreamPath(
          type: 'series',
          id: 'tt 1/2',
          season: 3,
          episode: 4,
        ),
        'series/tt%201%2F2:3:4',
      );
    });
  });
}
