import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/home/genre_preference_service.dart';

void main() {
  group('F6 GenrePreferenceService (v1.1.9)', () {
    test('rankByGenreOverlap sorts best-first', () {
      GenrePreferenceService.scores.value = {'action': 0.9, 'comedy': 0.2};
      final cands = ['A', 'B', 'C'];
      List<String> genresOf(String c) {
        return switch (c) {
          'A' => ['Comedy'],
          'B' => ['Action', 'Sci-Fi'],
          'C' => ['Drama'],
          _ => [],
        };
      }

      final ranked =
          GenrePreferenceService.rankByGenreOverlap(cands, genresOf);
      expect(ranked.first, 'B'); // action 0.9 wins
      expect(ranked, hasLength(3));
    });

    test('empty scores keep original order', () {
      GenrePreferenceService.scores.value = {};
      final cands = ['X', 'Y'];
      final ranked =
          GenrePreferenceService.rankByGenreOverlap(cands, (_) => ['Action']);
      expect(ranked, ['X', 'Y']);
    });

    test('exportScores returns a copy', () {
      GenrePreferenceService.scores.value = {'drama': 0.5};
      final out = GenrePreferenceService.exportScores();
      expect(out, {'drama': 0.5});
      out['drama'] = 1.0;
      expect(GenrePreferenceService.scores.value['drama'], 0.5);
    });
  });
}
