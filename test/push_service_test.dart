import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });
}
