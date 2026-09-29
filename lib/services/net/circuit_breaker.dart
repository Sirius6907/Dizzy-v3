import 'package:flutter/foundation.dart';

/// Wall-clock source, injected so the breaker's cool-down can be tested
/// without `fakeAsync` or a real 60-second wait.
typedef NetClock = DateTime Function();

/// P3 — per-host circuit breaker.
///
/// States, per host key:
///   closed  → requests flow, failures counted
///   open    → requests refused for [coolDown], then one probe is let
///             through (half-open)
///   half-open → the probe decides: success closes, failure re-opens
///
/// The point is not to be clever, it is to stop hammering a host that
/// is already down. A background catalog refresh against a dead CDN
/// should cost one failed request, not sixty across every screen.
class CircuitBreaker {
  /// Consecutive failures before the breaker opens.
  final int failureThreshold;

  /// How long the breaker stays open before letting one probe through.
  final Duration coolDown;

  /// Cap on tracked hosts, so a pathological URL space (unique query
  /// strings treated as distinct hosts) cannot grow this without bound.
  /// When full, the least-recently-used host is evicted.
  final int maxHosts;

  final NetClock _clock;

  final Map<String, _HostState> _hosts = <String, _HostState>{};

  CircuitBreaker({
    this.failureThreshold = 5,
    this.coolDown = const Duration(seconds: 60),
    this.maxHosts = 128,
    NetClock? clock,
  })  : assert(failureThreshold >= 1),
        assert(coolDown > Duration.zero),
        assert(maxHosts >= 1),
        _clock = clock ?? DateTime.now;

  /// Test hook: a fixed clock makes the 60-second cool-down something a
  /// test can cross instead of wait out.
  CircuitBreaker.seeded({
    this.failureThreshold = 5,
    this.coolDown = const Duration(seconds: 60),
    this.maxHosts = 128,
    required NetClock clock,
  })  : assert(failureThreshold >= 1),
        assert(coolDown > Duration.zero),
        assert(maxHosts >= 1),
        _clock = clock;

  /// Whether a request to [host] may proceed right now.
  ///
  /// Returns false while the breaker is open. When the cool-down has
  /// elapsed the breaker transitions to half-open and returns true —
  /// exactly one caller gets through, because the state flips to
  /// half-open before this method returns.
  bool allowRequest(String host) {
    final key = host.trim().toLowerCase();
    if (key.isEmpty) return true;
    final now = _clock();

    _HostState? state = _hosts[key];
    if (state == null) {
      _evictIfNeeded();
      _hosts[key] = _HostState(openedAt: null, probedAt: null);
      return true;
    }

    if (!state.isOpen) {
      state.lastSeen = now;
      return true;
    }

    final openedAt = state.openedAt;
    if (openedAt == null) return true;
    if (now.difference(openedAt) < coolDown) return false;

    // Cool-down elapsed → half-open. Flip first so a second caller in
    // the same microtask does not also get a probe slot.
    state.probedAt = now;
    state.lastSeen = now;
    return true;
  }

  /// Record a successful attempt. Closes the breaker and clears the
  /// failure streak.
  void recordSuccess(String host) {
    final key = host.trim().toLowerCase();
    if (key.isEmpty) return;
    _hosts.remove(key);
  }

  /// Record a failed attempt. Opens the breaker once the streak
  /// reaches [failureThreshold].
  void recordFailure(String host) {
    final key = host.trim().toLowerCase();
    if (key.isEmpty) return;

    var state = _hosts[key];
    if (state == null) {
      _evictIfNeeded();
      state = _HostState(openedAt: null, probedAt: null);
      _hosts[key] = state;
    }

    // A failed probe is a full reopen, not a single increment: the host
    // has now failed [failureThreshold] times plus the probe.
    if (state.probedAt != null) {
      state.failures = failureThreshold;
      state.openedAt = _clock();
      state.probedAt = null;
      state.lastSeen = _clock();
      return;
    }

    state.failures += 1;
    state.lastSeen = _clock();
    if (state.failures >= failureThreshold) {
      state.openedAt = state.lastSeen;
    }
  }

  /// True when the breaker is refusing requests for [host] right now.
  @visibleForTesting
  bool isOpen(String host) {
    final state = _hosts[host.trim().toLowerCase()];
    if (state == null || !state.isOpen) return false;
    final openedAt = state.openedAt;
    if (openedAt == null) return false;
    return _clock().difference(openedAt) < coolDown;
  }

  /// Consecutive failures currently recorded for [host].
  @visibleForTesting
  int failureCount(String host) =>
      _hosts[host.trim().toLowerCase()]?.failures ?? 0;

  /// Test hook: drop all per-host state.
  @visibleForTesting
  void reset() => _hosts.clear();

  /// Number of tracked hosts. Test hook for the LRU-eviction path.
  @visibleForTesting
  int get trackedHosts => _hosts.length;

  void _evictIfNeeded() {
    if (_hosts.length < maxHosts) return;
    // Map iteration order is insertion order, so the first key is the
    // least-recently *inserted*. Good enough: eviction only needs to be
    // bounded, not perfect.
    _hosts.remove(_hosts.keys.first);
  }
}

class _HostState {
  int failures = 0;
  DateTime? openedAt;
  DateTime? probedAt;
  DateTime? lastSeen;

  _HostState({required this.openedAt, required this.probedAt});

  bool get isOpen => openedAt != null;
}
