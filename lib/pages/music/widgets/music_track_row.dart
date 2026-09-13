import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../models/music/music_track.dart';
import '../../../services/music/music_download_service.dart';
import '../../../utils/perf/image_caps.dart';
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
    return MusicHoverable(
      scaleFactor: 1.01,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: isCurrent
            ? const Color(0xFF7C5CFF).withValues(alpha: 0.15)
            : const Color(0xFF13151F),
        leading: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: track.coverUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                // P12: decode-capped (was full-res).
                memCacheWidth: ImageCaps.kThumb,
                maxWidthDiskCache: ImageCaps.kThumb,
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
            color: isCurrent ? const Color(0xFF7C5CFF) : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          track.artist,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
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
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
              onPressed: onMoreTap,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildDownloadButton(BuildContext context) {
    final isDownloaded = MusicDownloadService.instance.isDownloaded(track.id);
    final task = MusicDownloadService.instance.getTask(track.id);
    final isDownloading = task != null &&
        (task.status == MusicDownloadStatus.extracting || task.status == MusicDownloadStatus.downloading);
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
      icon: const Icon(Icons.download_rounded, color: Colors.white38, size: 18),
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

