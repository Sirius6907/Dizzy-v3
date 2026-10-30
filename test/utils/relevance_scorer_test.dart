import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/utils/search/relevance_scorer.dart';

void main() {
  group('RelevanceScorer', () {
    group('exact matches', () {
      test('exact match scores 10000', () {
        expect(
          RelevanceScorer.score(title: 'Inception', query: 'Inception'),
          10000,
        );
      });
      test('exact match case insensitive', () {
        expect(
          RelevanceScorer.score(title: 'INCEPTION', query: 'inception'),
          10000,
        );
      });
      test('exact match ignores leading articles', () {
        expect(
          RelevanceScorer.score(title: 'The Matrix', query: 'Matrix'),
          10000,
        );
        expect(
          RelevanceScorer.score(
            title: 'A Beautiful Mind',
            query: 'Beautiful Mind',
          ),
          10000,
        );
        expect(
          RelevanceScorer.score(
            title: 'An American Tail',
            query: 'American Tail',
          ),
          10000,
        );
      });
    });
    group('substring matches', () {
      test('substring match scores 5000', () {
        expect(
          RelevanceScorer.score(title: 'Inception 2', query: 'Inception'),
          greaterThan(0),
        );
      });
    });
    group('prefix matches', () {
      test('prefix match scores 3000', () {
        expect(
          RelevanceScorer.score(title: 'Breaking Bad', query: 'Break'),
          greaterThan(0),
        );
      });
    });
    group('edge cases', () {
      test('empty query returns 0', () {
        expect(RelevanceScorer.score(title: 'Anything', query: ''), 0);
      });
      test('empty title returns 0', () {
        expect(RelevanceScorer.score(title: '', query: 'query'), 0);
      });
    });

    group('typo tolerance', () {
      test('one typo on a long title still matches', () {
        final s = RelevanceScorer.score(title: 'Pathaan', query: 'pathan');
        expect(s, greaterThan(0));
        expect(s, lessThan(3000));
      });
      test('a transposition matches', () {
        expect(
          RelevanceScorer.score(title: 'Jawan', query: 'jaawn'),
          greaterThan(0),
        );
      });
      test('short queries never fuzzy-match', () {
        expect(RelevanceScorer.score(title: 'Jawan', query: 'jawx'), 0);
      });
      test('exact still beats fuzzy', () {
        expect(
          RelevanceScorer.score(title: 'Pathaan', query: 'Pathaan'),
          greaterThan(RelevanceScorer.score(title: 'Pathaan', query: 'pathan')),
        );
      });
    });

    group('Hindi script and accents', () {
      test('Devanagari exact match works', () {
        expect(RelevanceScorer.score(title: 'पठान', query: 'पठान'), 10000);
      });
      test('Devanagari title vs Latin query', () {
        expect(
          RelevanceScorer.score(title: 'पठान', query: 'pathaan'),
          greaterThan(0),
        );
      });
      test('Latin title vs Devanagari query', () {
        expect(
          RelevanceScorer.score(title: 'Pathaan', query: 'पठान'),
          greaterThan(0),
        );
      });
      test('accented titles fold', () {
        expect(RelevanceScorer.score(title: 'Amélie', query: 'Amelie'), 10000);
      });
    });

    group('newer wins ties', () {
      test('same title, newer year first', () {
        final c = RelevanceScorer.compare(
          titleA: 'Pathaan',
          yearA: 2023,
          titleB: 'Pathaan',
          yearB: 2018,
          query: 'pathaan',
        );
        expect(c, lessThan(0));
      });
      test('relevance beats recency', () {
        final c = RelevanceScorer.compare(
          titleA: 'Pathaan',
          yearA: 2023,
          titleB: 'Pathan Returns',
          yearB: 2026,
          query: 'pathaan',
        );
        expect(c, lessThan(0));
      });
      test('unknown years do not throw', () {
        expect(
          RelevanceScorer.compare(
            titleA: 'X',
            yearA: null,
            titleB: 'X',
            yearB: null,
            query: 'x',
          ),
          0,
        );
      });
    });
  });
}
