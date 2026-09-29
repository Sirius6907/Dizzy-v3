import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dizzy/models/movie/movie_detail.dart';
import 'package:dizzy/models/movie/video.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/download/download_task_model.dart';
import '../../models/music/downloaded_music_track.dart';
import '../../services/download/download_service.dart';
import '../../services/download/download_trash.dart';
import '../../services/download/offline_hub_service.dart';
import '../../services/music/music_download_service.dart';
import '../../services/music/music_player_controller.dart';
import '../../services/theme/app_theme_service.dart';
import '../../utils/download/download_path_helper.dart';
import '../../utils/platform/open_file_location_helper.dart';
import '../../utils/platform/storage_space_helper.dart';
import '../../widgets/common/notify.dart';
import '../../widgets/common/offline_aware_scaffold.dart';
import '../../widgets/download/download_progress_card.dart';
import '../../widgets/download/downloaded_media_card.dart';
import '../../widgets/download/downloaded_music_tile.dart';
import '../../widgets/download/storage_sweep_sheet.dart';
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
    _bootOfflineHub();
    // v1.2.0-T2.6: first-time Downloads guide (skipable, never nags).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GuideCard.maybeShow(context, 'downloads', AppGuides.downloads);
    });
  }

  /// F2: bring the hub up, then ask the storage guard whether it has
  /// anything worth interrupting for. The sheet stays silent on its own
  /// when the disk is fine — that is the common case.
  Future<void> _bootOfflineHub() async {
    await OfflineHubService.instance.initialize();
    // F2: trash entries past the undo window are disposed of here, so the
    // space comes back without the user doing anything.
    await DownloadTrash.purgeExpired();
    if (!mounted) return;
    final suggestions = await OfflineHubService.instance.refreshStorageSuggestions();
    final undoable = await DownloadTrash.undoableEntries();
    if (!mounted) return;
    await StorageSweepSheet.maybeShow(
      context,
      suggestions: suggestions,
      undoable: undoable,
    );
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
    if (!ok) return;
    // F2: a delete is a move into the trash, not a delete, so the user
    // gets the 1-tap undo the brief asks for. The bytes stay on disk
    // until the 7-day window closes.
    final entry = await DownloadTrash.trash(task);
    if (!mounted) return;
    if (entry == null) {
      OfflineHubService.instance.dismissStorageSuggestions();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "${task.title}". Undo available for 7 days.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E212B),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => OfflineHubService.instance.undoTrash(entry.taskId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemePalette>(
      valueListenable: AppThemeService.currentPalette,
      builder: (context, palette, _) {
        return OfflineAwareScaffold(
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
                    );                  },
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
        return DownloadProgressCard(
          task: task,
          onCancel: () => _confirmDelete(task),
        );
      },
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
        return DownloadedMediaCard(
          task: task,
          onPlay: () => _playDownloadedMedia(task),
          onOpenFolder: () => _openTaskFolder(task),
          onDelete: () => _confirmDelete(task),
        );
      },
    );
  }

  Future<void> _openTaskFolder(DownloadTask task) async {
    final opened = await OpenFileLocationHelper.openLocation(task.targetFilePath);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Folder: ${File(task.targetFilePath).parent.path}')),
      );
    }
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

    final dizzyFormatted = formatDownloadBytes(dizzyTotalBytes);
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
        return DownloadedMusicTile(
          track: track,
          onPlay: () => MusicPlayerController.instance.playTrack(
            track.toMusicTrack(),
            playlistQueue: tracks.map((t) => t.toMusicTrack()).toList(),
          ),
          onDelete: () => _confirmDeleteMusic(track),
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

}
