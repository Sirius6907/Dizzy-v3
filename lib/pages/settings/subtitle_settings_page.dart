import 'package:flutter/material.dart';

import '../../services/player/player_settings.dart';
import '../../widgets/guide/guide_card.dart';

/// v1.2.0-T2.4: Subtitle appearance settings page.
///
/// Thin UI over PlayerSettings (presets + size + bold/italic + reset).
/// Same engine the player gear sheet uses — persist + live apply identical.
/// Easy English only. Live preview shows exactly what nani will see.
class SubtitleSettingsPage extends StatelessWidget {
  const SubtitleSettingsPage({super.key});

  Color _parseHex(String hex) {
    var s = hex.replaceAll('#', '').trim();
    if (s.length == 6) s = 'FF$s';
    final v = int.tryParse(s, radix: 16);
    if (v == null) return Colors.white;
    return Color(v);
  }

  @override
  Widget build(BuildContext context) {
    // v1.2.0-T2.6: first-time subtitles guide (skipable, never nags).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GuideCard.maybeShow(context, 'subtitles', AppGuides.subtitles);
    });
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080A0F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Words on screen',
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Pick how the words look while you watch.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          // ── Live preview ──
          ValueListenableBuilder<int>(
            valueListenable: PlayerSettings.changeNotifier,
            builder: (context, _, __) {
              final size =
                  (PlayerSettings.subFontSize.value * PlayerSettings.subScale.value)
                      .clamp(14.0, 80.0);
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 28),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  image: const DecorationImage(
                    image: NetworkImage(
                        'https://image.tmdb.org/t/p/w780/8Vt6mWEReuy4Of61Lnj5Xj704m8.jpg'),
                    fit: BoxFit.cover,
                    colorFilter:
                        ColorFilter.mode(Colors.black54, BlendMode.darken),
                  ),
                ),
                child: Center(
                  child: Text(
                    'This is how your words will look',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: size,
                      fontWeight: PlayerSettings.subBold.value
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontStyle: PlayerSettings.subItalic.value
                          ? FontStyle.italic
                          : FontStyle.normal,
                      color: _parseHex(PlayerSettings.subColor.value),
                      backgroundColor:
                          _parseHex(PlayerSettings.subBackColor.value),
                      shadows: PlayerSettings.subShadowOffset.value > 0
                          ? [
                              Shadow(
                                offset: Offset(
                                    PlayerSettings.subShadowOffset.value,
                                    PlayerSettings.subShadowOffset.value),
                                blurRadius: 4,
                                color: _parseHex(
                                    PlayerSettings.subShadowColor.value),
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          const _SectionLabel('PICK A STYLE'),
          const SizedBox(height: 10),
          // ── Presets ──
          ValueListenableBuilder<SubtitleStylePreset>(
            valueListenable: PlayerSettings.subStylePreset,
            builder: (context, active, _) {
              return Column(
                children: SubtitleStylePreset.values.map((preset) {
                  final selected = preset == active;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () =>
                          PlayerSettings.setSubStylePreset(preset),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF7C5CFF)
                                  .withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF7C5CFF)
                                : Colors.white.withValues(alpha: 0.1),
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: _parseHex(preset.textColor),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.white24, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: _parseHex(preset.borderColor),
                                    blurRadius: preset.borderSize * 2,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  'Cc',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: preset.bold
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: _parseHex(preset.backColor) ==
                                            Colors.transparent
                                        ? Colors.black
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    preset.label,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    preset.description,
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.5),
                                        fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              const Icon(Icons.check_circle_rounded,
                                  color: Color(0xFF7C5CFF), size: 22),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 16),
          const _SectionLabel('MAKE IT YOURS'),
          const SizedBox(height: 10),
          // ── Size slider ──
          ValueListenableBuilder<int>(
            valueListenable: PlayerSettings.subFontSize,
            builder: (context, size, _) {
              return _Tile(
                icon: Icons.format_size_rounded,
                title: 'Word size',
                subtitle: 'Bigger = easier to read.',
                trailing: Text('$size',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
                child: Slider(
                  value: size.toDouble().clamp(14.0, 80.0),
                  min: 14,
                  max: 80,
                  divisions: 33,
                  activeColor: const Color(0xFF7C5CFF),
                  onChanged: (v) =>
                      PlayerSettings.setSubFontSize(v.round()),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          // ── Bold / Italic ──
          ValueListenableBuilder<bool>(
            valueListenable: PlayerSettings.subBold,
            builder: (context, bold, _) {
              return _Tile(
                icon: Icons.format_bold_rounded,
                title: 'Thick words',
                subtitle: 'Makes words stand out more.',
                trailing: Switch(
                  value: bold,
                  activeColor: const Color(0xFF7C5CFF),
                  onChanged: (v) => PlayerSettings.setSubBold(v),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable: PlayerSettings.subItalic,
            builder: (context, italic, _) {
              return _Tile(
                icon: Icons.format_italic_rounded,
                title: 'Slanted words',
                subtitle: 'Tilts words a little.',
                trailing: Switch(
                  value: italic,
                  activeColor: const Color(0xFF7C5CFF),
                  onChanged: (v) => PlayerSettings.setSubItalic(v),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          // ── Reset ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => PlayerSettings.setSubStylePreset(
                  SubtitleStylePreset.classicWhite),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Back to normal'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.18)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: Colors.white38,
          letterSpacing: 1.1),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final Widget? child;

  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1017).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C5CFF).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon,
                    size: 20, color: const Color(0xFF7C5CFF)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.5),
                            height: 1.3)),
                  ],
                ),
              ),
              trailing,
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: 8),
            child!,
          ],
        ],
      ),
    );
  }
}
