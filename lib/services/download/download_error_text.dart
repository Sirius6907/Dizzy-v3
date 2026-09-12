/// v1.2.0-T2.2: raw download errors → Easy English user lines.
///
/// SINGLE SOURCE: this map must match UIUX.md §5 (Raw → Easy English table).
/// The `error` field stored on [DownloadTask] is ALWAYS the easy line —
/// raw exception text is never shown and never persisted.
///
/// Error CODES follow TRD.md §8.1 taxonomy (stable strings the admin
/// dashboard groups by). Only the code + screen travel to the server
/// (opt-in, via AppErrorLog) — never raw text, URLs, or titles.
class DownloadErrorText {
  const DownloadErrorText._();

  /// Classify a raw exception/message into a stable taxonomy code.
  /// Pure — safe to unit test without any platform services.
  static String classify(String raw) {
    final t = raw.toLowerCase();

    if (t.contains('insufficient free disk space') ||
        t.contains('no space left') ||
        t.contains('enospc') ||
        t.contains('storage is full')) {
      return 'E_SPACE_FULL';
    }
    if (t.contains('http 401') ||
        t.contains('http 403') ||
        t.contains('unauthorized') ||
        t.contains('forbidden') ||
        t.contains('needs login')) {
      return 'E_HTTP_401_403';
    }
    if (t.contains('http 404') ||
        t.contains('http 410') ||
        t.contains('not found') ||
        t.contains('gone')) {
      return 'E_HTTP_404_410';
    }
    if (t.contains('http 416') || t.contains('range_not_satisfiable')) {
      return 'E_HTTP_416_RANGE';
    }
    if (RegExp(r'http 5\d\d').hasMatch(t) ||
        t.contains('internal server error') ||
        t.contains('bad gateway') ||
        t.contains('service unavailable')) {
      return 'E_HTTP_5XX';
    }
    if (t.contains('empty download url') ||
        t.contains('moved or deleted') ||
        t.contains('file not found')) {
      return 'E_FILE_GONE';
    }
    if (t.contains('torrserver') ||
        t.contains('magnet') ||
        t.contains('infohash') ||
        t.contains('info_hash') ||
        t.contains('swarm') ||
        t.contains('torrent')) {
      return 'E_P2P_ENGINE';
    }
    if (t.contains('debrid')) {
      return 'E_DEBRID_RESOLVE';
    }
    if (t.contains('hls') ||
        t.contains('m3u8') ||
        t.contains('segment') ||
        t.contains('aes-128') ||
        t.contains('playlist')) {
      return 'E_HLS_PARSE';
    }
    if (t.contains('socketexception') ||
        t.contains('timeout') ||
        t.contains('timed out') ||
        t.contains('connection reset') ||
        t.contains('connection terminated') ||
        t.contains('failed host lookup') ||
        t.contains('network is unreachable') ||
        t.contains('handshake') ||
        t.contains('connection refused')) {
      return 'E_NET_TIMEOUT';
    }
    return 'E_UNKNOWN';
  }

  /// Easy-English user line for a taxonomy code. Never technical.
  static String easyText(String code) {
    switch (code) {
      case 'E_NET_TIMEOUT':
        return 'Slow internet. Trying again…';
      case 'E_HTTP_401_403':
        return 'This link needs login. Try another source.';
      case 'E_HTTP_404_410':
        return 'This file is gone. Pick another source.';
      case 'E_HTTP_416_RANGE':
        return 'Picking up where it stopped…';
      case 'E_HTTP_5XX':
        return 'Source is busy. Trying another…';
      case 'E_SPACE_FULL':
        return 'Phone storage is full. Free some space.';
      case 'E_FILE_GONE':
        return 'File was moved or deleted.';
      case 'E_P2P_ENGINE':
        return "Torrent engine didn't start. Try direct source.";
      case 'E_DEBRID_RESOLVE':
        return 'Cloud link failed. Try direct source.';
      case 'E_HLS_PARSE':
        return "This video won't load. Try another source.";
      default:
        return "Couldn't save. Tap Retry.";
    }
  }

  /// One-step: raw → user line.
  static String fromRaw(String raw) => easyText(classify(raw));

  /// Follow-up action hint for the UI (which button to offer).
  /// 'retry' | 'another' | 'direct' | 'storage' | 'remove' | 'none'
  static String action(String code) {
    switch (code) {
      case 'E_HTTP_401_403':
      case 'E_HTTP_404_410':
      case 'E_HTTP_5XX':
      case 'E_HLS_PARSE':
        return 'another';
      case 'E_P2P_ENGINE':
      case 'E_DEBRID_RESOLVE':
        return 'direct';
      case 'E_SPACE_FULL':
        return 'storage';
      case 'E_FILE_GONE':
        return 'remove';
      case 'E_HTTP_416_RANGE':
        return 'none';
      default:
        return 'retry';
    }
  }
}
