part of 'audiobook_player_screen.dart';

class _PlayerIconButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final AppThemePalette palette;
  final String? tooltip;
  final VoidCallback? onTap;

  const _PlayerIconButton({
    required this.icon,
    required this.palette,
    this.size = 24,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final padding = size <= 22 ? 7.0 : 10.0;

    final btn = Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Icon(
        icon,
        size: size,
        color: enabled ? Colors.white : Colors.white24,
      ),
    );

    return Tooltip(
      message: tooltip ?? '',
      child: AudiobookInteractivePhysicsButton(
        effect: AudiobookSettings.customHoverEffect.value,
        glowColor: palette.primaryColor,
        borderRadius: BorderRadius.circular(size + 10),
        enabled: enabled,
        onTap: onTap,
        child: btn,
      ),
    );
  }
}

class _VolumeButton extends StatefulWidget {
  final double volume;
  final AppThemePalette palette;
  final ValueChanged<double> onVolumeChanged;

  const _VolumeButton({
    required this.volume,
    required this.palette,
    required this.onVolumeChanged,
  });

  @override
  State<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<_VolumeButton> {
  bool _showSlider = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlayerIconButton(
          icon: widget.volume == 0
              ? Icons.volume_off_rounded
              : (widget.volume > 0.5 ? Icons.volume_up_rounded : Icons.volume_down_rounded),
          size: 22,
          palette: widget.palette,
          tooltip: 'Volume',
          onTap: () {
            setState(() => _showSlider = !_showSlider);
          },
        ),
        if (_showSlider)
          SizedBox(
            width: 80,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                activeTrackColor: widget.palette.primaryColor,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: widget.volume,
                min: 0.0,
                max: 1.0,
                onChanged: widget.onVolumeChanged,
              ),
            ),
          ),
      ],
    );
  }
}

class _ChapterListItemTile extends StatefulWidget {
  final AudiobookChapter chapter;
  final int index;
  final bool isSelected;
  final bool isPlaying;
  final AppThemePalette palette;
  final VoidCallback onTap;

  const _ChapterListItemTile({
    required this.chapter,
    required this.index,
    required this.isSelected,
    required this.isPlaying,
    required this.palette,
    required this.onTap,
  });

  @override
  State<_ChapterListItemTile> createState() => _ChapterListItemTileState();
}

class _ChapterListItemTileState extends State<_ChapterListItemTile> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.98 : (_isHovered ? 1.015 : 1.0);
    final palette = widget.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? palette.primaryColor.withValues(alpha: 0.22)
                    : (_isHovered ? Colors.white.withValues(alpha: 0.08) : Colors.transparent),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.isSelected
                      ? palette.primaryColor.withValues(alpha: 0.6)
                      : (_isHovered ? Colors.white.withValues(alpha: 0.12) : Colors.transparent),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isSelected
                        ? (widget.isPlaying ? Icons.graphic_eq_rounded : Icons.pause_circle_filled_rounded)
                        : Icons.play_circle_outline_rounded,
                    color: widget.isSelected ? palette.primaryColor : Colors.white54,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.chapter.title,
                      style: TextStyle(
                        color: widget.isSelected ? Colors.white : Colors.white70,
                        fontSize: 14,
                        fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
