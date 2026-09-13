import 'package:flutter/material.dart';

/// UX7 — Offline + calm error banner.
///
/// Easy English only. Shows cached fallback state with one Retry action.
/// Pure UI — caller decides when offline/cached.
class DizzyOfflineBanner extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (!isOffline) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      label: showingSavedCopy
          ? 'You are offline. Showing your saved copy.'
          : 'You are offline.',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.orange.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              color: Colors.orange,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                showingSavedCopy
                    ? 'You are offline. Showing your saved copy.'
                    : 'No internet. Waiting… your place is safe.',
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: 8),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  foregroundColor: Colors.orange,
                ),
                onPressed: onRetry,
                child: const Text(
                  'Retry',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// UX7 — calm empty/error face copy, shared by all screens.
abstract final class CalmFaceCopy {
  const CalmFaceCopy._();

  static String forError(String? raw) {
    final t = (raw ?? '').toLowerCase();
    if (t.contains('socket') ||
        t.contains('timeout') ||
        t.contains('network') ||
        t.contains('host lookup') ||
        t.contains('no internet')) {
      return 'Internet is slow or off. Check net, tap Try again.';
    }
    if (t.contains('401') ||
        t.contains('403') ||
        t.contains('unauthorized')) {
      return 'Login needed for this. Try another one.';
    }
    if (t.contains('404') || t.contains('not found')) {
      return 'Not found. It may be removed.';
    }
    return 'Something went wrong. Tap Try again.';
  }
}
