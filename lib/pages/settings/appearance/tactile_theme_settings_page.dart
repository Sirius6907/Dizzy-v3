import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';


/// v1.2.0-P30: Tactile Theme settings.
/// Replaces Liquid Glass setup with theme, elevation, edge, and haptic
/// controls. All settings map to existing DizzyTactile tokens.
class TactileThemeSettingsPage extends StatefulWidget {
  const TactileThemeSettingsPage({super.key});

  @override
  State<TactileThemeSettingsPage> createState() =>
      _TactileThemeSettingsPageState();
}

class _TactileThemeSettingsPageState extends State<TactileThemeSettingsPage> {
  final List<String> _palettes = [
    'Dark Void (Default)',
    'Anodized Aluminum',
    'Polished Silver',
  ];
  int _selectedPalette = 0;

  final List<String> _elevations = ['Low', 'Medium', 'High'];
  int _selectedElevation = 1;

  final List<String> _edges = ['Soft', 'Medium', 'Sharp'];
  int _selectedEdge = 1;

  final List<String> _haptics = ['Off', 'Low', 'Medium', 'High'];
  int _selectedHaptic = 2;

  final List<String> _shadows = ['Flat', 'Dimensional', 'Floating'];
  int _selectedShadow = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: DizzyVoid.voidB,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Tactile Theme',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              // Theme palette selector
              _buildSection(
                iconData: Icons.palette_rounded,
                title: 'Theme Palette',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(_palettes.length, (index) {
                    final selected = index == _selectedPalette;
                    return ChoiceChip(
                      selected: selected,
                      label: Text(
                        _palettes[index],
                        style: TextStyle(
                          color: selected ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      selectedColor: DizzyGlow.volt,
                      onSelected: (_) {
                        setState(() {
                          _selectedPalette = index;
                        });
                      },
                    );
                  }),
                ),
              ),

              const SizedBox(height: 16),

              // Elevation level
              _buildSection(
                iconData: Icons.vertical_align_top_rounded,
                title: 'Elevation Level',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(_elevations.length, (index) {
                    final selected = index == _selectedElevation;
                    return ChoiceChip(
                      label: Text(
                        _elevations[index],
                        style: TextStyle(
                          color: selected ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      selected: selected,
                      selectedColor: DizzyGlow.volt,
                      onSelected: (_) {
                        setState(() {
                          _selectedElevation = index;
                        });
                      },
                    );
                  }),
                ),
              ),

              const SizedBox(height: 16),

              // Edge sharpness
              _buildSection(
                iconData: Icons.aspect_ratio_rounded,
                title: 'Edge Sharpness',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(_edges.length, (index) {
                    final selected = index == _selectedEdge;
                    return ChoiceChip(
                      label: Text(
                        _edges[index],
                        style: TextStyle(
                          color: selected ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      selected: selected,
                      selectedColor: DizzyGlow.beam,
                      onSelected: (_) {
                        setState(() {
                          _selectedEdge = index;
                        });
                      },
                    );
                  }),
                ),
              ),

              const SizedBox(height: 16),

              // Haptic feedback intensity
              _buildSection(
                iconData: Icons.vibration_rounded,
                title: 'Haptic Feedback',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(_haptics.length, (index) {
                    final selected = index == _selectedHaptic;
                    return ChoiceChip(
                      label: Text(
                        _haptics[index],
                        style: TextStyle(
                          color: selected ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      selected: selected,
                      selectedColor: DizzyGlow.beam,
                      onSelected: (_) {
                        setState(() {
                          _selectedHaptic = index;
                        });
                      },
                    );
                  }),
                ),
              ),

              const SizedBox(height: 16),

              // Shadow style
              _buildSection(
                iconData: Icons.format_indent_increase_rounded,
                title: 'Shadow Style',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(_shadows.length, (index) {
                    final selected = index == _selectedShadow;
                    return ChoiceChip(
                      label: Text(
                        _shadows[index],
                        style: TextStyle(
                          color: selected ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      selected: selected,
                      selectedColor: DizzyGlow.red,
                      onSelected: (_) {
                        setState(() {
                          _selectedShadow = index;
                        });
                      },
                    );
                  }),
                ),
              ),

              const SizedBox(height: 28),

              // Apply button
              Center(
                child: SizedBox(
                  width: 200,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context, true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DizzyGlow.volt,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 3,
                      shadowColor: DizzyGlow.volt,
                    ),
                    child: const Text(
                      'Apply',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData iconData,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: DizzyVoid.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconData, color: DizzyGlow.volt, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}