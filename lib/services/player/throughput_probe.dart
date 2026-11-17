/// Real throughput measurement for the first bytes of a stream.
///
/// "Auto" quality must not guess from one noisy sample *after* the fact (the
/// old P8 meter needs a 10s stable window, so a 4K source already stuttered
/// for 10s before the ladder reacted). This probe times a small range request
/// against the very host that will serve playback, so the start decision is
/// based on measured bandwidth — not on a preset or on the network type.
///
/// Cost is bounded: at most [maxBytes] and at most [maxDuration]. Data Saver
/// callers pass a smaller cap.
library;

import 'dart:async';
import 'dart:io';

class ThroughputProbe {
  /// Never pull more than this for one measurement.
  static const int defaultMaxBytes = 2 * 1024 * 1024;

  /// Wall-clock ceiling for one measurement.
  static const Duration defaultMaxDuration = Duration(milliseconds: 1500);

  /// Fewer bytes than this cannot separate "slow" from "did not answer".
  static const int _minJudgedBytes = 32 * 1024;

  /// Query parameters that mark an expiring/single-use URL. Probing one
  /// burns the token and adds 1.5-3 s of startup delay for a sample that is
  /// unusable moments later.
  static const Set<String> _signatureParams = {
    'expires',
    'exp',
    'expiry',
    'signature',
    'sig',
    'token',
    'auth_key',
    'policy',
    'key-pair-id',
    'x-amz-signature',
    'x-amz-credential',
    'hdnts',
  };

  /// True when [url] must not be probed: HLS masters answer with a few KB of
  /// playlist text (the sample would mean "slow"), and signed links are
  /// one-shot.
  static bool shouldSkip(String? url) {
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.path.toLowerCase().contains('.m3u8')) return true;
    for (final key in uri.queryParametersAll.keys) {
      if (_signatureParams.contains(key.toLowerCase())) return true;
    }
    return false;
  }

  /// Measures download throughput (Mbps) for [url] by reading a bounded
  /// range of its bytes. Returns null when no trustworthy sample exists
  /// (non-http URL, instant completion of a tiny file, network error).
  static Future<double?> measureMbps(
    String? url, {
    Map<String, String>? headers,
    int maxBytes = defaultMaxBytes,
    Duration maxDuration = defaultMaxDuration,
  }) async {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    // TorrServer's loopback endpoint reads from local cache/disk — it says
    // nothing about the internet link.
    if (uri.host == '127.0.0.1' || uri.host == 'localhost') return null;
    // HLS playlists and one-shot signed URLs cannot be measured meaningfully.
    if (shouldSkip(url)) return null;

    HttpClient? client;
    StreamSubscription<List<int>>? sub;
    final clock = Stopwatch()..start();
    var bytes = 0;
    final done = Completer<void>();

    void finish() {
      if (!done.isCompleted) done.complete();
    }

    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3)
        ..autoUncompress = false;

      final req = await client
          .openUrl('GET', uri)
          .timeout(const Duration(seconds: 3));
      req.headers.set('Range', 'bytes=0-${maxBytes - 1}');
      req.headers.set(
        'User-Agent',
        headers?['User-Agent'] ??
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      );
      final headerKeys = headers?.keys ?? const <String>[];
      for (final k in headerKeys) {
        final v = headers![k];
        if (v == null || v.isEmpty) continue;
        if (k.toLowerCase() == 'range' || k.toLowerCase() == 'user-agent') {
          continue;
        }
        try {
          req.headers.set(k, v);
        } catch (_) {}
      }
      req.headers.set('Accept', '*/*');

      final resp = await req.close().timeout(const Duration(seconds: 3));
      if (resp.statusCode >= 400) {
        await resp.drain<void>();
        return null;
      }

      final timer = Timer(maxDuration, () {
        finish();
      });
      sub = resp.listen(
        (chunk) {
          bytes += chunk.length;
          if (bytes >= maxBytes || clock.elapsed >= maxDuration) finish();
        },
        onError: (_) => finish(),
        onDone: finish,
        cancelOnError: true,
      );

      await done.future;
      timer.cancel();
      await sub.cancel();

      final seconds = clock.elapsedMicroseconds / 1000000.0;
      if (bytes < _minJudgedBytes || seconds <= 0) return null;
      final mbps = (bytes * 8) / seconds / 1000000.0;
      // A sample that filled the cap instantly means "faster than we can
      // measure"; report the observed rate (already high) honestly.
      return mbps;
    } catch (_) {
      return null;
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
    }
  }
}
