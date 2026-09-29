import 'package:dizzy/services/cloud/cloud_client.dart';
import 'package:dizzy/services/social/dizzy_identity_service.dart';
import 'package:dizzy/services/device/device_id_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DizzyIdentityService (Phase 1)', () {
    test('deviceDisplayCode formats DIZ- prefix', () async {
      await DeviceIdService.initialize();
      expect(DizzyIdentityService.deviceDisplayCode, startsWith('DIZ-'));
    });

    test('isLinked is false after fresh init', () async {
      await DizzyIdentityService.init();
      expect(DizzyIdentityService.isLinked, isFalse);
    });

    test('deviceSid is set after init (DIZ format)', () async {
      await DizzyIdentityService.init();
      final sid = DizzyIdentityService.deviceSid.value;
      expect(sid, isNotNull);
      expect(sid!, startsWith('DIZ-'));
      // Verify it matches DeviceIdService display format
      expect(
        sid,
        equals(
          DeviceIdService.displayCode(
            DeviceIdService.deviceCode.value!,
          ),
        ),
      );
    });

    test('deviceSid persists after re-init', () async {
      await DizzyIdentityService.init();
      final firstSid = DizzyIdentityService.deviceSid.value;

      // Re-init should reuse stored value
      await DizzyIdentityService.init();
      expect(DizzyIdentityService.deviceSid.value, equals(firstSid));
    });

    test('linkedKind and linkedIdentifier are null after fresh init',
        () async {
      await DizzyIdentityService.init();
      expect(DizzyIdentityService.linkedKind.value, isNull);
      expect(DizzyIdentityService.linkedIdentifier.value, isNull);
    });

    test('isLinked becomes true after OTP link prefs set', () async {
      // Simulate post-merge state by setting SharedPreferences directly
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('diz_linked_kind_v1', 'phone');
      await prefs.setString('diz_linked_identifier_v1', '+15550001234');

      await DizzyIdentityService.init();
      expect(DizzyIdentityService.isLinked, isTrue);
      expect(DizzyIdentityService.linkedKind.value, 'phone');
      expect(DizzyIdentityService.linkedIdentifier.value, '+15550001234');
    });

    test('bootDevice fails soft when cloud unavailable', () async {
      // CloudClient.isReady is false in test env (no SUPABASE_URL)
      expect(CloudClient.isReady, isFalse);
      // Should complete without throwing
      await DizzyIdentityService.bootDevice();
      // No exception = pass (fail-soft)
    });

    test('requestPhoneOtp fails soft when cloud unavailable', () async {
      final result =
          await DizzyIdentityService.requestPhoneOtp('+15550001234');
      expect(result, isFalse);
    });

    test('requestEmailOtp fails soft when cloud unavailable', () async {
      final result =
          await DizzyIdentityService.requestEmailOtp('test@example.com');
      expect(result, isFalse);
    });

    test('verifyOtpAndMerge fails soft when cloud unavailable', () async {
      final result = await DizzyIdentityService.verifyOtpAndMerge(
        token: '123456',
        phone: '+15550001234',
      );
      expect(result, isFalse);
    });
  });
}
