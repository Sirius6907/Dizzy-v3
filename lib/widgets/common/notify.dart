import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/prism_tokens.dart';

import '../../design/dizzy_tokens.dart';
import '../../services/theme/app_theme_service.dart';

/// Polish P18 — ONE voice for toasts, dialogs, sheets.
///
/// One timing: toasts live 3s. One button order: Cancel (ghost, left) →
/// confirm (filled, right; red when dangerous). One copy rule:
/// Easy English, never raw tech text.
///
/// Follow-up: 170+ legacy SnackBar/AlertDialog call sites migrate here
/// opportunistically — new code MUST use this file.
enum NotifyTone { info, success, warn }

abstract final class DizzyNotify {
  const DizzyNotify._();

  /// Toast lifetime, frozen.
  static const Duration kLifetime = Duration(seconds: 3);

  /// Toast surface stays dark in both themes: Material's floating SnackBar is
  /// an inverse-surface element, and every tone here pairs it with white text.
  static Color backgroundFor(NotifyTone tone) {
    switch (tone) {
      case NotifyTone.success:
        return const Color(0xFF10B981);
      case NotifyTone.warn:
        return const Color(0xFFB45309);
      case NotifyTone.info:
        return DizzyVoid.surface2;
    }
  }

  static void show(
    BuildContext context,
    String line, {
    NotifyTone tone = NotifyTone.info,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          line,
          style: const TextStyle(
            color: Colors.white,
            fontSize: DizzyType.body,
            fontWeight: DizzyType.wMedium,
          ),
        ),
        backgroundColor: backgroundFor(tone),
        duration: kLifetime,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: DizzyRadius.mdAll),
      ),
    );
  }
}

/// One confirm dialog for the whole app.
///
/// Returns true when the user taps [confirmLabel].
/// Button order frozen: Cancel left, confirm right.
abstract final class DizzyDialogs {
  const DizzyDialogs._();

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String line,
    String confirmLabel = 'Confirm',
    bool danger = false,
  }) async {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white70;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.cardBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: DizzyRadius.lgAll),
        title: Text(
          title,
          style: TextStyle(
            color: ink,
            fontSize: DizzyType.subtitle,
            fontWeight: DizzyType.wBold,
          ),
        ),
        content: Text(
          line,
          style: TextStyle(color: inkSoft, fontSize: DizzyType.body),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: inkSoft)),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }
}
