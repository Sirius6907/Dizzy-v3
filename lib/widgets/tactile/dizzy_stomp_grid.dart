import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/widgets/tactile/dizzy_stomp_pad.dart';

/// Phase 6 — Boss footswitch array: grid of [DizzyStompPad]s.
///
/// Single-select ([selectedIndex]) or momentary (all [selectedIndex]
/// null) operation. Pure layout + [BoxDecoration]; no shaders.
class DizzyStompGrid extends StatelessWidget {
  final List<String> labels;
  final List<Widget>? icons;
  final int? selectedIndex;
  final ValueChanged<int>? onPad;
  final int crossAxisCount;
  final Color accent;
  final double padHeight;
  final double spacing;

  const DizzyStompGrid({
    super.key,
    required this.labels,
    this.icons,
    this.selectedIndex,
    this.onPad,
    this.crossAxisCount = 3,
    this.accent = DizzyGlow.red,
    this.padHeight = 72.0,
    this.spacing = 10.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DizzySpace.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DizzyRadius.lg),
        gradient: DizzyGradients.tactileSurface,
        border: Border.fromBorderSide(DizzyEdge.hairline),
        boxShadow: DizzyShadow.card,
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          mainAxisExtent: padHeight,
        ),
        itemCount: labels.length,
        itemBuilder: (context, i) => DizzyStompPad(
          label: labels[i],
          icon: icons != null && i < icons!.length ? icons![i] : null,
          toggled: selectedIndex == i,
          accent: accent,
          height: padHeight,
          onTap: onPad == null ? null : () => onPad!(i),
        ),
      ),
    );
  }
}
