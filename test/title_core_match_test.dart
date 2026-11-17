import 'package:dizzy/utils/torrent/title_core_match.dart';
import 'package:flutter_test/flutter_test.dart';

/// The torrent filter used to compare the release name with the app's
/// catalogue name VERBATIM, so a correctly indexed release of a subtitled
/// title was thrown away ("Dahaan (2026)" vs "Dahaan: The Evil Within").
/// That was a measurable "sources kam" cause for regional titles.
void main() {
  group('TitleCoreMatch.core', () {
    test('drops the subtitle, the brackets and the stop words', () {
      expect(TitleCoreMatch.core('Dahaan: The Evil Within'), 'dahaan');
      expect(TitleCoreMatch.core('AWM (Agney Weds Minal)'), 'awm');
      expect(TitleCoreMatch.core('Bhai - The Opening Part'), 'bhai');
      expect(TitleCoreMatch.core('Rakta Golapa'), 'raktagolapa');
    });
  });

  group('TitleCoreMatch.matches', () {
    test('a subtitled request matches the core release', () {
      expect(
        TitleCoreMatch.matches(
          requested: 'Dahaan: The Evil Within',
          candidate: 'Dahaan',
          year: 2026,
          candidateYear: 2026,
        ),
        isTrue,
      );
    });

    test('a spelling slip matches when the core is long', () {
      expect(
        TitleCoreMatch.matches(
          requested: 'Madhumallati',
          candidate: 'Madhumalati',
          year: 2026,
          candidateYear: 2026,
        ),
        isTrue,
      );
    });

    test('a short core never matches a different word', () {
      // "Murabi" must not be answered by "Murali".
      expect(
        TitleCoreMatch.matches(
          requested: 'Murabi',
          candidate: 'Murali',
          year: 2026,
          candidateYear: 2026,
        ),
        isFalse,
      );
    });

    test('a different film is rejected', () {
      expect(
        TitleCoreMatch.matches(
          requested: 'Dahaan',
          candidate: 'Rakta Golapa',
          year: 2026,
          candidateYear: 2026,
        ),
        isFalse,
      );
    });

    test('a wrong year is rejected even when the name matches', () {
      expect(
        TitleCoreMatch.matches(
          requested: 'Dahaan',
          candidate: 'Dahaan',
          year: 2026,
          candidateYear: 2014,
        ),
        isFalse,
      );
    });

    test('an unknown release year does not block a name match', () {
      expect(
        TitleCoreMatch.matches(
          requested: 'Dahaan',
          candidate: 'Dahaan',
          year: 2026,
        ),
        isTrue,
      );
    });

    test('the candidate may carry extra words', () {
      expect(
        TitleCoreMatch.matches(
          requested: 'Dahaan',
          candidate: 'Dahaan The Evil Within',
          year: 2026,
          candidateYear: 2026,
        ),
        isTrue,
      );
    });
  });
}
