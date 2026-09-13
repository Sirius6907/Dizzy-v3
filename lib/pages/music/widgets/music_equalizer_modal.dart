import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/music/music_equalizer_service.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import 'music_hoverable.dart';

class MusicEqualizerModal extends StatefulWidget {
  const MusicEqualizerModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MusicEqualizerModal(),
    );
  }

  @override
  State<MusicEqualizerModal> createState() => _MusicEqualizerModalState();
}

class _MusicEqualizerModalState extends State<MusicEqualizerModal> {
  final eq = MusicEqualizerService.instance;

  @override
  void initState() {
    super.initState();
    eq.isEnabled.addListener(_onEqChange);
    eq.currentPreset.addListener(_onEqChange);
    eq.bassBoostLevel.addListener(_onEqChange);
    eq.enable3dSpatializer.addListener(_onEqChange);
    eq.bandGains.addListener(_onEqChange);
  }

  @override
  void dispose() {
    eq.isEnabled.removeListener(_onEqChange);
    eq.currentPreset.removeListener(_onEqChange);
    eq.bassBoostLevel.removeListener(_onEqChange);
    eq.enable3dSpatializer.removeListener(_onEqChange);
    eq.bandGains.removeListener(_onEqChange);
    super.dispose();
  }

  void _onEqChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    final isEnabled = eq.isEnabled.value;
    final preset = eq.currentPreset.value;
    final bass = eq.bassBoostLevel.value;
    final spatial = eq.enable3dSpatializer.value;
    final gains = eq.bandGains.value;

    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.sheet,
      child: Container(
        constraints: BoxConstraints(maxHeight: screenH * 0.85),
        decoration: BoxDecoration(
          color: const Color(0xFF0F121C).withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header with Title & Master Toggle
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C5CFF).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.tune_rounded, color: Color(0xFF7C5CFF), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Equalizer & Spatial Audio',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Audiophile sound sculpting & 3D soundstage',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Switch.adaptive(
                    value: isEnabled,
                    activeColor: const Color(0xFF7C5CFF),
                    onChanged: (val) {
                      HapticFeedback.mediumImpact();
                      eq.setEnabled(val);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 3D Spatializer & Bass Boost Row
              Row(
                children: [
                  // 3D Spatializer Card
                  Expanded(
                    child: InkWell(
                      onTap: isEnabled
                          ? () {
                              HapticFeedback.selectionClick();
                              eq.set3dSpatializer(!spatial);
                            }
                          : null,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: spatial && isEnabled
                              ? const Color(0xFF00D2EF).withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: spatial && isEnabled
                                ? const Color(0xFF00D2EF).withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.surround_sound_rounded,
                              color: spatial && isEnabled ? const Color(0xFF00D2EF) : Colors.white38,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '3D Spatializer',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  Text(
                                    spatial ? 'Wide Stage' : 'Standard',
                                    style: TextStyle(
                                      color: spatial ? const Color(0xFF00D2EF) : Colors.white38,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Bass Boost Level Card
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: bass > 0 && isEnabled
                            ? const Color(0xFFFFB300).withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: bass > 0 && isEnabled
                              ? const Color(0xFFFFB300).withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Bass Boost',
                                style: TextStyle(
                                  color: bass > 0 && isEnabled ? const Color(0xFFFFD54F) : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '${(bass * 100).toInt()}%',
                                style: TextStyle(
                                  color: bass > 0 ? const Color(0xFFFFB300) : Colors.white38,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                              activeTrackColor: const Color(0xFFFFB300),
                              inactiveTrackColor: Colors.white12,
                              thumbColor: const Color(0xFFFFB300),
                            ),
                            child: Slider(
                              value: bass,
                              onChanged: isEnabled ? (v) => eq.setBassBoostLevel(v) : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Presets Carousel
              const Text(
                'PRESETS',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: MusicEqPreset.values.map((p) {
                    final isSelected = p == preset;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: MusicHoverable(
                        scaleFactor: 1.05,
                        child: ChoiceChip(
                          label: Text(_presetLabel(p)),
                          selected: isSelected,
                          selectedColor: const Color(0xFF7C5CFF),
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            fontSize: 12,
                          ),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFF7C5CFF) : Colors.white.withValues(alpha: 0.1),
                          ),
                          onSelected: isEnabled
                              ? (sel) {
                                  if (sel) {
                                    HapticFeedback.selectionClick();
                                    eq.setPreset(p);
                                  }
                                }
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),

              // 5-Band Graphic Equalizer Faders
              const Text(
                'FREQUENCY BANDS (-12dB to +12dB)',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildFaderBand(0, '60Hz', 'Sub', gains[0], isEnabled),
                    _buildFaderBand(1, '250Hz', 'Bass', gains[1], isEnabled),
                    _buildFaderBand(2, '1kHz', 'Mid', gains[2], isEnabled),
                    _buildFaderBand(3, '4kHz', 'High', gains[3], isEnabled),
                    _buildFaderBand(4, '16kHz', 'Air', gains[4], isEnabled),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _presetLabel(MusicEqPreset p) {
    switch (p) {
      case MusicEqPreset.flat:
        return 'Flat';
      case MusicEqPreset.bassBoost:
        return 'Bass Boost 💥';
      case MusicEqPreset.vocalBoost:
        return 'Vocal Clarity 🎙️';
      case MusicEqPreset.trebleBoost:
        return 'Treble Sparkle ✨';
      case MusicEqPreset.electronic:
        return 'Electronic / Club 🎧';
      case MusicEqPreset.rock:
        return 'Rock & Punch 🎸';
      case MusicEqPreset.acoustic:
        return 'Acoustic Warmth 🎻';
      case MusicEqPreset.custom:
        return 'Custom ⚙️';
    }
  }

  Widget _buildFaderBand(int index, String freq, String type, double gain, bool isEnabled) {
    final gainText = gain > 0 ? '+${gain.toStringAsFixed(1)}' : gain.toStringAsFixed(1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$gainText dB',
          style: TextStyle(
            color: gain != 0 && isEnabled ? const Color(0xFF7C5CFF) : Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 140,
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                activeTrackColor: const Color(0xFF7C5CFF),
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: gain,
                min: -12.0,
                max: 12.0,
                onChanged: isEnabled ? (v) => eq.setBandGain(index, v) : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          freq,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          type,
          style: const TextStyle(color: Colors.white38, fontSize: 9.5),
        ),
      ],
    );
  }
}
