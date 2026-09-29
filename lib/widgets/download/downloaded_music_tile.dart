/// F2 — saved music list.
///
/// Split out of `downloads_page.dart` for file size only; the behaviour is
/// unchanged. It sits beside the video download widgets so the downloads
/// screen's two halves can be read together.
library;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/music/downloaded_music_track.dart';

class DownloadedMusicTile extends StatelessWidget {
  final DownloadedMusicTrack track;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  const DownloadedMusicTile({
    super.key,
    required this.track,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _Cover(track: track),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${track.artist} • ${track.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
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
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        formatDownloadedMusicBytes(track.fileSizeBytes),
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.play_circle_fill_rounded,
                color: Color(0xFF00E5FF),
                size: 30,
              ),
              onPressed: onPlay,
              tooltip: 'Play',
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: scheme.onSurfaceVariant, size: 20),
              onPressed: onDelete,
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final DownloadedMusicTrack track;

  const _Cover({required this.track});

  @override
  Widget build(BuildContext context) {
    final local = track.localCoverPath;
    final hasLocal = local.isNotEmpty && File(local).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 50,
        height: 50,
        child: hasLocal
            ? Image.file(
                File(local),
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
    );
  }
}

String formatDownloadedMusicBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}
