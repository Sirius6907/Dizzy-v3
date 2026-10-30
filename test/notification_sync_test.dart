import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/notification/notification_prefs.dart';
import 'package:dizzy/services/notification/notification_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(NotificationSync.resetForTest);

  group('NotificationSync.paramsFor', () {
    test('maps the gate onto the RPC argument names', () {
      const gate = NotificationGate(
        off: {'releases', 'social'},
        quietEnabled: true,
        quietStartMinute: 1350,
        quietEndMinute: 390,
      );

      final p = NotificationSync.paramsFor(gate, tzOffsetMinutes: 330);

      expect(p['p_off'], containsAll(<String>['releases', 'social']));
      expect((p['p_off'] as List).length, 2);
      expect(p['p_quiet_enabled'], true);
      expect(p['p_quiet_start'], 1350);
      expect(p['p_quiet_end'], 390);
      expect(p['p_tz_offset'], 330);
    });

    test('fresh install mirrors the client defaults', () {
      final p = NotificationSync.paramsFor(
        const NotificationGate(),
        tzOffsetMinutes: -300,
      );

      expect(p['p_off'], isEmpty);
      expect(p['p_quiet_enabled'], false);
      expect(p['p_quiet_start'], 22 * 60);
      expect(p['p_quiet_end'], 7 * 60);
      expect(p['p_tz_offset'], -300);
    });

    test('clamps values the server would reject', () {
      const gate = NotificationGate(quietStartMinute: 5000, quietEndMinute: -3);
      final p = NotificationSync.paramsFor(gate, tzOffsetMinutes: 5000);

      expect(p['p_quiet_start'], 1439);
      expect(p['p_quiet_end'], 0);
      expect(p['p_tz_offset'], 840);
    });
  });

  group('NotificationSync.push', () {
    test('forwards the built params through the sender', () async {
      final seen = <Map<String, dynamic>>[];
      NotificationSync.configureForTest((params) async {
        seen.add(params);
        return true;
      });

      final ok = await NotificationSync.push(
        gate: const NotificationGate(quietEnabled: true),
        tzOffsetMinutes: 330,
      );

      expect(ok, true);
      expect(seen, hasLength(1));
      expect(seen.single['p_quiet_enabled'], true);
      expect(seen.single['p_tz_offset'], 330);
    });

    test('a failed sync stays soft and reports false', () async {
      NotificationSync.configureForTest((_) async {
        throw StateError('offline');
      });

      final ok = await NotificationSync.push(
        gate: const NotificationGate(),
        tzOffsetMinutes: 0,
      );

      expect(ok, false);
    });
  });
}
