import 'package:dizzy/design/prism_tokens.dart';
import 'package:dizzy/models/music/music_track.dart';
import 'package:dizzy/pages/music/widgets/music_expanded_player.dart';
import 'package:dizzy/services/music/music_player_controller.dart';
import 'package:dizzy/services/theme/app_theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const track = MusicTrack(
    id: 'player-test',
    title: 'A long song title for the clay player',
    artist: 'Test artist',
    album: 'Test album',
    coverUrl: '',
    durationSeconds: 200,
  );
  const next = MusicTrack(
    id: 'next-test',
    title: 'The next song',
    artist: 'Next artist',
    album: 'Next album',
    coverUrl: '',
    durationSeconds: 190,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MusicPlayerController.instance.debugSeedPlaybackState(
      track: track,
      queue: [track, next],
    );
  });

  for (final palette in AppThemeService.palettes) {
    testWidgets(
      '${palette.name} player is opaque, readable and exposes the next song',
      (tester) async {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppThemeService.currentPalette.value = palette;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MusicExpandedPlayer(
                playerController: MusicPlayerController.instance,
                isSaved: false,
                onToggleSave: () {},
                onCollapse: () {},
                onQueueTap: () {},
                onAddToPlaylist: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        final surface = tester.widget<ColoredBox>(
          find.byKey(const ValueKey('music-player-surface')),
        );
        expect(surface.color, palette.scaffoldBackgroundColor);
        expect(surface.color.a, 1);
        expect(
          tester.widget<Text>(find.text(track.title)).style!.color,
          PrismInk.primary(palette.isLight),
        );
        expect(find.text('The next song'), findsOneWidget);
        expect(find.byTooltip('Queue & Up Next'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('Queue & Up Next'));
        await tester.tap(find.byTooltip('Queue & Up Next'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Queue & Up Next'), findsOneWidget);
        expect(find.text('Paused'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('short landscape player scrolls without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(850, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MusicExpandedPlayer(
            playerController: MusicPlayerController.instance,
            isSaved: false,
            onToggleSave: () {},
            onCollapse: () {},
            onQueueTap: () {},
            onAddToPlaylist: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
