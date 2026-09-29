import 'dart:convert';

import 'package:dizzy/services/cloud/cloud_auth_service.dart';
import 'package:dizzy/services/config/feature_flags.dart';
import 'package:dizzy/services/device/device_id_service.dart';
import 'package:dizzy/services/errors/app_error_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// P2 — error pipeline: queue, throttle, consent, privacy gate, transport.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CloudAuthService.consentCrash.value = true;
    DeviceIdService.deviceCode.value = null;
    ServerFlags.reset();
  });

  tearDown(() async {
    CloudAuthService.consentCrash.value = false;
    await AppErrorLog.clearQueue();
  });

  group('AppErrorLog queue', () {
    test('caps the queue and drops the oldest entries', () async {
      expect(AppErrorLog.maxQueue, 100);
      for (var i = 0; i < 150; i++) {
        await AppErrorLog.log(code: 'perf_caution', screen: 'governor', detail: 'n$i');
      }
      final queue = await AppErrorLog.pending();
      expect(queue.length, 100);
      // Oldest went first, so entry #50 survived and #0 did not.
      expect(queue.first['detail'], 'n50');
      expect(queue.last['detail'], 'n149');
    });

    test('survives a corrupt queue blob instead of throwing', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'app_error_queue_v1': 'not json at all'},
      );
      await AppErrorLog.log(code: 'tmdb_fetch', screen: 'tmdb', detail: 'edge');
      final queue = await AppErrorLog.pending();
      expect(queue.length, 1);
      expect(queue.single['code'], 'tmdb_fetch');
    });
  });

  group('AppErrorLog throttle', () {
    test('sends immediately once per code+screen per 24h', () async {
      final prefs = await SharedPreferences.getInstance();
      final key = AppErrorLog.throttleKeyFor('tmdb_fetch', 'tmdb');

      await AppErrorLog.log(code: 'tmdb_fetch', screen: 'tmdb', detail: 'edge');
      final first = prefs.getInt(key);
      expect(first, isNotNull, reason: 'first report must claim the slot');

      await AppErrorLog.log(code: 'tmdb_fetch', screen: 'tmdb', detail: 'edge');
      expect(prefs.getInt(key), first, reason: 'second report must not move it');
    });

    test('a different screen is a different throttle slot', () async {
      final prefs = await SharedPreferences.getInstance();
      await AppErrorLog.log(code: 'tmdb_fetch', screen: 'tmdb');
      final tmdb = prefs.getInt(AppErrorLog.throttleKeyFor('tmdb_fetch', 'tmdb'));
      await AppErrorLog.log(code: 'tmdb_fetch', screen: 'player');
      final player =
          prefs.getInt(AppErrorLog.throttleKeyFor('tmdb_fetch', 'player'));
      expect(tmdb, isNotNull);
      expect(player, isNotNull);
    });

    test('window is 24 hours wide and not yet closed', () {
      const hour = 3600 * 1000;
      const now = 1700000000000;
      expect(AppErrorLog.shouldThrottle(now - 23 * hour, now), isTrue);
      expect(AppErrorLog.shouldThrottle(now - 25 * hour, now), isFalse);
      expect(AppErrorLog.shouldThrottle(0, now), isFalse);
    });
  });

  group('AppErrorLog consent', () {
    test('consent off drops the report without queueing it', () async {
      CloudAuthService.consentCrash.value = false;
      await AppErrorLog.log(code: 'tmdb_fetch', screen: 'tmdb', detail: 'edge');
      expect(await AppErrorLog.pending(), isEmpty);
    });

    test('consent off short-circuits the drain and keeps the queue', () async {
      await AppErrorLog.log(code: 'tmdb_fetch', screen: 'tmdb');
      var sent = 0;
      final drained = await AppErrorLog.drain(
        consent: false,
        send: (_) async => sent++,
      );
      expect(sent, 0);
      expect(drained, isFalse);
      expect((await AppErrorLog.pending()).length, 1);
    });
  });

  group('AppErrorLog privacy gate', () {
    test('payload is exactly the six contract fields', () {
      final p = AppErrorLog.buildPayload(
        deviceCode: '1234567',
        platform: 'android',
        appVersion: '1.2.1',
        screen: 'player',
        code: 'tmdb_fetch',
        detail: 'timeout_20s',
      );
      expect(
        p.keys.toSet(),
        <String>{
          'device_code',
          'platform',
          'app_version',
          'screen',
          'code',
          'detail',
        },
      );
      // No count: the server folds repeats into its own column.
      expect(p.containsKey('count'), isFalse);
    });

    test('raw exception text never reaches the wire', () {
      const raw = 'Bad state: No element #0 main (main.dart:1) '
          'https://tracker.example/magnet:?xt=urn:btih:secret';
      final p = AppErrorLog.buildPayload(
        deviceCode: '1234567',
        platform: 'android',
        appVersion: '1.2.1',
        screen: 'global',
        code: 'E_FLUTTER',
        detail: raw,
      );
      expect(p['detail'], 'redacted');
      final wire = jsonEncode(p);
      expect(wire, isNot(contains('http')));
      expect(wire, isNot(contains('magnet')));
      expect(wire, isNot(contains('main.dart')));
      expect(wire, isNot(contains('Bad state')));
    });

    test('raw text passed to log() is redacted in the queue too', () async {
      await AppErrorLog.log(
        code: 'E_ASYNC',
        screen: 'global',
        detail: 'Exception: socket failed to 10.0.0.5:5432',
      );
      final entry = (await AppErrorLog.pending()).single;
      expect(entry['detail'], 'redacted');
      expect(entry['code'], 'e_async', reason: 'codes normalise to lowercase');
    });

    test('enum details survive untouched', () {
      expect(AppErrorLog.sanitizeDetail('timeout_20s'), 'timeout_20s');
      expect(AppErrorLog.sanitizeDetail('edge'), 'edge');
      expect(AppErrorLog.sanitizeDetail('ram_412.5_cpu_7'), 'ram_412.5_cpu_7');
      expect(AppErrorLog.sanitizeDetail(''), '');
      expect(AppErrorLog.sanitizeDetail('has spaces'), 'redacted');
    });

    test('codes and screens fall back rather than dropping the report', () {
      expect(AppErrorLog.sanitizeCode('E_USER_REPORT'), 'e_user_report');
      expect(AppErrorLog.sanitizeCode('guest open'), 'unknown');
      expect(AppErrorLog.sanitizeScreen('next_episode'), 'next_episode');
      expect(AppErrorLog.sanitizeScreen(''), 'unknown');
      expect(AppErrorLog.sanitizeDeviceCode('1234567'), '1234567');
      expect(AppErrorLog.sanitizeDeviceCode('DIZ-1234567'), 'unknown');
      expect(AppErrorLog.sanitizeDeviceCode(''), 'unknown');
      expect(AppErrorLog.sanitizePlatform('Android'), 'android');
      expect(AppErrorLog.sanitizePlatform('plan9'), 'unknown');
    });

    test('over-long detail is refused, not truncated', () {
      final long = 'a' * 200;
      expect(AppErrorLog.sanitizeDetail(long), 'redacted');
      expect(AppErrorLog.sanitizeVersion('v' * 80), '');
    });
  });

  group('AppErrorLog transport', () {
    test('drain clears the queue when the edge accepts', () async {
      DeviceIdService.deviceCode.value = '1234567';
      await AppErrorLog.log(code: 'tmdb_fetch', screen: 'tmdb', detail: 'edge');
      await AppErrorLog.log(code: 'guest_open', screen: 'party');

      final sent = <Map<String, dynamic>>[];
      final drained = await AppErrorLog.drain(
        consent: true,
        send: (p) async => sent.add(p),
      );

      expect(drained, isTrue);
      expect(sent.length, 2);
      expect(await AppErrorLog.pending(), isEmpty);
      // Oldest first, and the install code rides along.
      expect(sent.first['code'], 'tmdb_fetch');
      expect(sent.last['code'], 'guest_open');
      expect(sent.first['device_code'], '1234567');
    });

    test('a failing edge keeps the queue intact for the next flush', () async {
      await AppErrorLog.log(code: 'tmdb_fetch', screen: 'tmdb');
      final drained = await AppErrorLog.drain(
        consent: true,
        send: (_) async => throw StateError('edge down'),
      );
      expect(drained, isFalse);
      expect((await AppErrorLog.pending()).length, 1);
    });

    test('drain on an empty queue is a no-op', () async {
      var sent = 0;
      final drained = await AppErrorLog.drain(
        consent: true,
        send: (_) async => sent++,
      );
      expect(drained, isTrue);
      expect(sent, 0);
    });
  });

  group('ServerFlags fallbacks', () {
    test('shipped defaults are complete and read as bools', () {
      expect(kServerFlagsFallback, isNotEmpty);
      // A Map<String, bool> is bool-valued by construction; this test is
      // really pinning "no flag was declared as a String or int".
      final retyped = <String, Object?>{
        for (final e in kServerFlagsFallback.entries) e.key: e.value,
      };
      expect(retyped.values.every((v) => v is bool), isTrue);
    });

    test('unknown keys read OFF even if injected into the map', () {
      ServerFlags.current.value = <String, bool>{'typo_flag': true};
      expect(ServerFlags.isOn('typo_flag'), isFalse);
      // A known key with no server row still resolves to its shipped
      // default rather than going dark.
      expect(ServerFlags.isOn('watch_party'), isTrue);
      expect(ServerFlags.isOn('kids_mode'), isFalse);
    });

    test('server rows overlay the defaults, unknown keys are discarded', () {
      final rows = ServerFlags.mergeable(<dynamic>[
        <String, dynamic>{'key': 'kids_mode', 'enabled': true},
        <String, dynamic>{'key': 'not_a_real_flag', 'enabled': true},
        <String, dynamic>{'key': 'error_reporting', 'enabled': 'yes'},
        'garbage',
        42,
      ]);
      expect(rows.length, 1);
      final merged = ServerFlags.merge(rows);
      expect(merged['kids_mode'], isTrue);
      expect(merged.containsKey('not_a_real_flag'), isFalse);
      expect(merged['error_reporting'], isTrue,
          reason: 'a bad row is ignored, the default stands');
      expect(merged.length, kServerFlagsFallback.length);
    });
  });
}
