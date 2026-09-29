import 'package:flutter/material.dart';

import 'guide_card.dart';

export 'app_guides.dart';
export 'guide_card.dart';
export 'guide_step.dart';

/// P7 — the one place a screen says "explain me".
///
/// Drop it around a page's root widget and the matching intro card opens the
/// first time that screen is visited:
/// ```dart
/// GuideTrigger(guideKey: 'stats', steps: AppGuides.stats, child: Scaffold(...))
/// ```
/// It fires from `initState` on the next frame, so it never competes with
/// the screen's own first build, and it renders nothing.
class GuideTrigger extends StatefulWidget {
  final String guideKey;
  final List<GuideStep> steps;
  final Widget child;

  const GuideTrigger({
    super.key,
    required this.guideKey,
    required this.steps,
    required this.child,
  });

  @override
  State<GuideTrigger> createState() => _GuideTriggerState();
}

class _GuideTriggerState extends State<GuideTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      GuideCard.maybeShow(context, widget.guideKey, widget.steps);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
