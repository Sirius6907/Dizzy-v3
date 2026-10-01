import 'dart:io';
import 'dart:math';

import 'package:dizzy/services/device/device_id_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PHASE 36 — Anonymous-First Verification.
///
/// Anonymous-first equivalents in this repo (no file literally named
/// `AnonymousFirstService`):
///   - [DeviceIdService]          → random 7-digit DIZ code on first launch
///   - CloudAuthService           → UUID anon id + Supabase anon sign-in, soft-fail offline
///   - DizzyIdentityService       → DIZ display code + HWID hash (cloud-ready only)
///   - CloudClient                → lazy client, offline = disabled, never blocks boot
String _stripComments(String src) {
  final noLine = src.replaceAll(RegExp(r'//.*'), '');
  return noLine.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
}

String _read(String rel) => File(rel).readAsStringSync();

void main() {
  group('Phase36 anonymous-first', () {
    test('1. App boots anonymously without auth prompt', () {
      final mainSrc = _read('lib/main.dart');
      // Home is the streaming hub, not a login gate.
      expect(mainSrc, contains('home: const HomePage()'));
      expect(mainSrc, isNot(contains('LoginPage')));
      expect(mainSrc, isNot(contains('AuthGate')));
      expect(mainSrc, isNot(contains('SignInPage')));
      expect(mainSrc, isNot(contains('initialRoute: "/login"')));
      // Cloud boots LAST + non-blocking (never delays startup).
      expect(mainSrc, contains('CloudClient.init()'));
      expect(
        mainSrc.contains('unawaited_futures') || mainSrc.contains('.then('),
        isTrue,
        reason: 'Cloud init must be non-blocking (unawaited/.then).',
      );
      // Device code is generated before anything cloud-related.
      final deviceIdx = mainSrc.indexOf('DeviceIdService.initialize()');
      final cloudIdx = mainSrc.indexOf('CloudClient.init()');
      expect(deviceIdx, isNot(-1));
      expect(cloudIdx, isNot(-1));
      expect(deviceIdx, lessThan(cloudIdx));

      final navSrc = _read('lib/core/nav_key.dart');
      expect(navSrc, isNot(contains('login')));
    });

    test('2. DeviceId generates random DIZ code on first launch', () async {
      // Pure generation: 7 digits, no leading zero, random per seed.
      final a = DeviceIdService.generateCode(Random(1));
      final b = DeviceIdService.generateCode(Random(2));
      expect(DeviceIdService.validCode(a), isTrue);
      expect(DeviceIdService.validCode(b), isTrue);
      expect(a, isNot(equals(b)));
      expect(DeviceIdService.displayCode(a), 'DIZ-$a');

      // First-launch persistence through SharedPreferences.
      DeviceIdService.deviceCode.value = null;
      SharedPreferences.setMockInitialValues({});
      final fresh = await DeviceIdService.initialize(Random(42));
      expect(DeviceIdService.validCode(fresh), isTrue);
      expect(DeviceIdService.deviceCode.value, fresh);

      // Second launch reuses the stored code (stable per install).
      DeviceIdService.deviceCode.value = null;
      final again = await DeviceIdService.initialize(Random(99));
      expect(again, fresh);
    });

    test('3. HWID hash computed only when cloud is ready', () {
      final src = _read('lib/services/social/dizzy_identity_service.dart');
      final bootStart = src.indexOf('static Future<void> bootDevice()');
      expect(bootStart, isNot(-1));
      final bootBody = src.substring(bootStart);
      final guardIdx = bootBody.indexOf('if (!CloudClient.isReady) return;');
      // Phase H: hash source moved to DeviceIdentityV2.stableHwid();
      // legacyHash is the old random-code derivation. Both must stay guarded.
      final hashIdx = bootBody.indexOf('DeviceIdentityV2.stableHwid()');
      expect(guardIdx, isNot(-1),
          reason: 'bootDevice must early-return when cloud is not ready.');
      expect(hashIdx, isNot(-1));
      expect(guardIdx, lessThan(hashIdx),
          reason: 'HWID hash must only be computed after the cloud-ready guard.');
      final legacyIdx = bootBody.indexOf('legacyHash');
      expect(legacyIdx, isNot(-1));
      expect(guardIdx, lessThan(legacyIdx),
          reason: 'Legacy hwid hash must also stay behind the guard.');

      // init() also gates the background registration on cloud readiness.
      final initStart = src.indexOf('static Future<void> init()');
      expect(initStart, isNot(-1));
      final initBody = src.substring(initStart, bootStart);
      expect(initBody, contains('if (CloudClient.isReady)'));

      // CloudClient itself fails soft when Supabase keys are missing.
      final clientSrc = _read('lib/services/cloud/cloud_client.dart');
      expect(clientSrc, contains('if (!isConfigured)'));
    });

    test('4. No OAuth redirect stored or triggered', () {
      const authFlowFiles = [
        'lib/services/cloud/cloud_auth_service.dart',
        'lib/services/cloud/cloud_client.dart',
        'lib/services/social/dizzy_identity_service.dart',
        'lib/main.dart',
      ];
      const banned = [
        'signInWithOAuth',
        'signInWithGoogle',
        'signInWithApple',
        'signInWithFacebook',
        'signInWithIdToken',
        'getOAuth',
        'oauthRedirect',
        'redirectUri',
        'oauth_callback',
      ];
      for (final rel in authFlowFiles) {
        final code = _stripComments(_read(rel)).toLowerCase();
        // Comments mentioning "OAuth removed" are stripped above; any
        // remaining oauth reference in code is a violation.
        expect(code, isNot(contains('oauth')),
            reason: '$rel must not reference oauth in code.');
        for (final b in banned) {
          expect(code, isNot(contains(b.toLowerCase())),
              reason: '$rel must not contain $b.');
        }
        // No persisted OAuth tokens in the auth flow.
        expect(code, isNot(contains('oauth_token')));
        expect(code, isNot(contains('oauth_code')));
      }
      // Anonymous-first proof: auth uses anonymous sign-in only.
      final authSrc =
          _stripComments(_read('lib/services/cloud/cloud_auth_service.dart'));
      expect(authSrc, contains('signInAnonymously'));
    });
  });
}
