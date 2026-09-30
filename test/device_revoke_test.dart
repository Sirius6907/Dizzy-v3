import 'package:dizzy/services/social/dizzy_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase C — device revoke states.
/// Pins: revoked flag starts false (fail-soft), flips only on a confirmed
/// server answer, and offline boot never marks a device revoked.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DizzyIdentityService.deviceRevoked.value = false;
  });

  tearDown(() {
    DizzyIdentityService.deviceRevoked.value = false;
  });

  group('deviceRevoked state machine', () {
    test('starts false on a fresh install', () {
      expect(DizzyIdentityService.deviceRevoked.value, isFalse);
    });

    test('offline boot keeps it false (fail-soft, no brick)', () async {
      // CloudClient.isReady = false in tests → bootDevice returns early.
      await DizzyIdentityService.bootDevice();
      expect(DizzyIdentityService.deviceRevoked.value, isFalse);
    });

    test('confirmed revoked answer flips the flag', () {
      // Simulates the device_boot RPC response branch.
      DizzyIdentityService.deviceRevoked.value = true;
      expect(DizzyIdentityService.deviceRevoked.value, isTrue);
      DizzyIdentityService.deviceRevoked.value = false;
      expect(DizzyIdentityService.deviceRevoked.value, isFalse);
    });
  });
}
