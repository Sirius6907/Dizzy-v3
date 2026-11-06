import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/anime/kitsu_resolver.dart';

void main() {
  group('KitsuResolver.pickCandidateId', () {
    test('picks the exact title', () {
      final id = KitsuResolver.pickCandidateId(
        const [
          KitsuCandidate(id: 1, title: 'Black Clover: Jump Festa 2016 Special'),
          KitsuCandidate(id: 2, title: 'Black Clover', year: 2017, episodes: 170),
        ],
        title: 'Black Clover',
        year: 2017,
      );
      expect(id, 2);
    });

    test('rejects a conflicting year', () {
      final id = KitsuResolver.pickCandidateId(
        const [
          KitsuCandidate(id: 3, title: 'Black Clover', year: 1999, episodes: 12),
        ],
        title: 'Black Clover',
        year: 2017,
      );
      expect(id, isNull);
    });

    test('prefers the TV entry over a same-name special', () {
      final id = KitsuResolver.pickCandidateId(
        const [
          KitsuCandidate(id: 4, title: 'Black Clover Special', episodes: 1),
          KitsuCandidate(id: 5, title: 'Black Clover', episodes: 170),
        ],
        title: 'Black Clover',
      );
      expect(id, 5);
    });

    test('matches when one title is a subset', () {
      final id = KitsuResolver.pickCandidateId(
        const [
          KitsuCandidate(id: 6, title: 'Attack on Titan', episodes: 25),
        ],
        title: 'Shingeki no Kyojin: Attack on Titan',
      );
      expect(id, 6);
    });

    test('returns null when nothing overlaps', () {
      final id = KitsuResolver.pickCandidateId(
        const [KitsuCandidate(id: 7, title: 'Naruto', episodes: 220)],
        title: 'Black Clover',
      );
      expect(id, isNull);
    });
  });
}
