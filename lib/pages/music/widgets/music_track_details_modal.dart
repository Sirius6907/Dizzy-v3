import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/music/music_track.dart';
import '../../../utils/perf/image_caps.dart';
import '../../../widgets/common/performance_liquid_lens.dart';

class MusicTrackDetailsModal extends StatelessWidget {
  final MusicTrack track;

  const MusicTrackDetailsModal({super.key, required this.track});

  static void show(BuildContext context, MusicTrack track) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MusicTrackDetailsModal(track: track),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLossless = track.title.toLowerCase().contains('flac') ||
        track.title.toLowerCase().contains('lossless');
    final bitrate = isLossless ? '1,411 kbps (Lossless)' : '320 kbps (CBR High)';
    final sampleRate = isLossless ? '48.0 kHz / 24-bit Studio' : '44.1 kHz / 16-bit';
    final format = isLossless ? 'FLAC (Free Lossless Audio)' : 'MPEG-4 AAC / MP3';
    final approxSizeMb = ((track.durationSeconds * (isLossless ? 1411 : 320)) / (8 * 1024)).toStringAsFixed(1);

    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.sheet,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0C0E14).withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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

            // Header with artwork
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: track.coverUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    memCacheWidth: ImageCaps.kThumb,
                    maxWidthDiskCache: ImageCaps.kThumb,
                    errorWidget: (_, __, ___) => Container(
                      width: 56,
                      height: 56,
                      color: Colors.white10,
                      child: const Icon(Icons.music_note_rounded, color: Colors.white30),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artist,
                        style: const TextStyle(color: Colors.white60, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            const Text(
              'AUDIO SPECIFICATIONS',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  _buildSpecRow('Audio Codec / Format', format, isHighlight: isLossless),
                  const Divider(color: Colors.white10, height: 16),
                  _buildSpecRow('Stream Bitrate', bitrate, isHighlight: isLossless),
                  const Divider(color: Colors.white10, height: 16),
                  _buildSpecRow('Sample Rate / Depth', sampleRate),
                  const Divider(color: Colors.white10, height: 16),
                  _buildSpecRow('Channel Configuration', 'Stereo 2.0 (Direct Hardware Out)'),
                  const Divider(color: Colors.white10, height: 16),
                  _buildSpecRow('Est. Stream Size', '~$approxSizeMb MB'),
                  const Divider(color: Colors.white10, height: 16),
                  _buildSpecRow('Target Loudness', '-14.0 LUFS (EBU R128 Norm)'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Copy ID3 Info button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Clipboard.setData(ClipboardData(
                    text: 'Title: ${track.title}\nArtist: ${track.artist}\nFormat: $format\nBitrate: $bitrate\nSample: $sampleRate',
                  ));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Audio specifications copied to clipboard! 📋')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy Audio Specs'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 13),
        ),
        Text(
          value,
          style: TextStyle(
            color: isHighlight ? const Color(0xFF00D2EF) : Colors.white,
            fontSize: 13,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
