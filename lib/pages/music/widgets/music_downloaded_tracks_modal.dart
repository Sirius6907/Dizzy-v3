import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../models/music/music_track.dart';
import '../../../services/music/music_download_service.dart';
import '../../../services/music/music_library_service.dart';
import '../../../utils/perf/image_caps.dart';
import '../../../widgets/common/performance_liquid_lens.dart';

class MusicDownloadedTracksModal extends StatefulWidget {
  final VoidCallback onClose;
  final Function(MusicTrack, List<MusicTrack>) onPlayTrack;
  final Function(MusicTrack) onAddToPlaylist;

  const MusicDownloadedTracksModal({
    super.key,
    required this.onClose,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
  });

  @override
  State<MusicDownloadedTracksModal> createState() => _MusicDownloadedTracksModalState();
}

class _MusicDownloadedTracksModalState extends State<MusicDownloadedTracksModal> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloadService = MusicDownloadService.instance;
    final allDownloaded = downloadService.downloadedTracks;
    final queue = downloadService.queue;
    final totalBytes = downloadService.totalDownloadedSizeBytes;
    final sizeMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);

    final filtered = _searchQuery.isEmpty
        ? allDownloaded
        : allDownloaded.where((t) =>
            t.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            t.artist.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            t.album.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            width: isMobile ? size.width - 24 : 760,
            height: isMobile ? size.height * 0.88 : 660,
            decoration: BoxDecoration(
              color: const Color(0xFF0F121C),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: isMobile ? 48 : 56,
                      height: isMobile ? 48 : 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0083B0), Color(0xFF00B4DB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.offline_pin_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Downloaded Songs',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isMobile ? 19 : 23,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${allDownloaded.length} offline tracks • $sizeMb MB storage',
                            style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Active Download Queue Card
                if (queue.isNotEmpty) ...[
                  _buildQueueBanner(queue, downloadService),
                  const SizedBox(height: 12),
                ],

                // Action Bar: Play All, Shuffle, Search
                Row(
                  children: [
                    if (filtered.isNotEmpty) ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00B4DB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onPressed: () {
                          final tracks = filtered.map((d) => d.toMusicTrack()).toList();
                          widget.onPlayTrack(tracks.first, tracks);
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('Play All', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        onPressed: () {
                          final tracks = filtered.map((d) => d.toMusicTrack()).toList()..shuffle();
                          widget.onPlayTrack(tracks.first, tracks);
                        },
                        icon: const Icon(Icons.shuffle_rounded, size: 18),
                        label: const Text('Shuffle'),
                      ),
                    ],
                    if (MusicLibraryService.instance.likedTracks.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00B4DB),
                          side: BorderSide(color: const Color(0xFF00B4DB).withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onPressed: () {
                          downloadService.downloadAllLikedTracks(MusicLibraryService.instance.likedTracks);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Queued all liked songs for offline download! 📥')),
                          );
                        },
                        icon: const Icon(Icons.download_for_offline_rounded, size: 18),
                        label: const Text('Download Liked'),
                      ),
                    ],
                    const Spacer(),
                    SizedBox(
                      width: isMobile ? 140 : 200,
                      height: 38,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        style: const TextStyle(color: Colors.white, fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText: 'Search offline...',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00B4DB), size: 16),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                const Divider(color: Colors.white10),
                const SizedBox(height: 6),

                // Downloaded Tracks List
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.cloud_download_rounded,
                                color: Colors.white24,
                                size: 48,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No downloaded tracks match "$_searchQuery"'
                                    : 'No offline downloads yet.\nTap the download icon on any song, album, or playlist to listen offline.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white54, fontSize: 13.5, height: 1.4),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final track = item.toMusicTrack();
                            final itemSizeMb = (item.fileSizeBytes / (1024 * 1024)).toStringAsFixed(1);
                            final isFlac = item.format.toLowerCase() == 'flac';

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              tileColor: const Color(0xFF13151F),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: item.localCoverPath.isNotEmpty && File(item.localCoverPath).existsSync()
                                    ? Image.file(
                                        File(item.localCoverPath),
                                        width: 46,
                                        height: 46,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _buildFallbackCover(track),
                                      )
                                    : _buildFallbackCover(track),
                              ),
                              title: Text(
                                item.title,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${item.artist} • ${item.album}',
                                      style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: isFlac
                                          ? const Color(0xFF7C5CFF).withValues(alpha: 0.25)
                                          : const Color(0xFF00B0FF).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isFlac ? 'FLAC' : item.format.toUpperCase(),
                                      style: TextStyle(
                                        color: isFlac ? const Color(0xFFB39DDB) : const Color(0xFF00E5FF),
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$itemSizeMb MB',
                                    style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                                    tooltip: 'Delete from downloads',
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          backgroundColor: const Color(0xFF161924),
                                          title: const Text('Delete Downloaded Song', style: TextStyle(color: Colors.white)),
                                          content: Text('Delete "${item.title}" from offline storage?', style: const TextStyle(color: Colors.white70)),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(c, false),
                                              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                              onPressed: () => Navigator.pop(c, true),
                                              child: const Text('Delete', style: TextStyle(color: Colors.white)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await downloadService.deleteDownloadedTrack(item.id);
                                        setState(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),
                              onTap: () {
                                final allTracks = filtered.map((d) => d.toMusicTrack()).toList();
                                widget.onPlayTrack(track, allTracks);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackCover(MusicTrack track) {
    if (track.coverUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: track.coverUrl,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        // P12: decode-capped (was full-res).
        memCacheWidth: ImageCaps.kThumb,
        maxWidthDiskCache: ImageCaps.kThumb,
        errorWidget: (_, __, ___) => Container(
          width: 46,
          height: 46,
          color: const Color(0xFF1B1E2B),
          child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 24),
        ),
      );
    }
    return Container(
      width: 46,
      height: 46,
      color: const Color(0xFF1B1E2B),
      child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 24),
    );
  }

  Widget _buildQueueBanner(List<MusicDownloadTask> queue, MusicDownloadService service) {
    final activeTask = queue.firstWhere(
      (t) => t.status == MusicDownloadStatus.downloading || t.status == MusicDownloadStatus.extracting,
      orElse: () => queue.first,
    );
    final isExtracting = activeTask.status == MusicDownloadStatus.extracting;
    final progress = activeTask.progress.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0083B0).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF00B4DB).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: isExtracting ? null : progress,
                  color: const Color(0xFF00E5FF),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isExtracting
                      ? 'Extracting stream for "${activeTask.track.title}"...'
                      : 'Downloading "${activeTask.track.title}" (${(progress * 100).toInt()}%)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${queue.length} in queue',
                style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => service.cancelTask(activeTask.track.id),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, color: Colors.white60, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: isExtracting ? null : progress,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }
}
