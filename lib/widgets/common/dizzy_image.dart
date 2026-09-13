import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../utils/perf/image_caps.dart';

/// P1 — the ONLY sanctioned image widget for remote art.
///
/// Every remote poster/backdrop/thumb/logo in Dizzy must go through here.
/// Decode size is hard-capped via [ImageCaps] so a 4K source file can never
/// inflate into an 8–30MB decoded bitmap in RAM:
///
/// - backdrop ≤960px (≈2MB) instead of 1920px (≈8MB)
/// - card     500×750px, thumb 220px, logo 400px
/// - disk cache mirrors the same cap (never stores full-res)
///
/// Use [DizzyImageKind] — never pass ad-hoc widths.
enum DizzyImageKind { backdrop, card, thumb, logo, original }

/// Maps a kind to its (memWidth, memHeight, diskWidth) caps.
(int? w, int? h, int disk) _capsFor(DizzyImageKind kind) {
  switch (kind) {
    case DizzyImageKind.backdrop:
      return (ImageCaps.kBackdrop, null, ImageCaps.kBackdrop);
    case DizzyImageKind.card:
      return (ImageCaps.kCardW, ImageCaps.kCardH, ImageCaps.kCardW);
    case DizzyImageKind.thumb:
      return (ImageCaps.kThumb, null, ImageCaps.kThumb);
    case DizzyImageKind.logo:
      return (ImageCaps.kLogo, null, ImageCaps.kLogo);
    case DizzyImageKind.original:
      return (ImageCaps.kBackdrop, null, ImageCaps.kBackdrop);
  }
}

class DizzyImage extends StatelessWidget {
  final String imageUrl;
  final DizzyImageKind kind;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;
  final Widget Function(BuildContext, String)? placeholderBuilder;
  final Widget Function(BuildContext, String, Object)? errorBuilder;

  const DizzyImage({
    super.key,
    required this.imageUrl,
    this.kind = DizzyImageKind.card,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.placeholderBuilder,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final caps = _capsFor(kind);
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      alignment: alignment,
      memCacheWidth: caps.$1,
      memCacheHeight: caps.$2,
      maxWidthDiskCache: caps.$3,
      placeholder: placeholderBuilder != null
          ? (c, u) => placeholderBuilder!(c, u)
          : (c, u) => const SizedBox.shrink(),
      errorWidget: errorBuilder != null
          ? (c, u, e) => errorBuilder!(c, u, e)
          : (c, u, e) => const SizedBox.shrink(),
    );
  }
}
