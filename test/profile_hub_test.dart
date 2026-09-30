import 'package:dizzy/pages/social/profile_hub_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase B (Profile Hub): header sections render, empty states, admin badge.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileHubSections.isAdmin.value = false;
  });

  Widget host() => const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ProfileHubSections()),
        ),
      );

  group('ProfileHubSections', () {
    testWidgets('renders every hub section', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      for (final title in [
        'My devices',
        'Updates',
        'Notifications',
        'Background',
        'Privacy',
        'Notices',
        'Appearance',
        'Downloads',
        'Help',
        'About Dizzy',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
    });

    testWidgets('notices shows empty state when nothing active',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('No notices right now.'), findsOneWidget);
    });

    testWidgets('admin console hidden for normal users', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('Admin Console'), findsNothing);
    });

    testWidgets('admin badge chip hidden when not admin', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ProfileHubAdminBadge())),
      );
      await tester.pumpAndSettle();

      expect(find.text('ADMIN'), findsNothing);
    });

    testWidgets('admin badge chip shows when admin', (tester) async {
      ProfileHubSections.isAdmin.value = true;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ProfileHubAdminBadge())),
      );
      await tester.pumpAndSettle();

      expect(find.text('ADMIN'), findsOneWidget);
    });
  });
}
