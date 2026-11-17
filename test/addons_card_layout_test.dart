import 'package:dizzy/models/addon/addon.dart';
import 'package:dizzy/pages/settings/addons_settings_page.dart';
import 'package:dizzy/services/theme/app_theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for a proven on-device defect (2026-11-13): the
/// Addons provider row overflowed by 72.4px on a 390dp phone when the
/// built-in badge sat next to the addon name. The badge must be able to
/// shrink (ellipsis) instead of forcing the row past its bounds.
InstalledAddon _builtin({
  required String id,
  required String name,
  required String version,
  required String baseUrl,
  int catalogs = 8,
}) {
  return InstalledAddon(
    manifest: AddonManifest(
      id: id,
      name: name,
      version: version,
      resources: const ['catalog', 'stream'],
      types: const ['movie', 'series'],
      idPrefixes: const ['tt', 'tmdb:'],
      catalogs: [
        for (var i = 0; i < catalogs; i++)
          AddonCatalog(
            type: 'movie',
            id: 'c$i',
            name: 'Catalog $i',
            genres: const [],
            supportsSearch: true,
            supportsSkip: false,
          ),
      ],
    ),
    baseUrl: baseUrl,
  );
}

Widget _host(InstalledAddon addon) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        // Mirrors the Addons page gutter (on-device card width at 390dp).
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AddonCard(
          index: 0,
          totalCount: 7,
          addon: addon,
          onMoveUp: null,
          onMoveDown: null,
          onToggle: (_) {},
          onUpdateFeature: ({bool? enableCatalogs, bool? enableSearch,
              bool? enableSubtitles, bool? enableStreams}) {},
          onRemove: () {},
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    AppThemeService.currentPalette.value = AppThemeService.palettes.first;
  });

  testWidgets('built-in torrent addon card fits a 390dp phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(
        _builtin(
          id: 'builtin.dizzy',
          name: 'Cinemeta',
          version: '3.0.14',
          baseUrl: 'builtin:dizzy',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Cinemeta'), findsOneWidget);
    expect(find.text('BUILT-IN TORRENT'), findsOneWidget);
  });

  testWidgets('built-in torrent addon card fits a 320dp phone', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(
        _builtin(
          id: 'builtin.dizzy',
          name: 'Cinemeta',
          version: '3.0.14',
          baseUrl: 'builtin:dizzy',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
