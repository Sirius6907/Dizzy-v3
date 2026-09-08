import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/scraper/scraper_quarantine_service.dart';

void main() {
  group('F0 ScraperQuarantineService', () {
    test('shouldSkip returns true within 7-day cooldown', () {
      final now = DateTime(2026, 9, 8);
      final map = {'flaxmovies': now.subtract(const Duration(days: 2))};
      expect(
        ScraperQuarantineService.shouldSkip(
          name: 'FlaxMovies',
          map: map,
          now: now,
        ),
        isTrue,
      );
    });

    test('shouldSkip returns false after 7-day cooldown', () {
      final now = DateTime(2026, 9, 8);
      final map = {'flaxmovies': now.subtract(const Duration(days: 8))};
      expect(
        ScraperQuarantineService.shouldSkip(
          name: 'FlaxMovies',
          map: map,
          now: now,
        ),
        isFalse,
      );
    });

    test('untracked scraper is never skipped', () {
      final now = DateTime(2026, 9, 8);
      expect(
        ScraperQuarantineService.shouldSkip(
          name: 'HindMoviez',
          map: {},
          now: now,
        ),
        isFalse,
      );
    });

    test('case-insensitive matching', () {
      final now = DateTime(2026, 9, 8);
      final map = {'peestream': now};
      expect(
        ScraperQuarantineService.shouldSkip(
          name: 'PEESTREAM',
          map: map,
          now: now,
        ),
        isTrue,
      );
    });
  });
}
