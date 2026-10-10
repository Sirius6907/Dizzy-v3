import 'package:dizzy/models/addon/addon.dart';
import 'package:dizzy/services/addon/addon_manager.dart';
import 'package:dizzy/services/adult/adult_directory.dart';
import 'package:dizzy/services/adult/adult_section_gate.dart';
import 'package:flutter_test/flutter_test.dart';

InstalledAddon _addon({
  required String id,
  required String name,
  required String baseUrl,
  List<String> types = const ['movie'],
  List<AddonCatalog> catalogs = const [],
}) =>
    InstalledAddon(
      baseUrl: baseUrl,
      manifest: AddonManifest(
        id: id,
        name: name,
        version: '1.0.0',
        resources: const ['catalog', 'stream'],
        types: types,
        idPrefixes: const [],
        catalogs: catalogs,
      ),
    );

void main() {
  group('18+ Heaven gate (pure)', () {
    test('needs all three locks', () {
      expect(
          AdultSectionGate.computeVisible(
              local: true, admin: true, kids: false),
          isTrue);
      expect(
          AdultSectionGate.computeVisible(
              local: false, admin: true, kids: false),
          isFalse);
      expect(
          AdultSectionGate.computeVisible(
              local: true, admin: false, kids: false),
          isFalse);
      expect(
          AdultSectionGate.computeVisible(
              local: true, admin: true, kids: true),
          isFalse);
      expect(
          AdultSectionGate.computeVisible(
              local: false, admin: false, kids: true),
          isFalse);
    });
  });

  group('18+ Heaven directory', () {
    test('ships 8 entries incl all 7 requested addons', () {
      expect(AdultDirectory.entries.length, 8);
      final urls = AdultDirectory.entries.map((e) => e.manifestUrl).join('|');
      expect(urls, contains('tpb-adult-addon.click'));
      expect(urls, contains('h-gate.site/AdultVideo'));
      expect(urls, contains('ptube.ers.pw'));
      expect(urls, contains('baby-beamup.club'));
      expect(urls, contains('asa.00696900.xyz'));
      expect(urls, contains('midnight.stravo.site'));
      expect(urls, contains('stravo.site/local'));
      expect(urls, contains('v2.stravo.site'));
    });

    test('section title is 18+ Heaven', () {
      expect(AdultDirectory.sectionTitle, '18+ Heaven');
    });
  });

  group('AddonManager.isAdultAddon', () {
    test('flags directory URLs', () {
      final a = _addon(
        id: 'com.tpb.adult.4k',
        name: 'TPB 4K Porn',
        baseUrl: 'https://tpb-adult-addon.click',
      );
      expect(AddonManager.isAdultAddon(a), isTrue);
    });

    test('flags adult markers in id/name/type', () {
      expect(
          AddonManager.isAdultAddon(_addon(
              id: 'x.porn', name: 'X', baseUrl: 'https://x.example.com')),
          isTrue);
      expect(
          AddonManager.isAdultAddon(_addon(
              id: 'x', name: 'X', baseUrl: 'https://x.example.com',
              types: const ['porn'])),
          isTrue);
      expect(
          AddonManager.isAdultAddon(_addon(
            id: 'x',
            name: 'X',
            baseUrl: 'https://x.example.com',
            catalogs: [
              AddonCatalog(
                  type: 'Porn',
                  id: 'top',
                  genres: const [],
                  supportsSearch: false,
                  supportsSkip: false),
            ],
          )),
          isTrue);
    });

    test('clean addons pass (Cinemeta)', () {
      final c = _addon(
        id: 'com.linvo.cinemeta',
        name: 'Cinemeta',
        baseUrl: 'https://v3-cinemeta.strem.io',
      );
      expect(AddonManager.isAdultAddon(c), isFalse);
    });
  });
}
