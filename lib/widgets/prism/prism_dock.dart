import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/prism_shadows.dart';
import '../../../design/prism_tokens.dart';
import '../../../pages/anime/anime_page.dart';
import '../../../pages/audiobooks/audiobooks_page.dart';
import '../../../pages/books/books_page.dart';
import '../../../pages/downloads/downloads_page.dart';
import '../../../pages/home/home_page.dart';
import '../../../pages/iptv/iptv_page.dart';
import '../../../pages/manga/manga_page.dart';
import '../../../pages/music/music_page.dart';
import '../../../pages/my_list/my_list_page.dart';
import '../../../pages/search/search_page.dart';
import '../../../pages/settings/addons_settings_page.dart';
import '../../../pages/settings/settings_page.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../services/theme/dock_settings.dart';
import '../../../utils/navigation/route_transitions.dart';

/// Prism bottom dock (SPEC §3): glass, 83px tall, icons + labels, active
/// item raised with an accent halo. Same navigation contract as the old
/// dock — same [DockSettings] filtering, same push/pushReplacement rules.
class PrismDock extends StatelessWidget {
  final DockItemKey? currentDestination;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onHomeTap;

  const PrismDock({
    super.key,
    this.currentDestination,
    this.onSettingsTap,
    this.onSearchTap,
    this.onHomeTap,
  });

  void _go(BuildContext context, Widget page, {bool overlay = false}) {
    if (overlay) {
      Navigator.push(context, LiquidRevealRoute(page: page, tapPosition: null));
      return;
    }
    if (currentDestination == DockItemKey.home) {
      Navigator.push(context, LiquidRevealRoute(page: page, tapPosition: null));
    } else {
      Navigator.pushReplacement(
        context,
        LiquidRevealRoute(page: page, tapPosition: null),
      );
    }
  }

  void _home(BuildContext context) {
    if (onHomeTap != null) {
      onHomeTap!();
      return;
    }
    if (currentDestination == DockItemKey.home) return;
    if (Navigator.canPop(context)) {
      Navigator.popUntil(context, (route) => route.isFirst);
    } else {
      Navigator.pushReplacement(
        context,
        LiquidRevealRoute(page: const HomePage(), tapPosition: null),
      );
    }
  }

  VoidCallback _tapFor(BuildContext context, DockItemKey key) {
    switch (key) {
      case DockItemKey.home:
        return () => _home(context);
      case DockItemKey.manga:
        return () {
          if (currentDestination == key) return;
          _go(context, const MangaPage());
        };
      case DockItemKey.books:
        return () {
          if (currentDestination == key) return;
          _go(context, const BooksPage());
        };
      case DockItemKey.audiobooks:
        return () {
          if (currentDestination == key) return;
          _go(context, const AudiobooksPage());
        };
      case DockItemKey.music:
        return () {
          if (currentDestination == key) return;
          _go(context, const MusicPage());
        };
      case DockItemKey.anime:
        return () {
          if (currentDestination == key) return;
          _go(context, const AnimePage());
        };
      case DockItemKey.liveTv:
        return () {
          if (currentDestination == key) return;
          _go(context, const IptvPage());
        };
      case DockItemKey.addons:
        return () => _go(context, const AddonsSettingsPage(), overlay: true);
      case DockItemKey.downloads:
        return () => _go(context, const DownloadsPage(), overlay: true);
      case DockItemKey.myList:
        return () {
          if (currentDestination == key) return;
          _go(context, const MyListPage());
        };
      case DockItemKey.settings:
        return () {
          if (onSettingsTap != null) {
            onSettingsTap!();
          } else {
            _go(context, const SettingsPage(), overlay: true);
          }
        };
      case DockItemKey.search:
        return () {
          if (onSearchTap != null) {
            onSearchTap!();
          } else {
            _go(context, const SearchPage(), overlay: true);
          }
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemePalette>(
      valueListenable: AppThemeService.currentPalette,
      builder: (context, palette, _) =>
          ValueListenableBuilder<Map<String, bool>>(
            valueListenable: DockSettings.enabledNotifier,
            builder: (context, enabledMap, _) {
              final keys = <DockItemKey>[];
              for (final k in DockItemKey.values) {
                final on = enabledMap[k.key] ?? true;
                if (!on && k.isRemovable) continue;
                keys.add(k);
              }

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: PrismSpace.md),
                decoration: BoxDecoration(
                  borderRadius: PrismRadius.xlAll,
                  boxShadow: PrismShadows.floating(
                    isLight: palette.isLight,
                    halo: palette.primaryColor,
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PrismSpace.xs,
                    vertical: PrismSpace.xs,
                  ),
                  decoration: BoxDecoration(
                    color: palette.isLight ? PrismLight.glass : PrismDark.glass,
                    borderRadius: PrismRadius.xlAll,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const itemWidth = 64.0;
                      final fits =
                          keys.length * itemWidth <= constraints.maxWidth;
                      final row = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final k in keys)
                            _PrismDockItem(
                              key: ValueKey(k.key),
                              item: k,
                              active: currentDestination == k,
                              accent: palette.primaryColor,
                              isLight: palette.isLight,
                              expanded: fits,
                              onTap: () {
                                if (PrismHaptics.enabled) {
                                  HapticFeedback.lightImpact();
                                }
                                _tapFor(context, k)();
                              },
                            ),
                        ],
                      );
                      if (fits) return row;
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: row,
                      );
                    },
                  ),
                ),
              );
            },
          ),
    );
  }
}

class _PrismDockItem extends StatelessWidget {
  final DockItemKey item;
  final bool active;
  final Color accent;
  final bool isLight;
  final bool expanded;
  final VoidCallback onTap;

  const _PrismDockItem({
    super.key,
    required this.item,
    required this.active,
    required this.accent,
    required this.isLight,
    this.expanded = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = isLight ? PrismLight.ink : PrismDark.ink;
    final soft = isLight ? PrismLight.inkSoft : PrismDark.inkSoft;

    final body = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: PrismMotion.standard,
            curve: PrismMotion.curve,
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: PrismShadows.surfaceGradient(isLight),
              boxShadow: active
                  ? [
                      ...PrismShadows.raised(isLight: isLight, scale: 0.8),
                      BoxShadow(
                        color: accent.withValues(alpha: 0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : PrismShadows.soft(isLight: isLight),
            ),
            child: Icon(item.icon, size: 22, color: active ? ink : soft),
          ),
          const SizedBox(height: PrismSpace.xxs),
          SizedBox(
            height: 11,
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.0,
                fontWeight: active ? PrismType.wBold : PrismType.wMedium,
                color: active ? ink : soft,
              ),
            ),
          ),
          SizedBox(
            height: 6,
            child: active
                ? Center(
                    child: Container(
                      width: 16,
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(PrismRadius.pill),
                        color: accent,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
    final semanticBody = Semantics(button: true, selected: active, child: body);
    if (expanded) return Expanded(child: semanticBody);
    return SizedBox(width: 64, child: semanticBody);
  }
}
