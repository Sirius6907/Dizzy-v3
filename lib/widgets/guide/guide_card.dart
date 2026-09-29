import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:flutter/material.dart';

import '../../design/dizzy_tokens.dart';
import '../../services/guide/guide_service.dart';
import 'guide_step.dart';

export 'app_guides.dart';
export 'guide_step.dart';

/// P7 — GuideCard 2.0: a tactile, skipable intro card.
///
/// Big emoji + one Easy English line, progress dots, Next/Skip. Never more
/// than [GuideService.maxSteps] cards, because a tour nobody finishes is a
/// tour nobody reads. Skip and Got it are the same action: the card is marked
/// seen forever, and Settings → Help → "Show guides again" brings it back.
class GuideCard extends StatefulWidget {
  final String guideKey;
  final List<GuideStep> steps;

  const GuideCard({
    super.key,
    required this.guideKey,
    required this.steps,
  });

  /// Show on first open only. Call from `initState` (post-frame).
  ///
  /// Runs the legacy-flag migration first so a user who dismissed an older
  /// card is never shown its replacement. Dialogs are serialised, so two
  /// screens that both trigger a guide in the same frame stack their cards
  /// instead of racing each other.
  static Future<void> maybeShow(
    BuildContext context,
    String guideKey,
    List<GuideStep> steps,
  ) {
    _queue = _queue.then((_) => _show(context, guideKey, steps));
    return _queue;
  }

  static Future<void> _queue = Future<void>.value();

  static Future<void> _show(
    BuildContext context,
    String guideKey,
    List<GuideStep> steps,
  ) async {
    if (!context.mounted) return;
    if (steps.isEmpty) return;
    await GuideService.migrateLegacyKeys();
    if (!context.mounted) return;
    if (!await GuideService.shouldShow(guideKey)) return;
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: DizzyVoid.surface1,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: DizzyRadius.lgAll),
        child: GuideCard(guideKey: guideKey, steps: steps),
      ),
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

  /// GuideCard 2.0 contract: never more than `GuideService.maxSteps` cards.
  List<GuideStep> get _visibleSteps =>
      widget.steps.take(GuideService.maxSteps).toList(growable: false);

  Future<void> _dismiss() async {
    await GuideService.markSeen(widget.guideKey);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final steps = _visibleSteps;
    final total = steps.length;
    final isLast = _page >= total - 1;

    return Semantics(
      label: 'Intro card ${_page + 1} of $total',
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: DizzyType.subtitle + 1,
                          fontWeight: DizzyType.wBold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: DizzySpace.xs),
                      Text(
                        s.line,
                        style: const TextStyle(
                          color: Colors.white70,
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
                      horizontal: DizzySpace.xxs - 1),
                  width: _page == i ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _page == i
                        ? const Color(0xFF7C5CFF)
                        : Colors.white24,
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
                  label: 'Skip intro',
                  child: TextButton(
                    onPressed: _dismiss,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                          color: Colors.white54, fontSize: DizzyType.body),
                    ),
                  ),
                ),
                const Spacer(),
                Semantics(
                  button: true,
                  label: isLast ? 'Finish intro' : 'Next intro card',
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C5CFF),
                      shape: RoundedRectangleBorder(
                        borderRadius: DizzyRadius.mdAll,
                      ),
                    ),
                    onPressed: () {
                      if (isLast) {
                        _dismiss();
                      } else {
                        _ctrl.nextPage(
                          duration: DizzyMotion.fast,
                          curve: DizzyMotion.easeOut,
                        );
                      }
                    },
                    child: Text(isLast ? 'Got it' : 'Next'),
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
