import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/addon/addon_manager.dart';

void main() {
  group('default stream addons', () {
    test('ships torrentio, torrentsdb and acuanime', () {
      expect(
        AddonManager.defaultStreamAddonUrls,
        containsAll([
          'https://torrentio.strem.fun',
          'https://torrentsdb.com',
          'https://acuanime.pages.dev',
        ]),
      );
    });

    test('installs only the missing defaults', () {
      final missing = AddonManager.missingDefaultStreamAddons([
        'https://torrentio.strem.fun/',
        'builtin:dizzy',
      ]);
      expect(missing, isNot(contains('https://torrentio.strem.fun')));
      expect(missing, contains('https://torrentsdb.com'));
      expect(missing, contains('https://acuanime.pages.dev'));
    });

    test('installed defaults need no work', () {
      expect(
        AddonManager.missingDefaultStreamAddons(
          AddonManager.defaultStreamAddonUrls,
        ),
        isEmpty,
      );
    });
  });
}
