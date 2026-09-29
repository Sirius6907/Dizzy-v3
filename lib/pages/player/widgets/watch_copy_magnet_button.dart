import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dizzy/design/dizzy_tokens.dart';

import 'watch_style.dart';

class WatchCopyMagnetButton extends StatefulWidget {
  final String magnetUrl;

  const WatchCopyMagnetButton({super.key, required this.magnetUrl});

  @override
  State<WatchCopyMagnetButton> createState() => WatchCopyMagnetButtonState();
}

class WatchCopyMagnetButtonState extends State<WatchCopyMagnetButton> {
  bool _copied = false;
  bool _hovered = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.magnetUrl));
    HapticFeedback.lightImpact();

    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
            SizedBox(width: 8),
            Text(
              'Magnet link copied to clipboard',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        backgroundColor: DizzyColors.scrim,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: _copied ? 'Copied!' : 'Copy Magnet Link',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _copy,
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _copied
                    ? const Color(0xFF10B981).withValues(alpha: 0.2)
                    : (_hovered
                        ? const Color(0xFF00E5FF).withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.06)),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _copied
                      ? const Color(0xFF10B981).withValues(alpha: 0.5)
                      : (_hovered
                          ? const Color(0xFF00E5FF).withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.08)),
                  width: 1,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  _copied ? Icons.check_rounded : Icons.link_rounded,
                  key: ValueKey(_copied),
                  color: _copied
                      ? const Color(0xFF10B981)
                      : (_hovered ? const Color(0xFF00E5FF) : WatchColors.textSecondary),
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

