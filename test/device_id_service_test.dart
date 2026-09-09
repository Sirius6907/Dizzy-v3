import 'dart:math';

import 'package:dizzy/services/device/device_id_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceIdService (WP-P0)', () {
    test('validCode accepts 7 digits without leading zero', () {
      expect(DeviceIdService.validCode('4820193'), isTrue);
      expect(DeviceIdService.validCode('1000000'), isTrue);
      expect(DeviceIdService.validCode('9999999'), isTrue);
    });

    test('validCode rejects bad input', () {
      expect(DeviceIdService.validCode(null), isFalse);
      expect(DeviceIdService.validCode(''), isFalse);
      expect(DeviceIdService.validCode('482019'), isFalse);
      expect(DeviceIdService.validCode('48201934'), isFalse);
      expect(DeviceIdService.validCode('0820193'), isFalse);
      expect(DeviceIdService.validCode('abc1234'), isFalse);
    });

    test('generateCode stays in range (seeded)', () {
      final code = DeviceIdService.generateCode(Random(42));
      expect(DeviceIdService.validCode(code), isTrue);
    });

    test('displayCode prefixes DIZ-', () {
      expect(DeviceIdService.displayCode('4820193'), 'DIZ-4820193');
    });

    test('pickUniqueCode skips taken + invalid, null when exhausted', () {
      expect(
        DeviceIdService.pickUniqueCode(
            ['1111111', '2222222'], {'1111111'}),
        '2222222',
      );
      expect(
        DeviceIdService.pickUniqueCode(['1111111'], {'1111111'}),
        isNull,
      );
      expect(
        DeviceIdService.pickUniqueCode(['abc', '0820193'], {}),
        isNull,
      );
    });
  });
}
