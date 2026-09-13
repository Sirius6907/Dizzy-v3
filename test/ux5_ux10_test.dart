import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/media/global_media_coordinator.dart';
import 'package:dizzy/services/theme/custom_accent_service.dart';
import 'package:dizzy/utils/tv/dpad_nav.dart';
import 'package:dizzy/widgets/common/offline_banner.dart';

void main() {
  group('UX5 GlobalMediaCoordinator.resolveConflict', () {
    test('video starting pauses music', () {
      expect(
        GlobalMediaCoordinator.resolveConflict(videoStarting: true),
        'pause-music',
      );
    });

    test('music starting pauses video', () {
      expect(
        GlobalMediaCoordinator.resolveConflict(videoStarting: false),
        'pause-video',
      );
    });
  });

  group('UX6 CustomAccentService hex', () {
    test('parses #RRGGBB', () {
      final c = CustomAccentService.tryParseHex('#00E5FF');
      expect(c, isNotNull);
      expect(c!.toARGB32(), const Color(0xFF00E5FF).toARGB32());
    });

    test('parses without hash', () {
      expect(
        CustomAccentService.tryParseHex('F59E0B')?.toARGB32(),
        const Color(0xFFF59E0B).toARGB32(),
      );
    });

    test('rejects garbage', () {
      expect(CustomAccentService.tryParseHex('xyz'), isNull);
      expect(CustomAccentService.tryParseHex('#12345'), isNull);
      expect(CustomAccentService.tryParseHex(''), isNull);
    });

    test('toHex round-trips', () {
      const c = Color(0xFF00E5FF);
      final hex = CustomAccentService.toHex(c);
      expect(CustomAccentService.tryParseHex(hex)?.toARGB32(),
          c.toARGB32());
    });
  });

  group('UX7 CalmFaceCopy', () {
    test('net failure -> easy net line', () {
      expect(
        CalmFaceCopy.forError('SocketException: failed host lookup'),
        contains('Try again'),
      );
    });

    test('auth failure -> login line', () {
      expect(
        CalmFaceCopy.forError('401 Unauthorized'),
        contains('Login'),
      );
    });

    test('missing -> not-found line', () {
      expect(
        CalmFaceCopy.forError('404 not found'),
        contains('Not found'),
      );
    });

    test('unknown -> generic, raw never leaks', () {
      final line = CalmFaceCopy.forError('E_CRASH stack trace 0x99');
      expect(line, contains('Try again'));
      expect(line, isNot(contains('0x99')));
    });
  });

  group('UX9 DpadNavScope keys', () {
    test('enter/space/gamepad-A are select keys', () {
      expect(DpadNavScope.isSelectKey(LogicalKeyboardKey.enter), true);
      expect(DpadNavScope.isSelectKey(LogicalKeyboardKey.space), true);
      expect(
          DpadNavScope.isSelectKey(LogicalKeyboardKey.gameButtonA), true);
    });

    test('arrows are arrow keys, letters are not', () {
      expect(
          DpadNavScope.isArrowKey(LogicalKeyboardKey.arrowUp), true);
      expect(DpadNavScope.isArrowKey(LogicalKeyboardKey.keyM), false);
    });
  });
}
