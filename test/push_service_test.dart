import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/models/movie/movie.dart';
import 'package:dizzy/services/notification/notification_inbox.dart';
import 'package:dizzy/services/notification/notification_prefs.dart';
import 'package:dizzy/services/notification/notification_service.dart';
import 'package:dizzy/services/push/push_service.dart';
import 'package:dizzy/services/taste/taste_event_service.dart';

PushPayload payload(Map<String, dynamic> data, {String? ft, String? fb}) =>
    PushPayload.fromData(data, fallbackTitle: ft, fallbackBody: fb);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PushPayload', () {
    test('reads kind, title, body and id from the data map', () {
      final p = payload({
        'kind': 'release',
        'title': '  Jawan  ',
        'body': ' Now streaming ',
        'id': 'rel-1',
      });
      expect(p.kind, NotificationKind.release);
      expect(p.title, 'Jawan');
      expect(p.body, 'Now streaming');
      expect(p.id, 'rel-1');
    });

    test('unknown kind falls back to releases', () {
      expect(payload({'kind': 'nonsense', 'title': 'A'}).kind,
          NotificationKind.release);
      expect(payload({'title': 'A'}).kind, NotificationKind.release);
    });

    test('notification title/body act as fallback', () {
      final p = payload({}, ft: 'FCM title', fb: 'FCM body');
      expect(p.title, 'FCM title');
      expect(p.body, 'FCM body');
    });

    test('trims and caps long text', () {
      final p = payload({'title': 'x' * 300, 'body': 'y' * 600});
      expect(p.title.length, PushPayload.maxTitle);
      expect(p.body.length, PushPayload.maxBody);
    });

    test('an empty payload is not showable', () {
      expect(payload({}).hasContent, isFalse);
      expect(payload({'title': '  '}).hasContent, isFalse);
    });

    test('an entity id makes the tap openable', () {
      final p = payload({
        'title': 'Jawan',
        'entity_id': '123',
        'entity_type': 'tv',
        'poster': 'p.jpg',
        'year': '2026',
        'rating': '7.8',
      });
      expect(p.openable, isTrue);
      final movie = p.toMovie();
      expect(movie, isNotNull);
      expect(movie!.id, '123');
      expect(movie.name, 'Jawan');
      expect(movie.type, 'series');
      expect(movie.year, '2026');
      expect(movie.poster, 'p.jpg');
      expect(payload({'title': 'Jawan'}).openable, isFalse);
      expect(payload({'title': 'Jawan'}).toMovie(), isNull);
    });
  });

  group('PushService.tapDataFor round-trip', () {
    test('rebuilt payload keeps content, id and opens the same title', () {
      final p = payload({
        'kind': 'release',
        'title': 'Jawan',
        'body': 'Now streaming',
        'id': 'rel-1',
        'entity_type': 'tv',
        'entity_id': '123',
        'lang': 'hi',
        'poster': 'p.jpg',
        'year': '2026',
        'rating': '7.8',
      });
      final rebuilt = PushPayload.fromData(PushService.tapDataFor(p));
      expect(rebuilt.hasContent, isTrue);
      expect(rebuilt.kind, NotificationKind.release);
      expect(rebuilt.title, 'Jawan');
      expect(rebuilt.body, 'Now streaming');
      expect(rebuilt.kind, p.kind);
      expect(rebuilt.id, 'rel-1');
      final movie = rebuilt.toMovie();
      expect(movie, isNotNull);
      expect(movie!.id, '123');
      expect(movie.name, 'Jawan');
      expect(movie.type, 'series');
      expect(movie.poster, 'p.jpg');
      expect(movie.year, '2026');
      expect(movie.imdbRating, '7.8');
    });

    test('a tap built from banner data with no id still does not navigate',
        () async {
      SharedPreferences.setMockInitialValues({});
      NotificationService.resetForTest();
      NotificationInbox.resetForTest();
      PushService.resetForTest();
      await PushService.handleTap(
        PushPayload.fromData(PushService.tapDataFor(payload({'title': 'News'}))),
      );
      expect(PushService.pendingTapForTest, isNull);
    });
  });

  group('NotificationService image card', () {
    setUp(() => NotificationService.resetForTest());

    test('no poster means no big-picture style', () async {
      expect(await NotificationService.bigPictureStyleForTest(null), isNull);
      expect(await NotificationService.bigPictureStyleForTest(''), isNull);
    });

    test('a failed download degrades to plain text style', () async {
      NotificationService.imageFetchForTest = (url) async => null;
      expect(
        await NotificationService.bigPictureStyleForTest('http://x/p.jpg'),
        isNull,
      );
      NotificationService.imageFetchForTest = (url) async {
        throw const HttpException('offline');
      };
      expect(
        await NotificationService.bigPictureStyleForTest('http://x/p.jpg'),
        isNull,
      );
    });

    test('a downloaded poster builds a big-picture style', () async {
      NotificationService.imageFetchForTest =
          (url) async => Uint8List.fromList([1, 2, 3]);
      NotificationService.directoryForTest =
          () async => Directory.systemTemp.createTemp('notify');
      final style = await NotificationService.bigPictureStyleForTest(
        'http://x/p.jpg',
      );
      expect(style, isA<BigPictureStyleInformation>());
      final big = style as BigPictureStyleInformation;
      final bitmap = big.bigPicture as FilePathAndroidBitmap;
      expect(bitmap.data, endsWith('.jpg'));
      await File(bitmap.data).delete();
    });
  });

  group('PushService.registerToken', () {
    setUp(PushService.resetForTest);

    test('skips when FCM hands back no token', () async {
      final calls = <Map<String, dynamic>>[];
      PushService.configureForTest(
        token: () async => null,
        appVersion: () async => '1.3.3',
        register: (params) async {
          calls.add(params);
          return true;
        },
      );
      expect(await PushService.registerToken(), isFalse);
      expect(calls, isEmpty);
    });

    test('registers token with platform and app version', () async {
      final calls = <Map<String, dynamic>>[];
      PushService.configureForTest(
        token: () async => 'a' * 40,
        appVersion: () async => '1.3.3',
        register: (params) async {
          calls.add(params);
          return true;
        },
      );
      expect(await PushService.registerToken(), isTrue);
      expect(calls, hasLength(1));
      expect(calls.single['p_token'], 'a' * 40);
      expect(calls.single['p_app_version'], '1.3.3');
      expect(
        calls.single['p_platform'],
        anyOf('android', 'ios', 'desktop', 'other'),
      );
    });

    test('does not re-register the same token twice', () async {
      var calls = 0;
      PushService.configureForTest(
        token: () async => 'a' * 40,
        appVersion: () async => '1.3.3',
        register: (_) async {
          calls++;
          return true;
        },
      );
      await PushService.registerToken();
      await PushService.registerToken();
      expect(calls, 1);
    });

    test('re-registers when the token rotates', () async {
      final seen = <String>[];
      var token = 'a' * 40;
      PushService.configureForTest(
        token: () async => token,
        appVersion: () async => '1.3.3',
        register: (params) async {
          seen.add(params['p_token'] as String);
          return true;
        },
      );
      await PushService.registerToken();
      token = 'b' * 40;
      await PushService.registerToken();
      expect(seen, ['a' * 40, 'b' * 40]);
    });

    test('a failed register can be retried', () async {
      var calls = 0;
      PushService.configureForTest(
        token: () async => 'a' * 40,
        appVersion: () async => '1.3.3',
        register: (_) async {
          calls++;
          return calls > 1;
        },
      );
      expect(await PushService.registerToken(), isFalse);
      expect(await PushService.registerToken(), isTrue);
      expect(calls, 2);
    });
  });

  group('PushService deliveries', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      NotificationService.resetForTest();
      NotificationInbox.resetForTest();
      PushService.resetForTest();
      TasteEventService.resetForTest();
    });

    test('dispatch lands the payload in the notification center', () async {
      final p = payload({
        'kind': 'release',
        'title': 'Jawan',
        'body': 'Now streaming',
        'id': 'rel-1',
      });
      await PushService.dispatch(p);
      expect(NotificationInbox.items.value, hasLength(1));
      final item = NotificationInbox.items.value.first;
      expect(item.title, 'Jawan');
      expect(item.body, 'Now streaming');
      expect(item.kind, NotificationKind.release);
      expect(item.id, 'rel-1');
    });

    test('background record writes the inbox without a banner path', () async {
      final p = payload({
        'kind': 'release',
        'title': 'Hi Nanna',
        'body': 'New on Dizzy',
        'id': 'rel-2',
      });
      await PushService.recordToInbox(p);
      expect(NotificationInbox.items.value, hasLength(1));
      expect(NotificationInbox.items.value.first.id, 'rel-2');
    });

    test('empty deliveries are ignored', () async {
      await PushService.dispatch(payload({}));
      await PushService.recordToInbox(payload({}));
      expect(NotificationInbox.items.value, isEmpty);
    });

    test('a tap without a navigator is queued for the first frame', () async {
      final p = payload({'title': 'Jawan', 'entity_id': '123'});
      await PushService.handleTap(p);
      expect(PushService.pendingTapForTest, same(p));
    });

    test('a tap with no title id never queues navigation', () async {
      final p = payload({'title': 'Just news'});
      await PushService.handleTap(p);
      expect(PushService.pendingTapForTest, isNull);
    });

    test('tap data round-trips through the local banner payload', () {
      final p = payload({
        'title': 'Jawan',
        'entity_id': '123',
        'entity_type': 'tv',
        'lang': 'hi',
        'poster': 'p.jpg',
        'year': '2026',
        'rating': '7.8',
      });
      final data = PushService.tapDataFor(p);
      expect(jsonEncode(data), isA<String>());
      final rebuilt = PushPayload.fromData(
        Map<String, dynamic>.from(data)..['title'] = p.title,
        fallbackTitle: p.title,
        fallbackBody: p.body,
      );
      final movie = rebuilt.toMovie();
      expect(movie, isNotNull);
      expect(movie!.id, '123');
      expect(movie.name, 'Jawan');
      expect(movie.type, 'series');
      expect(movie.year, '2026');
      expect(movie.poster, 'p.jpg');
      expect(movie.imdbRating, '7.8');
    });

    test('tap data for a non-openable payload carries empty ids', () {
      final p = payload({'title': 'Just news'});
      final data = PushService.tapDataFor(p);
      expect(data['entity_id'], isEmpty);
      expect(PushPayload.fromData(data).openable, isFalse);
    });
  });

  group('resolvePlanForPushEntity (tmdb → imdb bridge plan)', () {
    test('numeric tmdb id needs a plan with the right endpoint', () {
      final plan = resolvePlanForPushEntity(
        payload({'title': 'A', 'entity_id': '872598', 'entity_type': 'movie'}),
      );
      expect(plan, isNotNull);
      expect(plan!.endpoint, 'movie');
      expect(plan.tmdbId, 872598);
      final tvPlan = resolvePlanForPushEntity(
        payload({'title': 'A', 'entity_id': '12', 'entity_type': 'series'}),
      );
      expect(tvPlan!.endpoint, 'tv');
      expect(
        resolvePlanForPushEntity(
          payload({'title': 'A', 'entity_id': '12', 'entity_type': 'tv'}),
        )!.endpoint,
        'tv',
      );
    });

    test('tt, legacy and junk ids need no plan', () {
      expect(
        resolvePlanForPushEntity(
          payload({'title': 'A', 'entity_id': 'tt1375666'}),
        ),
        isNull,
      );
      // Legacy non-numeric shapes keep the pass-through behavior.
      expect(
        resolvePlanForPushEntity(
          payload({'title': 'A', 'entity_id': 'bestsimilar_x1'}),
        ),
        isNull,
      );
      expect(
        resolvePlanForPushEntity(payload({'title': 'A', 'entity_id': 'abc'})),
        isNull,
      );
      expect(
        resolvePlanForPushEntity(payload({'title': 'A', 'entity_id': '0'})),
        isNull,
      );
    });
  });

  group('displayTitleFor (notification copy → clean title)', () {
    test('strips emoji + known prefixes and suffixes', () {
      expect(displayTitleFor('🌙 Aaj raat: Fallen 🍿'), 'Fallen');
      expect(displayTitleFor('One episode? Breaking Bad 🎬'), 'Breaking Bad');
      expect(displayTitleFor('Episode time… Money Heist 🎬'), 'Money Heist');
      expect(displayTitleFor('🍿 Aaj raat: Dune 🍿'), 'Dune');
      expect(displayTitleFor('Dune — episode mood? 🍿'), 'Dune');
      expect(displayTitleFor('Psst… Oppenheimer 👀'), 'Oppenheimer');
      expect(displayTitleFor('Psst — Dune 🎬'), 'Dune');
      expect(displayTitleFor('Tonight: Interstellar 🍿'), 'Interstellar');
      expect(displayTitleFor('Aaj ka pick: Dil Chahta Hai 🔥'), 'Dil Chahta Hai');
      expect(displayTitleFor('Dune — aaj dekh lein?'), 'Dune');
      expect(displayTitleFor('Jawan — tum ke liye 🎬'), 'Jawan');
      expect(displayTitleFor('New on Dizzy: 3 Idiots'), '3 Idiots');
      expect(displayTitleFor('Jawan ab Dizzy par'), 'Jawan');
      expect(displayTitleFor('Inception just landed'), 'Inception');
      expect(displayTitleFor('Dune — tum ke liye'), 'Dune');
    });

    test('plain titles pass through untouched', () {
      expect(displayTitleFor('The Shawshank Redemption'), 'The Shawshank Redemption');
      expect(displayTitleFor('12 Angry Men'), '12 Angry Men');
      expect(displayTitleFor('(500) Days of Summer'), '(500) Days of Summer');
      expect(displayTitleFor('  Jawan  '), 'Jawan');
      expect(displayTitleFor(''), '');
    });
  });

  group('PushService.openMovieFor', () {
    setUp(PushService.resetForTest);

    test('numeric tmdb id is swapped for the bridged imdb id', () async {
      final endpoints = <String>[];
      final ids = <int>[];
      PushService.configureResolverForTest(
        imdbResolve: ({required endpoint, required tmdbId}) async {
          endpoints.add(endpoint);
          ids.add(tmdbId);
          return 'tt9362722';
        },
      );
      final movie = await PushService.openMovieFor(
        payload({'title': 'Psst — Fallout 🎬', 'entity_id': '872598', 'entity_type': 'movie'}),
      );
      expect(endpoints, ['movie']);
      expect(ids, [872598]);
      expect(movie, isNotNull);
      expect(movie!.id, 'tt9362722');
      expect(movie.name, 'Psst — Fallout 🎬');
    });

    test('series payload bridges through the tv endpoint', () async {
      final endpoints = <String>[];
      PushService.configureResolverForTest(
        imdbResolve: ({required endpoint, required tmdbId}) async {
          endpoints.add('$endpoint:$tmdbId');
          return 'tt1520211';
        },
      );
      final movie = await PushService.openMovieFor(
        payload({
          'title': 'One episode? The Witcher 🎬',
          'entity_id': '17754',
          'entity_type': 'series',
        }),
      );
      expect(endpoints, ['tv:17754']);
      expect(movie!.id, 'tt1520211');
    });

    test('a failed bridge falls back to the cleaned-title search', () async {
      final searched = <String>[];
      final types = <String>[];
      PushService.configureResolverForTest(
        imdbResolve: ({required endpoint, required tmdbId}) async => null,
        titleSearch: (title, type, year) async {
          searched.add(title);
          types.add(type);
          return null;
        },
      );
      final movie = await PushService.openMovieFor(
        payload({
          'title': 'Psst — Fallen 🎬',
          'entity_id': '872598',
          'entity_type': 'movie',
          'year': '2026',
        }),
      );
      expect(searched, ['Fallen']);
      expect(types, ['movie']);
      // Nothing found → prior pass-through behavior (raw tmdb id).
      expect(movie!.id, '872598');
    });

    test('a found title search result replaces the movie entirely', () async {
      PushService.configureResolverForTest(
        imdbResolve: ({required endpoint, required tmdbId}) async => null,
        titleSearch: (title, type, year) async => Movie(
          id: 'tt1200666',
          name: title,
          type: 'series',
          addonBaseUrl: 'https://v3-cinemeta.strem.io',
        ),
      );
      final movie = await PushService.openMovieFor(
        payload({
          'title': 'Dune — aaj dekh lein?',
          'entity_id': '1',
          'entity_type': 'tv',
        }),
      );
      expect(movie!.id, 'tt1200666');
      expect(movie.type, 'series');
      expect(movie.addonBaseUrl, 'https://v3-cinemeta.strem.io');
    });

    test('a bridging seam that throws degrades soft to the title search', () async {
      PushService.configureResolverForTest(
        imdbResolve: ({required endpoint, required tmdbId}) async {
          throw const HttpException('offline');
        },
        titleSearch: (title, type, year) async => Movie(
          id: 'tt777',
          name: title,
          type: type,
          addonBaseUrl: '',
        ),
      );
      final movie = await PushService.openMovieFor(
        payload({'title': 'Jawan', 'entity_id': '99', 'entity_type': 'movie'}),
      );
      expect(movie!.id, 'tt777');
    });

    test('tt ids passthrough without touching either seam', () async {
      var seams = 0;
      PushService.configureResolverForTest(
        imdbResolve: ({required endpoint, required tmdbId}) async {
          seams += 10;
          return null;
        },
        titleSearch: (title, type, year) async {
          seams += 1;
          return null;
        },
      );
      final movie = await PushService.openMovieFor(
        payload({'title': 'Jawan', 'entity_id': 'tt1375666'}),
      );
      expect(movie!.id, 'tt1375666');
      expect(seams, 0);
    });

    test('a non-openable payload resolves to null', () async {
      expect(await PushService.openMovieFor(payload({'title': 'A'})), isNull);
    });
  });
}
