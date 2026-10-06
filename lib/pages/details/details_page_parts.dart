part of 'details_page.dart';

class _EpisodeCard extends StatefulWidget {
  final Video episode;
  final String? fallbackImageUrl;
  final VoidCallback? onTap;

  const _EpisodeCard({required this.episode, this.fallbackImageUrl, this.onTap});

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    final imgUrl = ep.thumbnail ?? widget.fallbackImageUrl;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap ?? () {},
        child: AnimatedScale(
          scale: _hovered ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: Container(
            decoration: BoxDecoration(
              color: DizzyColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _hovered ? Colors.white.withOpacity(0.22) : Colors.white.withOpacity(0.04)),
              boxShadow: _hovered
                  ? [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 18, offset: const Offset(0, 8))]
                  : [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imgUrl != null)
                          CachedNetworkImage(
                            imageUrl: imgUrl,
                            fit: BoxFit.cover,
                            // Polish P14: uncapped decode = OOM risk on 3GB.
                            memCacheWidth: ImageCaps.kCardW,
                            maxWidthDiskCache: ImageCaps.kCardW,
                            errorWidget: (context, url, error) => const ColoredBox(color: DizzyColors.scrim),
                          )
                        else
                          const ColoredBox(color: DizzyColors.scrim),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                              stops: const [0.5, 1.0],
                            ),
                          ),
                        ),
                        Center(
                          child: AnimatedOpacity(
                            opacity: _hovered ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 150),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 24),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(DizzySpace.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text('EP ${ep.episode ?? "?"}', style: const TextStyle(color: DizzyColors.accent, fontWeight: FontWeight.bold, fontSize: 12)),
                            const Spacer(),
                            if (ep.released != null && ep.released!.length >= 10)
                              Text(ep.released!.substring(0, 10), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ep.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                        if (ep.overview != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            ep.overview!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.3),
                          ),
                        ],
                      ],
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

class _HoverButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleAmount;

  const _HoverButton({required this.child, required this.onTap, this.scaleAmount = 1.04});

  @override
  State<_HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<_HoverButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() { _isHovered = false; _isPressed = false; }),
      // Keyboard / DPAD friendly: Enter ya Space se bhi dab jaye (P3/P13).
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Semantics(
          button: true,
          child: GestureDetector(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: _isPressed ? 0.96 : (_isHovered ? widget.scaleAmount : 1.0),
              duration: DizzyMotion.instant,
              curve: DizzyMotion.easeOut,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}