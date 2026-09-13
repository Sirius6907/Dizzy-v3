import 'package:flutter/material.dart';
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
          color: const Color(0xFF080A0F).withValues(alpha: 0.85),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: Row(
          children: [
            MusicHoverable(
              scaleFactor: 1.08,
              child: IconButton(
                tooltip: 'Back to Home (Esc)',
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  padding: const EdgeInsets.all(8),
                ),
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
            SizedBox(width: isMobile ? 8 : 12),
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF13151F),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: Colors.white54, size: isMobile ? 18 : 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        focusNode: searchFocusNode,
                        onChanged: onSearchChanged,
                        style: TextStyle(color: Colors.white, fontSize: isMobile ? 13 : 14),
                        decoration: InputDecoration(
                          hintText: isVeryNarrow
                              ? 'Search…'
                              : (isMobile ? 'Search music…' : 'Search songs, artists, albums, playlists...'),
                          hintStyle: TextStyle(color: Colors.white38, fontSize: isMobile ? 12 : 13),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (searchController.text.isNotEmpty)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 16),
                        onPressed: onClearSearch,
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(width: isMobile ? 6 : 12),
            const MusicAudioSourceSelectorButton(),
            if (!isMobile) ...[
              SizedBox(width: isMobile ? 4 : 8),
              MusicHoverable(
                scaleFactor: 1.1,
                child: IconButton(
                  tooltip: 'Music Player Studio',
                  icon: const Icon(Icons.dashboard_customize_rounded, color: Colors.white70, size: 20),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MusicPlayerStudioPage()),
                    );
                  },
                ),
              ),
              SizedBox(width: isMobile ? 2 : 6),
              MusicHoverable(
                scaleFactor: 1.1,
                child: IconButton(
                  tooltip: 'Music Atmosphere Settings',
                  icon: const Icon(Icons.palette_rounded, color: Colors.white70, size: 20),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MusicSettingsPage()),
                    );
                  },
                ),
              ),
            ],
            SizedBox(width: isMobile ? 2 : 6),
            MusicHoverable(
              scaleFactor: 1.1,
              child: IconButton(
                tooltip: 'App Settings',
                icon: const Icon(Icons.settings_rounded, color: Colors.white70, size: 20),
                onPressed: onSettingsTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

