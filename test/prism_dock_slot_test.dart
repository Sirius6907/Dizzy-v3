import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/theme/dock_settings.dart';
import 'package:dizzy/widgets/prism/prism_dock.dart';

/// v1.4 one-app fix — the dock must sit at the same height on every tab.
///
/// Before this, Live TV placed the dock at a bare `bottom: 24` while the other
/// four tabs used `12 + safeArea.bottom`, so the bar jumped 22dp when you
/// switched tabs on a phone with a gesture inset. These tests pin the geometry
/// to [PrismDockSlot] and pin every dock page to using it.
const double _kDockHeight = 83; // 8 + 46 + 4 + 11 + 6 + 8

Future<void> _pumpSlot(
  WidgetTester tester, {
  required double bottomInset,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: const Size(400, 800),
        padding: EdgeInsets.only(bottom: bottomInset),
      ),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            PrismDockSlot(currentDestination: DockItemKey.home),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('PrismDockSlot geometry', () {
    testWidgets('sits bottomGap above the screen edge with no inset',
        (tester) async {
      await _pumpSlot(tester, bottomInset: 0);

      final rect = tester.getRect(find.byType(PrismDock));
      expect(rect.bottom, 800 - PrismDockSlot.bottomGap);
      expect(rect.height, _kDockHeight);
    });

    testWidgets('clears a 34dp gesture inset instead of sitting under it',
        (tester) async {
      await _pumpSlot(tester, bottomInset: 34);

      final rect = tester.getRect(find.byType(PrismDock));
      expect(rect.bottom, 800 - (PrismDockSlot.bottomGap + 34));
      expect(rect.height, _kDockHeight);
    });

    testWidgets('only the gap changes between insets — height is identical',
        (tester) async {
      await _pumpSlot(tester, bottomInset: 0);
      final withoutInset = tester.getRect(find.byType(PrismDock));

      await _pumpSlot(tester, bottomInset: 34);
      final withInset = tester.getRect(find.byType(PrismDock));

      expect(withInset.height, withoutInset.height);
      expect(withInset.bottom, withoutInset.bottom - 34);
    });

    testWidgets('centers the dock and spans the full width', (tester) async {
      await _pumpSlot(tester, bottomInset: 0);

      final slot = tester.getRect(find.byType(PrismDockSlot));
      expect(slot.left, 0);
      expect(slot.width, 400);
    });
  });

  group('every dock page uses the shared slot', () {
    test('no page hand-rolls its own dock Positioned', () {
      const pages = {
        'home': 'lib/pages/home/home_page.dart',
        'anime': 'lib/pages/anime/anime_page.dart',
        'books': 'lib/pages/books/books_page.dart',
        'manga': 'lib/pages/manga/manga_page.dart',
        'iptv': 'lib/pages/iptv/iptv_page.dart',
      };

      final directDock = RegExp(r'(?<![A-Za-z])PrismDock\(');
      final legacyOffset = RegExp(r'bottom:\s*(12\.0\s*\+|24\s*,)');

      pages.forEach((name, path) {
        final source = File(path).readAsStringSync();

        expect(source.contains('PrismDockSlot('), isTrue,
            reason: '$name must place the dock through PrismDockSlot');
        expect(directDock.hasMatch(source), isFalse,
            reason: '$name still builds a raw PrismDock()');
        expect(legacyOffset.hasMatch(source), isFalse,
            reason: '$name still hand-rolls the dock offset');
      });
    });
  });
}
