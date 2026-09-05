import 'dart:async';
import 'dart:io';
import '../../models/stream/stream_model.dart';
import '../player/player_settings.dart';

/// Production-grade HTTP/HLS/MP4 Stream Health & Liveness Checker for DizzyHTTP.
///
/// Uses lightweight zero-memory HEAD and range probes with Accept-Cookies handling,
/// respecting exact headers, referrers, and origins without downloading full video streams.
class StreamHealthChecker {
  /// Tests if a [StreamSource] is alive and delivers a valid video/audio stream.
  /// Automatically accepts cookies from responses & redirects and attaches them back to [source.headers].
  ///
  /// Torrent streams (`infoHash != null`) are always considered alive by this checker.
  static Future<bool> isAlive(StreamSource source) async {
    // Torrents are managed by TorrServer / DHT on-demand
    if (source.infoHash != null && source.infoHash!.isNotEmpty) {
      return true;
    }

    final rawUrl = source.url ?? source.externalUrl;
    if (rawUrl == null || rawUrl.isEmpty || !rawUrl.startsWith('http')) {
      return false;
    }

    // Resolve complete headers (including Referer, Origin, User-Agent)
    final effectiveHeaders = PlayerSettings.resolveStreamHeaders(rawUrl, source.headers);
    final cookiesCaptured = <String>[];

    final alive = await _probeUrl(rawUrl, effectiveHeaders, 0, cookiesCaptured);

    // Accept captured cookies and persist them into the source headers
    if (alive && cookiesCaptured.isNotEmpty) {
      final existingCookie = source.headers?['Cookie'] ?? source.headers?['cookie'] ?? '';
      source.headers ??= {};
      source.headers!['Cookie'] = _mergeCookies(existingCookie, cookiesCaptured);
    }

    return alive;
  }

  /// Merges existing Cookie headers with incoming Set-Cookie header strings.
  static String _mergeCookies(String existing, List<String> newCookies) {
    final cookieMap = <String, String>{};
    if (existing.isNotEmpty) {
      for (final part in existing.split(';')) {
        final kv = part.trim().split('=');
        if (kv.length >= 2) {
          cookieMap[kv[0].trim()] = kv.sublist(1).join('=').trim();
        }
      }
    }
    for (final c in newCookies) {
      final mainPart = c.split(';').first.trim();
      final kv = mainPart.split('=');
      if (kv.length >= 2) {
        cookieMap[kv[0].trim()] = kv.sublist(1).join('=').trim();
      }
    }
    return cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Probes the stream URL using a zero-memory HEAD request with Accept-Cookies handling.
  static Future<bool> _probeUrl(
    String url,
    Map<String, String> headers, [
    int redirectCount = 0,
    List<String>? cookiesCaptured,
  ]) async {
    if (redirectCount > 3) return false;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;

    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3)
        ..badCertificateCallback = ((_, __, ___) => true);

      // 1. Send fast HEAD request (0 MB downloaded!)
      final req = await client.openUrl('HEAD', uri).timeout(const Duration(seconds: 3));
      req.followRedirects = false;

      headers.forEach((k, v) {
        if (v.isNotEmpty && k.toLowerCase() != 'range' && k.toLowerCase() != 'content-length') {
          try {
            req.headers.set(k, v);
          } catch (_) {}
        }
      });
      req.headers.set('User-Agent', headers['User-Agent'] ?? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
      req.headers.set('Accept', '*/*');

      final resp = await req.close().timeout(const Duration(seconds: 3));
      final code = resp.statusCode;

      // Capture Set-Cookie headers
      for (final c in resp.cookies) {
        cookiesCaptured?.add('${c.name}=${c.value}');
      }

      // Handle 3xx Redirects
      if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        if (loc != null && loc.isNotEmpty) {
          final redirectedUri = uri.resolve(loc).toString();
          final redirectHeaders = PlayerSettings.resolveStreamHeaders(redirectedUri, headers);
          if (cookiesCaptured != null && cookiesCaptured.isNotEmpty) {
            final existing = redirectHeaders['Cookie'] ?? redirectHeaders['cookie'] ?? '';
            redirectHeaders['Cookie'] = _mergeCookies(existing, cookiesCaptured);
          }
          client.close(force: true);
          return await _probeUrl(redirectedUri, redirectHeaders, redirectCount + 1, cookiesCaptured);
        }
        return false;
      }

      // If HEAD returns 200 or 206, verify it's not an HTML/JSON error page
      if (code == 200 || code == 206) {
        final ct = (resp.headers.contentType?.mimeType ?? '').toLowerCase();
        final isDead = ct.contains('text/html') || ct.contains('application/json') || ct.contains('text/xml');
        if (!isDead) return true;
        return false;
      }

      // If HEAD is blocked (405 Method Not Allowed or 403), fallback to lightweight 64-byte GET
      if (code == 405 || code == 403 || code == 400) {
        final getReq = await client.openUrl('GET', uri).timeout(const Duration(seconds: 3));
        getReq.followRedirects = false;
        headers.forEach((k, v) {
          if (v.isNotEmpty) {
            try { getReq.headers.set(k, v); } catch (_) {}
          }
        });
        getReq.headers.set('Range', 'bytes=0-64');
        final getResp = await getReq.close().timeout(const Duration(seconds: 3));
        final getCode = getResp.statusCode;
        if (getCode == 200 || getCode == 206) {
          await getResp.drain();
          return true;
        }
      }

      return false;
    } catch (_) {
      return false;
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
    }
  }
}
