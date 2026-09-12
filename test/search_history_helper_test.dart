import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/search/search_history_helper.dart';

/// Polish P6: history rules frozen — 50 stored, 10 shown, bump-to-top.
void main() {
  group('SearchHistoryHelper', () {
    test('empty query leaves history unchanged', () {
      expect(SearchHistoryHelper.add(['a'], '   '), ['a']);
    });

    test('new query goes to top', () {
      expect(SearchHistoryHelper.add(['b', 'c'], 'a'), ['a', 'b', 'c']);
    });

    test('re-search bumps to top without dupes', () {
      expect(SearchHistoryHelper.add(['a', 'b', 'c'], 'c'), ['c', 'a', 'b']);
    });

    test('caps at 50 stored', () {
      final full = List<String>.generate(50, (i) => 'q$i');
      final next = SearchHistoryHelper.add(full, 'new');
      expect(next, hasLength(50));
      expect(next.first, 'new');
    });

    test('shown caps at 10', () {
      final full = List<String>.generate(30, (i) => 'q$i');
      expect(SearchHistoryHelper.shown(full), hasLength(10));
    });

    test('remove drops the entry', () {
      expect(SearchHistoryHelper.remove(['a', 'b'], 'a'), ['b']);
    });
  });
}
