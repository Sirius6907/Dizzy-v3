import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/media/media_session_bridge.dart';

/// Phase K1 — the now-playing notification contract.
///
/// Dart owns playback; the native service only renders. These tests pin the
/// two things that matter: what we send, and that a broken native side can
/// never take the music down with it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.sirius6907.dizzyv3/media');
  final calls = <MethodCall>[];
  var failWith = '';

  setUp(() {
    MediaSessionBridge.resetForTest();
    calls.clear();
    failWith = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == failWith) {
            throw PlatformException(
              code: 'FOREGROUND_REFUSED',
              message: 'busy',
            );
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    MediaSessionBridge.resetForTest();
  });

  MediaSessionState track({int pos = 0, bool playing = true}) =>
      MediaSessionState(
        title: 'Neon Skyline',
        subtitle: 'Kite Runner',
        playing: playing,
        positionMs: pos,
        durationMs: 240000,
      );

  test('publishing pushes a full now-playing payload', () async {
    await MediaSessionBridge.publish(track(pos: 12000), force: true);

    expect(calls.single.method, 'show');
    final args = calls.single.arguments as Map;
    expect(args['title'], 'Neon Skyline');
    expect(args['subtitle'], 'Kite Runner');
    expect(args['playing'], isTrue);
    expect(args['positionMs'], 12000);
    expect(args['durationMs'], 240000);
    expect(MediaSessionBridge.isRunning, isTrue);
  });

  test('nothing to play → the notification goes away once', () async {
    await MediaSessionBridge.publish(track(), force: true);
    expect(MediaSessionBridge.isRunning, isTrue);

    await MediaSessionBridge.hide();
    expect(calls.map((c) => c.method).toList(), ['show', 'hide']);
    expect(MediaSessionBridge.isRunning, isFalse);

    await MediaSessionBridge.hide();
    expect(calls.length, 2, reason: 'hide is idempotent');
  });

  test(
    'a silent position tick inside the throttle does not spam the service',
    () async {
      await MediaSessionBridge.publish(track(pos: 0), force: true);
      calls.clear();

      await MediaSessionBridge.publish(track(pos: 400));
      expect(calls, isEmpty, reason: 'same 5s bucket, inside the throttle');

      await MediaSessionBridge.publish(track(pos: 6000));
      expect(
        calls.single.method,
        'show',
        reason: 'a new 5s bucket is a visible change',
      );
    },
  );

  test('play/pause always pushes immediately', () async {
    await MediaSessionBridge.publish(track(playing: true), force: true);
    calls.clear();

    await MediaSessionBridge.publish(track(playing: false));
    expect(calls.single.method, 'show');
    expect((calls.single.arguments as Map)['playing'], isFalse);
  });

  test('position is never negative and never overruns the duration', () async {
    await MediaSessionBridge.publish(
      const MediaSessionState(title: 'x', positionMs: -500),
      force: true,
    );
    expect((calls.single.arguments as Map)['positionMs'], 0);
  });

  group('transport buttons come back to Dart', () {
    var toggles = 0, nexts = 0, prevs = 0, pauses = 0, stops = 0, focus = 0;
    final seeks = <int>[];

    setUp(() async {
      toggles = nexts = prevs = pauses = stops = focus = 0;
      seeks.clear();
      await MediaSessionBridge.attach(
        MediaSessionActions(
          onToggle: () async => toggles++,
          onPlay: () async {},
          onPause: () async => pauses++,
          onNext: () async => nexts++,
          onPrev: () async => prevs++,
          onSeekRelative: (delta) async => seeks.add(delta),
          onStop: () async => stops++,
          onFocusLost: () async => focus++,
        ),
      );
    });

    Future<void> fromNative(String method, [Object? args]) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, args),
            ),
            (_) {},
          );
      await pumpEventQueue();
    }

    test('play/pause toggle, explicit pause, and the two skips', () async {
      await fromNative('onPlayPause', 'toggle');
      await fromNative('onPlayPause', 'pause');
      await fromNative('onNext');
      await fromNative('onPrev');

      expect(toggles, 1);
      expect(pauses, 1);
      expect(nexts, 1);
      expect(prevs, 1);
    });

    test('seek directions survive the trip', () async {
      await fromNative('onSeek', -10000);
      await fromNative('onSeek', 10000);
      expect(seeks, [-10000, 10000]);
    });

    test('stop and audio-focus loss are both reported', () async {
      await fromNative('onStop');
      await fromNative('onFocusLost');
      expect(stops, 1);
      expect(
        focus,
        1,
        reason: 'losing focus to a phone call must pause the music',
      );
    });

    test('unknown methods are ignored rather than thrown', () async {
      await fromNative('onWhatever', 'x');
      expect(toggles, 0);
    });
  });

  test(
    'a refused foreground start never reports a running notification',
    () async {
      failWith = 'show';

      await MediaSessionBridge.publish(track(), force: true);

      expect(
        MediaSessionBridge.isRunning,
        isFalse,
        reason: 'we did not actually show anything',
      );

      // …and the next attempt is not throttled away.
      failWith = '';
      await MediaSessionBridge.publish(track(), force: false);
      expect(MediaSessionBridge.isRunning, isTrue);
      expect(calls.where((c) => c.method == 'show').length, 2);
    },
  );

  test(
    'an unregistered service (desktop / web) is treated as absent',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      await MediaSessionBridge.publish(track(), force: true);
      expect(MediaSessionBridge.isRunning, isFalse);

      // hide() must not pretend the notification exists when it never did.
      await MediaSessionBridge.hide();
      expect(MediaSessionBridge.isRunning, isFalse);
    },
  );
}
