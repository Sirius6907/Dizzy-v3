import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/player/pip_service.dart';

void main() {
  group('F1 PipService platform gating', () {
    test('isSupported evaluates without throwing', () {
      // On Windows test environment, this must be false.
      // On Android, it returns true.
      expect(PipService.isSupported, isA<bool>());
    });

    test('canEnterPip returns false on non-supported platform', () async {
      if (!PipService.isSupported) {
        expect(await PipService.canEnterPip(), isFalse);
        expect(await PipService.enterPip(), isFalse);
      }
    });
  });
}
