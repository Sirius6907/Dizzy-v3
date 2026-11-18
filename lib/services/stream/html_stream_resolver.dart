import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors/app_log.dart';
import '../adult/adult_log.dart';
import '../adult/adult_media.dart';

/// A media URL that was recovered from an HTML player page.
class HtmlStreamResolution {
  const HtmlStreamResolution({
    required this.url,
    this.headers = const {},
    this.kind = 'unknown',
  });

  /// The playable media URL (m3u8 / mp4 / mkv …).
  final String url;

  /// Extra headers the media host needs (Referer of the page, cookies…).
  final Map<String, String> headers;

  /// Which extraction rule produced the URL — for the log only.
  final String kind;
}

/// Resolves "player pages" into the media URL behind them.
///
/// Some upstream extractors no longer hand out a direct media URL: they
/// answer with an HTML page that only contains the stream inside a
/// script (`file: "…"`, `sources: [{file: "…"}]`, `hls: "…"`) or as a
/// `<video src>` tag. The old behaviour was to treat such a response as a
/// DEAD source, so a working scraper silently produced zero playable
/// sources — the "sources are not working" symptom.
///
/// This resolver closes that gap:
///  - [extractMediaUrl] is a pure function over an HTML body (used by the
///    health checker, which already downloaded the page);
///  - [resolve] does the network round trip and is used by the player
///    right before the media is opened.
class HtmlStreamResolver {
  static const _maxBodyBytes = 512 * 1024;

  /// True when the URL plausibly points at a page rather than a media
  /// file. Media URLs skip the resolver entirely (no extra request).
  static bool looksLikeMediaUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.startsWith('http://127.0.0.1') || lower.startsWith('http://localhost')) {
      // Local torrent engine stream.
      return true;
    }
    for (final ext in const [
      '.m3u8',
      '.mp4',
      '.mkv',
      '.webm',
      '.m4v',
      '.mov',
      '.avi',
      '.ts',
      '.flv',
      '.mpd',
    ]) {
      if (lower.contains(ext)) return true;
    }
    return false;
  }

  /// True when the body sniffs like an HTML document.
  static bool looksLikeHtml(String body) {
    final head = body.trimLeft().toLowerCase();
    if (head.isEmpty) return false;
    return head.startsWith('<!doctype html') ||
        head.startsWith('<html') ||
        head.startsWith('<?xml') && head.contains('<html') ||
        head.startsWith('<script') ||
        head.startsWith('<body') ||
        head.contains('<html') ||
        head.contains('<script');
  }

  /// Fetches [url] and returns the media URL hidden in an HTML player
  /// page. Returns null when the URL already serves media (or the page
  /// carries no usable stream).
  static Future<HtmlStreamResolution?> resolve(
    String url, {
    Map<String, String>? headers,
    http.Client Function()? clientFactory,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (url.isEmpty || !url.startsWith('http')) return null;
    if (looksLikeMediaUrl(url)) return null;

    final client = clientFactory?.call() ?? http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = true
        ..headers.addAll(_cleanHeaders(headers));
      // Ask for a slice: an HTML page is small, and a media response is
      // cut off before it can waste bandwidth.
      request.headers['Range'] = 'bytes=0-${_maxBodyBytes - 1}';

      final response = await client.send(request).timeout(timeout);
      final contentType =
          (response.headers['content-type'] ?? '').toLowerCase();

      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        if (bytes.length >= _maxBodyBytes) break;
      }
      if (bytes.isEmpty) return null;

      final body = utf8.decode(bytes.take(_maxBodyBytes).toList(),
          allowMalformed: true);

      final isHtml = contentType.contains('text/html') ||
          contentType.contains('application/xhtml') ||
          looksLikeHtml(body);
      if (!isHtml) return null;

      final media = extractMediaUrl(body, pageUrl: url);
      if (media == null) return null;

      final out = <String, String>{};
      final ref = headers?['Referer'] ?? headers?['referer'];
      out['Referer'] = (ref != null && ref.isNotEmpty) ? ref : url;
      final cookie = response.headers['set-cookie'];
      if (cookie != null && cookie.isNotEmpty) {
        out['Cookie'] = cookie.split(';').first;
      }

      final adult = AdultMedia.isAdultUrl(url) ||
          AdultMedia.isAdultUrl(media.url);
      AppLog.d(
        '[HtmlResolver] resolved player page → media: '
        '${media.kind} ${adult ? AdultLog.redactUrl(media.url) : media.url}',
      );
      return HtmlStreamResolution(
        url: media.url,
        headers: out,
        kind: media.kind,
      );
    } catch (e) {
      // A page URL or HTML error can carry the adult slug; keep only the host.
      if (AdultMedia.isAdultUrl(url)) {
        AppLog.d(
          '[HtmlResolver] resolve failed for ${AdultLog.redactUrl(url)}: '
          '${AdultLog.redactError(e)}',
        );
      } else {
        AppLog.d('[HtmlResolver] resolve failed for $url: $e');
      }
      return null;
    } finally {
      try {
        client.close();
      } catch (_) {}
    }
  }

  /// Extracts the media URL from an HTML player page.
  ///
  /// The rules are ordered by how specific they are, so a JWPlayer
  /// `file:` entry wins over a random CDN link in a footer.
  static HtmlStreamResolution? extractMediaUrl(
    String rawBody, {
    String? pageUrl,
  }) {
    if (rawBody.isEmpty) return null;
    final body = _unescape(rawBody);

    // 1. Player-config objects: file / hls / src / playlist / source.
    const fieldNames = [
      'file',
      'hls',
      'hls_url',
      'src',
      'source',
      'playlist',
      'playlist_url',
      'video_url',
      'stream_url',
      'url',
    ];
    for (final field in fieldNames) {
      final re = RegExp(
        '"$field"\\s*:\\s*"([^"]+)"',
        caseSensitive: false,
      );
      for (final m in re.allMatches(body)) {
        final candidate = _absolute(m.group(1) ?? '', pageUrl);
        if (_isPlayable(candidate)) {
          return HtmlStreamResolution(url: candidate, kind: 'json:$field');
        }
      }
    }

    // 2. `sources: [{file: "…"}]` / `[{file:"…",label:"…"}]`
    final srcBlock = RegExp(
      r'sources?\s*[:=]\s*\[(.{0,4000}?)\]',
      caseSensitive: false,
    ).firstMatch(body);
    if (srcBlock != null) {
      final fileRe = RegExp(
        r'''file\s*:\s*["']([^"']+)["']''',
        caseSensitive: false,
      );
      for (final m in fileRe.allMatches(srcBlock.group(1) ?? '')) {
        final candidate = _absolute(m.group(1) ?? '', pageUrl);
        if (_isPlayable(candidate)) {
          return HtmlStreamResolution(url: candidate, kind: 'sources[]');
        }
      }
    }

    // 3. HTML media tags / data attributes.
    const attrNames = [
      'src',
      'data-src',
      'data-file',
      'data-url',
      'data-video',
      'data-stream',
      'file',
      'content',
    ];
    for (final attr in attrNames) {
      final re = RegExp(
        '$attr\\s*=\\s*["\']([^"\']+)["\']',
        caseSensitive: false,
      );
      for (final m in re.allMatches(body)) {
        final candidate = _absolute(m.group(1) ?? '', pageUrl);
        if (_isPlayable(candidate)) {
          return HtmlStreamResolution(url: candidate, kind: 'attr:$attr');
        }
      }
    }

    // 4. Bare media URLs anywhere in the page.
    final bare = RegExp(
      r'''https?://[^\s"'<>\\]+?\.(?:m3u8|mp4|m4v|mkv|webm|ts)(?:\?[^\s"'<>\\]*)?''',
      caseSensitive: false,
    );
    for (final m in bare.allMatches(body)) {
      final candidate = m.group(0) ?? '';
      if (_isPlayable(candidate)) {
        return HtmlStreamResolution(url: candidate, kind: 'bare');
      }
    }

    // 5. HLS playlist paths served from the page host.
    final hlsPath = RegExp(
      r'''["'](/[^\s"']*?(?:playlist|master|index)[^\s"']*?\.m3u8[^\s"']*)["']''',
      caseSensitive: false,
    ).firstMatch(body);
    if (hlsPath != null && pageUrl != null) {
      final candidate = Uri.parse(pageUrl).resolve(hlsPath.group(1) ?? '').toString();
      if (_isPlayable(candidate)) {
        return HtmlStreamResolution(url: candidate, kind: 'relative-m3u8');
      }
    }

    return null;
  }

  /// True when the URL is something a player can actually open.
  static bool _isPlayable(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    if (lower.startsWith('data:')) return false;
    if (lower.contains('javascript:')) return false;
    if (lower.contains('/error')) return false;
    if (lower.endsWith('.txt')) return false;
    const playable = [
      '.m3u8',
      '.mp4',
      '.m4v',
      '.mkv',
      '.webm',
      '.ts',
      '.flv',
      '.mpd',
    ];
    if (playable.any(lower.contains)) return true;
    // Some CDNs serve HLS from extension-less paths.
    if (lower.contains('/hls/') ||
        lower.contains('/master') ||
        lower.contains('/playlist')) {
      return true;
    }
    return false;
  }

  static String _absolute(String url, String? pageUrl) {
    var u = url.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('//')) u = 'https:$u';
    if (u.startsWith('/') && pageUrl != null) {
      try {
        return Uri.parse(pageUrl).resolve(u).toString();
      } catch (_) {
        return u;
      }
    }
    return u;
  }

  /// Undoes the two obfuscations player pages use for their URLs.
  static String _unescape(String body) {
    return body
        .replaceAll(r'\u002F', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\/', '/')
        .replaceAll('&amp;', '&');
  }

  static Map<String, String> _cleanHeaders(Map<String, String>? headers) {
    final out = <String, String>{};
    if (headers == null) return out;
    headers.forEach((k, v) {
      if (v.isNotEmpty &&
          k.toLowerCase() != 'range' &&
          k.toLowerCase() != 'content-length') {
        out[k] = v;
      }
    });
    out['User-Agent'] = out['User-Agent'] ??
        out['user-agent'] ??
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
    out['Accept'] =
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
    return out;
  }
}
