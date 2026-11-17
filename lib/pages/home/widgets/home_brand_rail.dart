import 'package:flutter/material.dart';

import '../../../models/movie/movie_section.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../utils/navigation/route_transitions.dart';
import '../../catalog/catalog_page.dart';
import '../home_rails.dart';

/// One round brand tile for the Streaming Catalogs rail. Logos sit on a
/// light card circle so every bundled mark (dark, red, blue) stays legible
/// in both Light and Dark Clay. [group] holds every catalog section of the
/// same brand (movies + series, across provider addons); the catalog page
/// switches between them.
class BrandTile extends StatelessWidget {
  final List<MovieSection> group;
  const BrandTile({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final section = group.first;
    final asset = providerBrandAsset(section.title);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                LiquidRevealRoute(
                  page: CatalogPage(section: section, sections: group),
                  tapPosition: null,
                ),
              );
            },
            customBorder: const CircleBorder(),
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.isLight
                    ? Colors.white
                    : const Color(0xFFF4F7FC),
                border: Border.all(
                  color: palette.primaryColor.withValues(alpha: 0.10),
                ),
              ),
              padding: const EdgeInsets.all(14),
              child: asset != null
                  ? Image.asset(asset, fit: BoxFit.contain)
                  : Center(
                      child: Text(
                        section.title.characters.first.toUpperCase(),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: palette.primaryColor,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 76,
          child: Text(
            section.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.silverAccent,
            ),
          ),
        ),
      ],
    );
  }
}

/// The consolidated Streaming Catalogs rail: one row of round, clickable
/// brand tiles replacing the five per-provider rows.
class HomeBrandRail extends StatelessWidget {
  final List<MovieSection> brandSections;

  const HomeBrandRail({super.key, required this.brandSections});

  @override
  Widget build(BuildContext context) {
    if (brandSections.isEmpty) return const SizedBox.shrink();
    final palette = AppThemeService.currentPalette.value;
    final groups = groupBrandSections(brandSections);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            'Streaming Catalogs',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: palette.silverAccent,
              letterSpacing: -0.2,
            ),
          ),
        ),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) => BrandTile(group: groups[i]),
          ),
        ),
      ],
    );
  }
}
