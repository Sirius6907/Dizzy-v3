import 'package:dizzy/design/prism_shadows.dart';
import 'package:flutter/material.dart';

import '../../design/dizzy_tokens.dart';
import '../../design/prism_tokens.dart';
import '../../services/theme/app_theme_service.dart';
import '../prism/prism_button.dart';
import 'guide_step.dart';

export 'app_guides.dart';
export 'guide_step.dart';

/// A short, user-requested intro card: big emoji, one line, progress dots,
/// Next / Done. It never opens on its own — see [show].
class GuideCard extends StatefulWidget {
  final List<GuideStep> steps;

  const GuideCard({super.key, required this.steps});

  /// At most three cards per tour: a tour nobody finishes is a tour nobody reads.
  static const int maxSteps = 3;

  /// Open the card on top of the caller's navigator. Only ever called from an
  /// explicit "Take the tour" action.
  static Future<void> show(BuildContext context, List<GuideStep> steps) {
    if (steps.isEmpty) return Future<void>.value();
    return showDialog<void>(
      context: context,
      builder: (_) {
        final palette = AppThemeService.currentPalette.value;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: PrismRadius.xlAll,
              gradient: PrismShadows.surfaceGradient(palette.isLight),
              boxShadow: PrismShadows.floating(isLight: palette.isLight),
            ),
            child: GuideCard(steps: steps),
          ),
        );
      },
    );
  }

  @override
  State<GuideCard> createState() => _GuideCardState();
}

class _GuideCardState extends State<GuideCard> {
  final _ctrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<GuideStep> get _visibleSteps =>
      widget.steps.take(GuideCard.maxSteps).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final ink = palette.isLight ? PrismLight.ink : Colors.white;
    final inkSoft = palette.isLight ? PrismLight.inkSoft : Colors.white70;
    final steps = _visibleSteps;
    final total = steps.length;
    final isLast = _page >= total - 1;

    return Semantics(
      label: 'Tour card ${_page + 1} of $total',
      child: Padding(
        padding: const EdgeInsets.all(DizzySpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 220,
              child: PageView.builder(
                controller: _ctrl,
                itemCount: total,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  final s = steps[i];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(s.icon, style: const TextStyle(fontSize: 48)),
                      const SizedBox(height: DizzySpace.sm),
                      Text(
                        s.title,
                        style: TextStyle(
                          color: ink,
                          fontSize: DizzyType.subtitle + 1,
                          fontWeight: DizzyType.wBold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: DizzySpace.xs),
                      Text(
                        s.line,
                        style: TextStyle(
                          color: inkSoft,
                          fontSize: DizzyType.body - 0.5,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: DizzySpace.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                total,
                (i) => Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: DizzySpace.xxs - 1,
                  ),
                  width: _page == i ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _page == i
                        ? const Color(0xFF7C5CFF)
                        : (palette.isLight
                              ? PrismLight.borderSubtle
                              : Colors.white24),
                    borderRadius: DizzyRadius.smAll,
                  ),
                ),
              ),
            ),
            const SizedBox(height: DizzySpace.md),
            Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Close tour',
                  child: PrismButton(
                    label: 'Close',
                    small: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const Spacer(),
                Semantics(
                  button: true,
                  label: isLast ? 'Finish tour' : 'Next tour card',
                  child: PrismButton(
                    label: isLast ? 'Done' : 'Next',
                    small: true,
                    accent: true,
                    onPressed: () {
                      if (isLast) {
                        Navigator.of(context).pop();
                      } else {
                        _ctrl.nextPage(
                          duration: DizzyMotion.fast,
                          curve: DizzyMotion.easeOut,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
