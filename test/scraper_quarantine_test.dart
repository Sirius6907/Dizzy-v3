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

    // v1.2.0-P1: baseline dead list matches the new unique scraper keys.
    // Regression guard — pre-v1.2.0 all scrapers returned 'DizzyHTTP', so
    // quarantine never matched and was 100% dead code.
    test('baseline dead keys are real unique scraper names', () {
      const baselineDead = {
        'flaxmovies',
        'peestream',
        'vidfast',
        'vidgod',
        'vidup',
        'bcine',
      };
      final now = DateTime(2026, 9, 8);
      // All baseline keys resolve to the pretty brand (proof they exist
      // in the display-name registry → real scrapers, not typos).
      for (final key in baselineDead) {
        expect(ScraperQuarantineService.displayNames, contains(key));
        expect(ScraperQuarantineService.displayNameFor(key), isNot('Unknown'));
        expect(
          ScraperQuarantineService.shouldSkip(
            name: key,
            map: {key: now.subtract(const Duration(days: 1))},
            now: now,
          ),
          isTrue,
          reason: '$key must be quarantinable by its unique name',
        );
      }
    });

    test('healthy scrapers are not quarantined by unique name', () {
      final now = DateTime(2026, 9, 8);
      for (final name in ['flystream', 'vidsrc', 'hindmoviez', 'movy']) {
        expect(
          ScraperQuarantineService.shouldSkip(name: name, map: {}, now: now),
          isFalse,
        );
      }
    });

    test('displayNameFor falls back to Title Case for unknown keys', () {
      expect(ScraperQuarantineService.displayNameFor('flystream'), 'FlyStream');
      expect(ScraperQuarantineService.displayNameFor('someaddon'), 'Someaddon');
      expect(ScraperQuarantineService.displayNameFor(''), 'Unknown');
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
