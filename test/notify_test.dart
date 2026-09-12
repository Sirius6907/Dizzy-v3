import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/widgets/common/notify.dart';

/// Polish P18: one voice, one timing, one button order.
void main() {
  group('DizzyNotify', () {
    test('lifetime frozen at 3s', () {
      expect(DizzyNotify.kLifetime, const Duration(seconds: 3));
    });

    test('tones have distinct colors', () {
      expect(DizzyNotify.backgroundFor(NotifyTone.success),
          const Color(0xFF10B981));
      expect(DizzyNotify.backgroundFor(NotifyTone.warn),
          const Color(0xFFB45309));
      expect(
        DizzyNotify.backgroundFor(NotifyTone.info),
        isNot(DizzyNotify.backgroundFor(NotifyTone.success)),
      );
    });

    testWidgets('show renders the Easy English line', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('x')),
        ),
      );
      final ctx =
          tester.element(find.text('x'));
      DizzyNotify.show(ctx, 'Code copied.', tone: NotifyTone.success);
      await tester.pump();
      expect(find.text('Code copied.'), findsOneWidget);
    });
  });

  group('DizzyDialogs.confirm', () {
    testWidgets('Cancel → false, confirm → true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('x')),
        ),
      );
      final ctx = tester.element(find.text('x'));

      // Cancel path.
      var future = DizzyDialogs.confirm(
        ctx,
        title: 'Delete Download',
        line: 'Sure?',
        confirmLabel: 'Delete',
        danger: true,
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete Download'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // Button order: Cancel left of Delete.
      final cancelX = tester.getCenter(find.text('Cancel')).dx;
      final deleteX = tester.getCenter(find.text('Delete').last).dx;
      expect(cancelX, lessThan(deleteX));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await future, isFalse);

      // Confirm path.
      future = DizzyDialogs.confirm(
        ctx,
        title: 'Delete Download',
        line: 'Sure?',
        confirmLabel: 'Delete',
        danger: true,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(await future, isTrue);
    });
  });
}
