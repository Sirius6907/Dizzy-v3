import 'package:flutter/foundation.dart';

/// Phase L4 — one gate for "the user tapped too many times".
///
/// A phone registers the same button twice: once on press, once on release,
/// and impatient fingers add a third. For transport controls (play/pause,
/// next, previous) that accidental pair is a real bug: pause runs while the
/// fade is still going, the icon flips twice, and a track skips past the one
/// the user wanted.
///
/// [TapGate] makes an action **single-flight** (a second tap cannot start
/// the same work twice) and **debounced** per key (a tap that lands inside
/// the window is treated as the same tap).
///
/// Two ways to handle a tap that arrives while work is running:
/// - drop it (`coalesce: false`) — right for play/pause, where a queued
///   pause would silently undo the play the user just asked for;
/// - remember only the newest one (`coalesce: true`) — right for next/prev
///   and channel switching, where skipping while buffering should still
///   land the user one step forward, not three.
class TapGate {
  TapGate({
    this.window = const Duration(milliseconds: 300),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// How long after a tap a second identical tap counts as the same tap.
  final Duration window;

  final DateTime Function() _now;

  /// True while an action is running — surfaces use this for a pressed-state
  /// lock so the button cannot look tappable while it is already working.
  final ValueNotifier<bool> busy = ValueNotifier<bool>(false);

  bool _running = false;
  bool _disposed = false;
  String? _lastKey;
  DateTime? _lastAt;

  Future<void> Function()? _pending;
  String? _pendingKey;

  bool get isBusy => _running;

  /// True when a tap on [key] right now would be ignored.
  bool shouldSkip(String key, {Duration? window}) {
    if (_running) return true;
    final lastAt = _lastAt;
    if (lastAt == null || _lastKey != key) return false;
    return _now().difference(lastAt) < (window ?? this.window);
  }

  /// Runs [action] unless the tap is a duplicate or the gate is busy.
  ///
  /// Returns true when [action] actually ran (or, for a coalesced tap, when
  /// this call's action will run once the current one finishes).
  Future<bool> run(
    String key,
    Future<void> Function() action, {
    Duration? window,
    bool coalesce = false,
  }) async {
    if (_running) {
      if (coalesce) {
        // Latest wins: three impatient taps while buffering mean "go to the
        // next one", not "go three tracks forward".
        _pending = action;
        _pendingKey = key;
        return true;
      }
      return false;
    }
    if (shouldSkip(key, window: window)) return false;

    _running = true;
    _setBusy(true);
    var current = action;
    var currentKey = key;
    try {
      while (true) {
        _lastKey = currentKey;
        _lastAt = _now();
        await current();
        final next = _pending;
        if (next == null) break;
        _pending = null;
        currentKey = _pendingKey ?? currentKey;
        current = next;
      }
      return true;
    } finally {
      _pending = null;
      _pendingKey = null;
      _running = false;
      _setBusy(false);
    }
  }

  /// Test seam: forget the window and any pending tap.
  @visibleForTesting
  void reset() {
    _running = false;
    _lastKey = null;
    _lastAt = null;
    _pending = null;
    _pendingKey = null;
    _setBusy(false);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    busy.dispose();
  }

  /// The gate can outlive its screen by a few hundred milliseconds (a page
  /// closes while a stream is still opening), so never touch the notifier
  /// after dispose.
  void _setBusy(bool value) {
    if (_disposed) return;
    busy.value = value;
  }
}
