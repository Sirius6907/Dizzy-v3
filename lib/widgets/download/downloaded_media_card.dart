/// F2 — the saved-media grid card.
///
/// Split out of `downloads_page.dart` purely for file size; the behaviour
/// is unchanged. Kept beside [DownloadProgressCard] so the two halves of
/// the downloads screen live in one place, and so the "same card whatever
/// the engine" promise is easy to check by reading one folder.
library;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/download/download_task_model.dart';
import '../../utils/perf/image_caps.dart';

/// A finished download, as a poster with a play button, its folder, and a
/// delete affordance. Play and delete are the only two things anyone does
/// here, so they are the only two things on the card.
class DownloadedMediaCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onPlay;
  final VoidCallback onOpenFolder;
  final VoidCallback onDelete;

  const DownloadedMediaCard({
    super.key,
    required this.task,
    required this.onPlay,
    required this.onOpenFolder,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = task.posterUrl;
    final hasPoster = url != null && url.isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                hasPoster
                    ? CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        memCacheWidth: ImageCaps.kCardW,
                        maxWidthDiskCache: ImageCaps.kCardW,
                        errorWidget: (_, __, ___) => const _PosterFallback(),
                      )
                    : const _PosterFallback(),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xB3000000)],
                    ),
                  ),
                ),
                Center(
                  child: _CircleButton(
                    icon: Icons.play_arrow_rounded,
                    onPressed: onPlay,
                    tooltip: 'Play',
                  ),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: _CircleButton(
                    icon: Icons.folder_open_rounded,
                    onPressed: onOpenFolder,
                    tooltip: 'Open folder',
                    dimmed: true,
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: _CircleButton(
                    icon: Icons.delete_outline_rounded,
                    onPressed: onDelete,
                    tooltip: 'Delete',
                    dimmed: true,
                  ),
                ),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: _SizeTag(bytes: task.totalBytes),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle,
                  style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "S2:E5 • Offline", or the year for a movie. Never a file path.
  String get _subtitle {
    if (task.season != null && task.episode != null) {
      return 'S${task.season}:E${task.episode} • Offline';
    }
    if (task.year != null) return '${task.year} • Offline';
    return 'Offline media';
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF1C1E2A),
      child: Center(child: Icon(Icons.movie_rounded, size: 36)),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  /// Small overlay buttons (folder, delete) sit on the artwork and need a
  /// dark plate to stay legible against a bright poster.
  final bool dimmed;

  const _CircleButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        shape: const CircleBorder(),
        color: dimmed ? const Color(0xB3000000) : scheme.primary,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.all(dimmed ? 5 : 10),
            child: Icon(
              icon,
              size: dimmed ? 14 : 28,
              color: dimmed ? Colors.white : scheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SizeTag extends StatelessWidget {
  final int bytes;

  const _SizeTag({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        DownloadTask.formatBytes(bytes),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Bytes helper kept next to the card that prints it.
String formatDownloadBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

/// True when the file for [task] is still on disk. Checked on the page
/// before offering playback, so a moved file never opens a black player.
bool downloadFileExists(DownloadTask task) =>
    File(task.targetFilePath).existsSync();
