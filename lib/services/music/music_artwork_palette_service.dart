import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/music/music_track.dart';

class MusicTrackPalette {
  final Color primary;
  final Color secondary;
  final Color background;
  final Color accent;

  const MusicTrackPalette({
    required this.primary,
    required this.secondary,
    required this.background,
    required this.accent,
  });

  static const defaultDark = MusicTrackPalette(
    primary: Color(0xFF7C5CFF),
    secondary: Color(0xFF00D2EF),
    background: Color(0xFF080A12),
    accent: Color(0xFFB57CFF),
  );
}

/// High-speed, zero-dependency dominant color extractor with LRU caching.
/// Samples a tiny 16x16 thumbnail of the artwork (~256 pixels) in microseconds.
class MusicArtworkPaletteService {
  MusicArtworkPaletteService._();
  static final MusicArtworkPaletteService instance = MusicArtworkPaletteService._();

  final Map<String, MusicTrackPalette> _cache = {};
  final Map<String, Completer<MusicTrackPalette>> _inFlight = {};

  /// Synchronous fast fallback based on track metadata hash
  MusicTrackPalette getFastPalette(MusicTrack track) {
    if (_cache.containsKey(track.id)) {
      return _cache[track.id]!;
    }

    final hash = (track.title + track.artist).hashCode.abs();
    final hue1 = (hash % 360).toDouble();
    final hue2 = ((hash ~/ 360) % 360).toDouble();

    final c1 = HSLColor.fromAHSL(1.0, hue1, 0.70, 0.55).toColor();
    final c2 = HSLColor.fromAHSL(1.0, hue2, 0.65, 0.60).toColor();
    final bg = HSLColor.fromAHSL(1.0, hue1, 0.40, 0.08).toColor();
    final accent = HSLColor.fromAHSL(1.0, (hue1 + 40) % 360, 0.80, 0.70).toColor();

    final palette = MusicTrackPalette(
      primary: c1,
      secondary: c2,
      background: bg,
      accent: accent,
    );

    return palette;
  }

  /// Asynchronously extracts actual dominant colors from artwork image URL
  Future<MusicTrackPalette> extractPalette(MusicTrack track) async {
    if (_cache.containsKey(track.id)) {
      return _cache[track.id]!;
    }

    if (_inFlight.containsKey(track.id)) {
      return _inFlight[track.id]!.future;
    }

    final completer = Completer<MusicTrackPalette>();
    _inFlight[track.id] = completer;

    if (track.coverUrl.isEmpty) {
      final fallback = getFastPalette(track);
      _cache[track.id] = fallback;
      completer.complete(fallback);
      _inFlight.remove(track.id);
      return fallback;
    }

    try {
      final ImageProvider provider = NetworkImage(track.coverUrl);
      final ImageStream stream = provider.resolve(const ImageConfiguration(size: Size(32, 32)));

      late ImageStreamListener listener;
      final timer = Timer(const Duration(milliseconds: 1800), () {
        if (!completer.isCompleted) {
          final fallback = getFastPalette(track);
          _cache[track.id] = fallback;
          completer.complete(fallback);
          _inFlight.remove(track.id);
        }
      });

      listener = ImageStreamListener((ImageInfo info, bool _) async {
        timer.cancel();
        try {
          final image = info.image;
          // Downscale to 16x16 to keep calculation microsecond-fast
          final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          if (byteData == null) {
            final fallback = getFastPalette(track);
            _cache[track.id] = fallback;
            if (!completer.isCompleted) completer.complete(fallback);
            return;
          }

          int rTotal = 0, gTotal = 0, bTotal = 0;
          int sampleCount = 0;
          final totalBytes = byteData.lengthInBytes;

          // Bucket colors by hue
          int maxBucket = 0;
          Color vibrantColor = const Color(0xFF7C5CFF);
          final buckets = <int, int>{};
          final bucketColors = <int, Color>{};

          // Step by 16 bytes (every 4th pixel)
          for (int i = 0; i < totalBytes; i += 16) {
            final r = byteData.getUint8(i);
            final g = byteData.getUint8(i + 1);
            final b = byteData.getUint8(i + 2);
            final a = byteData.getUint8(i + 3);

            if (a < 128) continue;
            // Ignore near blacks and near whites for vibrant color
            final brightness = (0.299 * r + 0.587 * g + 0.114 * b);
            if (brightness < 30 || brightness > 235) continue;

            rTotal += r;
            gTotal += g;
            bTotal += b;
            sampleCount++;

            final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
            // Only consider reasonably saturated colors
            if (hsl.saturation >= 0.25) {
              final hueBucket = (hsl.hue / 30).floor();
              final count = (buckets[hueBucket] ?? 0) + 1;
              buckets[hueBucket] = count;
              if (count > maxBucket) {
                maxBucket = count;
                vibrantColor = Color.fromARGB(255, r, g, b);
              }
              bucketColors[hueBucket] = Color.fromARGB(255, r, g, b);
            }
          }

          Color primary = vibrantColor;
          if (sampleCount > 0 && maxBucket == 0) {
            // If all pixels were desaturated, average them
            primary = Color.fromARGB(
              255,
              (rTotal / sampleCount).round().clamp(0, 255),
              (gTotal / sampleCount).round().clamp(0, 255),
              (bTotal / sampleCount).round().clamp(0, 255),
            );
          }

          // Generate complementary secondary color
          final hslPrimary = HSLColor.fromColor(primary);
          final secondary = HSLColor.fromAHSL(
            1.0,
            (hslPrimary.hue + 45) % 360,
            (hslPrimary.saturation * 0.9).clamp(0.4, 0.9),
            (hslPrimary.lightness * 1.1).clamp(0.35, 0.75),
          ).toColor();

          final background = HSLColor.fromAHSL(
            1.0,
            hslPrimary.hue,
            (hslPrimary.saturation * 0.5).clamp(0.2, 0.5),
            0.07,
          ).toColor();

          final accent = HSLColor.fromAHSL(
            1.0,
            (hslPrimary.hue + 180) % 360,
            0.85,
            0.65,
          ).toColor();

          final palette = MusicTrackPalette(
            primary: primary,
            secondary: secondary,
            background: background,
            accent: accent,
          );

          _cache[track.id] = palette;
          if (!completer.isCompleted) completer.complete(palette);
        } catch (_) {
          final fallback = getFastPalette(track);
          _cache[track.id] = fallback;
          if (!completer.isCompleted) completer.complete(fallback);
        } finally {
          _inFlight.remove(track.id);
        }
      }, onError: (_, __) {
        final fallback = getFastPalette(track);
        _cache[track.id] = fallback;
        if (!completer.isCompleted) completer.complete(fallback);
        _inFlight.remove(track.id);
      });

      stream.addListener(listener);
    } catch (_) {
      final fallback = getFastPalette(track);
      _cache[track.id] = fallback;
      if (!completer.isCompleted) completer.complete(fallback);
      _inFlight.remove(track.id);
    }

    return completer.future;
  }
}
