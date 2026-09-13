import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/utils/net/net_retry.dart';

void main() {
  group('NetRetry.shouldRetry', () {
    test('429 and 5xx retry', () {
      expect(NetRetry.shouldRetry(Exception('x'), statusCode: 429), true);
      expect(NetRetry.shouldRetry(Exception('x'), statusCode: 500), true);
      expect(NetRetry.shouldRetry(Exception('x'), statusCode: 503), true);
    });

    test('4xx never retries', () {
      expect(NetRetry.shouldRetry(Exception('x'), statusCode: 400), false);
      expect(NetRetry.shouldRetry(Exception('x'), statusCode: 403), false);
      expect(NetRetry.shouldRetry(Exception('x'), statusCode: 404), false);
    });

    test('transient socket/timeout errors retry', () {
      expect(NetRetry.shouldRetry(const SocketException('down')), true);
      expect(NetRetry.shouldRetry(TimeoutException('slow')), true);
      expect(NetRetry.shouldRetry(const HttpException('reset')), true);
    });

    test('unknown errors do not retry', () {
      expect(NetRetry.shouldRetry(const FormatException('bad json')), false);
    });
  });

  group('NetRetry.run', () {
    test('succeeds first try without delay', () async {
      final v = await NetRetry.run(() async => 42);
      expect(v, 42);
    });

    test('retries transient failure then succeeds', () async {
      var calls = 0;
      final v = await NetRetry.run(() async {
        calls++;
        if (calls < 3) throw const SocketException('flaky');
        return 'ok';
      });
      expect(v, 'ok');
      expect(calls, 3);
    });

    test('gives up after maxAttempts', () async {
      var calls = 0;
      await expectLater(
        NetRetry.run(() async {
          calls++;
          throw const SocketException('dead');
        }),
        throwsA(isA<SocketException>()),
      );
      expect(calls, NetRetry.maxAttempts);
    });

    test('non-retryable error throws immediately', () async {
      var calls = 0;
      await expectLater(
        NetRetry.run(() async {
          calls++;
          throw const FormatException('bad');
        }),
        throwsA(isA<FormatException>()),
      );
      expect(calls, 1);
    });
  });
}
