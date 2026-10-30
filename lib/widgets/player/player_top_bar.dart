import 'package:flutter/material.dart';
import 'player_glass.dart';

/// Top header bar for the video player.
class PlayerTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? quality;
  final VoidCallback onBack;
  final VoidCallback? onToggleEpisodes;
  final bool isEpisodesActive;
  final VoidCallback? onScreenshot;
  final VoidCallback? onToggleAspect;
  final VoidCallback? onCast;
  final VoidCallback? onDownload;
  final bool isDownloading;
  final VoidCallback? onLock;
  final bool isLocked;
  final VoidCallback? onPip;

  const PlayerTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.quality,
    required this.onBack,
    this.onToggleEpisodes,
    this.isEpisodesActive = false,
    this.onScreenshot,
    this.onToggleAspect,
    this.onCast,
    this.onDownload,
    this.isDownloading = false,
    this.onLock,
    this.isLocked = false,
    this.onPip,
  });

  static const double _buttonSize = 40;
  static const double _buttonGap = 8;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 12,
        left: 20,
        right: 20,
        bottom: 24,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.72),
            Colors.black.withValues(alpha: 0.30),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlayerIconButton(
            size: _buttonSize,
            iconSize: 24,
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Back',
            onPressed: onBack,
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: PlayerTheme.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          height: 1.2,
                          shadows: [
                            Shadow(
                              color: Color(0x99000000),
                              offset: Offset(0, 2),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (quality != null && quality!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _QualityBadge(label: quality!),
                    ],
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: PlayerTheme.inkMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                      shadows: [
                        Shadow(
                          color: Color(0x99000000),
                          offset: Offset(0, 1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 12),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onPip != null) ...[
                PlayerIconButton(
                  size: _buttonSize,
                  iconSize: 20,
                  icon: const Icon(Icons.picture_in_picture_alt_rounded),
                  tooltip: 'Picture-in-Picture',
                  onPressed: onPip,
                ),
                const SizedBox(width: _buttonGap),
              ],
              if (onToggleEpisodes != null) ...[
                _EpisodesPill(
                  active: isEpisodesActive,
                  onTap: onToggleEpisodes!,
                ),
                const SizedBox(width: _buttonGap),
              ],
              if (onScreenshot != null) ...[
                PlayerIconButton(
                  size: _buttonSize,
                  iconSize: 20,
                  icon: const Icon(Icons.camera_alt_outlined),
                  tooltip: 'Screenshot',
                  onPressed: onScreenshot,
                ),
                const SizedBox(width: _buttonGap),
              ],
              if (onDownload != null) ...[
                PlayerIconButton(
                  size: _buttonSize,
                  iconSize: 20,
                  icon: isDownloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: PlayerTheme.success,
                          ),
                        )
                      : const Icon(Icons.file_download_outlined),
                  tooltip: isDownloading ? 'Downloading…' : 'Download media',
                  active: isDownloading,
                  activeColor: PlayerTheme.success,
                  backgroundColor: isDownloading
                      ? const Color(0x2610B981)
                      : null,
                  onPressed: onDownload,
                ),
                const SizedBox(width: _buttonGap),
              ],
              if (onCast != null) ...[
                PlayerIconButton(
                  size: _buttonSize,
                  iconSize: 20,
                  icon: const Icon(Icons.cast_rounded),
                  tooltip: 'Cast',
                  onPressed: onCast,
                ),
                if (onLock != null) const SizedBox(width: _buttonGap),
              ],
              // Lock sits at the far edge: the one control you cannot tap
              // by accident while reaching for something else.
              if (onLock != null)
                PlayerIconButton(
                  size: _buttonSize,
                  iconSize: 20,
                  icon: Icon(
                    isLocked ? Icons.lock_rounded : Icons.lock_outline_rounded,
                  ),
                  tooltip: isLocked ? 'Unlock player' : 'Lock player',
                  active: isLocked,
                  activeColor: PlayerTheme.danger,
                  backgroundColor: isLocked ? const Color(0x33EF4444) : null,
                  onPressed: onLock,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  final String label;

  const _QualityBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: PlayerTheme.raised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PlayerTheme.edgeSoft),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: PlayerTheme.inkMuted,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          height: 1.2,
        ),
      ),
    );
  }
}

class _EpisodesPill extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _EpisodesPill({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: PlayerTopBar._buttonSize,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: active ? PlayerTheme.accentSoft : PlayerTheme.raised,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? PlayerTheme.accent.withValues(alpha: 0.55)
                  : PlayerTheme.edgeSoft,
            ),
            boxShadow: PlayerTheme.buttonShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.video_library_rounded,
                size: 18,
                color: active ? PlayerTheme.accent : PlayerTheme.inkMuted,
              ),
              const SizedBox(width: 7),
              Text(
                'Episodes',
                style: TextStyle(
                  color: active ? PlayerTheme.ink : PlayerTheme.inkMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
