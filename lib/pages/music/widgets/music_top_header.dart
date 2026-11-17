import 'package:flutter/material.dart';
import 'package:dizzy/design/prism_shadows.dart';
import 'package:dizzy/design/prism_tokens.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../settings/appearance/music_player_studio_page.dart';
import '../../settings/appearance/music_settings_page.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import 'music_hoverable.dart';
import 'music_audio_source_selector.dart';

class MusicTopHeader extends StatelessWidget {
  final bool isDesktop;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool isSearching;
  final Function(String) onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onSettingsTap;

  const MusicTopHeader({
    super.key,
    required this.isDesktop,
    required this.searchController,
    required this.searchFocusNode,
    required this.isSearching,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final topInset = MediaQuery.paddingOf(context).top;
    final screenW = MediaQuery.sizeOf(context).width;
    final isMobile = screenW < 600;
    final isVeryNarrow = screenW < 400;

    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.dock,
      child: Container(
        height: isDesktop ? 68.0 : (58.0 + topInset),
        padding: EdgeInsets.fromLTRB(
          isMobile ? 10 : 20,
          isDesktop ? 0 : topInset,
          isMobile ? 10 : 20,
          0,
        ),
        decoration: BoxDecoration(
          gradient: PrismShadows.surfaceGradient(isLight),
          boxShadow: PrismShadows.raised(isLight: isLight, scale: 0.6),
        ),
        child: Row(
          children: [
            MusicHoverable(
              scaleFactor: 1.08,
              child: IconButton(
                tooltip: 'Back to Home (Esc)',
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: isLight ? PrismLight.ink : Colors.white,
                  size: 20,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: isLight
                      ? PrismLight.raisedTop
                      : Colors.white.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isLight
                          ? PrismLight.borderSubtle
                          : Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                ),
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
            SizedBox(width: isMobile ? 8 : 12),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isDesktop ? 520 : double.infinity,
                  ),
                  child: AnimatedBuilder(
                    animation: searchFocusNode,
                    builder: (context, _) {
                      final focused = searchFocusNode.hasFocus;
                      return Container(
                        key: const ValueKey('music-search-field'),
                        height: 42,
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 8 : 12,
                        ),
                        decoration: BoxDecoration(
                          color: isLight ? PrismLight.sunken : PrismDark.sunken,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: focused
                                ? palette.primaryColor.withValues(alpha: 0.55)
                                : (isLight
                                      ? PrismLight.borderSubtle
                                      : Colors.white.withValues(alpha: 0.10)),
                            width: focused ? 1.4 : 1.0,
                          ),
                          boxShadow: focused
                              ? [
                                  BoxShadow(
                                    color: palette.primaryColor.withValues(
                                      alpha: 0.18,
                                    ),
                                    blurRadius: 18,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : PrismShadows.soft(isLight: isLight, scale: 0.7),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search_rounded,
                              color: focused
                                  ? palette.primaryColor
                                  : (isLight
                                        ? PrismLight.inkSoft
                                        : Colors.white54),
                              size: 18,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: TextField(
                                controller: searchController,
                                focusNode: searchFocusNode,
                                onChanged: onSearchChanged,
                                textInputAction: TextInputAction.search,
                                cursorColor: palette.primaryColor,
                                style: TextStyle(
                                  color: isLight
                                      ? PrismLight.ink
                                      : Colors.white,
                                  fontSize: isMobile ? 13 : 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: InputDecoration(
                                  hintText: isVeryNarrow
                                      ? 'Search…'
                                      : (isMobile
                                            ? 'Search music…'
                                            : 'Search songs, artists, albums, playlists'),
                                  hintStyle: TextStyle(
                                    color: isLight
                                        ? PrismLight.inkFaint
                                        : Colors.white38,
                                    fontSize: isMobile ? 12.5 : 13.5,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            if (searchController.text.isNotEmpty)
                              IconButton(
                                tooltip: 'Clear search',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: isLight
                                      ? PrismLight.inkSoft
                                      : Colors.white54,
                                  size: 16,
                                ),
                                onPressed: onClearSearch,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            SizedBox(width: isMobile ? 6 : 12),
            if (isMobile)
              PopupMenuButton<String>(
                tooltip: 'Music options',
                color: palette.scaffoldBackgroundColor,
                icon: Icon(
                  Icons.tune_rounded,
                  color: PrismInk.primary(isLight),
                ),
                itemBuilder: (_) => [
                  for (final label in [
                    'Audio source',
                    'Music Atmosphere Settings',
                    'App Settings',
                  ])
                    PopupMenuItem(
                      value: label,
                      child: Text(
                        label,
                        style: TextStyle(color: PrismInk.primary(isLight)),
                      ),
                    ),
                ],
                onSelected: (value) {
                  switch (value) {
                    case 'Audio source':
                      MusicAudioSourceSelectorButton.showAudioSourceDialog(
                        context,
                      );
                    case 'Music Atmosphere Settings':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MusicSettingsPage(),
                        ),
                      );
                    case 'App Settings':
                      onSettingsTap();
                  }
                },
              )
            else ...[
              const MusicAudioSourceSelectorButton(),
              const SizedBox(width: 8),
              MusicHoverable(
                scaleFactor: 1.1,
                child: IconButton(
                  tooltip: 'Music Player Studio',
                  icon: Icon(
                    Icons.dashboard_customize_rounded,
                    color: isLight ? PrismLight.inkSoft : Colors.white70,
                    size: 20,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MusicPlayerStudioPage(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),
              MusicHoverable(
                scaleFactor: 1.1,
                child: IconButton(
                  tooltip: 'Music Atmosphere Settings',
                  icon: Icon(
                    Icons.palette_rounded,
                    color: isLight ? PrismLight.inkSoft : Colors.white70,
                    size: 20,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MusicSettingsPage(),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(width: isMobile ? 2 : 6),
              MusicHoverable(
                scaleFactor: 1.1,
                child: IconButton(
                  tooltip: 'App Settings',
                  icon: Icon(
                    Icons.settings_rounded,
                    color: isLight ? PrismLight.inkSoft : Colors.white70,
                    size: 20,
                  ),
                  onPressed: onSettingsTap,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
