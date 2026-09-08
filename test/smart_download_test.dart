import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/download/smart_download_service.dart';

void main() {
  group('F3 SmartDownloadService', () {
    test('hasSufficientStorage enforces 1 GB floor', () {
      const oneGb = 1024 * 1024 * 1024;
      expect(SmartDownloadService.hasSufficientStorage(oneGb), isTrue);
      expect(SmartDownloadService.hasSufficientStorage(oneGb + 1), isTrue);
      expect(SmartDownloadService.hasSufficientStorage(oneGb - 1), isFalse);
      expect(SmartDownloadService.hasSufficientStorage(0), isFalse);
    });

    test('default preferred quality is 720p', () {
      expect(SmartDownloadService.preferredQuality.value, '720p');
    });

    test('default enabled state is false (opt-in)', () {
      expect(SmartDownloadService.enabled.value, isFalse);
    });
  });
}
