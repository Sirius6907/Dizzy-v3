import 'package:dizzy/services/social/profile_avatar_service.dart';
import 'package:dizzy/widgets/profile/profile_avatar.dart';
import 'package:dizzy/widgets/profile/profile_avatar_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional profile photos: the monogram fallback must never be broken by a
/// missing file, and the sheet must always offer a way out ("Not now").
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileAvatarService.path.value = null;
  });

  group('avatarInitial', () {
    test('uses the first letter of a name, upper-cased', () {
      expect(avatarInitial('nala'), 'N');
      expect(avatarInitial('@Nala'), 'N');
    });

    test('ignores decoration and returns "?" when there is no name', () {
      expect(avatarInitial('  @__  '), '?');
      expect(avatarInitial(''), '?');
      expect(avatarInitial(null), '?');
    });

    test('keeps digits as they are', () {
      expect(avatarInitial('7even'), '7');
    });
  });

  group('ProfileAvatar', () {
    testWidgets('draws the monogram when no photo is set', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ProfileAvatar(size: 80, username: 'nala'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProfileAvatar), findsOneWidget);
      expect(find.text('N'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('shows the camera chip only when editable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ProfileAvatar(
                size: 80,
                username: 'nala',
                editable: true,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
    });
  });

  group('ProfileAvatarSheet', () {
    Widget host() => const MaterialApp(
          home: Scaffold(body: ProfileAvatarSheet(username: 'nala')),
        );

    testWidgets('offers a device pick and a way out', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('Profile photo'), findsOneWidget);
      expect(find.text('Choose from device'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Remove photo'), findsNothing);
      expect(find.text('JPG or PNG · never uploaded'), findsOneWidget);
    });

    testWidgets('stays honest that it is optional', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(
        find.text('Optional — your initials work just as well.'),
        findsOneWidget,
      );
    });
  });
}
