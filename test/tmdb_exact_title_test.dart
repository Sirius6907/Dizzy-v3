import 'package:dizzy/services/scraper/sites/tmdb_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wrong-content regression (2026-10-10): substring matching +
/// results.first fallback played a DIFFERENT movie — poster A, playback B.
/// Exact title match is REQUIRED; anything else resolves null.
void main() {
  Map<String, Object?> item(String title, int id, {String date = ''}) => {
        'title': title,
        'id': id,
        'release_date': date,
      };

  group('TmdbHelper.pickExactTitleId — strict gate', () {
    test('exact match (case/punct-insensitive) resolves', () {
      final results = [
        item('Inception: The Beginning', 111, date: '2010-01-01'),
        item('Inception', 27205, date: '2010-07-16'),
      ];
      expect(
        TmdbHelper.pickExactTitleId(
            results: results, title: 'Inception', year: 2010),
        27205,
      );
    });

    test('substring-only candidates resolve null (never results.first)', () {
      final results = [
        item('Inception: The Beginning', 111, date: '2010-01-01'),
        item('Inception Recut', 222, date: '2010-05-05'),
      ];
      expect(
        TmdbHelper.pickExactTitleId(
            results: results, title: 'Inception', year: 2010),
        isNull,
      );
    });

    test('exact title but wrong year resolves null', () {
      final results = [
        item('Inception', 999, date: '2024-01-01'),
      ];
      expect(
        TmdbHelper.pickExactTitleId(
            results: results, title: 'Inception', year: 2010),
        isNull,
      );
    });

    test('empty results resolve null', () {
      expect(
        TmdbHelper.pickExactTitleId(
            results: const [], title: 'Inception', year: 2010),
        isNull,
      );
    });

    test('year omitted: first exact-title hit wins', () {
      final results = [
        item('Dune', 111, date: '1984-12-14'),
        item('Dune', 438631, date: '2021-09-15'),
      ];
      expect(
        TmdbHelper.pickExactTitleId(results: results, title: 'Dune'),
        111,
      );
    });

    test('year within +-1 resolves', () {
      final results = [
        item('Dune', 438631, date: '2021-09-15'),
      ];
      expect(
        TmdbHelper.pickExactTitleId(
            results: results, title: 'Dune', year: 2022),
        438631,
      );
    });
  });
}
