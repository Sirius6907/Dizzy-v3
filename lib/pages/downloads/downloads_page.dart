import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:dizzy/models/movie/movie_detail.dart';
import 'package:dizzy/models/movie/video.dart';
import 'package:path_provider/path_provider.dart';

import '../../design/dizzy_tokens.dart';
import '../../models/download/download_task_model.dart';
import '../../models/music/downloaded_music_track.dart';
import '../../services/download/download_progress_text.dart';
import '../../services/download/download_service.dart';
import '../../services/music/music_download_service.dart';
import '../../services/music/music_player_controller.dart';
import '../../services/theme/app_theme_service.dart';
import '../../utils/download/download_path_helper.dart';
import '../../utils/perf/image_caps.dart';
import '../../utils/platform/open_file_location_helper.dart';
import '../../utils/platform/storage_space_helper.dart';
import '../../widgets/common/notify.dart';
import '../../widgets/guide/guide_card.dart';
import '../player/player_screen.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StorageSpaceInfo? _storageSpace;
  bool _isCleaningCache = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    MusicDownloadService.instance.addListener(_onMusicChanged);
    _loadStorageSpace();
    // v1.2.0-T2.6: first-time Downloads guide (skipable, never nags).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GuideCard.maybeShow(context, 'downloads', AppGuides.downloads);
    });
  }

  void _onMusicChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadStorageSpace() async {
    try {
      final path = await DownloadPathHelper.getDownloadsDirectoryPath();
      final space = await StorageSpaceHelper.getAvailableSpace(path);
      if (mounted) {
        setState(() => _storageSpace = space);
      }
    } catch (_) {}
  }

  Future<void> _cleanCache() async {
    if (_isCleaningCache) return;
    setState(() => _isCleaningCache = true);
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        final files = tempDir.listSync(recursive: false);
        for (final f in files) {
          try {
            if (f is File) await f.delete();
          } catch (_) {}
        }
      }
      await _loadStorageSpace();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cache cleaned successfully! 🧹 Storage freed.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF1E212B),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cache clean failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCleaningCache = false);
    }
  }

  @override
  void dispose() {
    MusicDownloadService.instance.removeListener(_onMusicChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _playDownloadedMedia(DownloadTask task) {
    final file = File(task.targetFilePath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File not found on disk. It may have been moved or deleted.')),
      );
      return;
    }

    final detail = MovieDetail(
      id: task.mediaId,
      name: task.title,
      type: task.type,
      poster: task.posterUrl,
      background: task.backdropUrl,
      year: task.year,
    );

    Video? episodeVideo;
    if (task.season != null && task.episode != null) {
      episodeVideo = Video(
        id: '${task.mediaId}:${task.season}:${task.episode}',
        title: task.episodeTitle ?? 'Episode ${task.episode}',
        season: task.season ?? 1,
        episode: task.episode ?? 1,
        thumbnail: task.backdropUrl,
      );
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          source: task.toLocalStreamSource(),
          title: task.title,
          detail: detail,
          episode: episodeVideo,
        ),
      ),
    );
  }

  void _confirmDelete(DownloadTask task) async {
    // Polish P18: one dialog voice — Cancel left, Delete right (red).
    final ok = await DizzyDialogs.confirm(
      context,
      title: 'Delete Download',
      line:
          'Are you sure you want to delete "${task.title}" and remove the file from storage?',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok) DownloadService.instance.deleteDownload(task.id);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemePalette>(
      valueListenable: AppThemeService.currentPalette,
      builder: (context, palette, _) {
        return Scaffold(
          backgroundColor: palette.scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: palette.appBarBackgroundColor,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: palette.primaryColor,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: palette.primaryColor.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Downloads',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.folder_open_rounded, color: Colors.white, size: 22),
                tooltip: 'Open Downloads Folder',
                onPressed: () async {
                  final dir = await DownloadPathHelper.getDownloadsDirectoryPath();
                  final opened = await OpenFileLocationHelper.openLocation(dir);
                  if (!opened && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Folder path: $dir')),
                    );
                  }
                },
              ),
              const SizedBox(width: 8),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: ValueListenableBuilder<List<DownloadTask>>(
                valueListenable: DownloadService.instance.tasksNotifier,
                builder: (context, tasks, _) {
                  final activeCount = tasks.where((t) => !t.isCompleted && !t.isFailed).length;
                  final completedCount = tasks.where((t) => t.isCompleted).length;
                  final musicCount = MusicDownloadService.instance.downloadedTracks.length;

                  return TabBar(
                    controller: _tabController,
                    indicatorColor: palette.primaryColor,
                    indicatorWeight: 3,
                    labelColor: palette.primaryColor,
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    tabs: [
                      Tab(text: 'Active ($activeCount)'),
                      Tab(text: 'Video ($completedCount)'),
                      Tab(text: 'Music ($musicCount)'),
                    ],
                  );
                },
              ),
            ),
          ),
          body: Column(
            children: [
              _buildStorageGauge(palette),
              // v1.2.0-T2.2: offline banner — Easy English, no tech words.
              ValueListenableBuilder<bool>(
                valueListenable: DownloadService.instance.offlineNotifier,
                builder: (context, offline, _) {
                  if (!offline) return const SizedBox.shrink();
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.wifi_off_rounded,
                            color: Colors.orange, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No internet. Waiting… downloads continue when you are back.',
                            style: TextStyle(
                                color: Colors.orange,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Expanded(
                child: ValueListenableBuilder<List<DownloadTask>>(
                  valueListenable: DownloadService.instance.tasksNotifier,
                  builder: (context, tasks, _) {
                    final activeTasks =
                        tasks.where((t) => !t.isCompleted).toList();
                    final completedTasks =
                        tasks.where((t) => t.isCompleted).toList();

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _buildActiveList(activeTasks, palette),
                        _buildCompletedList(completedTasks, palette),
                        _buildMusicDownloadedList(palette),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveList(List<DownloadTask> tasks, AppThemePalette palette) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_done_rounded, size: 64, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text(
              'No active downloads',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Text(
              'Media you download from the video player will show up here.',
              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4)),
            ),
            // v1.2.0-T2.7: empty state always has 1 action (nani test).
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C5CFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.explore_rounded, size: 18),
              label: const Text('Find something to save'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _buildActiveCard(task, palette);
      },
    );
  }

  Widget _buildActiveCard(DownloadTask task, AppThemePalette palette) {
    final progress = task.progressPercent;
    final isDownloading = task.status == DownloadStatus.downloading;
    final isPaused = task.status == DownloadStatus.paused;
    final isFailed = task.status == DownloadStatus.failed;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.cardBackgroundColor.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDownloading
              ? palette.primaryColor.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.08),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 50,
                  height: 70,
                  color: const Color(0xFF1E212E),
                  child: task.posterUrl != null && task.posterUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: task.posterUrl!,
                          fit: BoxFit.cover,
                          // P12: decode-capped (was full-res).
                          memCacheWidth: ImageCaps.kThumb,
                          maxWidthDiskCache: ImageCaps.kThumb,
                          errorWidget: (_, __, ___) => const Icon(Icons.movie_rounded, color: Colors.white24),
                        )
                      : const Icon(Icons.movie_rounded, color: Colors.white24),
                ),
              ),

              const SizedBox(width: 14),

              // Title & Engine Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: palette.primaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            task.sourceType == DownloadSourceType.p2p
                                ? 'P2P Torrent'
                                : (task.sourceType == DownloadSourceType.debrid ? 'Cloud Debrid' : 'Direct HTTP'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: palette.primaryColor,
                            ),
                          ),
                        ),
                        if (task.peers > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${task.peers} peers',
                            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DownloadProgressText.line(
                        progress: progress,
                        speedLabel: task.speedLabel,
                        etaLabel: task.etaLabel,
                        isPaused: isPaused,
                        isFailed: isFailed,
                        error: task.error,
                      ),
                      style: TextStyle(
                        fontSize: DizzyType.caption,
                        fontWeight: DizzyType.wMedium,
                        color: isFailed
                            ? const Color(0xFFEF4444)
                            : (isPaused ? Colors.amber : Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),

              // Actions (Polish P7: pause/resume always visible + labelled).
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDownloading)
                    Semantics(
                      button: true,
                      label: 'Pause download of ${task.title}',
                      child: IconButton(
                      icon: const Icon(Icons.pause_circle_rounded, color: Colors.amber, size: 26),
                      tooltip: 'Pause',
                      onPressed: () => DownloadService.instance.pauseDownload(task.id),
                    ),
                    )
                  else if (isPaused || isFailed)
                    Semantics(
                      button: true,
                      label: 'Resume download of ${task.title}',
                      child: IconButton(
                      icon: Icon(Icons.play_circle_fill_rounded, color: palette.primaryColor, size: 26),
                      tooltip: 'Resume',
                      onPressed: () => DownloadService.instance.resumeDownload(task.id),
                    ),
                    ),
                  IconButton(
                    icon: Icon(Icons.folder_open_rounded, color: Colors.white.withValues(alpha: 0.6), size: 22),
                    tooltip: 'Open Folder Location',
                    onPressed: () async {
                      final opened = await OpenFileLocationHelper.openLocation(task.targetFilePath);
                      if (!opened && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Folder: ${File(task.targetFilePath).parent.path}')),
                        );
                      }
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.4), size: 22),
                    tooltip: 'Cancel',
                    onPressed: () => _confirmDelete(task),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(
                isFailed
                    ? const Color(0xFFEF4444)
                    : (isPaused ? Colors.amber : palette.primaryColor),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                task.sizeLabel,
                style: TextStyle(fontSize: DizzyType.captionSm, color: Colors.white.withValues(alpha: 0.45)),
              ),
              Text(
                '${DownloadProgressText.wholePercent(progress)}%',
                style: TextStyle(fontSize: DizzyType.captionSm, fontWeight: DizzyType.wBold, color: Colors.white.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedList(List<DownloadTask> tasks, AppThemePalette palette) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_rounded, size: 64, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text(
              'No downloaded media',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Text(
              'Completed downloads will appear here for offline playback.',
              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4)),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.58,
      ),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _buildCompletedCard(task, palette);
      },
    );
  }

  Widget _buildCompletedCard(DownloadTask task, AppThemePalette palette) {
    return Container(
      decoration: BoxDecoration(
        color: palette.cardBackgroundColor.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster / Backdrop Thumbnail with Play Trigger
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: const Color(0xFF1E212E),
                    child: task.posterUrl != null && task.posterUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: task.posterUrl!,
                            fit: BoxFit.cover,
                            // P12: decode-capped (was full-res).
                            memCacheWidth: ImageCaps.kCardW,
                            maxWidthDiskCache: ImageCaps.kCardW,
                            errorWidget: (_, __, ___) => const Center(
                              child: Icon(Icons.movie_rounded, color: Colors.white24, size: 36),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.movie_rounded, color: Colors.white24, size: 36),
                          ),
                  ),

                  // Gradient
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Center Play Button
                  Center(
                    child: GestureDetector(
                      onTap: () => _playDownloadedMedia(task),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.primaryColor,
                          boxShadow: [
                            BoxShadow(
                              color: palette.primaryColor.withValues(alpha: 0.5),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),

                  // Open Folder Location (Top-Left)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: GestureDetector(
                      onTap: () async {
                        final opened = await OpenFileLocationHelper.openLocation(task.targetFilePath);
                        if (!opened && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Path: ${task.targetFilePath}')),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.7),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 0.8,
                          ),
                        ),
                        child: const Icon(Icons.folder_open_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  ),

                  // Delete Action (Top-Right)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () => _confirmDelete(task),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.7),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 0.8,
                          ),
                        ),
                        child: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  ),

                  // File size tag (Bottom-Right)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        DownloadTask.formatBytes(task.totalBytes),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Metadata Row
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    task.season != null && task.episode != null
                        ? 'S${task.season}:E${task.episode} • Offline'
                        : (task.year != null ? '${task.year} • Offline' : 'Offline Media'),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageGauge(AppThemePalette palette) {
    final videoBytes = DownloadService.instance.tasksNotifier.value
        .where((t) => t.isCompleted)
        .fold<int>(0, (sum, t) {
      try {
        final f = File(t.targetFilePath);
        return sum + (f.existsSync() ? f.lengthSync() : t.totalBytes);
      } catch (_) {
        return sum + t.totalBytes;
      }
    });
    final musicBytes = MusicDownloadService.instance.totalDownloadedSizeBytes;
    final dizzyTotalBytes = videoBytes + musicBytes;

    final dizzyFormatted = _formatBytes(dizzyTotalBytes);
    final freeFormatted = _storageSpace != null ? _storageSpace!.freeFormatted : 'Free space checking…';

    double usedRatio = 0.05;
    if (_storageSpace != null && _storageSpace!.totalBytes > 0) {
      usedRatio = (dizzyTotalBytes / _storageSpace!.totalBytes).clamp(0.02, 1.0);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF13151D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.pie_chart_outline_rounded, size: 18, color: palette.primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    'Dizzy Storage: $dizzyFormatted',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                freeFormatted,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 7,
              child: LinearProgressIndicator(
                value: usedRatio,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(palette.primaryColor),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  foregroundColor: const Color(0xFF00E5FF),
                ),
                onPressed: _cleanCache,
                icon: _isCleaningCache
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)),
                      )
                    : const Icon(Icons.cleaning_services_rounded, size: 16),
                label: const Text('Clean Cache', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  foregroundColor: Colors.white70,
                ),
                onPressed: () async {
                  final dir = await DownloadPathHelper.getDownloadsDirectoryPath();
                  final opened = await OpenFileLocationHelper.openLocation(dir);
                  if (!opened && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Folder path: $dir')),
                    );
                  }
                },
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: const Text('Export Downloads', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMusicDownloadedList(AppThemePalette palette) {
    final tracks = MusicDownloadService.instance.downloadedTracks;
    if (tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off_rounded, size: 64, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text(
              'No offline music yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Text(
              'Songs you download will show up here for offline listening.',
              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C5CFF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.music_note_rounded, size: 18),
              label: const Text('Explore Music'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final track = tracks[index];
        final sizeFormatted = _formatBytes(track.fileSizeBytes);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: palette.cardBackgroundColor.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 50,
                  height: 50,
                  color: const Color(0xFF1C1E2A),
                  child: track.localCoverPath.isNotEmpty && File(track.localCoverPath).existsSync()
                      ? Image.file(
                          File(track.localCoverPath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white38),
                        )
                      : (track.coverUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: track.coverUrl,
                              memCacheWidth: 100,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white38),
                            )
                          : const Icon(Icons.music_note, color: Colors.white38)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${track.artist} • ${track.album}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            track.format.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF00E5FF),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          sizeFormatted,
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF00E5FF), size: 30),
                onPressed: () {
                  MusicPlayerController.instance.playTrack(
                    track.toMusicTrack(),
                    playlistQueue: tracks.map((t) => t.toMusicTrack()).toList(),
                  );
                },
                tooltip: 'Play',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                onPressed: () => _confirmDeleteMusic(track),
                tooltip: 'Delete',
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteMusic(DownloadedMusicTrack track) async {
    final ok = await DizzyDialogs.confirm(
      context,
      title: 'Delete Music Download',
      line: 'Are you sure you want to delete "${track.title}" from offline storage?',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok) {
      await MusicDownloadService.instance.deleteDownloadedTrack(track.id);
      await _loadStorageSpace();
      if (mounted) setState(() {});
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }
}
