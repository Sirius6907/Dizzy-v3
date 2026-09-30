import 'package:dizzy/services/device/device_identity_v2.dart';
import 'package:dizzy/services/device/device_id_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase H — stable device identity v2.
/// Pins: hash determinism, salt sensitivity, weak-anchor fallback,
/// and the DIZ display-code format staying untouched.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeviceIdentityV2.resetCache();
  });

  tearDown(DeviceIdentityV2.resetCache);

  group('DeviceIdentityV2.hashOf', () {
    test('same platform id → same hash (reinstall reproduces it)', () {
      final a = DeviceIdentityV2.hashOf('android-id-abc123');
      final b = DeviceIdentityV2.hashOf('android-id-abc123');
      expect(a, equals(b));
      expect(a, hasLength(64)); // sha256 hex
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(a), isTrue);
    });

    test('different platform id → different hash', () {
      final a = DeviceIdentityV2.hashOf('android-id-abc123');
      final b = DeviceIdentityV2.hashOf('android-id-xyz789');
      expect(a, isNot(equals(b)));
    });

    test('raw id never appears inside the hash output', () {
      final h = DeviceIdentityV2.hashOf('secret-android-id');
      expect(h.contains('secret-android-id'), isFalse);
    });
  });

  group('DeviceIdentityV2.stableHwid (test env = no platform plugin)', () {
    test('falls back to a persisted weak id, stable=false', () async {
      final first = await DeviceIdentityV2.stableHwid();
      expect(first.stable, isFalse); // plugin unavailable in tests
      expect(first.hash, hasLength(64));

      // Persisted: a second call (fresh cache) reuses the same fallback id.
      DeviceIdentityV2.resetCache();
      final second = await DeviceIdentityV2.stableHwid();
      expect(second.hash, equals(first.hash));
      expect(second.stable, isFalse);
    });

    test('cache returns same values without re-querying', () async {
      final first = await DeviceIdentityV2.stableHwid();
      final second = await DeviceIdentityV2.stableHwid();
      expect(identical(first.hash, second.hash) || first.hash == second.hash,
          isTrue);
    });
  });

  group('Display code format untouched (per-install support code)', () {
    test('DIZ- prefix + 7 digits still hold', () async {
      final code = await DeviceIdService.initialize();
      expect(DeviceIdService.validCode(code), isTrue);
      expect(DeviceIdService.displayCode(code), 'DIZ-$code');
    });
  });
}
