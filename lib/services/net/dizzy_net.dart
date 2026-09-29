import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../errors/app_error_log.dart';
import 'circuit_breaker.dart';
import 'offline_queue.dart';
import 'retry_policy.dart';
import 'timeout_race.dart';

/// The one seam tests replace. Production uses a shared [http.Client];
/// a test supplies a function that fails N times and then succeeds.
typedef DizzyNetTransport = Future<http.Response> Function(
  String method,
  Uri uri,
  Map<String, String> headers,
  Object? body,
);

/// P3 — the single HTTP client for the app's shared services.
///
/// Why this exists: 51 files were calling `http` directly, each with its
/// own timeout, its own retry (usually none), and its own idea of what a
/// timeout should do — which in every case was to throw. A thrown
/// timeout inside a `Future.wait` or an unawaited `.then` is a silent
/// death: the screen simply stops updating, forever, with nothing in the
/// log to explain it.
///
/// The four rules this client enforces:
///
/// 1. **A timeout never throws.** It returns [syntheticTimeoutResponse].
///    Every caller already branches on `statusCode`, so the synthetic
///    answer flows down the same path a 5xx would.
/// 2. **Retries are bounded and jittered.** See [RetryPolicy].
/// 3. **A dead host is not hammered.** [CircuitBreaker] opens after 5
///    consecutive transport/5xx failures and cools down for 60s.
/// 4. **Offline GETs are remembered, not dropped.** They replay on
///    reconnect. POSTs are never queued, because replaying a POST is
///    how one tap becomes two torrents.
///
/// What it deliberately does not do: retry non-idempotent requests,
/// count a 404 as a host failure, or add a cache — the callers already
/// own their caches, and a second one is a second thing to invalidate.
class DizzyNet {
  DizzyNet._({
    http.Client? client,
    required this.breaker,
    required RetryPolicy policy,
    required math.Random random,
    DizzyNetTransport? transport,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _policy = policy,
        _random = random,
        _transport = transport;

  /// The app-wide instance. The breaker is shared process-wide on
  /// purpose: the point is that a dead CDN is remembered by the whole
  /// app, not re-discovered by every call site.
  static final DizzyNet instance = DizzyNet._(
    client: http.Client(),
    breaker: CircuitBreaker(),
    policy: RetryPolicy.quick,
    random: math.Random(),
  );

  /// Every collaborator is injected, so a test touches no socket and no
  /// wall clock.
  @visibleForTesting
  factory DizzyNet.forTesting({
    required DizzyNetTransport transport,
    CircuitBreaker? breaker,
    RetryPolicy policy = RetryPolicy.quick,
    math.Random? random,
    DateTime Function()? clock,
  }) {
    final rand = random ?? math.Random(7);
    return DizzyNet._(
      client: null,
      breaker: breaker ??
          CircuitBreaker(
            failureThreshold: 5,
            coolDown: const Duration(seconds: 60),
            clock: clock ?? _epochClock,
          ),
      policy: policy,
      random: rand,
      transport: transport,
    );
  }

  /// A breaker with the production shape — 5 failures, 60s cool-down —
  /// driven by [clock]. Exposed so a test can watch the cool-down
  /// expire instead of waiting for it.
  @visibleForTesting
  static CircuitBreaker breakerForTesting({DateTime Function()? clock}) =>
      CircuitBreaker(
        failureThreshold: 5,
        coolDown: const Duration(seconds: 60),
        clock: clock ?? _epochClock,
      );

  final CircuitBreaker breaker;
  final OfflineGetQueue offlineQueue = OfflineGetQueue();

  final http.Client _client;
  final bool _ownsClient;
  final RetryPolicy _policy;
  final math.Random _random;
  final DizzyNetTransport? _transport;

  /// Default retry budget for callers that do not name one.
  RetryPolicy get defaultPolicy => _policy;

  /// A GET. Retries, honours the breaker, and queues for replay when the
  /// host is unreachable.
  ///
  /// [screen] and [code] are logged, never shown. The user-facing
  /// message is the caller's to own — this layer cannot know whether a
  /// failed catalog fetch deserves a toast.
  Future<http.Response> get(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
    Duration timeout = const Duration(seconds: 12),
    RetryPolicy? policy,
    String screen = 'net',
    String code = 'net_get',
    bool queueWhenOffline = true,
  }) =>
      _send(
        'GET',
        uri,
        headers: headers,
        body: null,
        timeout: timeout,
        policy: policy,
        screen: screen,
        code: code,
        queueWhenOffline: queueWhenOffline,
      );

  /// A POST. Never queued, never replayed — see the class doc.
  Future<http.Response> post(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
    Object? body,
    Duration timeout = const Duration(seconds: 15),
    RetryPolicy? policy,
    String screen = 'net',
    String code = 'net_post',
  }) =>
      _send(
        'POST',
        uri,
        headers: headers,
        body: body,
        timeout: timeout,
        policy: policy,
        screen: screen,
        code: code,
        queueWhenOffline: false,
      );

  /// "I want the JSON map" in one call.
  ///
  /// Null rather than throwing on anything unusable: a decode failure, a
  /// non-2xx, an empty body. The old call sites each did this by hand,
  /// and three of the five did it differently.
  Future<Map<String, dynamic>?> getJson(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
    Duration timeout = const Duration(seconds: 12),
    RetryPolicy? policy,
    String screen = 'net',
    String code = 'net_get',
    bool queueWhenOffline = true,
  }) async {
    final res = await get(
      uri,
      headers: headers,
      timeout: timeout,
      policy: policy,
      screen: screen,
      code: code,
      queueWhenOffline: queueWhenOffline,
    );
    return decodeJsonMap(res);
  }

  /// Shared decode. Never throws.
  @visibleForTesting
  static Map<String, dynamic>? decodeJsonMap(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final body = res.body.trim();
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Replay everything the offline queue is holding. Call on reconnect.
  ///
  /// A successful replay is reported through [onDrained] so a screen can
  /// refresh without the queue layer knowing that screens exist.
  Future<int> drainOfflineQueue({
    Future<void> Function(QueuedGet item)? onDrained,
  }) =>
      offlineQueue.drain(_replay, (item, res) async {
        final ok = res.statusCode >= 200 && res.statusCode < 300;
        if (ok) await onDrained?.call(item);
        return ok;
      });

  void close() {
    if (_ownsClient) _client.close();
    offlineQueue.clear();
  }

  // ── internals ──

  Future<http.Response> _replay(QueuedGet item) => _send(
        'GET',
        item.uri,
        headers: item.headers,
        body: null,
        timeout: const Duration(seconds: 12),
        policy: RetryPolicy.quick,
        screen: item.screen,
        code: 'net_replay',
        queueWhenOffline: false,
      );

  Future<http.Response> _send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    required Object? body,
    required Duration timeout,
    required RetryPolicy? policy,
    required String screen,
    required String code,
    required bool queueWhenOffline,
  }) async {
    final host = uri.host;
    final effective = policy ?? defaultPolicy;

    if (host.isNotEmpty && !breaker.allowRequest(host)) {
      // The breaker is open. Do not spend a socket discovering that.
      _log(code: 'net_breaker_open', screen: screen);
      if (method == 'GET' && queueWhenOffline) {
        offlineQueue.enqueue(
          QueuedGet(uri: uri, headers: headers, screen: screen),
        );
      }
      return syntheticTimeoutResponse();
    }

    var attempt = 0;
    var last = NetAttempt.transportError;
    http.Response? terminalRes;

    while (attempt < effective.maxAttempts) {
      attempt += 1;
      final result = await _attempt(
        method,
        uri,
        headers: headers,
        body: body,
        timeout: timeout,
      );
      last = result.$1;

      if (last == NetAttempt.success) {
        if (host.isNotEmpty) breaker.recordSuccess(host);
        return result.$2;
      }

      if (host.isNotEmpty) {
        if (RetryPolicy.countsTowardBreaker(last)) {
          breaker.recordFailure(host);
        } else {
          // A 404 proves the host is up. Leaving an earlier streak here
          // would let one dead catalogue entry poison the whole host.
          breaker.recordSuccess(host);
        }
      }

      // A definitive refusal carries its real status home: the caller's
      // contract says the answer survives, not a synthetic 504.
      if (last == NetAttempt.terminalStatus) {
        terminalRes = result.$2;
        break;
      }

      if (!effective.shouldRetry(last, attempt)) break;

      final wait = effective.delayFor(attempt, random: _random.nextDouble());
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    }

    final terminal = terminalRes;
    if (terminal != null) return terminal;

    _log(code: code, screen: screen, detail: 'fail_${last.name}');
    if (method == 'GET' && queueWhenOffline) {
      offlineQueue.enqueue(
        QueuedGet(uri: uri, headers: headers, screen: screen),
      );
    }
    return syntheticTimeoutResponse();
  }

  /// One attempt. Always returns `(outcome, response)` — never throws.
  ///
  /// A timeout becomes a synthetic 504 through [_raceTimeout], not a
  /// throw. That is the point of the whole exercise: a value is the only
  /// way to turn a hung socket into an answer without unwinding the
  /// caller's stack.
  Future<(NetAttempt, http.Response)> _attempt(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    required Object? body,
    required Duration timeout,
  }) async {
    final transport = _transport;
    Future<http.Response> pending;
    try {
      // Future.sync so a synchronously-throwing transport becomes an
      // error-future instead of an escape.
      pending = Future.sync(
        () => transport != null
            ? transport(method, uri, headers, body)
            : (method == 'POST'
                ? _client.post(uri, headers: headers, body: body)
                : _client.get(uri, headers: headers)),
      );
    } catch (_) {
      _log(code: 'net_transport', screen: 'net', detail: 'attempt_failed');
      return (NetAttempt.transportError, syntheticTimeoutResponse());
    }
    try {
      final res = await _raceTimeout(pending, timeout);
      if (res.statusCode == kSyntheticTimeoutStatus) {
        // Either the gateway genuinely answered 504, or we synthesised
        // it. Both mean "try again later"; neither unwinds the stack.
        return (NetAttempt.retryableStatus, res);
      }
      return (RetryPolicy.classifyStatus(res.statusCode), res);
    } catch (_) {
      // Socket error, DNS failure, TLS problem — all transport-class.
      _log(code: 'net_transport', screen: 'net', detail: 'attempt_failed');
      return (NetAttempt.transportError, syntheticTimeoutResponse());
    }
  }

  /// Race [pending] against [timeout] with an explicit timer instead of
  /// [Future.timeout].
  ///
  /// `Future.timeout`'s `onTimeout` is checked against the receiver's
  /// *runtime* type argument, not the static one. A transport whose body
  /// only throws is inferred `Future<Never>`, so the runtime rejects
  /// `onTimeout: () => synthetic...` with a TypeError before a single
  /// listener is attached: the timeout machinery never runs, and the
  /// pending error escapes to the zone as an unhandled error even though
  /// the caller's `catch` does run. Both handlers are attached here,
  /// synchronously, so a throwing transport is always contained by the
  /// caller's catch — and the timer is cancelled the moment [pending]
  /// settles, so no request leaves a stray timer behind.
  static Future<http.Response> _raceTimeout(
    Future<http.Response> pending,
    Duration timeout,
  ) =>
      raceTimeout(pending, timeout, syntheticTimeoutResponse);

  void _log({required String code, required String screen, String detail = ''}) {
    unawaited(AppErrorLog.log(code: code, screen: screen, detail: detail));
  }

  static DateTime _epochClock() => DateTime(2026);
}
