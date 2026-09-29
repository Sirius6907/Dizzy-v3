/// F2 — the one download card.
///
/// Whatever engine saved the file, the card is identical: same progress
/// bar, same numbers, same buttons, same failure line. The only thing
/// that varies is a small badge naming the engine, because users already
/// know the words "Torrent" and "Direct".
///
/// The button set is not decided here. It comes from `DownloadTaskActions`
/// — a pure function of the task's status — so a new engine cannot
/// produce a new card, and the parity between torrent/HLS/HTTP is a
/// property the tests assert rather than a thing to keep in sync by hand.
///
/// Failure handling follows the app's error contract: the user reads one
/// Easy English sentence and a Retry button, while the technical detail
/// has already gone to `AppErrorLog` on the failure path in
/// `DownloadService`. Raw exception text never reaches this widget.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/download/download_task_model.dart';
import '../../../services/download/download_progress_text.dart';
import '../../../services/download/download_service.dart';
import '../../../services/download/download_task_actions.dart';
import '../../../utils/perf/image_caps.dart';
import '../../../utils/platform/open_file_location_helper.dart';

class DownloadProgressCard extends StatelessWidget {
  final DownloadTask task;

  /// Called for Cancel. The page owns the confirmation dialog — a card in
  /// a list has no business opening modals of its own.
  final VoidCallback onCancel;

  const DownloadProgressCard({
    super.key,
    required this.task,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plan = DownloadTaskActions.actionsFor(task);
    final progress = task.progressPercent;
    final isFailed = task.status == DownloadStatus.failed;
    final isPaused = task.status == DownloadStatus.paused;
    final isDownloading = task.status == DownloadStatus.downloading;
    final barColor = isFailed
        ? scheme.error
        : (isPaused ? Colors.amber : scheme.primary);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumb(task: task),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _EngineBadge(label: plan.engineLabel, color: scheme.primary),
                      const SizedBox(height: 6),
                      Text(
                        _statusLine(),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isFailed
                              ? scheme.error
                              : (isPaused ? Colors.amber : scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                minHeight: 5,
                backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(task.sizeLabel, style: const TextStyle(fontSize: 11.5)),
                Text(
                  '${DownloadProgressText.wholePercent(progress)}%',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (isDownloading && task.etaSeconds != null) ...[
              const SizedBox(height: 4),
              Text(
                'About ${task.etaLabel} left',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            _ActionRow(plan: plan, task: task, onCancel: onCancel),
          ],
        ),
      ),
    );
  }

  /// One line, one voice — [DownloadProgressText] owns the wording so the
  /// card and any future summary cannot drift apart.
  String _statusLine() => DownloadProgressText.line(
        progress: task.progressPercent,
        speedLabel: task.speedLabel,
        etaLabel: task.etaLabel,
        isPaused: task.status == DownloadStatus.paused,
        isFailed: task.status == DownloadStatus.failed,
        error: task.error,
      );
}

class _ActionRow extends StatelessWidget {
  final DownloadActionSet plan;
  final DownloadTask task;
  final VoidCallback onCancel;

  const _ActionRow({
    required this.plan,
    required this.task,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final service = DownloadService.instance;

    return Wrap(
      spacing: 8,
      children: [
        for (final action in plan.actions)
          if (action == DownloadAction.openFolder)
            _IconAction(
              icon: Icons.folder_open_rounded,
              label: 'Open folder',
              onPressed: () => _openFolder(context, task),
            )
          else if (action == DownloadAction.cancel)
            _IconAction(
              icon: Icons.close_rounded,
              label: 'Remove',
              onPressed: onCancel,
            )
          else if (action == DownloadAction.pause)
            _IconAction(
              icon: Icons.pause_circle_rounded,
              label: 'Pause',
              color: Colors.amber,
              onPressed: () => service.pauseDownload(task.id),
            )
          else if (action == DownloadAction.resume)
            _IconAction(
              icon: Icons.play_circle_fill_rounded,
              label: 'Resume',
              color: scheme.primary,
              onPressed: () => service.resumeDownload(task.id),
            )
          else if (action == DownloadAction.retry)
            _IconAction(
              icon: Icons.refresh_rounded,
              label: 'Retry',
              color: scheme.primary,
              onPressed: () => service.resumeDownload(task.id),
            ),
      ],
    );
  }

  Future<void> _openFolder(BuildContext context, DownloadTask task) async {
    final opened = await OpenFileLocationHelper.openLocation(task.targetFilePath);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the folder.')),
      );
    }
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onPressed;

  const _IconAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: color),
        label: Text(label, style: const TextStyle(fontSize: 12.5)),
      ),
    );
  }
}

class _EngineBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _EngineBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final DownloadTask task;

  const _Thumb({required this.task});

  @override
  Widget build(BuildContext context) {
    final url = task.posterUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 62,
        child: url != null && url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: ImageCaps.kThumb,
                maxWidthDiskCache: ImageCaps.kThumb,
                errorWidget: (_, __, ___) => const Icon(Icons.movie_rounded),
              )
            : const Icon(Icons.movie_rounded),
      ),
    );
  }
}
