import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class HomeHeroTitle extends StatelessWidget {
  final String title;
  final String? logoUrl;
  final bool isCompact;

  const HomeHeroTitle({super.key,
    required this.title,
    required this.logoUrl,
    required this.isCompact,
  });

  @override
  Widget build(BuildContext context) {
    final maxHeight = isCompact ? 76.0 : 118.0;
    final textStyle = TextStyle(
      fontSize: isCompact ? 32 : 46,
      fontWeight: FontWeight.w900,
      letterSpacing: -1.2,
      height: 1.05,
      color: Colors.white,
    );

    final titleText = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: textStyle,
    );

    if (logoUrl == null || logoUrl!.isEmpty) {
      return titleText;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: CachedNetworkImage(
          imageUrl: logoUrl!,
          fit: BoxFit.contain,
          alignment: Alignment.bottomLeft,
          filterQuality: FilterQuality.medium,
          memCacheWidth: 800,
          maxWidthDiskCache: 800,
          fadeInDuration: const Duration(milliseconds: 250),
          placeholder: (_, __) => titleText,
          errorWidget: (_, __, ___) => titleText,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Scroll Track
// ─────────────────────────────────────────────────────────────────────────────

