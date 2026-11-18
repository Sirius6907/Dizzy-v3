import 'package:dizzy/services/adult/private_mode_shield.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.sirius6907.dizzyv3/secure');
  final calls = <MethodCall>[];

  void mockHandler(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    calls.clear();
    PrivateModeShield.debugReset();
    mockHandler((_) => true);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    PrivateModeShield.debugReset();
  });

  group('PrivateModeShield', () {
    test('engages FLAG_SECURE through the native channel', () async {
      await PrivateModeShield.setSecure(true);

      expect(PrivateModeShield.engaged, isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'setSecure');
      expect(calls.single.arguments, {'enabled': true});
    });

    test('repeats are idempotent', () async {
      await PrivateModeShield.setSecure(true);
      await PrivateModeShield.setSecure(true);

      expect(calls, hasLength(1));
      expect(PrivateModeShield.engaged, isTrue);
    });

    test('release clears the flag and the cached state', () async {
      await PrivateModeShield.setSecure(true);
      await PrivateModeShield.release();

      expect(PrivateModeShield.engaged, isFalse);
      expect(calls, hasLength(2));
      expect(calls.last.arguments, {'enabled': false});
    });

    test('release is a no-op when nothing is engaged', () async {
      await PrivateModeShield.release();

      expect(calls, isEmpty);
      expect(PrivateModeShield.engaged, isFalse);
    });

    test('missing native handler is swallowed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      await expectLater(PrivateModeShield.setSecure(true), completes);
      expect(PrivateModeShield.engaged, isFalse);
    });

    test('native refusal leaves the state alone so it retries', () async {
      mockHandler((_) => throw PlatformException(code: 'SECURE_ERROR'));

      await expectLater(PrivateModeShield.setSecure(true), completes);
      expect(PrivateModeShield.engaged, isFalse);

      // Next attempt with the platform healthy again succeeds.
      mockHandler((_) => true);
      await PrivateModeShield.setSecure(true);
      expect(PrivateModeShield.engaged, isTrue);
    });
  });
}
