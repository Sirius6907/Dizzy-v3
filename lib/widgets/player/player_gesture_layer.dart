// Player gesture layer — touch-first controls overlay:
//   • horizontal drag            → seek (with preview HUD + haptic ticks)
//   • left-zone vertical drag    → screen brightness
//   • right-zone vertical drag   → volume
//   • double-tap left/right zone → ±10s skip with ripple
//   • double-tap center          → fullscreen (host)
//   • long-press                 → 2x speed while held
//   • single tap                 → toggle controls (host)
// Works for touch AND mouse drags; desktop keyboard/mouse flow unchanged.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../services/theme/app_theme_service.dart';

/// Callbacks the host player screen must provide.
class PlayerGestureHost {
  final Duration Function() position;
  final Duration Function() duration;
  final void Function(Duration target) seekTo;
  final void Function(Duration delta) seekBy;
  final double Function() volume;
  final void Function(double vol) setVolume;
  final double Function() speed;
  final void Function(double speed) setSpeed;
  final VoidCallback toggleControls;
  final VoidCallback toggleFullscreen;

  const PlayerGestureHost({
    required this.position,
    required this.duration,
    required this.seekTo,
    required this.seekBy,
    required this.volume,
    required this.setVolume,
    required this.speed,
    required this.setSpeed,
    required this.toggleControls,
    required this.toggleFullscreen,
  });
}

class PlayerGestureLayer extends StatefulWidget {
  final PlayerGestureHost host;
  final bool enabled;
  final Widget child;

  const PlayerGestureLayer({
    super.key,
    required this.host,
    this.enabled = true,
    required this.child,
  });

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  // ─── Seek drag state ──────────────────────────────────────────
  bool _seeking = false;
  Duration _seekFrom = Duration.zero;
  Duration _seekTarget = Duration.zero;
  double _dragStartDx = 0;

  // ─── Brightness/volume drag state ─────────────────────────────
  _SideDragMode _sideMode = _SideDragMode.none;
  double _dragStartDy = 0;
  double _dragStartValue = 0;
  double _liveValue = 0;
  bool _brightnessSupported = true;
  // v1.1.9 (Task 13): exact value captured at open — dispose restores THIS,
  // so the player never leaves the system dimmed/brightened.
  double? _originalBrightness;

  // ─── Speed hold state ─────────────────────────────────────────
  bool _speedHolding = false;
  double _speedBeforeHold = 1.0;

  // ─── Double-tap ripple state ─────────────────────────────────
  Timer? _rippleTimer;
  bool _showRipple = false;
  bool _rippleIsForward = true;

  @override
  void initState() {
    super.initState();
    _captureOriginalBrightness();
  }

  Future<void> _captureOriginalBrightness() async {
    // Store the EXACT value so dispose can restore it (v1.1.9 Task 13).
    try {
      _originalBrightness = await ScreenBrightness.instance.application;
      _brightnessSupported = true;
    } catch (_) {
      _originalBrightness = null;
      _brightnessSupported = false;
    }
  }

  @override
  void dispose() {
    _rippleTimer?.cancel();
    // Restore the user's original brightness when the player closes.
    if (_brightnessSupported) {
      try {
        final orig = _originalBrightness;
        if (orig != null) {
          ScreenBrightness.instance.setApplicationScreenBrightness(orig);
        } else {
          ScreenBrightness.instance.resetApplicationScreenBrightness();
        }
      } catch (_) {}
    }
    super.dispose();
  }

  void _onPanStart(DragStartDetails d) {
    final w = context.size?.width ?? 1;
    _dragStartDx = d.localPosition.dx;
    _dragStartDy = d.localPosition.dy;

    if (d.localPosition.dx > w * 0.65) {
      _sideMode = _SideDragMode.volume;
      _dragStartValue = widget.host.volume().clamp(0.0, 1.0);
      _liveValue = _dragStartValue;
    } else if (d.localPosition.dx < w * 0.35) {
      _sideMode = _SideDragMode.brightness;
      _dragStartValue = _liveValue = 1;
      if (_brightnessSupported) {
        ScreenBrightness.instance.application.then((v) {
          if (mounted) {
            _dragStartValue = _liveValue = v.clamp(0.05, 1.0);
          }
        }).catchError((_) {
          _brightnessSupported = false;
        });
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final size = context.size ?? const Size(400, 300);
    final totalMs = widget.host.duration().inMilliseconds;
    if (totalMs <= 0) return;

    final horizontal = (d.localPosition.dy - _dragStartDy).abs() <
        (d.localPosition.dx - _dragStartDx).abs();

    if (horizontal || _seeking) {
      // ── Horizontal drag → seek ──
      if (!_seeking) {
        _seeking = true;
        _seekFrom = widget.host.position();
        _seekTarget = _seekFrom;
        HapticFeedback.selectionClick();
      }
      final dx = d.localPosition.dx - _dragStartDx;
      final ratio = (dx / (size.width * 0.85)).clamp(-1.0, 1.0);
      // v1.1.9 (Task 14): 0.75 scale — long movies need fewer drags.
      final deltaMs = (ratio * totalMs * 0.75).round();
      _seekTarget = Duration(
        milliseconds: (_seekFrom.inMilliseconds + deltaMs).clamp(0, totalMs),
      );
      if (mounted) setState(() {});
      return;
    }

    if (_sideMode == _SideDragMode.none) return;

    // ── Vertical drag → brightness (left) / volume (right) ──
    final dy = d.localPosition.dy - _dragStartDy;
    final ratio = (dy / (size.height * 0.7)).clamp(-1.0, 1.0);
    final next = (_dragStartValue + ratio * -0.6).clamp(0.0, 1.0);
    _liveValue = next;

    if (_sideMode == _SideDragMode.brightness) {
      if (_brightnessSupported) {
        ScreenBrightness.instance
            .setApplicationScreenBrightness(next.clamp(0.05, 1.0))
            .catchError((_) {
          _brightnessSupported = false;
          return null;
        });
      }
    } else {
      widget.host.setVolume(next);
    }
    if (mounted) setState(() {});
  }

  void _onPanEnd(DragEndDetails d) {
    if (_seeking) {
      widget.host.seekTo(_seekTarget);
      _seeking = false;
      HapticFeedback.lightImpact();
    }
    _sideMode = _SideDragMode.none;
    if (mounted) setState(() {});
  }

  Offset? _doubleTapPos;

  void _onDoubleTapDown(TapDownDetails d) => _doubleTapPos = d.localPosition;

  void _onDoubleTap() {
    final size = context.size ?? const Size(400, 300);
    final pos = _doubleTapPos ?? size.center(Offset.zero);
    final w = size.width;

    if (pos.dx > w * 0.65) {
      // right zone → +10s
      widget.host.seekBy(const Duration(seconds: 10));
      _showRippleAt(forward: true);
      HapticFeedback.lightImpact();
    } else if (pos.dx < w * 0.35) {
      // left zone → -10s
      widget.host.seekBy(const Duration(seconds: -10));
      _showRippleAt(forward: false);
      HapticFeedback.lightImpact();
    } else {
      // center → fullscreen (previous double-tap behavior)
      widget.host.toggleFullscreen();
    }
    _doubleTapPos = null;
  }

  void _showRippleAt({required bool forward}) {
    _rippleTimer?.cancel();
    setState(() {
      _showRipple = true;
      _rippleIsForward = forward;
    });
    _rippleTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showRipple = false);
    });
  }

  void _onLongPressStart(LongPressStartDetails d) {
    _speedBeforeHold = widget.host.speed();
    if (_speedBeforeHold < 0.5) _speedBeforeHold = 1.0;
    widget.host.setSpeed(2.0);
    setState(() => _speedHolding = true);
    HapticFeedback.mediumImpact();
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    widget.host.setSpeed(_speedBeforeHold);
    setState(() => _speedHolding = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onTap: widget.host.toggleControls,
      onDoubleTapDown: _onDoubleTapDown,
      onDoubleTap: _onDoubleTap,
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      child: Stack(
        children: [
          widget.child,
          if (_seeking) Positioned.fill(child: _buildSeekHud()),
          if (_sideMode != _SideDragMode.none && !_seeking)
            Center(child: _buildSideHud()),
          if (_speedHolding) Center(child: _buildSpeedHud()),
          if (_showRipple) _buildRipple(),
        ],
      ),
    );
  }

  Color get _accentColor => AppThemeService.currentPalette.value.primaryColor;

  Widget _buildSeekHud() {
    final total = widget.host.duration();
    final diff = _seekTarget - _seekFrom;
    final sign = diff.isNegative ? '- ' : '+ ';

    return Container(
      color: Colors.black.withValues(alpha: 0.25),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _accentColor.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fast_forward_rounded, color: _accentColor, size: 34),
            const SizedBox(height: 10),
            Text(
              _fmt(_seekTarget),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '$sign${_fmt(diff.abs())} • ${_fmt(total)}',
              style: TextStyle(
                color: _accentColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideHud() {
    final isBrightness = _sideMode == _SideDragMode.brightness;
    final value = _liveValue;
    final icon = isBrightness
        ? (value > 0.55
            ? Icons.brightness_high_rounded
            : value > 0.15
                ? Icons.brightness_4_rounded
                : Icons.brightness_low_rounded)
        : (value <= 0.0
            ? Icons.volume_off_rounded
            : value > 0.55
                ? Icons.volume_up_rounded
                : Icons.volume_down_rounded);
    final label = isBrightness ? 'Brightness' : 'Volume';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accentColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _accentColor, size: 34),
          const SizedBox(height: 12),
          SizedBox(
            width: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                color: _accentColor,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$label ${(value * 100).round()}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedHud() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accentColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fast_forward_rounded, color: _accentColor, size: 28),
          const SizedBox(width: 10),
          const Text(
            '2x Speed',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRipple() {
    final size = context.size ?? const Size(400, 300);
    final showLeft = _rippleIsForward == false;
    return Positioned(
      left: showLeft ? 28 : null,
      right: showLeft ? null : 28,
      top: size.height / 2 - 55,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _showRipple ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
              border: Border.all(color: _accentColor.withValues(alpha: 0.5)),
            ),
            child: Icon(
              _rippleIsForward
                  ? Icons.forward_10_rounded
                  : Icons.replay_10_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

enum _SideDragMode { none, brightness, volume }
