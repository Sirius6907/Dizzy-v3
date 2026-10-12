import 'package:dizzy/services/social/phone_link_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PhoneLinkService T1.3 (missed-call stub)', () {
    test('normalize accepts E.164', () {
      expect(PhoneLinkService.normalize('+919876543210'), '+919876543210');
    });

    test('normalize assumes +91 for bare 10-digit Indian numbers', () {
      expect(PhoneLinkService.normalize('9876543210'), '+919876543210');
    });

    test('normalize rejects garbage', () {
      expect(PhoneLinkService.normalize('bad-number'), isNull);
      expect(PhoneLinkService.normalize('123'), isNull);
      expect(PhoneLinkService.normalize(''), isNull);
    });

    test('requestLink rejects invalid numbers without touching cloud', () async {
      final res = await PhoneLinkService.requestLink('not-a-number');
      expect(res['success'], isFalse);
    });

    test('requestLink saves number locally when offline (stub mode)', () async {
      // CloudClient.isReady is false in test env (no SUPABASE_URL).
      final res = await PhoneLinkService.requestLink('+919876543210');
      expect(res['success'], isTrue);
      expect(res['status'], 'pending');
      expect(PhoneLinkService.phoneNumber.value, '+919876543210');
      expect(PhoneLinkService.phoneVerified.value, isFalse);
    });

    test('pollVerified returns false offline (no hang)', () async {
      final ok = await PhoneLinkService.pollVerified(tries: 1);
      expect(ok, isFalse);
    });

    test('missedCallSupported is true in this build', () {
      expect(PhoneLinkService.missedCallSupported, isTrue);
    });
  });
}
