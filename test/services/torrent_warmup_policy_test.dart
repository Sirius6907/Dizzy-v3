import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/stream/torrent_warmup_policy.dart';

void main() {
  group('TorrentWarmupPolicy', () {
    test('2 MB buffered is ready regardless of the clock', () {
      expect(
        TorrentWarmupPolicy.evaluate(
          loadedBytes: 2 * 1024 * 1024,
          activePeers: 0,
          speedBps: 0,
          sinceBytesGrew: const Duration(seconds: 30),
          elapsed: const Duration(seconds: 1),
        ),
        TorrentReadiness.ready,
      );
    });

    test('a slow-but-sustainable swarm becomes ready once it has data', () {
      expect(
        TorrentWarmupPolicy.evaluate(
          loadedBytes: 512 * 1024 + 1,
          activePeers: 3,
          speedBps: TorrentWarmupPolicy.healthySpeedBps,
          sinceBytesGrew: Duration.zero,
          elapsed: const Duration(seconds: 3),
        ),
        TorrentReadiness.ready,
      );
    });

    test('slow swarm below the minimum start floor keeps warming', () {
      expect(
        TorrentWarmupPolicy.evaluate(
          loadedBytes: 100 * 1024,
          activePeers: 4,
          speedBps: 100 * 1024,
          sinceBytesGrew: Duration.zero,
          elapsed: const Duration(seconds: 5),
        ),
        TorrentReadiness.warming,
      );
    });

    test('no active peers after the grace is hopeless', () {
      expect(
        TorrentWarmupPolicy.evaluate(
          loadedBytes: 0,
          activePeers: 0,
          speedBps: 0,
          sinceBytesGrew: const Duration(seconds: 8),
          elapsed: TorrentWarmupPolicy.peerGrace,
        ),
        TorrentReadiness.hopeless,
      );
    });

    test('listed DHT peers without activity still warm (not hopeless yet)', () {
      expect(
        TorrentWarmupPolicy.evaluate(
          loadedBytes: 0,
          activePeers: 0,
          speedBps: 0,
          sinceBytesGrew: Duration.zero,
          elapsed: const Duration(seconds: 5),
        ),
        TorrentReadiness.warming,
      );
    });

    test('frozen byte counter after the grace is hopeless even with peers', () {
      expect(
        TorrentWarmupPolicy.evaluate(
          loadedBytes: 256 * 1024,
          activePeers: 6,
          speedBps: 0,
          sinceBytesGrew: TorrentWarmupPolicy.noByteGrace,
          elapsed: TorrentWarmupPolicy.noByteGrace,
        ),
        TorrentReadiness.hopeless,
      );
    });

    test('at the ceiling a fed swarm is ready, a starved one is hopeless', () {
      expect(
        TorrentWarmupPolicy.evaluate(
          loadedBytes: 600 * 1024,
          activePeers: 2,
          speedBps: 50 * 1024,
          sinceBytesGrew: Duration.zero,
          elapsed: TorrentWarmupPolicy.maxWait,
        ),
        TorrentReadiness.ready,
      );
      expect(
        TorrentWarmupPolicy.evaluate(
          loadedBytes: 0,
          activePeers: 1,
          speedBps: 0,
          sinceBytesGrew: TorrentWarmupPolicy.maxWait,
          elapsed: TorrentWarmupPolicy.maxWait,
        ),
        TorrentReadiness.hopeless,
      );
    });

    test('bytes served to the reader count as buffer even when loaded is 0', () {
      // TorrServer's `loaded_size` can lag (or stay 0 for disk-backed files);
      // bytes handed to the live reader are the real proof.
      expect(
        TorrentWarmupPolicy.evaluate(
          loadedBytes: 0,
          servedBytes: 2 * 1024 * 1024,
          activePeers: 0,
          speedBps: 0,
          sinceBytesGrew: const Duration(seconds: 30),
          elapsed: const Duration(seconds: 4),
        ),
        TorrentReadiness.ready,
      );
    });

    test('served-only growth prevents a false "frozen" verdict', () {
      expect(
        TorrentWarmupPolicy.evaluate(
          loadedBytes: 0,
          servedBytes: 900 * 1024,
          activePeers: 0,
          speedBps: 0,
          sinceBytesGrew: Duration.zero,
          elapsed: TorrentWarmupPolicy.noByteGrace,
        ),
        TorrentReadiness.warming,
      );
    });

    test('no peers but live throughput keeps warming (active_peers=0 quirk)', () {
      // TorrServer reports active_peers = 0 whenever no transfer is in
      // flight, so peers/seeders alone must never mark a swarm hopeless.
      expect(
        TorrentWarmupPolicy.evaluate(
          loadedBytes: 256 * 1024,
          activePeers: 0,
          speedBps: 400 * 1024,
          sinceBytesGrew: const Duration(seconds: 9),
          elapsed: TorrentWarmupPolicy.noByteGrace,
        ),
        TorrentReadiness.hopeless,
      );
      expect(
        TorrentWarmupPolicy.evaluate(
          loadedBytes: 256 * 1024,
          activePeers: 0,
          speedBps: 400 * 1024,
          sinceBytesGrew: const Duration(seconds: 2),
          elapsed: TorrentWarmupPolicy.noByteGrace,
        ),
        TorrentReadiness.warming,
      );
    });

    test('isReady is evaluate == ready', () {
      expect(
        TorrentWarmupPolicy.isReady(
          loadedBytes: 2 * 1024 * 1024,
          activePeers: 0,
          speedBps: 0,
          sinceBytesGrew: const Duration(seconds: 5),
          elapsed: const Duration(seconds: 5),
        ),
        isTrue,
      );
      expect(
        TorrentWarmupPolicy.isReady(
          loadedBytes: 0,
          activePeers: 0,
          speedBps: 0,
          sinceBytesGrew: const Duration(seconds: 8),
          elapsed: TorrentWarmupPolicy.maxWait,
        ),
        isFalse,
      );
    });

    test('minimumSustainableBps adds 35% headroom', () {
      expect(TorrentWarmupPolicy.minimumSustainableBps(0), 0);
      expect(TorrentWarmupPolicy.minimumSustainableBps(1000000), 1350000);
    });
  });
}
