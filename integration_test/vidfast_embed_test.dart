import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:media_kit/media_kit.dart';

import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/pages/player/embed_webview_player.dart';
import 'package:dizzy/rust/frb_generated.dart';

/// ON-DEVICE proof of the M1 assumption.
///
/// Run (emulator, keys injected like a release build):
///   flutter test integration_test/vidfast_embed_test.dart \
///     -d emulator-5554 --dart-define-from-file=.env
///
/// It answers the two questions the plan says M1 must prove before anything
/// else is built on top:
///   1. does VidFast's embed play inside an Android WebView at all
///      (the site has a TLS/JS protection gate), and
///   2. does the intercepted traffic contain a media URL we can hand to mpv.
///
/// A failure here is a REAL finding (the gate blocks WebView), not a test bug:
/// the widget then falls back to in-webview playback, which is still ad-free
/// but cannot hand off to mpv.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // The shipped app initializes these in main(); a widget test must do it
    // itself or the engine silently degrades to "allow everything".
    await RustLib.init();
    MediaKit.ensureInitialized();
  });

  testWidgets('vidfast embed captures a media URL in the adblocked webview', (
    tester,
  ) async {
    final captured = Completer<CapturedMedia>();
    final source = StreamSource(
      name: 'VidFast',
      addonName: 'vidfast',
      title: 'VidFast · Embed',
      externalUrl: 'https://vidfast.vc/movie/550?autoPlay=true',
      behaviorHints: const {'dizzyEmbed': true},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: EmbedWebviewPlayer(
            source: source,
            onMediaCaptured: (media) {
              if (!captured.isCompleted) captured.complete(media);
            },
          ),
        ),
      ),
    );
    await tester.pump();

    // Frames must keep flowing: the webview is a platform view, and a single
    // pump leaves it unattached (the widget then cannot intercept anything).
    // Every real second of waiting is paired with a pump.
    for (var second = 0; second < 150 && !captured.isCompleted; second++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pump();
    }

    expect(
      captured.isCompleted,
      isTrue,
      reason:
          'No media URL was captured from the VidFast embed within 150 s. '
          'Either the embed gate blocks WebView, or the player never issued a '
          'm3u8/mp4 request (the in-webview fallback keeps playback alive).',
    );
    final media = await captured.future;
    expect(media.url, isNotEmpty);
    expect(media.headers['Referer'], isNotNull);
    debugPrint('[M1] captured media from ${Uri.parse(media.url).host}');

    // ── The actual handoff ────────────────────────────────────────────
    // A captured URL is only useful if mpv accepts it with the captured
    // Referer. Position advancing past 2 s is the proof that bytes decoded
    // (a URL that 403s would leave position at 0 and log an error).
    final player = Player();
    try {
      await player.open(
        Media(media.url, httpHeaders: media.headers),
        play: true,
      );
      var position = Duration.zero;
      for (var second = 0; second < 45; second++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 1)),
        );
        await tester.pump();
        position = player.state.position;
        if (position.inSeconds >= 2) break;
      }
      debugPrint('[M1] mpv position after handoff: ${position.inSeconds}s');
      expect(
        position.inSeconds >= 2,
        isTrue,
        reason:
            'mpv did not advance on the captured URL within 45 s — the CDN '
            'refused the handoff (Referer/UA/token) even though the webview '
            'was playing it.',
      );
    } finally {
      await player.dispose();
    }
  });
}
