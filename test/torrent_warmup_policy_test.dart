import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/stream/torrent_warmup_policy.dart';

void main() {
  TorrentReadiness evaluate({
    int loaded = 0,
    int peers = 0,
    int speed = 0,
    int grewSecondsAgo = 99,
    int elapsed = 1,
  }) =>
      TorrentWarmupPolicy.evaluate(
        loadedBytes: loaded,
        activePeers: peers,
        speedBps: speed,
        sinceBytesGrew: Duration(seconds: grewSecondsAgo),
        elapsed: Duration(seconds: elapsed),
      );

  group('ready', () {
    test('2 MB buffered is ready immediately', () {
      expect(
        evaluate(loaded: 2 * 1024 * 1024, peers: 3, elapsed: 1),
        TorrentReadiness.ready,
      );
    });

    test('slow but sustainable swarm starts after the floor', () {
      expect(
        evaluate(
          loaded: 600 * 1024,
          peers: 12,
          speed: 1300 * 1024,
          grewSecondsAgo: 0,
          elapsed: 4,
        ),
        TorrentReadiness.ready,
      );
    });

    test('at the ceiling, a grown buffer still opens', () {
      expect(
        evaluate(
          loaded: 600 * 1024,
          peers: 2,
          speed: 10 * 1024,
          grewSecondsAgo: 1,
          elapsed: 15,
        ),
        TorrentReadiness.ready,
      );
    });
  });

  group('hopeless', () {
    test('zero active peers after the grace (DHT size lies)', () {
      // 500 total peers in the wild looked exactly like this.
      expect(
        evaluate(loaded: 0, peers: 0, elapsed: 9),
        TorrentReadiness.hopeless,
      );
    });

    test('peers connected but bytes frozen', () {
      expect(
        evaluate(loaded: 250 * 1024, peers: 51, grewSecondsAgo: 10, elapsed: 12),
        TorrentReadiness.hopeless,
      );
    });

    test('still empty at the ceiling', () {
      expect(
        evaluate(loaded: 0, peers: 4, speed: 5000, elapsed: 15),
        TorrentReadiness.hopeless,
      );
    });
  });

  group('warming', () {
    test('first seconds are neither ready nor dead', () {
      expect(
        evaluate(loaded: 240 * 1024, peers: 1, grewSecondsAgo: 1, elapsed: 2),
        TorrentReadiness.warming,
      );
    });

    test('no peers yet but still inside the grace window', () {
      expect(evaluate(loaded: 0, peers: 0, elapsed: 5), TorrentReadiness.warming);
    });
  });

  test('minimum sustainable throughput has headroom', () {
    expect(TorrentWarmupPolicy.minimumSustainableBps(0), 0);
    expect(
      TorrentWarmupPolicy.minimumSustainableBps(8000000),
      greaterThan(8000000),
    );
  });
}
