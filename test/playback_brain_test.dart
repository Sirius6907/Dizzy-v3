import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/player/playback_brain.dart';

void main() {
  group('P6: state machine', () {
    test('happy path idle → resolving → buffering → playing', () {
      final b = PlaybackBrain();
      expect(b.state, PlaybackState.idle);
      b.startResolve();
      expect(b.state, PlaybackState.resolving);
      b.onBuffering();
      expect(b.state, PlaybackState.buffering);
      b.onPlaying();
      expect(b.state, PlaybackState.playing);
    });

    test('illegal moves are ignored (stray late events)', () {
      final b = PlaybackBrain();
      expect(b.move(PlaybackState.playing), isFalse); // idle → playing illegal
      expect(b.state, PlaybackState.idle);
      b.startResolve();
      expect(b.move(PlaybackState.playing), isFalse); // skip buffering
      expect(b.state, PlaybackState.resolving);
    });

    test('error → resolving retry, error → idle give-up', () {
      final b = PlaybackBrain()
        ..startResolve()
        ..onBuffering();
      b.onError('boom');
      expect(b.state, PlaybackState.error);
      b.startResolve();
      expect(b.state, PlaybackState.resolving);
    });

    test('onError remembers dead url + easy message, reset clears', () {
      final b = PlaybackBrain()..startResolve();
      final msg = b.onError('Connection timed out', deadUrl: 'http://a/x.mp4');
      expect(b.isUrlFailed('http://a/x.mp4'), isTrue);
      expect(msg, isNotEmpty);
      b.reset();
      expect(b.state, PlaybackState.idle);
      expect(b.isUrlFailed('http://a/x.mp4'), isFalse);
      expect(b.switches, 0);
    });
  });

  group('P6: url classification', () {
    test('direct / hls / torrent / debrid / empty', () {
      expect(PlaybackBrain.classifyUrl('https://cdn/a/movie.mp4'),
          SourceKind.direct);
      expect(PlaybackBrain.classifyUrl('https://cdn/a/master.m3u8?tok=1'),
          SourceKind.hlsMaster);
      expect(PlaybackBrain.classifyUrl('magnet:?xt=urn:btih:abc'),
          SourceKind.torrent);
      expect(PlaybackBrain.classifyUrl('https://real-debrid.com/dl/xyz'),
          SourceKind.debrid);
      expect(PlaybackBrain.classifyUrl(''), SourceKind.unknown);
    });

    test('kindOverride wins', () {
      const s = BrainSource(
          url: 'https://x/y.mp4',
          label: 't',
          kindOverride: SourceKind.torrent);
      expect(s.kind, SourceKind.torrent);
    });
  });

  group('P6: attempt plan — direct → HLS → lower rendition → next source', () {
    test('main url first, renditions high → low after', () {
      final sources = [
        const BrainSource(url: 'https://cdn/a/master.m3u8', label: 'A', renditions: [
          BrainRendition(label: '480p', url: 'https://cdn/a/480.m3u8', bitrate: 800000),
          BrainRendition(label: '1080p', url: 'https://cdn/a/1080.m3u8', bitrate: 5000000),
        ]),
      ];
      final plan = PlaybackBrain().buildPlan(sources);
      expect(plan.map((p) => p.url), [
        'https://cdn/a/master.m3u8',
        'https://cdn/a/1080.m3u8',
        'https://cdn/a/480.m3u8',
      ]);
      expect(plan.first.reason, 'hls-master');
    });

    test('http sources come before torrents (instant feel first)', () {
      final sources = [
        const BrainSource(url: 'magnet:?xt=urn:btih:abc', label: 'T'),
        const BrainSource(url: 'https://cdn/b/f.mp4', label: 'H'),
      ];
      final plan = PlaybackBrain().buildPlan(sources);
      expect(plan.first.url, 'https://cdn/b/f.mp4');
      expect(plan.last.url, startsWith('magnet:'));
    });

    test('dead urls are skipped', () {
      final b = PlaybackBrain()..onError('x', deadUrl: 'https://cdn/a.mp4');
      final plan = b.buildPlan([
        const BrainSource(url: 'https://cdn/a.mp4', label: 'A'),
        const BrainSource(url: 'https://cdn/b.mp4', label: 'B'),
      ]);
      expect(plan.map((p) => p.url), ['https://cdn/b.mp4']);
    });
  });

  group('P6: switch policy', () {
    test('nextAfterFailure steps through plan then stops at cap', () {
      final b = PlaybackBrain();
      final sources = [
        const BrainSource(url: 'https://cdn/a.mp4', label: 'A'),
        const BrainSource(url: 'https://cdn/b.mp4', label: 'B'),
      ];
      final n1 = b.nextAfterFailure(sources, 'https://cdn/a.mp4');
      expect(n1?.url, 'https://cdn/b.mp4');
      expect(b.switches, 1);
      // Exhaust: fail b too → null (plan empty).
      final n2 = b.nextAfterFailure(sources, 'https://cdn/b.mp4');
      expect(n2, isNull);
    });

    test('cap stops auto-switch even with candidates left', () {
      final b = PlaybackBrain();
      final sources = [
        for (var i = 0; i < 6; i++)
          BrainSource(url: 'https://cdn/$i.mp4', label: 'S$i'),
      ];
      BrainAttempt? n;
      for (var i = 0; i < 6; i++) {
        n = b.nextAfterFailure(sources, 'https://cdn/$i.mp4',
            maxSwitches: 3);
        if (n == null) break;
      }
      expect(b.switches, 3);
      expect(n, isNull);
      expect(b.canAutoSwitch(maxSwitches: 3), isFalse);
    });
  });

  group('P6: easy errors — no tech words', () {
    const banned = [
      'mpv', 'ffmpeg', 'averror', 'codec', 'demuxer',
      'ffurl', 'exception', 'stacktrace', 'null',
    ];

    String check(String raw) {
      final msg = PlaybackBrain.easyErrorMessage(raw);
      for (final w in banned) {
        expect(msg.toLowerCase().contains(w), isFalse,
            reason: '"$w" leaked into "$msg"');
      }
      return msg;
    }

    test('network blip', () {
      expect(check('tcp: ffurl_read timed out'), contains('Slow connection'));
    });
    test('dns dead', () {
      expect(check('Failed to resolve no such host'), contains('internet'));
    });
    test('403 / 404 / 5xx / 401', () {
      expect(check('Server returned 403 Forbidden'), contains('said no'));
      expect(check('404 not found'), contains('gone'));
      expect(check('Server returned 503'), contains('trouble'));
      expect(check('401 unauthorized'), contains('login'));
    });
    test('torrent with no peers', () {
      expect(check('magnet: no seeds found'), contains('sharing'));
    });
    test('unplayable format', () {
      expect(check('Failed to recognize file format'), contains('video type'));
    });
    test('unknown garbage still friendly', () {
      expect(check('xyzzy ¯\\_(ツ)_/¯'), contains('will not play'));
    });
    test('all-failed message points to picker', () {
      expect(PlaybackBrain.allFailedMessage, contains('Pick another'));
    });
  });
}
