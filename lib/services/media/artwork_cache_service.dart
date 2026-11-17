import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../models/music/music_track.dart';

/// Phase K1b — local artwork for the system media notification.
///
/// The native service only decodes a local file; it never fetches. This
/// service mirrors a track's remote cover into the app cache exactly once per
/// track, so the lock screen and notification can show the real cover while
/// the app is in the background.
///
/// Fail-soft by design: no network, no cover, a full disk or a dead CDN just
/// means the notification falls back to the app icon. Artwork must never be
/// able to stop the music.
class ArtworkCacheService {
  ArtworkCacheService._();
  static final ArtworkCacheService instance = ArtworkCacheService._();

  static const Duration _timeout = Duration(seconds: 10);
  static const int _maxBytes = 5 * 1024 * 1024;

  /// Track key -> local path (null = tried and unavailable).
  final Map<String, String?> _resolved = {};
  final Map<String, Future<String?>> _inFlight = {};

  @visibleForTesting
  Directory? debugDirectoryOverride;

  @visibleForTesting
  Future<http.Response> Function(Uri uri)? debugFetch;

  @visibleForTesting
  void debugReset() {
    _resolved.clear();
    _inFlight.clear();
    debugDirectoryOverride = null;
    debugFetch = null;
  }

  /// Returns a local cover file for [track], or `null` when unavailable.
  ///
  /// Safe to call every second: the download happens at most once per track
  /// and a miss is remembered so an offline device does not retry forever.
  Future<String?> localPathFor(MusicTrack track) {
    final url = track.coverUrl.trim();
    if (url.isEmpty) return Future<String?>.value();

    final key = _keyFor(track, url);
    if (_resolved.containsKey(key)) {
      return Future<String?>.value(_resolved[key]);
    }
    return _inFlight.putIfAbsent(key, () => _resolve(key, url));
  }

  Future<String?> _resolve(String key, String url) async {
    try {
      final dir = await _directory();

      // A previous session already cached this cover — reuse it.
      for (final ext in const ['.jpg', '.png', '.webp']) {
        final existing = File(_join(dir.path, '$key$ext'));
        if (await existing.exists() && await existing.length() > 0) {
          _resolved[key] = existing.path;
          return existing.path;
        }
      }

      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) {
        _resolved[key] = null;
        return null;
      }

      final fetch = debugFetch ?? http.get;
      final response = await fetch(uri).timeout(_timeout);
      final bytes = response.bodyBytes;
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          bytes.isEmpty ||
          bytes.length > _maxBytes) {
        _resolved[key] = null;
        return null;
      }

      final file = File(
        _join(dir.path, '$key${_extension(uri, response.headers['content-type'])}'),
      );
      await file.writeAsBytes(bytes, flush: true);
      _resolved[key] = file.path;
      return file.path;
    } catch (e) {
      // Covers are optional. Never log the URL — it can carry a token.
      debugPrint('[ArtworkCache] cover unavailable: ${e.runtimeType}');
      _resolved[key] = null;
      return null;
    } finally {
      _inFlight.remove(key);
    }
  }

  String _keyFor(MusicTrack track, String url) {
    final digest = sha1.convert(url.codeUnits).toString().substring(0, 10);
    final id = track.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '${id.isEmpty ? 'track' : id}-$digest';
  }

  Future<Directory> _directory() async {
    final override = debugDirectoryOverride;
    if (override != null) {
      if (!await override.exists()) await override.create(recursive: true);
      return override;
    }
    final base = await getTemporaryDirectory();
    final dir = Directory(_join(base.path, 'media_art'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _extension(Uri uri, String? contentType) {
    final type = (contentType ?? '').toLowerCase();
    if (type.contains('png')) return '.png';
    if (type.contains('webp')) return '.webp';
    if (type.contains('jpeg') || type.contains('jpg')) return '.jpg';

    final path = uri.path.toLowerCase();
    if (path.endsWith('.png')) return '.png';
    if (path.endsWith('.webp')) return '.webp';
    if (path.endsWith('.jpeg') || path.endsWith('.jpg')) return '.jpg';
    return '.jpg';
  }

  String _join(String dir, String name) =>
      '$dir${Platform.pathSeparator}$name';
}
