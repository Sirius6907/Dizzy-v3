import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/pages/player/embed_webview_player.dart';
import 'package:dizzy/rust/api.dart';
import 'package:dizzy/rust/frb_generated.dart';

void main() {
  group('resource typing', () {
    test('main frame is a document, assets map by shape', () {
      expect(
        EmbedWebviewPlayer.resourceTypeFor(
          'https://vidfast.vc/movie/550',
          isForMainFrame: true,
        ),
        'document',
      );
      expect(
        EmbedWebviewPlayer.resourceTypeFor('https://cdn.site/app.js'),
        'script',
      );
      expect(
        EmbedWebviewPlayer.resourceTypeFor('https://cdn.site/app.css'),
        'stylesheet',
      );
      expect(
        EmbedWebviewPlayer.resourceTypeFor('https://cdn.site/poster.webp'),
        'image',
      );
      expect(
        EmbedWebviewPlayer.resourceTypeFor('https://cdn.site/font.woff2'),
        'font',
      );
      expect(
        EmbedWebviewPlayer.resourceTypeFor(
          'https://cdn.site/hls/550/index.m3u8?sig=abc',
        ),
        'media',
      );
      expect(
        EmbedWebviewPlayer.resourceTypeFor('https://api.site/v1/session'),
        'xhr',
      );
    });

    test('media URLs exclude segments and subtitles', () {
      expect(
        EmbedWebviewPlayer.isMediaUrl('https://cdn/a/index.m3u8?t=1'),
        isTrue,
      );
      expect(EmbedWebviewPlayer.isMediaUrl('https://cdn/a/movie.mp4'), isTrue);
      expect(EmbedWebviewPlayer.isMediaUrl('https://cdn/a/seg-0001.ts'), isFalse);
      expect(EmbedWebviewPlayer.isMediaUrl('https://cdn/a/seg-1.m4s'), isFalse);
      expect(EmbedWebviewPlayer.isMediaUrl('https://cdn/a/sub.vtt'), isFalse);
      expect(EmbedWebviewPlayer.isMediaUrl('https://cdn/a/manifest.mpd'), isTrue);
    });
  });

  group('block decisions (native engine)', () {
    final dll = File(
      'rust/dizzy_adblock/target/x86_64-pc-windows-msvc/release/dizzy_adblock.dll',
    );
    final available = Platform.isWindows && dll.existsSync();
    final skipReason = available ? null : 'native adblock lib not built here';

    setUpAll(() async {
      if (!available) return;
      await RustLib.init(externalLibrary: ExternalLibrary.open(dll.path));
    });

    test('blocks an ad host and always allows the page document', () async {
      final engine = await newEngine(
        rules: const ['||vinnyvower.cfd^', '||googletagmanager.com^'],
      );

      expect(
        await EmbedWebviewPlayer.shouldBlock(
          engine,
          'https://vinnyvower.cfd/cuid/',
          'vidfast.vc',
          'xhr',
        ),
        isTrue,
      );
      expect(
        await EmbedWebviewPlayer.shouldBlock(
          engine,
          'https://googletagmanager.com/gtag/js',
          'vidfast.vc',
          'script',
        ),
        isTrue,
      );
      // The embed page itself is never blocked, even if a list says so.
      expect(
        await EmbedWebviewPlayer.shouldBlock(
          engine,
          'https://vidfast.vc/movie/550',
          'vidfast.vc',
          'document',
        ),
        isFalse,
      );
      expect(
        await EmbedWebviewPlayer.shouldBlock(
          engine,
          'https://cdn.example/hls/550/index.m3u8',
          'vidfast.vc',
          'media',
        ),
        isFalse,
      );
    }, skip: skipReason);
  });
}
