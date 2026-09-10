import 'dart:async';
import 'dart:io';
import '../../models/stream/stream_model.dart';
import '../player/player_settings.dart';

/// Production-grade HTTP/HLS/MP4 Stream Health & Liveness Checker for built-in sources.
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

  static bool _isKnownMediaUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.mkv') ||
        lower.contains('.ts') ||
        lower.contains('/hls/') ||
        lower.contains('master.m3u8');
  }

  /// Probes the stream URL using a zero-memory HEAD request with Accept-Cookies handling,
  /// with automatic fallback to GET when HEAD is not supported by the CDN/origin.
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
      // v1.1.9: only accept bad certs when the user explicitly opted in
      // (local/dev servers). Default OFF — blind accept was an MITM hole.
      final allowInsecure = PlayerSettings.allowInsecureProbes.value;
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4)
        ..badCertificateCallback = ((_, __, ___) => allowInsecure);

      // 1. Send fast HEAD request (0 MB downloaded!)
      final req = await client.openUrl('HEAD', uri).timeout(const Duration(seconds: 4));
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

      final resp = await req.close().timeout(const Duration(seconds: 4));
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
        if (!isDead || _isKnownMediaUrl(url)) return true;
        return false;
      }

      // 2. If HEAD is not allowed (405/501), fallback to lightweight GET.
      // Many CDNs (Cloudflare, Akamai, video proxies) reject HEAD requests.
      // Any other 4xx/5xx fails fast — no second request (v1.1.9 halves
      // slow-network probe cost per dead source).
      if (code != 405 && code != 501) return false;
      final getReq = await client.openUrl('GET', uri).timeout(const Duration(seconds: 4));
      getReq.followRedirects = true;
      getReq.maxRedirects = 4;
      headers.forEach((k, v) {
        if (v.isNotEmpty && k.toLowerCase() != 'range' && k.toLowerCase() != 'content-length') {
          try { getReq.headers.set(k, v); } catch (_) {}
        }
      });
      getReq.headers.set('User-Agent', headers['User-Agent'] ?? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
      getReq.headers.set('Accept', '*/*');
      getReq.headers.set('Range', 'bytes=0-512');

      final getResp = await getReq.close().timeout(const Duration(seconds: 4));
      final getCode = getResp.statusCode;

      for (final c in getResp.cookies) {
        cookiesCaptured?.add('${c.name}=${c.value}');
      }

      // 200 (OK), 206 (Partial), 416 (Range Not Satisfiable = endpoint is active video server)
      if (getCode == 200 || getCode == 206 || getCode == 416) {
        final ct = (getResp.headers.contentType?.mimeType ?? '').toLowerCase();
        final isDead = (ct.contains('text/html') || ct.contains('application/json') || ct.contains('text/xml')) &&
            !_isKnownMediaUrl(url);
        await getResp.drain();
        return !isDead;
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
