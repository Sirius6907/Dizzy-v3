import 'package:dizzy/services/guide/guide_service.dart';
import 'package:dizzy/widgets/guide/guide_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/widgets/onboarding/onboarding_superpower_sheet.dart';

/// P7 — the 25 intro cards, the card widget itself, and the welcome tour.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// `maybeShow` hops through prefs + migration futures and a static dialog
/// queue before anything appears, so give those microtasks room to land.
Future<void> _settleGuideQueue(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P7 GuideService v2 — coverage', () {
    test('25 feature keys are registered', () {
      expect(GuideService.allKeys.length, 25);
      expect(GuideService.allKeys.toSet().length, 25,
          reason: 'duplicate guide key');
    });

    test('every registered key has copy, and vice versa', () {
      for (final key in GuideService.allKeys) {
        expect(AppGuides.forKey(key), isNotEmpty, reason: 'no copy for $key');
      }
      for (final key in AppGuides.byKey.keys) {
        expect(GuideService.allKeys, contains(key),
            reason: '$key has copy but no flag');
      }
    });

    test('the pre-P7 keys survived the rename', () {
      expect(GuideService.allKeys,
          containsAll(<String>['downloads', 'cloud_sync', 'sources_health', 'subtitles', 'party_v2']));
    });
  });

  group('P7 guide copy — house rules', () {
    test('no guide runs past 3 cards', () {
      for (final entry in AppGuides.byKey.entries) {
        expect(entry.value.length, lessThanOrEqualTo(GuideService.maxSteps),
            reason: '${entry.key} has ${entry.value.length} cards');
        expect(entry.value, isNotEmpty);
      }
    });

    test('every card has an icon, a title and one short line', () {
      for (final entry in AppGuides.byKey.entries) {
        for (final step in entry.value) {
          expect(step.icon.trim(), isNotEmpty, reason: entry.key);
          expect(step.title.trim(), isNotEmpty, reason: entry.key);
          expect(step.line.trim(), isNotEmpty, reason: entry.key);
          expect(step.line.length, lessThanOrEqualTo(60),
              reason: '${entry.key}: "${step.line}" is more than one job');
        }
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
      for (final entry in AppGuides.byKey.entries) {
        for (final step in entry.value) {
          final text = '${step.title} ${step.line}'.toLowerCase();
          for (final word in banned) {
            expect(text.contains(word), isFalse,
                reason: '"$word" leaked into ${entry.key}: ${step.line}');
          }
        }
      }
    });

    test('an unknown key resolves to nothing rather than throwing', () {
      expect(AppGuides.forKey('nope'), isEmpty);
    });
  });

  group('P7 skip persistence — never nag', () {
    test('a fresh user sees the card', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await GuideService.shouldShow('stats'), isTrue);
    });

    test('Skip once = never again', () async {
      SharedPreferences.setMockInitialValues({});
      await GuideService.markSeen('stats');
      expect(await GuideService.shouldShow('stats'), isFalse);
      expect(await GuideService.shouldShow('stats'), isFalse);
    });

    test('skipping one guide leaves the rest alone', () async {
      SharedPreferences.setMockInitialValues({});
      await GuideService.markSeen('stats');
      expect(await GuideService.shouldShow('debrid'), isTrue);
    });

    test('Settings → Help → Show again replays every guide', () async {
      SharedPreferences.setMockInitialValues({
        for (final k in GuideService.allKeys) 'guide_seen_$k': true,
      });
      await GuideService.resetAll(GuideService.allKeys);
      for (final key in GuideService.allKeys) {
        expect(await GuideService.shouldShow(key), isTrue, reason: key);
      }
    });

    test('replay does not open the tour unless it is asked for too', () async {
      SharedPreferences.setMockInitialValues({});
      await GuideService.resetAll(GuideService.allKeys);
      expect(await GuideService.shouldShow(GuideService.onboardingKey), isTrue);
    });
  });

  group('P7 migration — no re-nag after upgrade', () {
    test('a retired party key silences its replacement', () async {
      SharedPreferences.setMockInitialValues({'guide_seen_watch_party': true});
      await GuideService.migrateLegacyKeys();
      expect(await GuideService.shouldShow('party_v2'), isFalse);
    });

    test('a fresh user still gets the party card', () async {
      SharedPreferences.setMockInitialValues({});
      await GuideService.migrateLegacyKeys();
      expect(await GuideService.shouldShow('party_v2'), isTrue);
    });

    test('migration is idempotent', () async {
      SharedPreferences.setMockInitialValues({'guide_seen_watch_party': true});
      await GuideService.migrateLegacyKeys();
      await GuideService.migrateLegacyKeys();
      expect(await GuideService.shouldShow('party_v2'), isFalse);
    });

    test('the v1 welcome tour carries over to the v2 flag', () async {
      SharedPreferences.setMockInitialValues(
          {'has_seen_superpower_onboarding_v1_2': true});
      await GuideService.migrateLegacyKeys();
      expect(await GuideService.shouldShow(GuideService.onboardingKey), isFalse);
    });

    test('a brand-new install still gets the welcome tour', () async {
      SharedPreferences.setMockInitialValues({});
      await GuideService.migrateLegacyKeys();
      expect(await GuideService.shouldShow(GuideService.onboardingKey), isTrue);
    });
  });

  group('P7 GuideCard 2.0', () {
    testWidgets('shows at most 3 cards even when given more', (tester) async {
      const tooMany = [
        GuideStep(icon: '1️⃣', title: 'One', line: 'First job.'),
        GuideStep(icon: '2️⃣', title: 'Two', line: 'Second job.'),
        GuideStep(icon: '3️⃣', title: 'Three', line: 'Third job.'),
        GuideStep(icon: '4️⃣', title: 'Four', line: 'Never shown.'),
      ];
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, const GuideCard(guideKey: 'cap', steps: tooMany));
      await tester.pumpAndSettle();

      expect(find.text('One'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      // Three dots, not four.
      expect(find.byType(PageView), findsOneWidget);
      final dots = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.constraints?.maxWidth == 20)
          .length;
      expect(dots, 1);
    });

    testWidgets('the last card swaps Next for Got it', (tester) async {
      const one = [GuideStep(icon: '🎬', title: 'Only card', line: 'That is it.')];
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, const GuideCard(guideKey: 'single', steps: one));
      await tester.pumpAndSettle();
      expect(find.text('Got it'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
    });

    testWidgets('Skip writes the flag and never nags again', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(
        tester,
        const GuideCard(
          guideKey: 'skipme',
          steps: [GuideStep(icon: '👋', title: 'Hi', line: 'Bye.')],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(await GuideService.shouldShow('skipme'), isFalse);
    });

    testWidgets('Got it writes the flag too', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(
        tester,
        const GuideCard(
          guideKey: 'gotit',
          steps: [GuideStep(icon: '👋', title: 'Hi', line: 'Bye.')],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(await GuideService.shouldShow('gotit'), isFalse);
    });

    testWidgets('maybeShow is silent for an already-seen guide',
        (tester) async {
      SharedPreferences.setMockInitialValues({'guide_seen_quiet': true});
      await _pump(tester, Builder(builder: (context) {
        return TextButton(
          onPressed: () =>
              GuideCard.maybeShow(context, 'quiet', AppGuides.stats),
          child: const Text('open'),
        );
      }));
      await tester.tap(find.text('open'));
      await _settleGuideQueue(tester);
      expect(find.byType(GuideCard), findsNothing);
    });

    testWidgets('maybeShow opens the card for a fresh user', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, Builder(builder: (context) {
        return TextButton(
          onPressed: () =>
              GuideCard.maybeShow(context, 'fresh', AppGuides.stats),
          child: const Text('open'),
        );
      }));
      await tester.tap(find.text('open'));
      await _settleGuideQueue(tester);
      expect(find.byType(GuideCard), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('maybeShow does nothing for an empty guide', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, Builder(builder: (context) {
        return TextButton(
          onPressed: () => GuideCard.maybeShow(context, 'empty', const []),
          child: const Text('open'),
        );
      }));
      await tester.tap(find.text('open'));
      await _settleGuideQueue(tester);
      expect(find.byType(GuideCard), findsNothing);
    });
  });

  group('P7 Onboarding 2.0', () {
    test('the tour is shown once, then never again', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await OnboardingSuperpowerSheet.shouldShow(), isTrue);
      await OnboardingSuperpowerSheet.markSeen();
      expect(await OnboardingSuperpowerSheet.shouldShow(), isFalse);
    });

    test('the tour shares the guide flag space so Help can replay it',
        () async {
      SharedPreferences.setMockInitialValues({});
      await OnboardingSuperpowerSheet.markSeen();
      expect(await GuideService.shouldShow(GuideService.onboardingKey), isFalse);
    });

    testWidgets('five slides, and the last one starts the app',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: OnboardingSuperpowerSheet()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Everything in one place'), findsOneWidget);
      expect(find.text('WELCOME'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Yours alone'), findsOneWidget);
      expect(find.text('Explore Dizzy'), findsOneWidget);
    });
  });
}
