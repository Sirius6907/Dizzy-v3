import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/pages/player/watch_resolve_controller.dart';
import 'package:dizzy/services/player/dub_mode_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// P17: resolve pipeline moved out of the god-file verbatim. These tests
/// drive `start()` through the `scrapeOverride` seam (no network) and pin
/// the screen↔controller contract: batches emitted, loading cleared,
/// English fallback released + noticed, no instant-open when gated.
void main() {
  StreamSource src(String tag) => StreamSource(addonName: tag, title: tag);

  WatchResolveController make({
    Stream<StreamSource>? scrape,
    List<List<StreamSource>>? out,
    void Function()? onDone,
    void Function()? onFallback,
    List<StreamSource>? opened,
    int Function()? hindiReader,
  }) {
    return WatchResolveController(
      type: 'movie',
      streamId: 'id',
      title: 'T',
      mediaTitle: 'T',
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
      expect(out.expand((b) => b).map((s) => s.addonName),
          contains('english-only'));
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

  test('empty flush is a no-op; dispose/cancelAutoplay never throw', () {
    final c = make();
    expect(() => c.flush(), returnsNormally);
    expect(() => c.cancelAutoplay(), returnsNormally);
    expect(() => c.dispose(), returnsNormally);
  });
}
