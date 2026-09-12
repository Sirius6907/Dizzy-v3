import 'package:flutter/material.dart';

import '../../design/dizzy_tokens.dart';

/// Polish P10 — every empty/error/offline state speaks in ONE voice:
/// illustration + Easy English copy + ONE action. No white screens,
/// no dead ends, never raw tech text.
///
/// Trio contract: [icon] + [title] + [line] + optional [actionLabel].
class DizzyStateView extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String line;
  final String? actionLabel;
  final VoidCallback? onAction;

  const DizzyStateView({
    super.key,
    required this.icon,
    this.iconColor = Colors.white38,
    required this.title,
    required this.line,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title. $line',
      button: onAction != null,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(DizzySpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: iconColor),
              const SizedBox(height: DizzySpace.md - 2),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: DizzyType.title,
                  fontWeight: DizzyType.wBold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: DizzySpace.xs),
              Text(
                line,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: DizzyType.body,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: DizzySpace.lg - 4),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(actionLabel!),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C5CFF),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Raw error → Easy English. Pure — raw text never reaches the screen.
abstract final class StateViewCopy {
  const StateViewCopy._();

  static String friendlyError(String? raw) {
    final t = (raw ?? '').toLowerCase();
    if (t.contains('socketexception') ||
        t.contains('timeout') ||
        t.contains('timed out') ||
        t.contains('failed host lookup') ||
        t.contains('network is unreachable') ||
        t.contains('connection refused') ||
        t.contains('no internet') ||
        t.contains('unable to resolve')) {
      return 'Internet is slow or off. Check net, tap Try again.';
    }
    if (t.contains('401') ||
        t.contains('403') ||
        t.contains('unauthorized') ||
        t.contains('forbidden')) {
      return 'Login needed for this. Try another one.';
    }
    if (t.contains('404') || t.contains('not found')) {
      return 'Not found. It may be removed.';
    }
    return 'Something went wrong. Tap Try again.';
  }

  static String friendlyEmpty(String what) =>
      'No $what yet. Explore and add some you love.';
}
