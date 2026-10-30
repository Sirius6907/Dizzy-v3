import 'package:dizzy/widgets/guide/guide_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tour is the only guide that still exists, and it never opens by itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tour copy — house rules', () {
    test('three cards, at most', () {
      expect(AppGuides.tour, isNotEmpty);
      expect(AppGuides.tour.length, lessThanOrEqualTo(GuideCard.maxSteps));
    });

    test('every card has an icon, a title and one short line', () {
      for (final step in AppGuides.tour) {
        expect(step.icon.trim(), isNotEmpty);
        expect(step.title.trim(), isNotEmpty);
        expect(step.line.trim(), isNotEmpty);
        expect(
          step.line.length,
          lessThanOrEqualTo(60),
          reason: '"${step.line}" is more than one job',
        );
      }
    });

    test('no tech words leak into a card', () {
      const banned = [
        'api',
        'token',
        'stream',
        'endpoint',
        'payload',
        'cache',
        'middleware',
        'deprecated',
        'authentication',
        'authorization',
      ];
      for (final step in AppGuides.tour) {
        final text = '${step.title} ${step.line}'.toLowerCase();
        for (final word in banned) {
          expect(
            text.contains(word),
            isFalse,
            reason: '"$word" leaked into: ${step.line}',
          );
        }
      }
    });
  });

  group('GuideCard', () {
    testWidgets('never shows more than three cards', (tester) async {
      const tooMany = [
        GuideStep(icon: '1️⃣', title: 'One', line: 'First job.'),
        GuideStep(icon: '2️⃣', title: 'Two', line: 'Second job.'),
        GuideStep(icon: '3️⃣', title: 'Three', line: 'Third job.'),
        GuideStep(icon: '4️⃣', title: 'Four', line: 'Never shown.'),
      ];
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: GuideCard(steps: tooMany)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Three'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Four'), findsNothing);
    });

    testWidgets('steps through the tour and closes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => GuideCard.show(context, AppGuides.tour),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(AppGuides.tour.first.title), findsOneWidget);
      for (final step in AppGuides.tour.skip(1)) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text(step.title), findsOneWidget);
      }
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text(AppGuides.tour.last.title), findsNothing);
    });

    testWidgets('an empty tour opens nothing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => GuideCard.show(context, const []),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(GuideCard), findsNothing);
    });
  });
}
