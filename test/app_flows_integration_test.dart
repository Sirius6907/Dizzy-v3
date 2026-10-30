import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/updater/app_updater_service.dart';
import 'package:dizzy/widgets/common/offline_banner.dart';
import 'package:dizzy/widgets/guide/guide_card.dart';
import 'package:dizzy/widgets/social/social_hub_sheet.dart';
import 'package:dizzy/widgets/updater/release_notes_studio.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Dizzy App Complete Flows Verification', () {
    testWidgets('Flow 1: opt-in tour card steps through all three cards', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => GuideCard.show(context, AppGuides.tour),
                child: const Text('tour'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('tour'));
      await tester.pumpAndSettle();

      expect(find.text(AppGuides.tour.first.title), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      for (final step in AppGuides.tour.skip(1)) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text(step.title), findsOneWidget);
      }
      expect(find.text('Done'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text(AppGuides.tour.last.title), findsNothing);
    });

    testWidgets('Flow 3: Social Hub Sheet (UX8) renders rooms and controls', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SocialHubSheet())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Social Hub'), findsOneWidget);
      expect(find.text('Listen Together'), findsOneWidget);
      expect(find.text('Start a jam room'), findsOneWidget);
      expect(find.text('Join with code'), findsOneWidget);
    });

    testWidgets('Flow 4: Release Notes Studio (UX10) parses and renders cards', (
      tester,
    ) async {
      final info = UpdateInfo(
        currentVersion: '1.1.9',
        latestVersion: '1.2.0',
        releaseNotes:
            '- Universal Spotlight Search\n- Unified Download Hub\n- Low-End Device Mode',
        downloadUrl: 'https://github.com/test/download.apk',
        publishedAt: DateTime(2026, 9, 13),
        isMacOS: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReleaseNotesStudio(updateInfo: info)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("What's New in v1.2.0"), findsOneWidget);
      expect(find.text('Universal Spotlight Search'), findsOneWidget);
      expect(find.text('Unified Download Hub'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets(
      'Flow 5: Offline Banner (UX7) shows cached state and calls retry',
      (tester) async {
        bool retried = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DizzyOfflineBanner(
                isOffline: true,
                showingSavedCopy: true,
                onRetry: () => retried = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('You are offline. Showing your saved copy.'),
          findsOneWidget,
        );
        final retryBtn = find.text('Retry');
        expect(retryBtn, findsOneWidget);
        await tester.tap(retryBtn);
        expect(retried, isTrue);
      },
    );
  });
}
