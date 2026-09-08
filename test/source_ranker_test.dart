import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/stream/source_ranker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dizzy/services/stream/last_good_source_store.dart';

StreamSource _src({
  String addon = 'A',
  String? url,
  String? infoHash,
  String? name,
  String? desc,
}) {
  return StreamSource(
    addonName: addon,
    url: url,
    infoHash: infoHash,
    name: name,
    description: desc,
  );
}

void main() {
  group('SourceRanker', () {
    test('debrid-with-history beats direct-no-history', () {
      final hist = StreamSource(
        addonName: 'TorboxAddon',
        url: 'https://torbox.example/file.mkv',
        name: 'Torbox 1080p',
      );
      final fresh = StreamSource(
        addonName: 'Other',
        url: 'https://cdn.example/file.mkv',
        name: 'CDN 1080p',
      );
      const ctx = RankerContext(
        lastGoodByAddon: {'TorboxAddon': 'x'},
      );
      final ordered = SourceRanker.order([fresh, hist], ctx);
      expect(ordered.first, hist);
    });

    test('failed-this-session sinks below fresh torrent', () {
      final failed = StreamSource(
        addonName: 'A',
        url: 'https://a.example/f.mkv',
        name: '1080p',
      );
      final freshTorrent = StreamSource(
        addonName: 'B',
        infoHash: 'abc123',
        name: '720p 500 seeders',
      );
      final ctx = RankerContext(
        failedThisSession: {SourceRanker.fingerprint(failed)},
      );
      final ordered = SourceRanker.order([failed, freshTorrent], ctx);
      expect(ordered.first, freshTorrent);
    });

    test('higher resolution ranks above lower', () {
      final q1080 = _src(url: 'https://x/f1.mkv', name: '1080p');
      final q720 = _src(url: 'https://x/f2.mkv', name: '720p');
      final ordered = SourceRanker.order([q720, q1080], const RankerContext());
      expect(ordered.first, q1080);
    });

    test('ordering is stable/deterministic on ties', () {
      final a = _src(url: 'https://x/a.mkv');
      final b = _src(url: 'https://x/b.mkv', addon: 'B');
      const ctx = RankerContext();
      final o1 = SourceRanker.order([a, b], ctx);
      final o2 = SourceRanker.order([a, b], ctx);
      expect(identical(o1, o2), isFalse);
      expect(o1.map(SourceRanker.fingerprint).toList(),
          o2.map(SourceRanker.fingerprint).toList());
    });

    test('fingerprint is stable across copyWith', () {
      final s = _src(url: 'https://x/a.mkv');
      expect(
        SourceRanker.fingerprint(s),
        SourceRanker.fingerprint(s.copyWith(name: 'renamed')),
      );
    });

    test('hindi mode: hindi-tagged source beats english same-addon source',
        () {
      final hindi = _src(
          url: 'https://x/h.mkv', name: 'Movie Hindi Dub 1080p');
      final english = _src(
          url: 'https://x/e.mkv', name: 'Movie 1080p BluRay');
      const ctx = RankerContext(preferredLang: 'hindi');
      final ordered = SourceRanker.order([english, hindi], ctx);
      expect(ordered.first, hindi);
    });

    test('hindi mode: hindi beats english even with addon history', () {
      // Real-world bug: history (+40) buried fresh hindi sources, so Hindi
      // mode kept autoplaying English. Language match must beat history.
      final hindi = _src(
          addon: 'NewAddon',
          url: 'https://new/x/h.mkv',
          name: 'Movie Hindi Dub 1080p');
      final english = _src(
          addon: 'KnownGood',
          url: 'https://known/x/e.mkv',
          name: 'Movie 1080p BluRay');
      const ctx = RankerContext(
        lastGoodByAddon: {'KnownGood': 'x'},
        preferredLang: 'hindi',
      );
      final ordered = SourceRanker.order([english, hindi], ctx);
      expect(ordered.first, hindi);
    });

    test('english mode: no language boost changes baseline order', () {
      final a = _src(url: 'https://x/a.mkv', name: '1080p');
      final b = _src(url: 'https://x/b.mkv', name: '720p');
      final plain = SourceRanker.order(
          [b, a], const RankerContext(preferredLang: 'eng'));
      final noLang =
          SourceRanker.order([b, a], const RankerContext());
      expect(
        plain.map(SourceRanker.fingerprint).toList(),
        noLang.map(SourceRanker.fingerprint).toList(),
      );
    });
  });

  group('LastGoodSourceStore', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('record then addonHistoryFor returns the addon', () async {
      final src = StreamSource(
          addonName: 'BestAddon', url: 'https://x/y.mkv', name: 'n');
      await LastGoodSourceStore.record(
          titleKey: 'imdb:tt1', source: src);
      final hist = await LastGoodSourceStore.addonHistoryFor(titleKey: 'imdb:tt1');
      expect(hist, containsPair('BestAddon', anything));
    });

    test('corrupt JSON returns empty map (no throw)', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_good_sources_v1', 'not-json{{{{');
      final map = await LastGoodSourceStore.load();
      expect(map, isEmpty);
    });

    test('episode key recorded alongside title key', () async {
      final src = StreamSource(
          addonName: 'Ep', url: 'https://x/e.mkv', name: 'n');
      await LastGoodSourceStore.record(
          titleKey: 'imdb:tt2', episodeKey: 'imdb:tt2:S1E3', source: src);
      final hist = await LastGoodSourceStore.addonHistoryFor(
          titleKey: 'imdb:tt2', episodeKey: 'imdb:tt2:S1E3');
      expect(hist.containsKey('Ep'), isTrue);
    });

    test('LRU evicts beyond 200 entries', () async {
      final src = _src(url: 'https://x/z.mkv');
      for (var i = 0; i < 205; i++) {
        await LastGoodSourceStore.record(titleKey: 'k$i', source: src);
      }
      final map = await LastGoodSourceStore.load();
      expect(map.length, lessThanOrEqualTo(200));
    });
  });
}
