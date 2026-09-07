import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/movie/video.dart';
import '../../services/theme/app_theme_service.dart';

/// Netflix-style next-episode countdown overlay.
///
/// Shows the upcoming episode's title + thumbnail with a shrinking ring
/// timer. Auto-plays when the ring completes; "Play now" fires immediately;
/// cancel keeps the user on the ended episode.
class NextEpisodeCountdown extends StatefulWidget {
  final Video nextEpisode;
  final String showName;
  final String? backdropUrl;
  final VoidCallback onPlayNow;
  final VoidCallback onCancel;
  final Duration countdownDuration;

  const NextEpisodeCountdown({
    super.key,
    required this.nextEpisode,
    required this.showName,
    this.backdropUrl,
    required this.onPlayNow,
    required this.onCancel,
    this.countdownDuration = const Duration(seconds: 5),
  });

  @override
  State<NextEpisodeCountdown> createState() => _NextEpisodeCountdownState();
}

class _NextEpisodeCountdownState extends State<NextEpisodeCountdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _tickTimer;
  int _secondsLeft = 5;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.countdownDuration.inSeconds;
    _controller = AnimationController(
      vsync: this,
      duration: widget.countdownDuration,
    )..forward();

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        widget.onPlayNow();
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final ep = widget.nextEpisode;
    final sNum = ep.season ?? 1;
    final eNum = ep.episode ?? 1;
    final epTitle =
        ep.title.isNotEmpty ? ep.title : 'Episode $eNum';

    final thumb = ep.thumbnail ??
        widget.backdropUrl ??
        ep.thumbnail;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          color: Colors.black.withValues(alpha: 0.82),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF10131B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: palette.primaryColor.withValues(alpha: 0.25),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 40,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Thumbnail with episode badge
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: Stack(
                      children: [
                        if (thumb != null && thumb.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: thumb,
                            height: 170,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            memCacheWidth: 600,
                            maxWidthDiskCache: 600,
                            errorWidget: (_, __, ___) => Container(
                              height: 170,
                              color: const Color(0xFF171B26),
                              child: const Icon(
                                Icons.smart_display_rounded,
                                color: Colors.white24,
                                size: 44,
                              ),
                            ),
                          )
                        else
                          Container(
                            height: 170,
                            color: const Color(0xFF171B26),
                            child: const Icon(
                              Icons.smart_display_rounded,
                              color: Colors.white24,
                              size: 44,
                            ),
                          ),
                        Positioned(
                          left: 12,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color:
                                    palette.primaryColor.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              'NEXT: S$sNum:E$eNum',
                              style: TextStyle(
                                color: palette.primaryColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.showName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          epTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Buttons: Play now (ring) + Cancel
                        Row(
                          children: [
                            // Play-now with countdown ring
                            _RingButton(
                              progress: 1.0 - _controller.value,
                              secondsLeft: _secondsLeft,
                              color: palette.primaryColor,
                              label: 'Play Now',
                              onTap: widget.onPlayNow,
                            ),
                            const SizedBox(width: 12),
                            // Cancel
                            Expanded(
                              child: SizedBox(
                                height: 46,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color:
                                          Colors.white.withValues(alpha: 0.2),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: widget.onCancel,
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Filled button with a shrinking circular countdown ring on its icon.
class _RingButton extends StatelessWidget {
  final double progress; // 1.0 → 0.0
  final int secondsLeft;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _RingButton({
    required this.progress,
    required this.secondsLeft,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SizedBox(
        height: 46,
        child: Material(
          color: color.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          strokeWidth: 2.5,
                          color: color,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.15),
                        ),
                        Center(
                          child: Text(
                            '$secondsLeft',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
