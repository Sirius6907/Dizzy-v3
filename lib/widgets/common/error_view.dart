import 'package:flutter/material.dart';

import 'state_view.dart';

/// Full-screen error view with retry button.
///
/// Polish P10: same API (all callers keep working), but the screen now
/// shows the illustration + copy + action trio — raw tech text never
/// reaches non-tech users (see [StateViewCopy]).
class ErrorView extends StatelessWidget {
  final String? error;
  final VoidCallback onRetry;

  const ErrorView({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return DizzyStateView(
      icon: Icons.cloud_off_rounded,
      iconColor: Colors.orangeAccent,
      title: 'Could not load',
      line: StateViewCopy.friendlyError(error),
      actionLabel: 'Try again',
      onAction: onRetry,
    );
  }
}
