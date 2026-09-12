/// P9 — HLS master-playlist → renditions (pure string parsing).
///
/// Lets ANY extractor that emits a `.m3u8` master grow a rendition ladder
/// without being rewritten: the player fetches the master in the background,
/// parses it here, and attaches [Rendition]s to the source. Garbage in →
/// empty list out (never throw on network-supplied text).
library;

import '../../models/stream/stream_model.dart';

class HlsRenditionParser {
  /// Parse an EXT-X-STREAM-INF master. [masterUrl] resolves relative URIs.
  static List<Rendition> parseMaster(String body, String masterUrl) {
    final lines = body
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final out = <Rendition>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.toUpperCase().startsWith('#EXT-X-STREAM-INF')) continue;
      // The URI is the next non-comment line.
      String? uri;
      for (var j = i + 1; j < lines.length; j++) {
        if (!lines[j].startsWith('#')) {
          uri = lines[j];
          break;
        }
      }
      if (uri == null || uri.isEmpty) continue;
      final upper = line.toUpperCase();
      final bitrate = _numAfter(upper, 'BANDWIDTH=');
      final height = _resolutionHeight(upper);
      final label = height != null
          ? _labelForHeight(height)
          : _labelForBitrate(bitrate);
      final resolved = _resolve(masterUrl, uri);
      if (resolved.isEmpty) continue;
      out.add(Rendition(label: label, url: resolved, bitrate: bitrate));
    }
    // Best-first (unknown-bitrate keeps file order at the end).
    out.sort((a, b) {
      if (a.bitrate <= 0 && b.bitrate <= 0) return 0;
      if (a.bitrate <= 0) return 1;
      if (b.bitrate <= 0) return -1;
      return b.bitrate.compareTo(a.bitrate);
    });
    return out;
  }

  static String _labelForHeight(int h) {
    if (h >= 2000) return '2160p';
    if (h >= 1300) return '1440p';
    if (h >= 900) return '1080p';
    if (h >= 600) return '720p';
    return '480p';
  }

  static String _labelForBitrate(int bps) {
    if (bps >= 20000000) return '2160p';
    if (bps >= 8000000) return '1080p';
    if (bps >= 3000000) return '720p';
    return '480p';
  }

  static int _numAfter(String line, String key) {
    final idx = line.indexOf(key);
    if (idx < 0) return 0;
    final rest = line.substring(idx + key.length);
    final m = RegExp(r'^\d+').firstMatch(rest);
    return int.tryParse(m?.group(0) ?? '') ?? 0;
  }

  static int? _resolutionHeight(String upperLine) {
    // NOTE: input is pre-uppercased, so the 'x' separator is 'X' here.
    final m = RegExp(r'RESOLUTION=\d+X(\d+)').firstMatch(upperLine);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  static String _resolve(String base, String uri) {
    try {
      if (uri.startsWith('http://') || uri.startsWith('https://')) return uri;
      return Uri.parse(base).resolve(uri).toString();
    } catch (_) {
      return '';
    }
  }
}
