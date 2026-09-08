import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/metadata/watched_history_import_service.dart';

void main() {
  group('F4 WatchedHistoryImportService', () {
    test('mergeWatchedIds performs union and preserves all local IDs', () {
      final local = {'tt0137523', 'tt0111161'};
      final remote = {'tt0111161', 'tt0068646'};
      final merged = WatchedHistoryImportService.mergeWatchedIds(local, remote);
      expect(merged, {'tt0137523', 'tt0111161', 'tt0068646'});
      expect(merged.containsAll(local), isTrue);
    });

    test('empty remote returns identical local set', () {
      final local = {'tt0137523'};
      final merged = WatchedHistoryImportService.mergeWatchedIds(local, {});
      expect(merged, local);
    });
  });
}
