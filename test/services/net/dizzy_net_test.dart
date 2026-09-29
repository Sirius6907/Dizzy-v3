import 'dart:async';
import 'dart:math' as math;

import 'package:dizzy/services/cloud/cloud_auth_service.dart';
import 'package:dizzy/services/debrid/debrid_resolver.dart';
import 'package:dizzy/services/debrid/models/debrid_file.dart';
import 'package:dizzy/services/errors/app_error_log.dart';
import 'package:dizzy/services/net/circuit_breaker.dart';
import 'package:dizzy/services/net/dizzy_net.dart';
import 'package:dizzy/services/net/offline_queue.dart';
import 'package:dizzy/services/net/retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// P3 — the networking contract.
///
/// Every test here drives the injected transport or the injected clock.
/// No socket, no wall-clock wait, no sleeping through a 60-second
/// cool-down. A test that needs 60 real seconds to prove a breaker opens
/// is a test nobody runs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CloudAuthService.consentCrash.value = true;
  });

  tearDown(() async {
    CloudAuthService.consentCrash.value = false;
    await AppErrorLog.clearQueue();
  });

  // ── helpers ────────────────────────────────────────────────────────────

  http.Response ok(String body) => http.Response(body, 200);
  http.Response status(int code) => http.Response('', code);

  Uri uri(String host, [String path = '/v1']) => Uri.parse('https://$host$path');

  /// A clock a test can wind forward by hand.
  ({DateTime Function() now, CircuitBreaker Function() newBreaker})
      seedClock() {
    var t = DateTime.utc(2026);
    return (
      now: () => t,
      newBreaker: () => DizzyNet.breakerForTesting(clock: () => t),
    );
  }

  // ── 1. retry-then-win ──────────────────────────────────────────────────

  group('retry', () {
    test('a transient failure is retried and the retry is returned', () async {
      var calls = 0;
      final net = DizzyNet.forTesting(
        transport: (method, target, headers, body) async {
          calls += 1;
          if (calls == 1) return status(503);
          return ok('{"page":1}');
        },
        // Zero base delay: the backoff curve is asserted separately in
        // the RetryPolicy group. Here we only care that attempt 2 ran.
        policy: const RetryPolicy(maxAttempts: 3),
        random: math.Random(1),
      );

      final res = await net.get(uri('api.example'), screen: 'test');

      expect(calls, 2, reason: 'one failure must buy exactly one retry');
      expect(res.statusCode, 200);
      expect(res.body, '{"page":1}');
    });

    test('retry budget is bounded — a permanently dead host gets N tries', () async {
      var calls = 0;
      final net = DizzyNet.forTesting(
        transport: (method, target, headers, body) async {
          calls += 1;
          return status(500);
        },
        policy: const RetryPolicy(maxAttempts: 3),
        random: math.Random(1),
      );

      final res = await net.get(uri('api.example'), screen: 'test');

      expect(calls, 3, reason: 'maxAttempts is a ceiling, not a hint');
      expect(res.statusCode, kSyntheticTimeoutStatus);
    });

    test('a 404 is answered, not retried, and does not poison the host', () async {
      var calls = 0;
      final clock = seedClock();
      final net = DizzyNet.forTesting(
        transport: (method, target, headers, body) async {
          calls += 1;
          return status(404);
        },
        policy: RetryPolicy.patient,
        breaker: clock.newBreaker(),
        random: math.Random(1),
      );

      final res = await net.get(uri('api.example'), screen: 'test');

      expect(calls, 1, reason: 'the server answered; asking again cannot help');
      expect(res.statusCode, 404, reason: 'the real status must survive');
      expect(
        net.breaker.failureCount('api.example'),
        0,
        reason: 'a 404 proves the host is alive',
      );
    });
  });

  // ── 2. no-throw-on-timeout / timeout-synthetic ─────────────────────────

  group('timeout', () {
    test('a hung socket returns a synthetic 504 instead of throwing', () async {
      final net = DizzyNet.forTesting(
        transport: (method, target, headers, body) =>
            Completer<http.Response>().future,
        policy: RetryPolicy.none,
      );

      Object? caught;
      http.Response? res;
      try {
        res = await net.get(
          uri('slow.example'),
          timeout: const Duration(milliseconds: 5),
          screen: 'test',
        );
      } catch (e) {
        caught = e;
      }

      expect(caught, isNull, reason: 'a timeout must never unwind the caller');
      expect(res, isNotNull);
      expect(res!.statusCode, kSyntheticTimeoutStatus);
      expect(res.body, isEmpty, reason: 'no body is better than a fake one');
    });

    test('the synthetic status classifies as retryable, not terminal', () {
      expect(
        RetryPolicy.classifyStatus(kSyntheticTimeoutStatus),
        NetAttempt.retryableStatus,
      );
      expect(RetryPolicy.countsTowardBreaker(NetAttempt.retryableStatus), isTrue);
    });

    test('a transport that throws is contained the same way', () async {
      final net = DizzyNet.forTesting(
        transport: (method, target, headers, body) async =>
            throw const SocketFailure(),
        policy: RetryPolicy.none,
      );

      final res = await net.get(uri('down.example'), screen: 'test');

      expect(res.statusCode, kSyntheticTimeoutStatus);
    });
  });

  // ── 3. breaker-opens ───────────────────────────────────────────────────

  group('circuit breaker', () {
    test('opens after the failure threshold and stops spending sockets', () async {
      final clock = seedClock();
      var calls = 0;
      final breaker = clock.newBreaker();
      final net = DizzyNet.forTesting(
        transport: (method, target, headers, body) async {
          calls += 1;
          return status(500);
        },
        policy: RetryPolicy.none,
        breaker: breaker,
      );

      for (var i = 0; i < 5; i++) {
        await net.get(uri('dead.example'), screen: 'test');
      }
      expect(calls, 5, reason: 'threshold is 5, so the 5th request still goes');
      expect(breaker.isOpen('dead.example'), isTrue);

      // Sixth call: refused before the transport is ever touched.
      final res = await net.get(uri('dead.example'), screen: 'test');
      expect(calls, 5, reason: 'an open breaker must not open a socket');
      expect(res.statusCode, kSyntheticTimeoutStatus);
    });

    test('the breaker is per host — one dead host does not block another', () async {
      final clock = seedClock();
      final breaker = clock.newBreaker();
      final net = DizzyNet.forTesting(
        transport: (method, target, headers, body) async =>
            target.host == 'dead.example' ? status(500) : ok('{}'),
        policy: RetryPolicy.none,
        breaker: breaker,
      );

      for (var i = 0; i < 5; i++) {
        await net.get(uri('dead.example'), screen: 'test');
      }
      expect(breaker.isOpen('dead.example'), isTrue);

      final other = await net.get(uri('healthy.example'), screen: 'test');
      expect(other.statusCode, 200);
      expect(breaker.isOpen('healthy.example'), isFalse);
    });

    test('a success resets the streak before the threshold', () {
      final clock = seedClock();
      final breaker = clock.newBreaker();

      for (var i = 0; i < 4; i++) {
        breaker.recordFailure('api.example');
      }
      expect(breaker.isOpen('api.example'), isFalse);

      breaker.recordSuccess('api.example');
      expect(breaker.failureCount('api.example'), 0);

      breaker.recordFailure('api.example');
      expect(
        breaker.isOpen('api.example'),
        isFalse,
        reason: 'the streak restarted, so 1 is not 5',
      );
    });
  });

  // ── 4. breaker-recovers ────────────────────────────────────────────────

  group('breaker recovery', () {
    test('after the cool-down one probe is let through and success closes it',
        () async {
      var now = DateTime.utc(2026);
      final breaker = DizzyNet.breakerForTesting(clock: () => now);
      var calls = 0;
      var dead = true;

      final net = DizzyNet.forTesting(
        transport: (method, target, headers, body) async {
          calls += 1;
          return dead ? status(500) : ok('{"back":true}');
        },
        policy: RetryPolicy.none,
        breaker: breaker,
      );

      for (var i = 0; i < 5; i++) {
        await net.get(uri('flaky.example'), screen: 'test');
      }
      expect(breaker.isOpen('flaky.example'), isTrue);
      expect(calls, 5);

      // Still cooling down.
      now = now.add(const Duration(seconds: 59));
      await net.get(uri('flaky.example'), screen: 'test');
      expect(calls, 5, reason: '59s is still inside the 60s cool-down');

      // Cool-down elapsed → exactly one probe.
      now = now.add(const Duration(seconds: 2));
      dead = false;
      final res = await net.get(uri('flaky.example'), screen: 'test');

      expect(calls, 6, reason: 'half-open allows one probe, not a flood');
      expect(res.statusCode, 200);
      expect(breaker.isOpen('flaky.example'), isFalse);
      expect(breaker.failureCount('flaky.example'), 0);
    });

    test('a failed probe re-opens for a full cool-down', () async {
      var now = DateTime.utc(2026);
      final breaker = DizzyNet.breakerForTesting(clock: () => now);
      final net = DizzyNet.forTesting(
        transport: (method, target, headers, body) async => status(500),
        policy: RetryPolicy.none,
        breaker: breaker,
      );

      for (var i = 0; i < 5; i++) {
        await net.get(uri('dead.example'), screen: 'test');
      }
      expect(breaker.isOpen('dead.example'), isTrue);

      now = now.add(const Duration(seconds: 61));
      await net.get(uri('dead.example'), screen: 'test'); // the probe, fails

      expect(
        breaker.isOpen('dead.example'),
        isTrue,
        reason: 'a failed probe restarts the cool-down from now',
      );
      now = now.add(const Duration(seconds: 59));
      expect(breaker.isOpen('dead.example'), isTrue);
      now = now.add(const Duration(seconds: 2));
      expect(breaker.isOpen('dead.example'), isFalse);
    });
  });

  // ── 5. offline queue ───────────────────────────────────────────────────

  group('offline queue', () {
    test('a failed GET is remembered and replays on drain', () async {
      var dead = true;
      var calls = 0;
      final net = DizzyNet.forTesting(
        transport: (method, target, headers, body) async {
          calls += 1;
          return dead ? status(500) : ok('{"ok":1}');
        },
        policy: RetryPolicy.none,
        breaker: CircuitBreaker(coolDown: const Duration(seconds: 60)),
      );

      await net.get(uri('a.example', '/one'), screen: 'home');
      await net.get(uri('a.example', '/two'), screen: 'home');
      expect(net.offlineQueue.length, 2);

      dead = false;
      final drainedUrls = <String>[];
      final replayed = await net.drainOfflineQueue(
        onDrained: (item) async => drainedUrls.add(item.uri.path),
      );

      expect(replayed, 2);
      expect(drainedUrls, ['/one', '/two'], reason: 'replays oldest first');
      expect(net.offlineQueue.isEmpty, isTrue);
      expect(calls, 4, reason: '2 original failures + 2 replays');
    });

    test('POSTs are never queued — a replayed POST is a second action', () async {
      final net = DizzyNet.forTesting(
        transport: (method, target, headers, body) async => status(500),
        policy: RetryPolicy.none,
        breaker: CircuitBreaker(coolDown: const Duration(seconds: 60)),
      );

      await net.post(uri('a.example'), body: 'magnet=x', screen: 'player');

      expect(
        net.offlineQueue.isEmpty,
        isTrue,
        reason: 'queueing a POST is how one tap becomes two torrents',
      );
    });

    test('a duplicate URL is queued once, and the queue is bounded', () {
      final queue = OfflineGetQueue();

      expect(
        queue.enqueue(
          QueuedGet(uri: uri('a.example', '/same'), headers: const {}, screen: 'home'),
        ),
        isTrue,
      );
      expect(
        queue.enqueue(
          QueuedGet(uri: uri('a.example', '/same'), headers: const {}, screen: 'home'),
        ),
        isFalse,
        reason: 'a reconnect replays every screen; /same must not be fetched twice',
      );
      expect(queue.length, 1);

      for (var i = 0; i < OfflineGetQueue.maxEntries; i++) {
        expect(
          queue.enqueue(
            QueuedGet(uri: uri('a.example', '/$i'), headers: const {}, screen: 'home'),
          ),
          isTrue,
        );
      }
      // One past the cap, and the oldest is the one that goes.
      queue.enqueue(
        QueuedGet(uri: uri('a.example', '/overflow'), headers: const {}, screen: 'home'),
      );

      expect(queue.length, OfflineGetQueue.maxEntries);
      expect(queue.urls.first, contains('/1'), reason: '/0 was dropped');
      expect(queue.urls.last, contains('/overflow'));
    });

    test('drain stops at the first rejection — the network is still down', () async {
      final net = DizzyNet.forTesting(
        transport: (method, target, headers, body) async => status(500),
        policy: RetryPolicy.none,
        breaker: CircuitBreaker(coolDown: const Duration(seconds: 60)),
      );

      await net.get(uri('a.example', '/one'), screen: 'home');
      await net.get(uri('a.example', '/two'), screen: 'home');

      final replayed = await net.drainOfflineQueue();

      expect(replayed, 0);
      expect(
        net.offlineQueue.length,
        2,
        reason: 'nothing is dropped while the network is still down',
      );
    });
  });

  // ── 6. debrid failover ─────────────────────────────────────────────────

  group('debrid failover', () {
    DebridFile file(String name) =>
        DebridFile(filename: name, filesize: 1024, downloadUrl: 'https://d/$name');

    DebridAttempt attempt({
      required String label,
      bool configured = true,
      bool? hasKeyThrows,
      List<DebridFile>? files,
      bool throws = false,
      List<String>? log,
    }) =>
        DebridAttempt(
          label,
          () async {
            if (hasKeyThrows ?? false) throw const SocketFailure();
            return configured;
          },
          (magnet, {fileIndex, filename, season, episode, episodeTitle}) async {
            log?.add(label);
            if (throws) throw const SocketFailure();
            return files ?? <DebridFile>[];
          },
        );

    /// The chain is a method, not a constant, so a test can hand the
    /// resolver a scripted chain without inventing a real provider.
    DebridResolver withChain(List<DebridAttempt> chain) =>
        _ScriptedResolver(chain);

    test('tries providers in order and stops at the first valid answer', () async {
      final calls = <String>[];
      final resolver = withChain([
        attempt(
          label: 'Real-Debrid',
          throws: true,
          log: calls,
        ),
        attempt(label: 'TorBox', files: [file('ep1.mkv')], log: calls),
        attempt(label: 'AllDebrid', files: [file('other.mkv')], log: calls),
      ]);

      final result = await resolver.resolve(magnet: 'magnet:?xt=1');

      expect(result.isResolved, isTrue);
      expect(result.provider, 'TorBox');
      expect(result.files.single.filename, 'ep1.mkv');
      expect(
        calls,
        ['Real-Debrid', 'TorBox'],
        reason: 'AllDebrid must not be asked once TorBox answered',
      );
    });

    test('a provider that throws is contained — the chain moves on', () async {
      final calls = <String>[];
      final resolver = withChain([
        attempt(label: 'Real-Debrid', throws: true, log: calls),
        attempt(label: 'TorBox', throws: true, log: calls),
        attempt(label: 'AllDebrid', files: [file('ep1.mkv')], log: calls),
      ]);

      final result = await resolver.resolve(magnet: 'magnet:?xt=1');

      expect(result.isResolved, isTrue);
      expect(result.provider, 'AllDebrid');
      expect(calls, ['Real-Debrid', 'TorBox', 'AllDebrid']);
    });

    test('an empty answer is a failure, not a win', () async {
      final calls = <String>[];
      final resolver = withChain([
        attempt(label: 'Real-Debrid', files: const [], log: calls),
        attempt(label: 'TorBox', files: [file('ep1.mkv')], log: calls),
      ]);

      final result = await resolver.resolve(magnet: 'magnet:?xt=1');

      expect(
        result.provider,
        'TorBox',
        reason: 'an empty list would strand the player with nothing to open',
      );
      expect(calls, ['Real-Debrid', 'TorBox']);
    });

    test('an unconfigured provider is skipped without a network call', () async {
      final calls = <String>[];
      final resolver = withChain([
        attempt(label: 'Real-Debrid', configured: false, log: calls),
        attempt(label: 'TorBox', configured: false, log: calls),
        attempt(label: 'AllDebrid', files: [file('ep1.mkv')], log: calls),
      ]);

      final result = await resolver.resolve(magnet: 'magnet:?xt=1');

      expect(result.provider, 'AllDebrid');
      expect(calls, ['AllDebrid'], reason: 'no key means no request');
    });

    test('a hasKey() that throws skips that provider instead of aborting', () async {
      final calls = <String>[];
      final resolver = withChain([
        attempt(label: 'Real-Debrid', hasKeyThrows: true, log: calls),
        attempt(label: 'TorBox', files: [file('ep1.mkv')], log: calls),
      ]);

      final result = await resolver.resolve(magnet: 'magnet:?xt=1');

      expect(result.isResolved, isTrue);
      expect(calls, ['TorBox']);
    });

    test('every provider failing is reported, never a partial answer', () async {
      final resolver = withChain([
        attempt(label: 'Real-Debrid', throws: true),
        attempt(label: 'TorBox', files: const []),
        attempt(label: 'AllDebrid', throws: true),
      ]);

      final result = await resolver.resolve(magnet: 'magnet:?xt=1');

      expect(result.isResolved, isFalse);
      expect(result.outcome, DebridFailoverOutcome.allProvidersFailed);
      expect(result.files, isEmpty);
      expect(result.attempted, ['Real-Debrid', 'TorBox', 'AllDebrid']);
    });

    test('no keys at all is distinguished from every key failing', () async {
      final resolver = withChain([
        attempt(label: 'Real-Debrid', configured: false),
        attempt(label: 'TorBox', configured: false),
      ]);

      final result = await resolver.resolve(magnet: 'magnet:?xt=1');

      expect(result.outcome, DebridFailoverOutcome.noProviderConfigured);
      expect(result.attempted, isEmpty);
    });

    test('the empty magnet never reaches a provider', () async {
      final calls = <String>[];
      final resolver = withChain([
        attempt(label: 'Real-Debrid', files: [file('x.mkv')], log: calls),
      ]);

      final result = await resolver.resolve(magnet: '   ');

      expect(result.isResolved, isFalse);
      expect(calls, isEmpty);
    });

    test('the production chain is the documented order', () {
      final order = DebridResolver().chain().map((a) => a.label).toList();
      expect(
        order,
        ['Real-Debrid', 'TorBox', 'AllDebrid', 'Premiumize', 'Debrid-Link'],
      );
    });
  });

  // ── policy and queue units ─────────────────────────────────────────────

  group('RetryPolicy', () {
    test('backoff grows geometrically and stays inside maxDelay', () {
      const p = RetryPolicy(
        maxAttempts: 8,
        baseDelay: Duration(milliseconds: 100),
        maxDelay: Duration(seconds: 1),
      );
      expect(p.delayFor(1, random: 0).inMilliseconds, 100);
      expect(p.delayFor(2, random: 0).inMilliseconds, 200);
      expect(p.delayFor(3, random: 0).inMilliseconds, 400);
      // Capped, and no overflow to infinity on the way.
      expect(p.delayFor(8, random: 0), const Duration(seconds: 1));
      expect(p.delayFor(999, random: 0), const Duration(seconds: 1));
    });

    test('jitter only ever shortens the wait, and never below zero', () {
      const p = RetryPolicy(baseDelay: Duration(milliseconds: 100), jitterRatio: 0.2);
      expect(p.delayFor(1, random: 0).inMilliseconds, 100);
      expect(p.delayFor(1, random: 1).inMilliseconds, 80);
      // A misbehaving random source cannot produce a negative Duration.
      expect(p.delayFor(1, random: -5).inMicroseconds, greaterThanOrEqualTo(0));
    });

    test('status classification splits definitive from worth-retrying', () {
      expect(RetryPolicy.classifyStatus(200), NetAttempt.success);
      expect(RetryPolicy.classifyStatus(302), NetAttempt.success);
      expect(RetryPolicy.classifyStatus(408), NetAttempt.retryableStatus);
      expect(RetryPolicy.classifyStatus(429), NetAttempt.retryableStatus);
      expect(RetryPolicy.classifyStatus(500), NetAttempt.retryableStatus);
      expect(RetryPolicy.classifyStatus(404), NetAttempt.terminalStatus);
      expect(RetryPolicy.classifyStatus(401), NetAttempt.terminalStatus);
      expect(RetryPolicy.classifyStatus(100), NetAttempt.terminalStatus);
    });

    test('a terminal outcome is never retried, whatever the budget', () {
      const p = RetryPolicy(maxAttempts: 9);
      expect(p.shouldRetry(NetAttempt.terminalStatus, 1), isFalse);
      expect(p.shouldRetry(NetAttempt.success, 1), isFalse);
      expect(p.shouldRetry(NetAttempt.transportError, 8), isTrue);
      expect(p.shouldRetry(NetAttempt.transportError, 9), isFalse);
    });
  });

  group('decodeJsonMap', () {
    test('returns null for anything unusable rather than throwing', () {
      expect(DizzyNet.decodeJsonMap(ok('{"a":1}')), <String, dynamic>{'a': 1});
      expect(DizzyNet.decodeJsonMap(ok('  ')), isNull, reason: 'empty body');
      expect(DizzyNet.decodeJsonMap(ok('not json')), isNull);
      expect(DizzyNet.decodeJsonMap(ok('[1,2]')), isNull, reason: 'not a map');
      expect(DizzyNet.decodeJsonMap(status(500)), isNull);
      expect(DizzyNet.decodeJsonMap(status(404)), isNull);
    });
  });
}

/// Subclass seam: [DebridResolver.chain] is a method precisely so the
/// failover order can be scripted without a real API key.
class _ScriptedResolver extends DebridResolver {
  final List<DebridAttempt> _script;

  _ScriptedResolver(this._script);

  @override
  List<DebridAttempt> chain() => _script;
}

/// Stand-in for a socket-level failure, so a test does not depend on any
/// particular exception type from a particular HTTP package.
class SocketFailure implements Exception {
  const SocketFailure();

  @override
  String toString() => 'SocketFailure';
}
