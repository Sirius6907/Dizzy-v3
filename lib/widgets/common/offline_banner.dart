import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_card.dart';

/// Phase 31 — Universal Offline Fail-Soft Banner.
///
/// Shows a tactile banner at the top of every page
/// when offline. When connectivity returns the banner slides
/// away with an animated transition (no shaders).
/// All user-facing copy is Easy English.
class DizzyOfflineBanner extends StatefulWidget {
  final bool isOffline;
  final bool showingSavedCopy;
  final VoidCallback? onRetry;

  const DizzyOfflineBanner({
    super.key,
    required this.isOffline,
    this.showingSavedCopy = false,
    this.onRetry,
  });

  @override
  State<DizzyOfflineBanner> createState() => _DizzyOfflineBannerState();
}

class _DizzyOfflineBannerState extends State<DizzyOfflineBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0.0, -1.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeInOutCubic),
    );
    if (widget.isOffline) {
      _visible = true;
      _slideCtrl.forward();
    } else {
      _slideCtrl.value = 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant DizzyOfflineBanner old) {
    super.didUpdateWidget(old);
    if (widget.isOffline && !_visible) {
      _visible = true;
      _slideCtrl.forward(from: 0.0);
    } else if (!widget.isOffline && _visible) {
      _slideCtrl.reverse().then((_) {
        if (mounted && !widget.isOffline) {
          setState(() => _visible = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final bool saved = widget.showingSavedCopy;
    final String mainLine = saved
        ? 'You are offline. Showing your saved copy.'
        : 'No internet. Waiting…';
    return SlideTransition(
      position: _slideAnim,
      child: Semantics(
        liveRegion: true,
        label: 'No internet. Waiting for connection.',
        child: DizzyTactileCard(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.wifi_off_rounded, color: DizzyGlow.red, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mainLine,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (saved)
                TextButton(
                  onPressed: widget.onRetry,
                  child: const Text('Retry'),
                )
              else
                const Text(
                  'Your place is safe.',
                  style: TextStyle(
                    color: DizzyVoid.ash,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phase 31 — Calm-face Easy English error copy.
///
/// Converts raw technical errors into short, human-friendly lines.
/// Raw details (stack traces, hex codes) are NEVER passed through.
abstract final class CalmFaceCopy {
  static String forError(String error) {
    final String lower = error.toLowerCase();
    if (lower.contains('401') ||
        lower.contains('unauthorized') ||
        lower.contains('unauthorised')) {
      return 'Please Login again. Then Try again.';
    }
    if (lower.contains('404') || lower.contains('not found')) {
      return 'Not found. It may have moved. Ask again later.';
    }
    return 'Something went wrong. Try again.';
  }
}

/// Global connectivity stream shared by all offline-aware widgets.
/// Extends [ValueNotifier] so it is a [ValueListenable] directly.
class ConnectivityListener extends ValueNotifier<List<ConnectivityResult>> {
  static final ConnectivityListener _instance = ConnectivityListener._();
  static ConnectivityListener get instance => _instance;

  ConnectivityListener._() : super([ConnectivityResult.wifi]);

  StreamSubscription<List<ConnectivityResult>>? _sub;

  void start() {
    if (_sub != null) return;
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      value = results;
    });
    Connectivity().checkConnectivity().then((dynamic result) {
      if (result is List) {
        value = result.cast<ConnectivityResult>();
      } else {
        value = <ConnectivityResult>[result as ConnectivityResult];
      }
    }).catchError((_) {});
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
