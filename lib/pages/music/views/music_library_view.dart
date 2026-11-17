import 'package:flutter/material.dart';
import '../../../design/prism_tokens.dart';
import '../../../models/music/music_track.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../services/music/music_download_service.dart';
import '../../../services/music/music_playlist_sharing_service.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import '../widgets/music_hoverable.dart';
import '../widgets/music_track_row.dart';
import '../widgets/music_wrapped_modal.dart';
import '../widgets/music_listen_together_modal.dart';

class MusicLibraryView extends StatelessWidget {
  final ScrollController scrollController;
  final List<MusicTrack> likedTracks;
  final List<UserPlaylist> userPlaylists;
  final List<MusicTrack> recentTracks;
  final VoidCallback onCreatePlaylist;
  final VoidCallback onOpenDownloads;
  final VoidCallback onPlayLiked;
  final Function(UserPlaylist) onOpenUserPlaylist;
  final Function(MusicTrack, List<MusicTrack>) onPlayTrack;
  final Function(MusicTrack) onAddToPlaylist;
  final MusicTrack? currentPlayingTrack;
  final bool isPlaying;

  const MusicLibraryView({
    super.key,
    required this.scrollController,
    required this.likedTracks,
    required this.userPlaylists,
    required this.recentTracks,
    required this.onCreatePlaylist,
    required this.onOpenDownloads,
    required this.onPlayLiked,
    required this.onOpenUserPlaylist,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
    required this.currentPlayingTrack,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    // Header (58px + status inset) floats over the list; start below it.
    final topInset = MediaQuery.paddingOf(context).top;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 150).copyWith(
        top: 72 + topInset,
      ),
      children: [
        Row(
          children: [
            Text(
              'Your Library',
              style: TextStyle(
                color: PrismInk.primary(
                  AppThemeService.currentPalette.value.isLight,
                ),
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
              ),
            ),
            const Spacer(),
            // Chips strip — sized to the biggest chip and horizontally
            // scrollable so the header never overflows on narrow screens.
            Expanded(
              child: SizedBox(
                height: 40,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Wrapped Chip
                          MusicHoverable(
                            scaleFactor: 1.05,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    AppThemeService.currentPalette.value.isLight
                                    ? PrismAccent.starTextLight
                                    : Colors.amberAccent,
                                side: BorderSide(
                                  color:
                                      (AppThemeService
                                              .currentPalette
                                              .value
                                              .isLight
                                          ? PrismAccent.starTextLight
                                          : Colors.amberAccent)
                                      .withValues(alpha: 0.4),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              onPressed: () =>
                                  MusicWrappedModal.show(context),
                              icon: const Icon(
                                Icons.auto_awesome_rounded,
                                size: 16,
                              ),
                              label: const Text(
                                'Wrapped',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Listen Together Chip
                          MusicHoverable(
                            scaleFactor: 1.05,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    AppThemeService.currentPalette.value.isLight
                                    ? const Color(0xFF007A8C)
                                    : const Color(0xFF00D2EF),
                                side: BorderSide(
                                  color:
                                      (AppThemeService
                                              .currentPalette
                                              .value
                                              .isLight
                                          ? const Color(0xFF007A8C)
                                          : const Color(0xFF00D2EF))
                                      .withValues(alpha: 0.4),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              onPressed: () =>
                                  MusicListenTogetherModal.show(context),
                              icon: const Icon(Icons.people_alt_rounded, size: 16),
                              label: const Text(
                                'Jam Party',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Import Playlist Chip
                          MusicHoverable(
                            scaleFactor: 1.05,
                            child: IconButton(
                              tooltip: 'Import Playlist',
                              style: IconButton.styleFrom(
                                backgroundColor: isLight
                                    ? PrismLight.raisedTop
                                    : PrismDark.ink.withValues(alpha: 0.08),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: isLight
                                        ? PrismLight.borderSubtle
                                        : PrismDark.ink.withValues(alpha: 0.12),
                                  ),
                                ),
                              ),
                              onPressed: () => _showImportDialog(context),
                              icon: Icon(
                                Icons.file_download_outlined,
                                color: PrismInk.soft(
                                  AppThemeService.currentPalette.value.isLight,
                                ),
                                size: 20,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          MusicHoverable(
                            scaleFactor: 1.05,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: palette.primaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: onCreatePlaylist,
                              icon: const Icon(
                                Icons.add_rounded,
                                color: PrismAccent.onAccent,
                                size: 18,
                              ),
                              label: const Text(
                                'New Playlist',
                                style: TextStyle(
                                  color: PrismAccent.onAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ),
        const SizedBox(height: 20),

        // Liked Songs Banner
        MusicHoverable(
          scaleFactor: 1.02,
          child: GestureDetector(
            onTap: onPlayLiked,
            child: PerformanceLiquidLens(
              style: PerformanceGlassStyles.menu,
              child: Container(
                height: 110,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    // Palette-derived: light banner keeps the page accent,
                    // dark end is the same hue deepened for depth.
                    colors: [
                      palette.primaryColor,
                      HSLColor.fromColor(palette.primaryColor)
                          .withLightness(.45)
                          .toColor(),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: palette.primaryColor.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: PrismAccent.onAccent.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: PrismAccent.onAccent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Liked Songs',
                            style: TextStyle(
                              color: PrismAccent.onAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${likedTracks.length} favourite tracks',
                            style: TextStyle(
                              color: PrismAccent.onAccent.withValues(alpha: 0.75),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (likedTracks.isNotEmpty)
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: PrismAccent.onAccent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: palette.primaryColor,
                          size: 30,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Downloaded Songs Banner (Offline Music)
        Builder(
          builder: (context) {
            final downloaded = MusicDownloadService.instance.downloadedTracks;
            final queue = MusicDownloadService.instance.queue;
            final totalBytes =
                MusicDownloadService.instance.totalDownloadedSizeBytes;
            final sizeMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);

            return MusicHoverable(
              scaleFactor: 1.02,
              child: GestureDetector(
                onTap: onOpenDownloads,
                child: PerformanceLiquidLens(
                  style: PerformanceGlassStyles.menu,
                  child: Container(
                    height: 110,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          palette.amberAccent,
                          HSLColor.fromColor(palette.amberAccent)
                              .withLightness(.52)
                              .toColor(),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: palette.amberAccent.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22331C).withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.download_done_rounded,
                            color: PrismAccent.successTextLight,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Downloaded Songs',
                                    style: TextStyle(
                                      color: PrismAccent.successTextLight,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if (queue.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E2B18)
                                            .withValues(alpha: 0.28),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Queue (${queue.length})',
                                        style: const TextStyle(
                                          color: PrismAccent.successTextLight,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${downloaded.length} offline tracks • $sizeMb MB',
                                style: const TextStyle(
                                  color: PrismAccent.successTextLight,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: PrismAccent.successTextLight,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            color: PrismLight.raisedTop,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 28),

        // User Playlists Section
        if (userPlaylists.isNotEmpty) ...[
          Text(
            'Custom Playlists',
            style: TextStyle(
              color: PrismInk.primary(
                AppThemeService.currentPalette.value.isLight,
              ),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.1,
            ),
            itemCount: userPlaylists.length,
            itemBuilder: (context, index) {
              final pl = userPlaylists[index];
              return MusicHoverable(
                scaleFactor: 1.04,
                child: GestureDetector(
                  onTap: () => onOpenUserPlaylist(pl),
                  child: Container(
                    decoration: BoxDecoration(
                      color: palette.cardBackgroundColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: palette.isLight
                            ? PrismLight.borderSubtle
                            : PrismDark.borderSubtle,
                      ),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 70,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: palette.primaryColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.queue_music_rounded,
                            color: palette.primaryColor,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          pl.title,
                          style: TextStyle(
                            color: PrismInk.primary(palette.isLight),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${pl.tracks.length} tracks',
                          style: TextStyle(
                            color: PrismInk.faint(palette.isLight),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 28),
        ],

        // Recent History Section
        if (recentTracks.isNotEmpty) ...[
          Text(
            'Recently Played',
            style: TextStyle(
              color: PrismInk.primary(
                AppThemeService.currentPalette.value.isLight,
              ),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recentTracks.length.clamp(0, 10),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final track = recentTracks[index];
              return MusicTrackRow(
                track: track,
                isPlaying: currentPlayingTrack?.id == track.id && isPlaying,
                isCurrent: currentPlayingTrack?.id == track.id,
                onTap: () => onPlayTrack(track, recentTracks),
                onMoreTap: () => onAddToPlaylist(track),
              );
            },
          ),
        ],
      ],
    );
  }

  void _showImportDialog(BuildContext context) {
    final controller = TextEditingController();
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final showLiveCount =
        MusicDownloadService.instance.downloadedTracks.isNotEmpty;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.cardBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.download_rounded, color: palette.primaryColor, size: 22),
            const SizedBox(width: 8),
            Text(
              'Import Playlist',
              style: TextStyle(
                color: PrismInk.primary(isLight),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste a Dizzy share code (DIZZY-PLAYLIST:...) or JSON exported from another device:',
              style: TextStyle(
                color: PrismInk.soft(isLight),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: TextStyle(color: PrismInk.primary(isLight), fontSize: 13),
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Paste code or JSON here...',
                hintStyle: TextStyle(color: PrismInk.faint(isLight), fontSize: 12),
                filled: true,
                fillColor: PrismInk.primary(isLight).withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: PrismInk.primary(isLight).withValues(alpha: 0.1),
                  ),
                ),
              ),
            ),
            if (showLiveCount) ...[
              const SizedBox(height: 10),
              Text(
                '${MusicDownloadService.instance.downloadedTracks.length} offline tracks • ${(MusicDownloadService.instance.totalDownloadedSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                style: TextStyle(color: PrismInk.faint(isLight), fontSize: 10.5),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: PrismInk.faint(isLight)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.primaryColor,
              foregroundColor: PrismAccent.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                final pl = await MusicPlaylistSharingService.instance
                    .importFromJson(text);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  if (pl != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Successfully imported "${pl.title}" with ${pl.tracks.length} tracks! 🎵',
                        ),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Invalid playlist format. Please check code.',
                        ),
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }
}
