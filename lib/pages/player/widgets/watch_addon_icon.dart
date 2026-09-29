import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../services/addon/addon_manager.dart';
import '../../../utils/perf/image_caps.dart';
import 'watch_style.dart';

class WatchAddonIcon extends StatelessWidget {
  final String addonName;

  const WatchAddonIcon({super.key, required this.addonName});

  @override
  Widget build(BuildContext context) {
    final nameLower = addonName.trim().toLowerCase();
    final isBuiltIn = nameLower == 'dizzy' ||
        nameLower == 'dizzyhttp' ||
        nameLower.startsWith('builtin');

    if (isBuiltIn) {
      return Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF7C5CFF).withValues(alpha: 0.25),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/icon.png',
            width: 30,
            height: 30,
            fit: BoxFit.contain,
          ),
        ),
      );
    }

    final logoUrl = AddonManager.instance.getAddonLogo(addonName);

    if (logoUrl != null && logoUrl.isNotEmpty) {
      if (logoUrl.startsWith('asset:')) {
        final assetPath = logoUrl.substring('asset:'.length);
        return Container(
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              assetPath,
              width: 30,
              height: 30,
              fit: BoxFit.contain,
            ),
          ),
        );
      }

      return Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CachedNetworkImage(
            imageUrl: logoUrl,
            width: 32,
            height: 32,
            fit: BoxFit.contain,
            // P12: decode-capped (was full-res).
            memCacheWidth: ImageCaps.kThumb,
            maxWidthDiskCache: ImageCaps.kThumb,
            placeholder: (context, url) => Container(
              color: Colors.white.withValues(alpha: 0.04),
              child: const Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: WatchColors.accent,
                  ),
                ),
              ),
            ),
            errorWidget: (context, url, error) => _buildFallbackIcon(),
          ),
        ),
      );
    }

    return _buildFallbackIcon();
  }

  Widget _buildFallbackIcon() {
    final firstLetter = addonName.isNotEmpty ? addonName[0].toUpperCase() : 'A';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: WatchColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WatchColors.accent.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(
          firstLetter,
          style: const TextStyle(
            color: WatchColors.accent,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

