import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dizzy/models/continue_watching/continue_watching_item.dart';
import 'package:dizzy/pages/stats/stats_page.dart';
import 'package:dizzy/services/continue_watching/continue_watching_service.dart';
import 'package:dizzy/services/home/genre_preference_service.dart';
import 'package:dizzy/services/theme/app_theme_service.dart';

ContinueWatchingItem item({
  required String id,
  required int pos,
  required int total,
  required DateTime at,
  String type = 'movie',
}) => ContinueWatchingItem(
  id: id,
  title: id,
  type: type,
  positionSeconds: pos,
  totalDurationSeconds: total,
  lastWatchedAt: at,
  isTorrent: false,
);

Widget wrap(Widget child, {double scale = 1.0}) => MaterialApp(
  builder: (context, inner) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: inner!,
  ),
  home: child,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ContinueWatchingService.activeItems.value = const [];
    GenrePreferenceService.scores.value = {};
    AppThemeService.currentPalette.value = AppThemeService.palettes[0];
  });

  group('StatsPage weekly recap', () {
    testWidgets('summary counts only the last seven days', (tester) async {
      final now = DateTime.now();
      ContinueWatchingService.activeItems.value = [
        item(id: 'new', pos: 3600, total: 7200, at: now),
        item(
          id: 'old',
          pos: 6000,
          total: 7200,
          at: now.subtract(const Duration(days: 30)),
        ),
      ];

      await tester.pumpWidget(wrap(const StatsPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('This week'), findsOneWidget);
      // Weekly: 60 min, 1 title, 0 finished. All-time hero keeps 160 min.
      expect(find.textContaining('60 min'), findsWidgets);
      expect(find.textContaining('1 title'), findsOneWidget);
    });

    testWidgets('empty week shows the gentle empty line', (tester) async {
      ContinueWatchingService.activeItems.value = [
        item(
          id: 'old',
          pos: 3600,
          total: 7200,
          at: DateTime.now().subtract(const Duration(days: 30)),
        ),
      ];

      await tester.pumpWidget(wrap(const StatsPage()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No watches in the last 7 days'),
        findsOneWidget,
      );
    });

    testWidgets('survives 200% text scaling without overflow', (tester) async {
      final now = DateTime.now();
      ContinueWatchingService.activeItems.value = [
        item(id: 'a', pos: 10800, total: 14400, at: now),
        item(id: 'b', pos: 3600, total: 7200, at: now, type: 'series'),
      ];
      GenrePreferenceService.scores.value = {
        'action': 0.9,
        'comedy': 0.6,
        'thriller': 0.3,
      };

      await tester.pumpWidget(wrap(const StatsPage(), scale: 2.0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('This week'), findsOneWidget);
    });

    testWidgets('recap ink follows the two-theme rule', (tester) async {
      ContinueWatchingService.activeItems.value = [
        item(id: 'a', pos: 3600, total: 7200, at: DateTime.now()),
      ];

      await tester.pumpWidget(wrap(const StatsPage()));
      await tester.pumpAndSettle();
      var title = tester.widget<Text>(find.text('This week'));
      expect(title.style?.color, const Color(0xFF000000));

      AppThemeService.currentPalette.value = AppThemeService.palettes[1];
      await tester.pumpWidget(wrap(const StatsPage()));
      await tester.pumpAndSettle();
      title = tester.widget<Text>(find.text('This week'));
      expect(title.style?.color, const Color(0xFFFFFFFF));
      expect(tester.takeException(), isNull);
    });
  });
}
