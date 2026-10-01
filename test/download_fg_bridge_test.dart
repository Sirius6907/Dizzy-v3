import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/download/download_fg_bridge.dart';

/// Phase K2 — the dataSync notification follows real download state:
/// publishes while work exists, disappears when it doesn't, and buttons
/// come back to Dart. Every platform failure must be swallowed, because a
/// missing foreground service is a lost convenience, never a lost download.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.sirius6907.dizzyv3/downloads');
  final calls = <MethodCall>[];
  var failNext = false;

  setUp(() {
    DownloadFgBridge.resetForTest();
    DownloadFgBridge.onPause = null;
    DownloadFgBridge.onClearAll = null;
    calls.clear();
    failNext = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (failNext) {
            throw PlatformException(
              code: 'FOREGROUND_REFUSED',
              message: 'nope',
            );
          }
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    DownloadFgBridge.resetForTest();
    DownloadFgBridge.onPause = null;
    DownloadFgBridge.onClearAll = null;
  });

  test('publishing active work pushes the aggregate state', () async {
    await DownloadFgBridge.publish(active: 2, percent: 42, label: 'S01E04');

    expect(calls.single.method, 'show');
    final args = calls.single.arguments as Map;
    expect(args['active'], 2);
    expect(args['percent'], 42);
    expect(args['label'], 'S01E04');
    expect(DownloadFgBridge.isRunning, isTrue);
  });

  test(
    'an empty queue stops the service instead of leaving a stale banner',
    () async {
      await DownloadFgBridge.publish(active: 1, percent: 10);
      expect(calls.length, 1);

      await DownloadFgBridge.publish(active: 0, percent: 0);

      expect(calls.map((c) => c.method).toList(), ['show', 'stop']);
      expect(DownloadFgBridge.isRunning, isFalse);
    },
  );

  test('stop is never sent twice in a row', () async {
    await DownloadFgBridge.publish(active: 0, percent: 0);
    await DownloadFgBridge.publish(active: 0, percent: 0);
    expect(calls, isEmpty, reason: 'nothing was running to stop');
  });

  test(
    'percent is clamped — a bad byte count cannot break the service',
    () async {
      await DownloadFgBridge.publish(active: 1, percent: 150);
      expect((calls.single.arguments as Map)['percent'], 100);

      calls.clear();
      await DownloadFgBridge.publish(active: 1, percent: -5);
      expect((calls.single.arguments as Map)['percent'], 0);
    },
  );

  test('the Pause button routes to onPause', () async {
    var paused = 0;
    DownloadFgBridge.onPause = () => paused++;
    DownloadFgBridge.attach();

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'com.sirius6907.dizzyv3/downloads',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onAction', 'pause'),
          ),
          (_) {},
        );
    await pumpEventQueue();

    expect(paused, 1);
  });

  test('the Cancel button routes to onClearAll and marks us stopped', () async {
    var cleared = 0;
    DownloadFgBridge.onClearAll = () => cleared++;
    DownloadFgBridge.attach();
    await DownloadFgBridge.publish(active: 1, percent: 50);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'com.sirius6907.dizzyv3/downloads',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onAction', 'stop'),
          ),
          (_) {},
        );
    await pumpEventQueue();

    expect(cleared, 1);
    expect(DownloadFgBridge.isRunning, isFalse);
  });

  test(
    'a refused foreground service never throws into the download loop',
    () async {
      failNext = true;

      await DownloadFgBridge.publish(active: 3, percent: 12);
      await DownloadFgBridge.stop();

      expect(DownloadFgBridge.isRunning, isFalse);
    },
  );

  test('unknown methods from the service are ignored', () async {
    DownloadFgBridge.attach();
    final reply = await TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .handlePlatformMessage(
          'com.sirius6907.dizzyv3/downloads',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('somethingElse', 'x'),
          ),
          (data) => data,
        );
    expect(reply, isNotNull);
  });
}
