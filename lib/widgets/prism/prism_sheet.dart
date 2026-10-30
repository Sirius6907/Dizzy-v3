import 'package:flutter/material.dart';

import '../../../design/prism_shadows.dart';
import '../../../design/prism_tokens.dart';
import '../../../services/theme/app_theme_service.dart';
import 'prism_button.dart';

/// Prism sheet scaffold (SPEC §3): slide-up panel, grab handle,
/// content, Accept (accent) / Cancel (neu) row optional.
class PrismSheet extends StatelessWidget {
  final Widget child;
  final double? maxHeightFactor;
  final bool scrollable;

  const PrismSheet({
    super.key,
    required this.child,
    this.maxHeightFactor,
    this.scrollable = true,
  });

  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    double? maxHeightFactor,
    bool scrollable = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => PrismSheet(
        maxHeightFactor: maxHeightFactor,
        scrollable: scrollable,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final maxH = MediaQuery.sizeOf(context).height * (maxHeightFactor ?? 0.88);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      margin: EdgeInsets.fromLTRB(10, 0, 10, 10 + safeBottom),
      decoration: BoxDecoration(
        borderRadius: PrismRadius.xlAll,
        gradient: PrismShadows.surfaceGradient(palette.isLight),
        boxShadow: PrismShadows.floating(
          isLight: palette.isLight,
          halo: palette.primaryColor,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              borderRadius: PrismRadius.pillAll,
              gradient: PrismShadows.pressedGradient(palette.isLight),
              boxShadow: PrismShadows.resting(
                isLight: palette.isLight,
                scale: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: scrollable
                ? SingleChildScrollView(
                    padding: EdgeInsets.only(bottom: keyboard + PrismSpace.md),
                    child: child,
                  )
                : Padding(
                    padding: EdgeInsets.only(bottom: keyboard),
                    child: child,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Prism dialog (SPEC §3): clay card, title, optional body,
/// Accept = accent / Cancel = neu row.
class PrismDialog extends StatelessWidget {
  final String title;
  final String? message;
  final Widget? body;
  final String confirmLabel;
  final String cancelLabel;
  final bool danger;

  const PrismDialog({
    super.key,
    required this.title,
    this.message,
    this.body,
    this.confirmLabel = 'OK',
    this.cancelLabel = 'Cancel',
    this.danger = false,
  });

  static Future<bool> show(
    BuildContext context, {
    required String title,
    String? message,
    Widget? body,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    bool danger = false,
    bool dismissible = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: dismissible,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => PrismDialog(
        title: title,
        message: message,
        body: body,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        danger: danger,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final ink = palette.isLight ? PrismLight.ink : PrismDark.ink;
    final soft = palette.isLight ? PrismLight.inkSoft : PrismDark.inkSoft;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          borderRadius: PrismRadius.xlAll,
          gradient: PrismShadows.surfaceGradient(palette.isLight),
          boxShadow: PrismShadows.floating(
            isLight: palette.isLight,
            halo: danger ? PrismAccent.danger : palette.primaryColor,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: PrismType.title,
                fontWeight: PrismType.wBold,
                letterSpacing: -0.4,
                color: danger ? PrismAccent.danger : ink,
              ),
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: TextStyle(
                  fontSize: PrismType.body,
                  height: 1.5,
                  color: soft,
                ),
              ),
            ],
            if (body != null) ...[const SizedBox(height: 10), body!],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PrismButton(
                  label: cancelLabel,
                  small: true,
                  onPressed: () => Navigator.pop(context, false),
                ),
                const SizedBox(width: 10),
                PrismButton(
                  label: confirmLabel,
                  small: true,
                  accent: true,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
