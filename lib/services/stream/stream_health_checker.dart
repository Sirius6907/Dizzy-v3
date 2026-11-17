import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../models/stream/stream_model.dart';
import 'html_stream_resolver.dart';
import 'torrent_stream_service.dart';
import '../player/player_settings.dart';

/// Production-grade HTTP/HLS/MP4 Stream Health & Liveness Checker for built-in sources.
///
/// Uses lightweight zero-memory HEAD and range probes with Accept-Cookies handling,
/// respecting exact headers, referrers, and origins without downloading full video streams.
class StreamHealthChecker {
  /// Tests if a [StreamSource] is alive and delivers a valid video/audio stream.
  /// Automatically accepts cookies from responses & redirects and attaches them back to [source.headers].
  ///
  /// Torrent streams are only "alive" for instant play when they expose
  /// seeders and the TorrServer engine already has bytes cached; otherwise
  /// they win the race and then stall waiting for metadata/DHT.
  static Future<bool> isAlive(
    StreamSource source, {
    http.Client Function()? clientFactory,
  }) async {
    // v1.3.5: an embed source IS a page. Probing its URL with a HEAD would
    // either fail the TLS/JS gate or prove nothing — the webview is the probe,
    // and it is never "dead" before it has been given a chance to load.
    if (source.isEmbedSource) {
      source.probeDead = false;
      return true;
    }

    if (source.infoHash != null &&
        source.infoHash!.isNotEmpty &&
        !source.isDebrid) {
      final seeders = source.seeders;
      if (!isTorrentCandidateViable(seeders: seeders)) {
        source.probeDead = true;
        return false;
      }
      // Instant play only: a cold torrent still has to gather metadata and
      // peers. It stays in the failover chain — the ranker decides when the
      // torrent tier is reached, not this probe.
      final cached = TorrentStreamService().isCached(source.infoHash!);
      // A cold torrent is not "dead" — it is a last-resort candidate that
      // needs a swarm. Only a torrent without peers is dropped for good.
      source.probeDead = false;
      return cached;
    }

    final rawUrl = source.url ?? source.externalUrl;
    if (rawUrl == null || rawUrl.isEmpty || !rawUrl.startsWith('http')) {
      return false;
    }

    // Resolve complete headers (including Referer, Origin, User-Agent)
    final effectiveHeaders = PlayerSettings.resolveStreamHeaders(
      rawUrl,
      source.headers,
    );
    final cookiesCaptured = <String>[];

    final alive = await _probeUrl(
      rawUrl,
      effectiveHeaders,
      cookiesCaptured,
      clientFactory: clientFactory,
      source: source,
    );

    // The verdict travels with the source: the failover chain must not pick a
    // source the probe already proved dead.
    source.probeDead = !alive;

    // Accept captured cookies and persist them into the source headers
    if (alive && cookiesCaptured.isNotEmpty) {
      final existingCookie =
          source.headers?['Cookie'] ?? source.headers?['cookie'] ?? '';
      source.headers ??= {};
      source.headers!['Cookie'] = _mergeCookies(
        existingCookie,
        cookiesCaptured,
      );
    }

    return alive;
  }

  /// A torrent candidate is viable when it advertises peers. An unknown peer
  /// count is NOT treated as dead — the swarm decides that at warm-up time.
  static bool isTorrentCandidateViable({int? seeders}) =>
      seeders == null || seeders > 0;

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
    for (final cookie in newCookies) {
      final mainPart = cookie.split(';').first.trim();
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

  /// Probes the stream URL using a zero-memory HEAD request with Accept-Cookies
  /// handling, and confirms a suspicious HEAD answer with a ranged GET.
  ///
  /// Many extractors answer HEAD with their HTML player page, so a dead-looking
  /// HEAD is only a suspicion: the ranged GET decides.
  static Future<bool> _probeUrl(
    String url,
    Map<String, String> headers,
    List<String> cookiesCaptured, {
    http.Client Function()? clientFactory,
    int redirectCount = 0,
    StreamSource? source,
  }) async {
    if (redirectCount > 3) return false;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;

    final client = clientFactory?.call() ?? _defaultClient();
    try {
      // 1. Fast HEAD request (0 MB downloaded!)
      final head = http.Request('HEAD', uri)..followRedirects = false;
      head.headers.addAll(_requestHeaders(headers));
      final resp = await client.send(head).timeout(const Duration(seconds: 4));
      final code = resp.statusCode;

      // Capture Set-Cookie headers
      cookiesCaptured.addAll(_setCookies(resp));

      // Handle 3xx Redirects
      if (code == 301 ||
          code == 302 ||
          code == 303 ||
          code == 307 ||
          code == 308) {
        final loc = resp.headers['location'];
        if (loc != null && loc.isNotEmpty) {
          final redirectedUri = uri.resolve(loc).toString();
          final redirectHeaders = PlayerSettings.resolveStreamHeaders(
            redirectedUri,
            headers,
          );
          if (cookiesCaptured.isNotEmpty) {
            final existing =
                redirectHeaders['Cookie'] ?? redirectHeaders['cookie'] ?? '';
            redirectHeaders['Cookie'] = _mergeCookies(
              existing,
              cookiesCaptured,
            );
          }
          return await _probeUrl(
            redirectedUri,
            redirectHeaders,
            cookiesCaptured,
            clientFactory: clientFactory,
            redirectCount: redirectCount + 1,
            source: source,
          );
        }
        return false;
      }

      if (code == 200 || code == 206) {
        final ct = (resp.headers['content-type'] ?? '').toLowerCase();
        if (!_contentTypeLooksLikeErrorPage(ct)) return true;
        // A HEAD that answers with an error page is only a suspicion —
        // confirm with a ranged GET before dropping the source.
      } else if (code != 405 && code != 501) {
        // Any other 4xx/5xx fails fast — no second request.
        return false;
      }

      // 2. Confirm with a lightweight ranged GET (also the fallback when HEAD
      // is not allowed). Any other 4xx/5xx fails fast.
      final get = http.Request('GET', uri)..followRedirects = true;
      get.headers.addAll(_requestHeaders(headers));
      get.headers['Range'] = 'bytes=0-512';
      final getResp = await client
          .send(get)
          .timeout(const Duration(seconds: 4));
      final getCode = getResp.statusCode;

      cookiesCaptured.addAll(_setCookies(getResp));

      // 200 (OK), 206 (Partial), 416 (Range Not Satisfiable = endpoint is
      // an active video server).
      if (getCode == 200 || getCode == 206 || getCode == 416) {
        if (getCode == 416) return true;
        final ct = (getResp.headers['content-type'] ?? '').toLowerCase();
        final bytes = <int>[];
        await for (final chunk in getResp.stream) {
          bytes.addAll(chunk);
          if (bytes.length >= 512) break;
        }
        // The body decides when the content type lied: an extractor that
        // answers with its HTML player page is not a playable source —
        // UNLESS the page carries the stream (which is the normal case for
        // the embed-style extractors). The stream behind the page is
        // extracted here, so a working source is no longer marked dead.
        final sniff = utf8
            .decode(bytes.take(64).toList(), allowMalformed: true)
            .trimLeft()
            .toLowerCase();
        final body = utf8.decode(bytes, allowMalformed: true);
        if (sniff.startsWith('<!doctype html') || sniff.startsWith('<html')) {
          final media = HtmlStreamResolver.extractMediaUrl(body, pageUrl: url);
          if (media != null) {
            source?.resolvedMediaUrl = media.url;
            return true;
          }
          return false;
        }
        if (_looksDead(ct, url)) {
          final media = HtmlStreamResolver.extractMediaUrl(body, pageUrl: url);
          if (media != null) {
            source?.resolvedMediaUrl = media.url;
            return true;
          }
          return false;
        }
        return true;
      }

      return false;
    } catch (_) {
      return false;
    } finally {
      try {
        client.close();
      } catch (_) {}
    }
  }

  /// Set-Cookie header values of a response (package:http keeps them raw).
  static List<String> _setCookies(http.StreamedResponse response) {
    final raw = response.headers['set-cookie'];
    if (raw == null) return const <String>[];
    // A joined header keeps its commas (Expires dates contain them), so it
    // is treated as one cookie header instead of being split.
    return [raw];
  }

  /// True when the content type itself announces an error page.
  static bool _contentTypeLooksLikeErrorPage(String contentType) {
    final ct = contentType.toLowerCase();
    return ct.contains('text/html') ||
        ct.contains('application/json') ||
        ct.contains('text/xml');
  }

  /// True when the response looks like an error page rather than media.
  static bool _looksDead(String contentType, String url) {
    final ct = contentType.toLowerCase();
    final dead =
        ct.contains('text/html') ||
        ct.contains('application/json') ||
        ct.contains('text/xml');
    return dead && !_isKnownMediaUrl(url);
  }

  static Map<String, String> _requestHeaders(Map<String, String> headers) {
    final out = <String, String>{};
    headers.forEach((k, v) {
      if (v.isNotEmpty &&
          k.toLowerCase() != 'range' &&
          k.toLowerCase() != 'content-length') {
        out[k] = v;
      }
    });
    out['User-Agent'] =
        headers['User-Agent'] ??
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
    out['Accept'] = '*/*';
    return out;
  }

  static http.Client _defaultClient() {
    // v1.1.9: only accept bad certs when the user explicitly opted in
    // (local/dev servers). Default OFF — blind accept was a MITM hole.
    final allowInsecure = PlayerSettings.allowInsecureProbes.value;
    return IOClient(
      HttpClient()
        ..connectionTimeout = const Duration(seconds: 4)
        ..badCertificateCallback = ((_, __, ___) => allowInsecure),
    );
  }
}
