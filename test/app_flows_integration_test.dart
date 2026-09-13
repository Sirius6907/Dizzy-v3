import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/theme/custom_accent_service.dart';
import 'package:dizzy/services/updater/app_updater_service.dart';
import 'package:dizzy/widgets/common/offline_banner.dart';
import 'package:dizzy/widgets/onboarding/onboarding_superpower_sheet.dart';
import 'package:dizzy/widgets/social/social_hub_sheet.dart';
import 'package:dizzy/widgets/theme/accent_studio_sheet.dart';
import 'package:dizzy/widgets/updater/release_notes_studio.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Dizzy App Complete Flows Verification', () {
    testWidgets('Flow 1: Onboarding Superpower Sheet (UX4) renders and steps through',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OnboardingSuperpowerSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify first slide content
      expect(find.text('SUPERPOWERS'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Everything in One Place'), findsOneWidget);

      // Tap Next to advance
      final nextButton = find.text('Next');
      expect(nextButton, findsOneWidget);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      // Verify second slide
      expect(find.text('Lossless Audio & Zero Ads'), findsOneWidget);

      // Tap Next again
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      // Verify third slide has Explore Dizzy button
      expect(find.text('Watch & Listen Together'), findsOneWidget);
      expect(find.text('Explore Dizzy'), findsOneWidget);
    });

    testWidgets('Flow 2: Accent Studio & OLED Engine (UX6) toggles live',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccentStudioSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Accent Studio & OLED'), findsOneWidget);
      expect(find.text('AMOLED True Black'), findsOneWidget);
      expect(find.text('Backdrop Blur Intensity'), findsOneWidget);

      // Verify AMOLED toggle flips state
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(CustomAccentService.amoledTrueBlack.value, isTrue);
    });

    testWidgets('Flow 3: Social Hub Sheet (UX8) renders rooms and controls',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SocialHubSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Social Hub'), findsOneWidget);
      expect(find.text('Listen Together'), findsOneWidget);
      expect(find.text('Start a jam room'), findsOneWidget);
      expect(find.text('Join with code'), findsOneWidget);
    });

    testWidgets('Flow 4: Release Notes Studio (UX10) parses and renders cards',
        (tester) async {
      final info = UpdateInfo(
        currentVersion: '1.1.9',
        latestVersion: '1.2.0',
        releaseNotes: '- Universal Spotlight Search\n- Unified Download Hub\n- Low-End Device Mode',
        downloadUrl: 'https://github.com/test/download.apk',
        publishedAt: DateTime(2026, 9, 13),
        isMacOS: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReleaseNotesStudio(updateInfo: info),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("What's New in v1.2.0"), findsOneWidget);
      expect(find.text('Universal Spotlight Search'), findsOneWidget);
      expect(find.text('Unified Download Hub'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets('Flow 5: Offline Banner (UX7) shows cached state and calls retry',
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

      expect(find.text('You are offline. Showing your saved copy.'), findsOneWidget);
      final retryBtn = find.text('Retry');
      expect(retryBtn, findsOneWidget);
      await tester.tap(retryBtn);
      expect(retried, isTrue);
    });
  });
}
