import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/cloud/announcement_service.dart';
import 'package:dizzy/services/cloud/remote_config_service.dart';

void main() {
  group('RemoteConfigService.parseKillMap', () {
    test('parses kill map keys lowercase', () {
      final kill = RemoteConfigService.parseKillMap(
          '{"VidFast": "dead", "VIDGOD": "down"}');
      expect(kill, {'vidfast', 'vidgod'});
    });

    test('empty/invalid returns empty set', () {
      expect(RemoteConfigService.parseKillMap('{}'), isEmpty);
      expect(RemoteConfigService.parseKillMap('not json'), isEmpty);
      expect(RemoteConfigService.parseKillMap('[]'), isEmpty);
    });
  });

  group('RemoteConfigService.featureEnabled', () {
    test('missing key returns fallback', () {
      expect(RemoteConfigService.featureEnabled('nope'), isTrue);
      expect(
          RemoteConfigService.featureEnabled('nope', fallback: false),
          isFalse);
    });
  });

  group('AnnouncementService.versionOk', () {
    test('blank bounds match everything', () {
      expect(AnnouncementService.versionOk('', '', '1.2.0'), isTrue);
    });

    test('min version gates older apps', () {
      expect(AnnouncementService.versionOk('1.2.0', '', '1.1.9'), isFalse);
      expect(AnnouncementService.versionOk('1.2.0', '', '1.2.0'), isTrue);
      expect(AnnouncementService.versionOk('1.2.0', '', '1.3.0'), isTrue);
    });

    test('max version gates newer apps', () {
      expect(AnnouncementService.versionOk('', '1.2.0', '1.3.0'), isFalse);
      expect(AnnouncementService.versionOk('', '1.2.0', '1.2.0'), isTrue);
      expect(AnnouncementService.versionOk('', '1.2.0', '1.1.9'), isTrue);
    });
  });

  group('AnnouncementService.compareVersions', () {
    test('dot-separated compare', () {
      expect(AnnouncementService.compareVersions('1.2.0', '1.2.0'), 0);
      expect(AnnouncementService.compareVersions('1.1.9', '1.2.0'), -1);
      expect(AnnouncementService.compareVersions('1.10.0', '1.9.0'), 1);
      expect(AnnouncementService.compareVersions('2.0', '1.99.99'), 1);
    });
  });
}
