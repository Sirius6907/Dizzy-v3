import 'package:flutter/material.dart';

import '../../services/theme/app_theme_service.dart';
import '../../services/theme/custom_accent_service.dart';

/// UX6 — Dynamic Theming sheet: AMOLED true black + hex accent + blur slider.
///
/// Easy English only. Opens from Appearance settings.
class AccentStudioSheet extends StatefulWidget {
  const AccentStudioSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AccentStudioSheet(),
    );
  }

  @override
  State<AccentStudioSheet> createState() => _AccentStudioSheetState();
}

class _AccentStudioSheetState extends State<AccentStudioSheet> {
  final TextEditingController _hexController = TextEditingController();
  String? _hexError;

  static const List<Color> _presets = [
    Color(0xFFF59E0B),
    Color(0xFF00E5FF),
    Color(0xFF7C5CFF),
    Color(0xFF10B981),
    Color(0xFFFF2A85),
    Color(0xFFE50914),
    Color(0xFF3B82F6),
    Color(0xFFE2E8F0),
  ];

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _applyHex(String raw) {
    final c = CustomAccentService.tryParseHex(raw);
    if (c == null) {
      setState(() => _hexError = 'That code did not work. Try like #00E5FF.');
      return;
    }
    setState(() => _hexError = null);
    CustomAccentService.setCustomAccent(c);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F121C),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 30),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Make it yours',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pick a glow color. Pure black saves battery on OLED screens.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 18),
            const Text(
              'GLOW COLOR',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder(
              valueListenable: CustomAccentService.customAccent,
              builder: (context, custom, _) {
                final active =
                    custom ?? palette.primaryColor;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final c in _presets)
                      _Swatch(
                        color: c,
                        selected: active.toARGB32() == c.toARGB32(),
                        onTap: () =>
                            CustomAccentService.setCustomAccent(c),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hexController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: '#00E5FF',
                      hintStyle:
                          const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: const Color(0xFF161A26),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      errorText: _hexError,
                    ),
                    onSubmitted: _applyHex,
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: () => _applyHex(_hexController.text),
                  child: const Text('Apply'),
                ),
              ],
            ),
            TextButton(
              onPressed: () =>
                  CustomAccentService.setCustomAccent(null),
              child: const Text('Back to theme color'),
            ),
            const Divider(color: Color(0x14FFFFFF)),
            ValueListenableBuilder(
              valueListenable: CustomAccentService.amoledTrueBlack,
              builder: (context, on, _) {
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Pure black mode',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Saves battery on OLED screens.',
                    style:
                        TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  value: on,
                  onChanged: CustomAccentService.setAmoled,
                );
              },
            ),
            ValueListenableBuilder(
              valueListenable: CustomAccentService.backdropBlur,
              builder: (context, blur, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Background blur',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          blur.toStringAsFixed(0),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                    Slider(
                      value: blur,
                      min: 0,
                      max: 24,
                      divisions: 12,
                      onChanged: CustomAccentService.setBlur,
                    ),
                    const Text(
                      'Lower blur = faster on older phones.',
                      style: TextStyle(
                          color: Colors.white38, fontSize: 11.5),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 3 : 1,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 12,
              ),
          ],
        ),
        child: selected
            ? const Icon(Icons.check_rounded,
                color: Colors.black87, size: 22)
            : null,
      ),
    );
  }
}
