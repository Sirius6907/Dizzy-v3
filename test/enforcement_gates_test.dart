import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/updater/update_gate.dart';

/// Phase E5 — one test per enforcement gate.
void main() {
  group('UpdateGate (E1 force-update)', () {
    test('no min_app_version → none (never blocks)', () {
      final g = UpdateGate.evaluate(
        currentVersion: '1.0.0',
        minVersion: '',
        now: DateTime(2026, 10, 1),
      );
      expect(g.level, UpdateGateLevel.none);
      expect(g.isBlocking, isFalse);
    });

    test('below min + no deadline → banner (advisory, no brick)', () {
      final g = UpdateGate.evaluate(
        currentVersion: '1.0.0',
        minVersion: '2.0.0',
        now: DateTime(2026, 10, 1),
      );
      expect(g.level, UpdateGateLevel.banner);
      expect(g.isBlocking, isFalse);
    });

    test('below min + before force_after → banner with countdown', () {
      final g = UpdateGate.evaluate(
        currentVersion: '1.0.0',
        minVersion: '2.0.0',
        forceAfter: '2026-10-20T00:00:00Z',
        now: DateTime(2026, 10, 10),
      );
      expect(g.level, UpdateGateLevel.banner);
      expect(g.forceAfter, isNotNull);
    });

    test('below min + past force_after → blocking', () {
      final g = UpdateGate.evaluate(
        currentVersion: '1.0.0',
        minVersion: '2.0.0',
        forceAfter: '2026-10-01T00:00:00Z',
        now: DateTime(2026, 10, 5),
      );
      expect(g.level, UpdateGateLevel.blocking);
      expect(g.isBlocking, isTrue);
    });

    test('at/above min → none even past deadline', () {
      final g = UpdateGate.evaluate(
        currentVersion: '2.0.1',
        minVersion: '2.0.0',
        forceAfter: '2026-01-01T00:00:00Z',
        now: DateTime(2026, 10, 5),
      );
      expect(g.level, UpdateGateLevel.none);
    });

    test('multi-digit versions compare correctly (1.10.0 > 1.9.0)', () {
      expect(UpdateGate.compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(UpdateGate.compareVersions('1.9.0', '1.10.0'), lessThan(0));
      expect(UpdateGate.compareVersions('2.0.0', '2.0.0'), 0);
    });

    test('unparseable force_after degrades to banner (never brick)', () {
      final g = UpdateGate.evaluate(
        currentVersion: '1.0.0',
        minVersion: '2.0.0',
        forceAfter: 'not-a-date',
        now: DateTime(2026, 10, 5),
      );
      expect(g.level, UpdateGateLevel.banner);
      expect(g.isBlocking, isFalse);
    });
  });

  group('source pins — gates are wired at real call sites', () {
    final anime = _read('lib/services/anime/anime_scraper_service.dart');
    final audio = _read(
      'lib/services/audiobook/audiobook_scraper_service.dart',
    );
    final party = _read('lib/pages/settings/watch_party_page.dart');
    final dm = _read('lib/pages/social/direct_message_page.dart');
    final home = _read('lib/pages/home/home_page.dart');
    final banner = _read('lib/pages/home/home_notice_banner.dart');
    final main = _read('lib/main.dart');
    final block = _read('lib/pages/common/update_required_screen.dart');
    final rcs = _read('lib/services/cloud/remote_config_service.dart');

    test('E3: every anime extractor goes through the kill gate', () {
      expect(anime.contains('RemoteConfigService.isKilled(key)'), isTrue);
      // dart format splits the first arg onto its own line → allow \s+
      expect(RegExp(r"addTask\(\s*'megaplay'").hasMatch(anime), isTrue);
      expect(RegExp(r"addTask\(\s*'hentaini'").hasMatch(anime), isTrue);
      // only the 2 helper definitions may call tasks.add directly
      expect(RegExp(r'tasks\.add\(').allMatches(anime).length, 2);
    });

    test('E3: audiobook search filters killed sources', () {
      expect(
        audio.contains('.where((e) => !RemoteConfigService.isKilled(e.key))'),
        isTrue,
      );
    });

    test('E2: party create/join + voice + DMs check feature flags', () {
      expect(
        RegExp(r"featureEnabled\('watch_party'\)").allMatches(party).length,
        3, // create, join, joinPublic
      );
      expect(
        RegExp(r"featureEnabled\('voice'\)").allMatches(party).length,
        greaterThanOrEqualTo(1),
      );
      expect(RegExp(r"featureEnabled\('dm'\)").allMatches(dm).length, 2);
      expect(dm.contains('paused for fixes'), isTrue);
    });

    test('E4: home renders the notice banner slot', () {
      expect(home.contains('HomeNoticeBanner()'), isTrue);
      expect(banner.contains('AnnouncementService.active'), isTrue);
      expect(banner.contains('_kDismissedAnns'), isTrue); // dismiss persists
      expect(rcs.contains('forceAfter'), isTrue);
    });

    test('E1: main enforces blocking update, screen is back-proof', () {
      expect(main.contains('_enforceForceUpdate'), isTrue);
      expect(main.contains('UpdateRequiredScreen'), isTrue);
      expect(block.contains('canPop: false'), isTrue);
      expect(block.contains('PopScope'), isTrue);
    });
  });
}

String _read(String rel) => File(
  '${Directory.current.path}${Platform.pathSeparator}$rel'.replaceAll(
    '/',
    Platform.pathSeparator,
  ),
).readAsStringSync();
