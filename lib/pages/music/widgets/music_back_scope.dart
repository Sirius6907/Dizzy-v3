import 'package:flutter/widgets.dart';

/// Back-button policy for the music section.
///
/// The now-playing player, the queue and the lyrics drawer are in-page
/// overlays, not routes. Without this, Android back pops the whole music
/// route and dumps the user on the app home even though something is still
/// open on screen. Here back always means "close the topmost layer", and only
/// when nothing is open does it mean "leave the section".
class MusicBackScope extends StatelessWidget {
  const MusicBackScope({
    super.key,
    required this.hasOverlay,
    required this.onDismiss,
    required this.child,
  });

  /// True when at least one in-page layer is covering the section.
  final bool hasOverlay;

  /// Closes exactly one layer — the topmost one.
  final VoidCallback onDismiss;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !hasOverlay,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        onDismiss();
      },
      child: child,
    );
  }
}
