import 'dart:async';

import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/pages/player/watch_resolve_controller.dart';
import 'package:dizzy/services/player/dub_mode_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// P17: resolve pipeline moved out of the god-file verbatim. These tests
/// drive `start()` through the `scrapeOverride` seam (no network) and pin
/// the screen↔controller contract: batches emitted, loading cleared,
/// English fallback released + noticed, no instant-open when gated.
void main() {
  setUp(() => DubModeService.mode.value = AudioDubMode.english);
  tearDown(() => DubModeService.mode.value = AudioDubMode.english);

  StreamSource src(String tag) => StreamSource(addonName: tag, title: tag);

  WatchResolveController make({
    Stream<StreamSource>? scrape,
    List<List<StreamSource>>? out,
    void Function()? onDone,
    void Function()? onFallback,
    List<StreamSource>? opened,
    int Function()? hindiReader,
    String type = 'movie',
    String title = 'T',
    int? year,
    int? season,
    int? episode,
  }) {
    return WatchResolveController(
      type: type,
      streamId: 'id',
      title: title,
      year: year,
      season: season,
      episode: episode,
      mediaTitle: title,
      embeddedStreams: const [],
      isMounted: () => true,
      shouldAutoOpen: () => false,
      hindiCountReader: hindiReader ?? () => 99,
      onBatch: (b) => out?.add(b),
      onLoadingDone: () => onDone?.call(),
      onInstantOpen: (s) => opened?.add(s),
      onEnglishFallback: () => onFallback?.call(),
      scrapeOverride: scrape,
    );
  }

  test('scraped sources arrive as batches + loading clears', () async {
    final out = <List<StreamSource>>[];
    var done = false;
    final c = make(
      scrape: Stream.fromIterable([src('a'), src('b')]),
      out: out,
      onDone: () => done = true,
    );
    await c.start();
    c.dispose();
    expect(out.expand((b) => b).map((s) => s.addonName), ['a', 'b']);
    expect(done, isTrue);
  });

  test('hindi mode with zero hindi: pool released + notice shown', () async {
    DubModeService.mode.value = AudioDubMode.hindi;
    try {
      final out = <List<StreamSource>>[];
      var noticed = false;
      final c = make(
        scrape: Stream.fromIterable([src('english-only')]),
        out: out,
        hindiReader: () => 0,
        onFallback: () => noticed = true,
      );
      await c.start();
      c.dispose();
      expect(
        out.expand((b) => b).map((s) => s.addonName),
        contains('english-only'),
      );
      expect(noticed, isTrue);
    } finally {
      DubModeService.mode.value = AudioDubMode.english;
    }
  });

  test('hindi mode with hindi present: pool held, no notice', () async {
    DubModeService.mode.value = AudioDubMode.hindi;
    try {
      var noticed = false;
      final c = make(
        scrape: Stream.fromIterable([src('x')]),
        hindiReader: () => 1,
        onFallback: () => noticed = true,
      );
      await c.start();
      c.dispose();
      expect(noticed, isFalse);
    } finally {
      DubModeService.mode.value = AudioDubMode.english;
    }
  });

  group('hindi-first bounded fallback', () {
    StreamSource tagged(String tag, String language) => StreamSource(
      addonName: tag,
      title: tag,
      description: 'Audio: $language',
      url: 'https://example.com/$tag.m3u8',
    );

    WatchResolveController makeLive({
      required Stream<StreamSource> scrape,
      required bool Function(StreamSource) alive,
      required List<StreamSource> opened,
      required List<StreamSource> exposed,
      required void Function() onFallback,
    }) {
      return WatchResolveController(
        type: 'movie',
        streamId: 'id',
        title: 'T',
        mediaTitle: 'T',
        embeddedStreams: const [],
        isMounted: () => true,
        shouldAutoOpen: () => true,
        hindiCountReader: () => 99,
        onBatch: exposed.addAll,
        onLoadingDone: () {},
        onInstantOpen: opened.add,
        onEnglishFallback: onFallback,
        scrapeOverride: scrape,
        hindiFirstWindow: const Duration(milliseconds: 50),
        probeFn: (source) async => alive(source),
      );
    }

    test('dead Hindi cannot starve a live English source or black-screen',
        () async {
      DubModeService.mode.value = AudioDubMode.hindi;
      final feed = StreamController<StreamSource>();
      final opened = <StreamSource>[];
      final exposed = <StreamSource>[];
      var notices = 0;
      final c = makeLive(
        scrape: feed.stream,
        alive: (s) => s.addonName == 'english-alive',
        opened: opened,
        exposed: exposed,
        onFallback: () => notices++,
      );
      c.start();
      feed.add(tagged('hindi-dead', 'Hindi'));
      feed.add(tagged('english-alive', 'English'));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(opened, isEmpty);
      expect(notices, 0);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(opened.map((s) => s.addonName), ['english-alive']);
      expect(exposed.map((s) => s.addonName), contains('english-alive'));
      expect(notices, 1);

      c.dispose();
      await feed.close();
      DubModeService.mode.value = AudioDubMode.english;
    });

    test('a playable Hindi source wins inside the window and suppresses the '
        'fallback notice', () async {
      DubModeService.mode.value = AudioDubMode.hindi;
      final feed = StreamController<StreamSource>();
      final opened = <StreamSource>[];
      var notices = 0;
      final c = makeLive(
        scrape: feed.stream,
        alive: (s) => true,
        opened: opened,
        exposed: <StreamSource>[],
        onFallback: () => notices++,
      );
      c.start();
      feed.add(tagged('hindi-alive', 'Hindi'));
      feed.add(tagged('english-alive', 'English'));

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(opened.map((s) => s.addonName), ['hindi-alive']);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(opened.length, 1);
      expect(notices, 0);

      c.dispose();
      await feed.close();
      DubModeService.mode.value = AudioDubMode.english;
    });

    test('no Hindi at all releases English before slow discovery finishes',
        () async {
      DubModeService.mode.value = AudioDubMode.hindi;
      final feed = StreamController<StreamSource>();
      final opened = <StreamSource>[];
      var notices = 0;
      final c = makeLive(
        scrape: feed.stream,
        alive: (s) => true,
        opened: opened,
        exposed: <StreamSource>[],
        onFallback: () => notices++,
      );
      c.start();
      feed.add(tagged('english-alive', 'English'));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(opened, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(opened.map((s) => s.addonName), ['english-alive']);
      expect(notices, 1);

      // A later Hindi source must not replay the notice or restart playback.
      feed.add(tagged('hindi-late', 'Hindi'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(notices, 1);
      expect(opened.map((s) => s.addonName), ['english-alive']);

      c.dispose();
      await feed.close();
      DubModeService.mode.value = AudioDubMode.english;
    });
  });

  test('empty flush is a no-op; dispose/cancelAutoplay never throw', () {
    final c = make();
    expect(() => c.flush(), returnsNormally);
    expect(() => c.cancelAutoplay(), returnsNormally);
    expect(() => c.dispose(), returnsNormally);
  });

  test('torrent-only movie autoplays the best-seeded torrent', () async {
    final opened = <StreamSource>[];
    final c = WatchResolveController(
      type: 'movie',
      streamId: 'tt1',
      title: 'Godzilla Minus Zero',
      year: 2026,
      mediaTitle: 'Godzilla Minus Zero',
      embeddedStreams: const [],
      isMounted: () => true,
      shouldAutoOpen: () => true,
      hindiCountReader: () => 99,
      onBatch: (_) {},
      onLoadingDone: () {},
      onInstantOpen: opened.add,
      onEnglishFallback: () {},
      scrapeOverride: Stream.fromIterable([
        StreamSource(
          addonName: 'torrentio',
          title: 'Godzilla Minus Zero 1080p 👤 12',
          infoHash: 'aaa',
        ),
        StreamSource(
          addonName: 'torrentio',
          title: 'Godzilla Minus Zero 1080p 👤 900',
          infoHash: 'bbb',
        ),
      ]),
      // Every HTTP probe fails; torrents carry no URL to probe.
      probeFn: (_) async => false,
    );
    await c.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c.dispose();
    expect(opened.map((s) => s.infoHash), ['bbb']);
  });

  group('episode relevance gate', () {
    StreamSource titled(String title) => StreamSource(
      addonName: title,
      title: title,
      url: 'https://example.com/${Uri.encodeComponent(title)}.mkv',
    );

    test('wrong show and wrong episode never reach the list or autoplay',
        () async {
      final out = <List<StreamSource>>[];
      final opened = <StreamSource>[];
      final c = WatchResolveController(
        type: 'series',
        streamId: 'tt1',
        title: 'Nocturne',
        year: 2026,
        season: 1,
        episode: 2,
        mediaTitle: 'Nocturne',
        embeddedStreams: const [],
        isMounted: () => true,
        shouldAutoOpen: () => true,
        hindiCountReader: () => 99,
        onBatch: (b) => out.add(b),
        onLoadingDone: () {},
        onInstantOpen: opened.add,
        onEnglishFallback: () {},
        scrapeOverride: Stream.fromIterable([
          titled('Castlevania Nocturne (2023) S01E01 A Common Enemy in Evil'),
          titled('Nocturne (2026) - S01E01 - Lazarus Come Forth!'),
          titled('Nocturne (2026) - S01E02 - For Such a Time as This'),
        ]),
        probeFn: (_) async => true,
      );
      await c.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      c.dispose();

      expect(
        out.expand((b) => b).map((s) => s.title),
        ['Nocturne (2026) - S01E02 - For Such a Time as This'],
      );
      expect(
        opened.map((s) => s.title),
        ['Nocturne (2026) - S01E02 - For Such a Time as This'],
      );
    });

    test('keeps an untitled source: missing metadata is not a mismatch',
        () async {
      final plain = StreamSource(
        addonName: 'plain',
        url: 'https://example.com/plain.mkv',
      );
      final out = <List<StreamSource>>[];
      final c = WatchResolveController(
        type: 'series',
        streamId: 'tt1',
        title: 'Nocturne',
        year: 2026,
        season: 1,
        episode: 2,
        mediaTitle: 'Nocturne',
        embeddedStreams: const [],
        isMounted: () => true,
        shouldAutoOpen: () => false,
        hindiCountReader: () => 99,
        onBatch: (b) => out.add(b),
        onLoadingDone: () {},
        onInstantOpen: (_) {},
        onEnglishFallback: () {},
        scrapeOverride: Stream.fromIterable([plain]),
      );
      await c.start();
      c.dispose();
      expect(out.expand((b) => b), [plain]);
    });
  });
}
