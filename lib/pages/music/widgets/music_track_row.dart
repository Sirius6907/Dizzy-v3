import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/prism_tokens.dart';
import '../../../models/music/music_track.dart';
import '../../../services/music/music_download_service.dart';
import '../../../services/theme/app_theme_service.dart';
import 'music_cover_image.dart';
import 'music_hoverable.dart';

class MusicTrackRow extends StatelessWidget {
  final MusicTrack track;
  final bool isPlaying;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;

  const MusicTrackRow({
    super.key,
    required this.track,
    required this.isPlaying,
    required this.isCurrent,
    required this.onTap,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = PrismInk.primary(isLight);
    final inkFaint = PrismInk.faint(isLight);
    return MusicHoverable(
      scaleFactor: 1.01,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: isCurrent
            ? const Color(0xFF7C5CFF).withValues(alpha: isLight ? 0.14 : 0.15)
            : (isLight ? PrismLight.raisedTop : DizzyVoid.surface1),
        leading: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: MusicCoverImage(
                imageUrl: track.coverUrl,
                width: 48,
                height: 48,
              ),
            ),
            if (isCurrent)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: const Color(0xFF7C5CFF),
                  size: 28,
                ),
              ),
          ],
        ),
        title: Text(
          track.title,
          style: TextStyle(
            color: isCurrent ? const Color(0xFF7C5CFF) : ink,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          track.artist,
          style: TextStyle(color: inkFaint, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDownloadButton(context),
            const SizedBox(width: 4),
            Text(
              track.formattedDuration,
              style: TextStyle(color: inkFaint, fontSize: 12),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.more_vert_rounded, color: inkFaint, size: 20),
              onPressed: onMoreTap,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildDownloadButton(BuildContext context) {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final idleInk = PrismInk.faint(isLight);
    final isDownloaded = MusicDownloadService.instance.isDownloaded(track.id);
    final task = MusicDownloadService.instance.getTask(track.id);
    final isDownloading =
        task != null &&
        (task.status == MusicDownloadStatus.extracting ||
            task.status == MusicDownloadStatus.downloading);
    final isQueued = task != null && task.status == MusicDownloadStatus.queued;

    if (isDownloaded) {
      return Tooltip(
        message: 'Downloaded (Offline)',
        child: Container(
          padding: const EdgeInsets.all(6),
          child: const Icon(
            Icons.download_done_rounded,
            color: Color(0xFF00E5FF),
            size: 18,
          ),
        ),
      );
    }

    if (isDownloading) {
      return Tooltip(
        message: 'Downloading ${(task.progress * 100).toInt()}%',
        child: Container(
          width: 28,
          height: 28,
          padding: const EdgeInsets.all(5),
          child: CircularProgressIndicator(
            value: task.progress > 0.05 ? task.progress : null,
            strokeWidth: 2.2,
            color: const Color(0xFF00E5FF),
          ),
        ),
      );
    }

    if (isQueued) {
      return Tooltip(
        message: 'Queued for download',
        child: Container(
          padding: const EdgeInsets.all(6),
          child: const Icon(
            Icons.hourglass_top_rounded,
            color: Colors.amberAccent,
            size: 18,
          ),
        ),
      );
    }

    return IconButton(
      icon: Icon(Icons.download_rounded, color: idleInk, size: 18),
      tooltip: 'Download Track',
      onPressed: () {
        MusicDownloadService.instance.queueTrack(track);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${track.title}" to download queue'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }
}
