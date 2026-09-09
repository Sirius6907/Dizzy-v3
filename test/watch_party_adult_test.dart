import 'package:dizzy/services/cloud/watch_party_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WatchParty 18+ filter (WP-P1b)', () {
    test('tmdb flag or host declaration marks adult', () {
      expect(WatchPartyService.isAdultContent(tmdbAdult: true), isTrue);
      expect(WatchPartyService.isAdultContent(hostDeclared: true), isTrue);
      expect(WatchPartyService.isAdultContent(), isFalse);
    });

    test('title keywords mark adult, clean titles pass', () {
      expect(WatchPartyService.isAdultContent(title: 'XXX Nights'), isTrue);
      expect(
          WatchPartyService.isAdultContent(title: 'Hot Porn Parody'), isTrue);
      expect(WatchPartyService.isAdultContent(title: 'UNCENSORED cut'),
          isTrue);
      expect(
          WatchPartyService.isAdultContent(title: 'Blue Film Classics'),
          isTrue);
      expect(WatchPartyService.isAdultContent(title: 'Thor: Ragnarok'),
          isFalse);
      expect(WatchPartyService.isAdultContent(title: 'Dune: Part Two'),
          isFalse);
    });

    test('blocked genre ids mark adult', () {
      expect(
        WatchPartyService.isAdultContent(
            genreIds: [27, 99], blockedGenreIds: [99]),
        isTrue,
      );
      expect(
        WatchPartyService.isAdultContent(
            genreIds: [28, 12], blockedGenreIds: [99]),
        isFalse,
      );
    });

    test('fromJson carries is_adult, defaults false', () {
      final adult = WatchPartyRoom.fromJson(
          {'room_id': 'K7Q2M9', 'is_adult': true});
      expect(adult.isAdult, isTrue);
      final clean =
          WatchPartyRoom.fromJson({'room_id': 'K7Q2M9'});
      expect(clean.isAdult, isFalse);
    });
  });
}
