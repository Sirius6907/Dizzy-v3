import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/music/music_track.dart';
import 'music_library_service.dart';

class MusicPlaylistSharingService {
  MusicPlaylistSharingService._();
  static final MusicPlaylistSharingService instance = MusicPlaylistSharingService._();

  /// Exports playlist to standard extended M3U format
  String exportToM3U(UserPlaylist playlist) {
    final buffer = StringBuffer();
    buffer.writeln('#EXTM3U');
    buffer.writeln('#PLAYLIST:${playlist.title}');
    buffer.writeln();

    for (final track in playlist.tracks) {
      buffer.writeln('#EXTINF:${track.durationSeconds},${track.artist} - ${track.title}');
      buffer.writeln('https://music.youtube.com/watch?v=${track.id}');
    }

    return buffer.toString();
  }

  /// Exports playlist to JSON format
  String exportToJson(UserPlaylist playlist) {
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'dizzy_playlist_v3',
      'version': '1.0',
      'title': playlist.title,
      'exported_at': DateTime.now().toIso8601String(),
      'tracks_count': playlist.tracks.length,
      'tracks': playlist.tracks.map((t) => t.toJson()).toList(),
    });
  }

  /// Imports playlist from JSON string
  Future<UserPlaylist?> importFromJson(String rawJson) async {
    try {
      final cleanJson = rawJson.startsWith('DIZZY-PLAYLIST:')
          ? rawJson.substring('DIZZY-PLAYLIST:'.length).trim()
          : rawJson.trim();

      final data = jsonDecode(cleanJson) as Map<String, dynamic>;
      final title = data['title'] as String? ?? data['name'] as String? ?? 'Imported Playlist';
      final tracksList = data['tracks'] as List<dynamic>? ?? [];

      final tracks = tracksList
          .whereType<Map<String, dynamic>>()
          .map((item) => MusicTrack.fromJson(item))
          .toList();

      final newPlaylist = UserPlaylist(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        title: '$title (Imported)',
        createdAt: DateTime.now().toIso8601String(),
        tracks: tracks,
      );

      await MusicLibraryService.instance.importUserPlaylist(newPlaylist);
      return newPlaylist;
    } catch (e) {
      debugPrint('[MusicPlaylistSharing] Import error: $e');
      return null;
    }
  }

  /// Shows the share / export bottom sheet modal
  static void showShareDialog(BuildContext context, UserPlaylist playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F121C),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.share_rounded, color: Color(0xFF7C5CFF), size: 24),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share "${playlist.title}"',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${playlist.tracks.length} tracks ready to export',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 1. Copy Dizzy Share Code
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              tileColor: Colors.white.withValues(alpha: 0.04),
              leading: const Icon(Icons.qr_code_rounded, color: Color(0xFF00D2EF)),
              title: const Text('Copy Dizzy Share Code', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text('Send to a friend with Dizzy app', style: TextStyle(color: Colors.white38, fontSize: 11)),
              trailing: const Icon(Icons.copy_rounded, color: Colors.white54, size: 18),
              onTap: () {
                Navigator.pop(ctx);
                final jsonStr = instance.exportToJson(playlist);
                Clipboard.setData(ClipboardData(text: 'DIZZY-PLAYLIST:$jsonStr'));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Dizzy Share Code copied to clipboard! 📋')),
                );
              },
            ),
            const SizedBox(height: 10),

            // 2. Export M3U Standard Playlist
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              tileColor: Colors.white.withValues(alpha: 0.04),
              leading: const Icon(Icons.playlist_play_rounded, color: Colors.amberAccent),
              title: const Text('Export M3U Audio Playlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text('Compatible with VLC, Foobar2000, and media players', style: TextStyle(color: Colors.white38, fontSize: 11)),
              trailing: const Icon(Icons.file_download_outlined, color: Colors.white54, size: 18),
              onTap: () {
                Navigator.pop(ctx);
                final m3u = instance.exportToM3U(playlist);
                Clipboard.setData(ClipboardData(text: m3u));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('M3U playlist copied to clipboard! 🎶')),
                );
              },
            ),
            const SizedBox(height: 10),

            // 3. Export JSON Backup
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              tileColor: Colors.white.withValues(alpha: 0.04),
              leading: const Icon(Icons.data_object_rounded, color: Color(0xFF1DB954)),
              title: const Text('Export JSON Backup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text('Full raw metadata & artwork backup', style: TextStyle(color: Colors.white38, fontSize: 11)),
              trailing: const Icon(Icons.copy_rounded, color: Colors.white54, size: 18),
              onTap: () {
                Navigator.pop(ctx);
                final json = instance.exportToJson(playlist);
                Clipboard.setData(ClipboardData(text: json));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('JSON playlist backup copied! 📦')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
