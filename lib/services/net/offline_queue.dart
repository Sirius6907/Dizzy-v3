import 'dart:async';

import 'package:http/http.dart' as http;

/// One GET waiting for the network to come back.
///
/// Deliberately not persisted: a queued read that is a day old is a
/// worse answer than no answer, and the callers that use this already
/// keep their own long-lived snapshots (catalog prefs, catalogue cache).
/// This queue lives for one offline episode.
class QueuedGet {
  final Uri uri;
  final Map<String, String> headers;
  final String screen;

  const QueuedGet({
    required this.uri,
    required this.headers,
    required this.screen,
  });

  @override
  String toString() => 'QueuedGet(${uri.host})';
}

/// Fetches one queued item. Injected by [DizzyNet], which owns the
/// transport; the queue itself does no I/O.
typedef QueuedGetFetcher = Future<http.Response> Function(QueuedGet item);

/// Where a drained GET goes. Returns true when the response was
/// accepted (2xx/3xx), which is the only thing the queue cares about.
typedef QueuedGetSink = Future<bool> Function(QueuedGet item, http.Response res);

/// P3 — the offline queue for idempotent GETs.
///
/// Only GETs are ever queued. Replaying a POST is how you get two
/// torrents, two purchases, or two chat messages out of one tap, so
/// POSTs are refused at the call site instead of here.
///
/// Bounded, and drop-oldest like every other queue in this app: a
/// reconnect storm on a flaky network must not turn into unbounded
/// memory growth.
class OfflineGetQueue {
  static const int maxEntries = 32;

  final List<QueuedGet> _items = <QueuedGet>[];

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  /// The waiting URLs. Test hook.
  List<String> get urls =>
      _items.map((q) => q.uri.toString()).toList(growable: false);

  /// Queue a GET. A duplicate URL is not queued twice — a reconnect
  /// that replays every screen would otherwise fetch the same home
  /// feed fifty times.
  ///
  /// Returns true when the item was actually added.
  bool enqueue(QueuedGet item) {
    final key = item.uri.toString();
    if (_items.any((q) => q.uri.toString() == key)) return false;
    _items.add(item);
    while (_items.length > maxEntries) {
      _items.removeAt(0);
    }
    return true;
  }

  /// Replay everything, oldest first, through [fetch] then [sink].
  ///
  /// Stops at the first item the sink rejects or the fetcher throws:
  /// the network is evidently still down, and hammering the rest of the
  /// queue would only repeat the same failure more slowly.
  ///
  /// Returns the number of entries successfully drained. Never throws.
  Future<int> drain(QueuedGetFetcher fetch, QueuedGetSink sink) async {
    var drained = 0;
    while (_items.isNotEmpty) {
      final item = _items.first;
      bool accepted;
      try {
        accepted = await sink(item, await fetch(item));
      } catch (_) {
        break;
      }
      if (!accepted) break;
      _items.removeAt(0);
      drained += 1;
    }
    return drained;
  }

  /// Drop everything without sending. Test hook.
  void clear() => _items.clear();
}

/// Status carried by the synthetic response handed back instead of
/// throwing a timeout. 504 is what a gateway answers, and 5xx
/// classifies as retryable rather than as a definitive refusal — so a
/// caller that checks the status sees a coherent answer, and one that
/// only checks `!= 200` behaves exactly as it did before.
const int kSyntheticTimeoutStatus = 504;

/// A real response with a real status, so every existing
/// `if (res.statusCode == 200)` check keeps working and no caller has to
/// learn a new failure shape.
http.Response syntheticTimeoutResponse() =>
    http.Response('', kSyntheticTimeoutStatus);
