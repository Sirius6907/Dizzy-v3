import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/widgets/tactile/dizzy_eq_fader.dart';

/// Phase 4 — 7-band (default 5-band) hardware EQ strip.
///
/// Holds [DizzyEqFader]s in a row and wires them to a
/// `ValueListenable` of `List<double>` such as
/// `MusicEqualizerService.instance.bandGains`.
///
/// If [bandGains] is null the panel runs in local demo mode.
class DizzyEqPanel extends StatelessWidget {
  final ValueListenable<List<double>>? bandGains;
  final void Function(int index, double gainDb)? onBandChanged;
  final List<String> bandLabels;
  final double faderHeight;

  const DizzyEqPanel({
    super.key,
    this.bandGains,
    this.onBandChanged,
    this.bandLabels = const ['60Hz', '250Hz', '1kHz', '4kHz', '16kHz'],
    this.faderHeight = 190.0,
  });

  @override
  Widget build(BuildContext context) {
    if (bandGains == null) {
      return _PanelShell(
        gains: List<double>.filled(bandLabels.length, 0.0),
        onBand: onBandChanged,
        labels: bandLabels,
        faderHeight: faderHeight,
      );
    }
    return ValueListenableBuilder<List<double>>(
      valueListenable: bandGains!,
      builder: (context, gains, _) => _PanelShell(
        gains: gains,
        onBand: onBandChanged,
        labels: bandLabels,
        faderHeight: faderHeight,
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  final List<double> gains;
  final void Function(int index, double gainDb)? onBand;
  final List<String> labels;
  final double faderHeight;

  const _PanelShell({
    required this.gains,
    required this.onBand,
    required this.labels,
    required this.faderHeight,
  });

  @override
  Widget build(BuildContext context) {
    final count = labels.length;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DizzySpace.md,
        vertical: DizzySpace.sm,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DizzyRadius.lg),
        gradient: DizzyGradients.tactileSurface,
        border: Border.fromBorderSide(DizzyEdge.hairline),
        boxShadow: DizzyShadow.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'EQ',
                style: TextStyle(
                  color: DizzyVoid.bone,
                  fontSize: DizzyType.subtitle,
                  fontWeight: DizzyType.wBold,
                ),
              ),
              Row(
                children: [
                  _LedDot(color: DizzyGlow.volt),
                  SizedBox(width: 4),
                  Text(
                    'HARDWARE',
                    style: TextStyle(
                      color: DizzyVoid.ash,
                      fontSize: DizzyType.micro,
                      fontWeight: DizzyType.wSemiBold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: DizzySpace.xs),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(count, (i) {
                final g = i < gains.length ? gains[i] : 0.0;
                return Padding(
                  padding: EdgeInsets.only(
                    right: i == count - 1 ? 0 : DizzySpace.sm,
                  ),
                  child: DizzyEqFader(
                    value: g,
                    label: labels[i],
                    height: faderHeight,
                    onChanged: onBand == null
                        ? null
                        : (v) => onBand!(i, v),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedDot extends StatelessWidget {
  final Color color;
  const _LedDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(
          color: const Color(0xFF000000).withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
