import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/music/music_track.dart';
import '../../../services/music/music_artwork_palette_service.dart';
import '../../../utils/perf/image_caps.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import 'music_hoverable.dart';

class MusicLyricShareDialog extends StatefulWidget {
  final MusicTrack track;
  final LyricsData lyrics;
  final int initialLineIndex;

  const MusicLyricShareDialog({
    super.key,
    required this.track,
    required this.lyrics,
    this.initialLineIndex = 0,
  });

  static void show(
    BuildContext context, {
    required MusicTrack track,
    required LyricsData lyrics,
    int initialLineIndex = 0,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (_) => MusicLyricShareDialog(
        track: track,
        lyrics: lyrics,
        initialLineIndex: initialLineIndex,
      ),
    );
  }

  @override
  State<MusicLyricShareDialog> createState() => _MusicLyricShareDialogState();
}

class _MusicLyricShareDialogState extends State<MusicLyricShareDialog> {
  late final Set<int> _selectedLineIndices;
  int _aspectRatioMode = 0; // 0: Story (9:16), 1: Square (1:1), 2: Card (4:5)
  late MusicTrackPalette _palette;

  @override
  void initState() {
    super.initState();
    _palette = MusicArtworkPaletteService.instance.getFastPalette(widget.track);
    _loadPalette();

    _selectedLineIndices = <int>{};
    if (widget.lyrics.syncedLines.isNotEmpty) {
      final start = widget.initialLineIndex.clamp(0, widget.lyrics.syncedLines.length - 1);
      _selectedLineIndices.add(start);
      if (start + 1 < widget.lyrics.syncedLines.length) {
        _selectedLineIndices.add(start + 1);
      }
    }
  }

  Future<void> _loadPalette() async {
    final real = await MusicArtworkPaletteService.instance.extractPalette(widget.track);
    if (mounted) setState(() => _palette = real);
  }

  void _toggleLine(int index) {
    setState(() {
      if (_selectedLineIndices.contains(index)) {
        if (_selectedLineIndices.length > 1) {
          _selectedLineIndices.remove(index);
        }
      } else {
        if (_selectedLineIndices.length >= 4) {
          // Keep max 4 lines
          final first = _selectedLineIndices.first;
          _selectedLineIndices.remove(first);
        }
        _selectedLineIndices.add(index);
      }
    });
  }

  String _getShareableText() {
    final lines = widget.lyrics.syncedLines;
    final sorted = _selectedLineIndices.toList()..sort();
    final selectedText = sorted.map((i) => lines[i].text).join('\n');
    return '"$selectedText"\n\n— ${widget.track.title} by ${widget.track.artist}\nShared from Dizzy Music';
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final isMobile = screenW < 650;
    final lines = widget.lyrics.syncedLines;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isMobile ? screenW - 24 : 760,
          maxHeight: 680,
        ),
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            decoration: BoxDecoration(
              color: const Color(0xFF0D101A),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _palette.primary.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.auto_awesome_rounded, color: _palette.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Lyric Card Studio',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Main Studio Body: Preview on Left/Top, Line Selector on Right
                Expanded(
                  child: isMobile
                      ? SingleChildScrollView(
                          child: Column(
                            children: [
                              _buildCardPreview(),
                              const SizedBox(height: 16),
                              _buildLineSelector(lines),
                            ],
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Card Live Preview
                            Expanded(
                              flex: 5,
                              child: Center(child: _buildCardPreview()),
                            ),
                            const SizedBox(width: 20),
                            // Line Selector & Format Controls
                            Expanded(
                              flex: 6,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'Pick up to 4 lines:',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const Spacer(),
                                      _aspectButton('9:16', 0),
                                      const SizedBox(width: 6),
                                      _aspectButton('1:1', 1),
                                      const SizedBox(width: 6),
                                      _aspectButton('4:5', 2),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Expanded(child: _buildLineSelector(lines)),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),

                // Bottom Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    MusicHoverable(
                      scaleFactor: 1.04,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _getShareableText()));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Lyric quotes copied to clipboard! ✨'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copy Lyrics'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    MusicHoverable(
                      scaleFactor: 1.05,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _palette.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _getShareableText()));
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: _palette.primary,
                              content: const Text('Lyric card copied & ready to share on Instagram/WhatsApp! 🚀'),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        },
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text('Share Card', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _aspectButton(String label, int mode) {
    final isSelected = _aspectRatioMode == mode;
    return InkWell(
      onTap: () => setState(() => _aspectRatioMode = mode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? _palette.primary : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildCardPreview() {
    final lines = widget.lyrics.syncedLines;
    final sorted = _selectedLineIndices.toList()..sort();
    final selectedTextList = sorted.map((i) => lines[i].text).toList();

    double aspect = 9 / 16;
    if (_aspectRatioMode == 1) aspect = 1.0;
    if (_aspectRatioMode == 2) aspect = 4 / 5;

    return AspectRatio(
      aspectRatio: aspect,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _palette.primary,
              _palette.secondary.withValues(alpha: 0.8),
              _palette.background,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: _palette.primary.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Track Info Header
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: widget.track.coverUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    memCacheWidth: ImageCaps.kThumb,
                    maxWidthDiskCache: ImageCaps.kThumb,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.track.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.track.artist,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),

            // Large Quote mark
            Text(
              '“',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 48,
                height: 0.8,
                fontFamily: 'serif',
              ),
            ),

            // Lyrics Lines
            for (final line in selectedTextList) ...[
              Text(
                line,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                  height: 1.35,
                  letterSpacing: -0.3,
                  shadows: [
                    Shadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],

            const Spacer(),

            // Dizzy Branding Pill
            Align(
              alignment: Alignment.bottomRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.music_note_rounded, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Dizzy Music',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineSelector(List<SyncedLyricLine> lines) {
    if (lines.isEmpty) {
      return Center(
        child: Text(
          widget.lyrics.plainLyrics.isNotEmpty
              ? 'Plain lyrics available — copy from text.'
              : 'No synced lines available.',
          style: const TextStyle(color: Colors.white38),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        itemCount: lines.length,
        separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
        itemBuilder: (context, index) {
          final isSelected = _selectedLineIndices.contains(index);
          return InkWell(
            onTap: () => _toggleLine(index),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? _palette.primary.withValues(alpha: 0.25) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: isSelected ? _palette.primary : Colors.white30,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      lines[index].text,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
