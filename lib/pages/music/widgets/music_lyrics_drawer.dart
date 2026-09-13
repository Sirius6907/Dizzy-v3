import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/music/music_track.dart';
import '../../../services/music/music_player_controller.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import 'music_hoverable.dart';
import 'music_lyric_share_dialog.dart';

class MusicLyricsDrawer extends StatefulWidget {
  final MusicTrack track;
  final MusicPlayerController playerController;
  final VoidCallback onClose;

  const MusicLyricsDrawer({
    super.key,
    required this.track,
    required this.playerController,
    required this.onClose,
  });

  @override
  State<MusicLyricsDrawer> createState() => _MusicLyricsDrawerState();
}

class _MusicLyricsDrawerState extends State<MusicLyricsDrawer> {
  final ScrollController _scrollController = ScrollController();
  bool _userIsScrolling = false;
  Timer? _resumeScrollTimer;
  int _lastActiveIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.playerController.addListener(_onPlayerTick);
  }

  @override
  void dispose() {
    widget.playerController.removeListener(_onPlayerTick);
    _resumeScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onPlayerTick() {
    if (!mounted) return;
    final index = widget.playerController.activeLyricIndex;
    if (index != _lastActiveIndex) {
      _lastActiveIndex = index;
      if (!_userIsScrolling && index >= 0) {
        _scrollToIndex(index);
      }
      setState(() {});
    }
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    // Each line is roughly 52px on average
    const estimatedItemHeight = 52.0;
    final target = (index * estimatedItemHeight) - 140.0;
    final clamped = target.clamp(0.0, _scrollController.position.maxScrollExtent);

    _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _onUserScrollStart() {
    _userIsScrolling = true;
    _resumeScrollTimer?.cancel();
    _resumeScrollTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _userIsScrolling = false);
        final idx = widget.playerController.activeLyricIndex;
        if (idx >= 0) _scrollToIndex(idx);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.playerController.currentLyrics;
    final activeIndex = widget.playerController.activeLyricIndex;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.sheet,
      child: Container(
        width: isMobile ? MediaQuery.sizeOf(context).width : 380,
        decoration: BoxDecoration(
          color: const Color(0xFF0F121C).withValues(alpha: 0.96),
          borderRadius: isMobile
              ? const BorderRadius.vertical(top: Radius.circular(28))
              : const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  bottomLeft: Radius.circular(28),
                ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 36,
              offset: const Offset(-8, 0),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C5CFF).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.format_quote_rounded,
                    color: Color(0xFF7C5CFF),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Karaoke Lyrics',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                // Share Lyric Card Button
                if (lyrics.isSynced || lyrics.plainLyrics.isNotEmpty)
                  MusicHoverable(
                    scaleFactor: 1.08,
                    child: IconButton(
                      tooltip: 'Generate Lyric Card',
                      icon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF00D2EF), size: 20),
                      onPressed: () {
                        MusicLyricShareDialog.show(
                          context,
                          track: widget.track,
                          lyrics: lyrics,
                          initialLineIndex: activeIndex >= 0 ? activeIndex : 0,
                        );
                      },
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                  onPressed: widget.onClose,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Content Area
            if (widget.playerController.isLoadingLyrics)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF7C5CFF)),
                      SizedBox(height: 12),
                      Text(
                        'Fetching synced karaoke lyrics...',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else if (!lyrics.isSynced && lyrics.plainLyrics.isEmpty)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.music_off_rounded, color: Colors.white24, size: 40),
                      SizedBox(height: 10),
                      Text(
                        'No lyrics found for this track.',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else if (lyrics.isSynced)
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification &&
                        notification.dragDetails != null) {
                      _onUserScrollStart();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    itemCount: lyrics.syncedLines.length,
                    itemBuilder: (context, index) {
                      final line = lyrics.syncedLines[index];
                      final isActive = index == activeIndex;

                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.playerController.seekTo(line.timestamp);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: isActive
                                ? const Color(0xFF7C5CFF).withValues(alpha: 0.18)
                                : Colors.transparent,
                          ),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            style: TextStyle(
                              color: isActive
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.40),
                              fontSize: isActive ? 18.5 : 15.0,
                              fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
                              letterSpacing: isActive ? -0.2 : 0.0,
                              height: 1.35,
                              shadows: isActive
                                  ? [
                                      const Shadow(
                                        color: Color(0xFF7C5CFF),
                                        blurRadius: 14,
                                        offset: Offset(0, 0),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(line.text),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    lyrics.plainLyrics,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.65,
                    ),
                  ),
                ),
              ),

            // Bottom Tap Hint
            if (lyrics.isSynced)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.touch_app_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Tap any lyric line to jump to timestamp',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11,
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
}
