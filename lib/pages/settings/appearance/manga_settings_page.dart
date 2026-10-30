import 'package:flutter/material.dart';
import 'package:dizzy/design/prism_tokens.dart';
import '../../../services/theme/app_theme_service.dart';
import '../../../services/home/home_page_settings.dart';
import '../../../services/manga/manga_settings.dart';
import '../../../widgets/common/animated_ambient_background.dart';

class MangaSettingsPage extends StatefulWidget {
  const MangaSettingsPage({super.key});

  @override
  State<MangaSettingsPage> createState() => _MangaSettingsPageState();
}

class _MangaSettingsPageState extends State<MangaSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;

    return Scaffold(
      backgroundColor: palette.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: palette.appBarBackgroundColor,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Manga UI & Reader Atmosphere',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              // ── 1. Ambient Background Lighting ──
              _buildSectionHeader('AMBIENT BACKGROUND LIGHTING & MOVING GLOWS'),
              const SizedBox(height: 12),
              _buildAmbientLightsCard(palette),

              const SizedBox(height: 28),

              // ── 3. Discovery & Cards ──
              _buildSectionHeader('DISCOVERY & POSTER CARDS'),
              const SizedBox(height: 12),
              _buildCardsConfigCard(palette),

              const SizedBox(height: 28),

              // ── 4. Manga Reader Customization ──
              _buildSectionHeader('MANGA READER & CHAPTER VIEWER'),
              const SizedBox(height: 12),
              _buildReaderConfigCard(palette),

              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final isLight = AppThemeService.currentPalette.value.isLight;

    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: isLight
            ? PrismLight.inkFaint
            : Colors.white.withValues(alpha: 0.35),
        letterSpacing: 1.1,
      ),
    );
  }

  // ── 1. Ambient Lighting Card ──
  Widget _buildAmbientLightsCard(AppThemePalette palette) {
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white54;
    final labelColor = isLight
        ? PrismLight.inkSoft
        : Colors.white.withValues(alpha: 0.8);
    final cardColor = isLight ? PrismLight.raisedTop : PrismDark.raised;
    final fieldColor = isLight ? PrismLight.raisedBottom : PrismDark.sunken;
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.enableAmbientLights,
            builder: (context, enabled, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Enable Moving Ambient Lighting',
                  style: TextStyle(
                    color: ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  'Soft flowing glowing orbs and aurora waves themed to ${palette.name}',
                  style: TextStyle(color: inkSoft, fontSize: 12),
                ),
                value: enabled,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setEnableAmbientLights(val),
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: hairline),
          const SizedBox(height: 12),

          // Pattern selector
          Text(
            'Lighting Flow Pattern',
            style: TextStyle(
              color: labelColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<AmbientLightPattern>(
            valueListenable: MangaSettings.ambientLightPattern,
            builder: (context, currentPattern, _) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AmbientLightPattern.values.map((p) {
                  final isSelected = p == currentPattern;
                  return ChoiceChip(
                    label: Text(p.label),
                    selected: isSelected,
                    selectedColor: palette.primaryColor.withValues(alpha: 0.25),
                    backgroundColor: fieldColor,
                    labelStyle: TextStyle(
                      color: isSelected ? palette.primaryColor : inkSoft,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w500,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? palette.primaryColor.withValues(alpha: 0.6)
                          : hairline,
                    ),
                    onSelected: (selected) {
                      if (selected) MangaSettings.setAmbientLightPattern(p);
                    },
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 16),

          // Intensity Slider
          ValueListenableBuilder<double>(
            valueListenable: MangaSettings.ambientLightIntensity,
            builder: (context, intensity, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Glow Strength / Opacity',
                        style: TextStyle(
                          color: labelColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${(intensity * 100).round()}%',
                        style: TextStyle(
                          color: palette.primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: palette.primaryColor,
                      inactiveTrackColor: hairline,
                      thumbColor: palette.primaryColor,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: intensity,
                      min: 0.08,
                      max: 0.60,
                      divisions: 26,
                      onChanged: (val) =>
                          MangaSettings.setAmbientLightIntensity(val),
                    ),
                  ),
                ],
              );
            },
          ),

          // Speed Slider
          ValueListenableBuilder<double>(
            valueListenable: MangaSettings.ambientLightSpeed,
            builder: (context, speed, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Motion Drift Speed',
                        style: TextStyle(
                          color: labelColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${speed.toStringAsFixed(1)}x',
                        style: TextStyle(
                          color: palette.primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: palette.primaryColor,
                      inactiveTrackColor: hairline,
                      thumbColor: palette.primaryColor,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: speed,
                      min: 0.2,
                      max: 3.0,
                      divisions: 14,
                      onChanged: (val) =>
                          MangaSettings.setAmbientLightSpeed(val),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 10),

          // Atmosphere Live Preview Box
          Container(
            height: 80,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: hairline),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  const Positioned.fill(child: AnimatedAmbientBackground()),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: palette.primaryColor,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Live Atmosphere Preview',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. Discovery & Cards Config Card ──
  Widget _buildCardsConfigCard(AppThemePalette palette) {
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white54;
    final labelColor = isLight
        ? PrismLight.inkSoft
        : Colors.white.withValues(alpha: 0.8);
    final cardColor = isLight ? PrismLight.raisedTop : PrismDark.raised;
    final fieldColor = isLight ? PrismLight.raisedBottom : PrismDark.sunken;
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.showContinueReading,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Show "Continue Reading" Slider',
                  style: TextStyle(
                    color: ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  'Display your active reading history at the top of the Manga page',
                  style: TextStyle(color: inkSoft, fontSize: 12),
                ),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setShowContinueReading(val),
              );
            },
          ),

          const SizedBox(height: 12),
          Divider(color: hairline),
          const SizedBox(height: 12),

          Text(
            'Manga Poster Card Density',
            style: TextStyle(
              color: labelColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<MangaCardDensity>(
            valueListenable: MangaSettings.cardDensity,
            builder: (context, currentDensity, _) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MangaCardDensity.values.map((d) {
                  final isSelected = d == currentDensity;
                  return ChoiceChip(
                    label: Text(d.label),
                    selected: isSelected,
                    selectedColor: palette.primaryColor.withValues(alpha: 0.25),
                    backgroundColor: fieldColor,
                    labelStyle: TextStyle(
                      color: isSelected ? palette.primaryColor : inkSoft,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w500,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? palette.primaryColor.withValues(alpha: 0.6)
                          : hairline,
                    ),
                    onSelected: (selected) {
                      if (selected) MangaSettings.setCardDensity(d);
                    },
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 14),

          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.showContentTypeBadge,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Show Content Type Badge (Manga/Manhwa)',
                  style: TextStyle(color: ink, fontSize: 13.5),
                ),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setShowContentTypeBadge(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.showMangaYear,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Show Publication Year on Cards',
                  style: TextStyle(color: ink, fontSize: 13.5),
                ),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setShowMangaYear(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.ambientCardGlow,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Poster Card Hover Glow Effect',
                  style: TextStyle(color: ink, fontSize: 13.5),
                ),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setAmbientCardGlow(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.showScrollTrack,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Show Desktop Scroll Track',
                  style: TextStyle(color: ink, fontSize: 13.5),
                ),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setShowScrollTrack(val),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── 4. Reader Configuration Card ──
  Widget _buildReaderConfigCard(AppThemePalette palette) {
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white54;
    final labelColor = isLight
        ? PrismLight.inkSoft
        : Colors.white.withValues(alpha: 0.8);
    final cardColor = isLight ? PrismLight.raisedTop : PrismDark.raised;
    final fieldColor = isLight ? PrismLight.raisedBottom : PrismDark.sunken;
    final hairline = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Default Reading Mode
          Text(
            'Default Reading Mode',
            style: TextStyle(
              color: labelColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<MangaReadingMode>(
            valueListenable: MangaSettings.defaultReadingMode,
            builder: (context, currentMode, _) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MangaReadingMode.values.map((m) {
                  final isSelected = m == currentMode;
                  return ChoiceChip(
                    label: Text(m.label),
                    selected: isSelected,
                    selectedColor: palette.primaryColor.withValues(alpha: 0.25),
                    backgroundColor: fieldColor,
                    labelStyle: TextStyle(
                      color: isSelected ? palette.primaryColor : inkSoft,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w500,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? palette.primaryColor.withValues(alpha: 0.6)
                          : hairline,
                    ),
                    onSelected: (selected) {
                      if (selected) MangaSettings.setDefaultReadingMode(m);
                    },
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 16),

          // Reader Max Width
          Text(
            'Page Reading Width Constraint',
            style: TextStyle(
              color: labelColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<MangaReaderMaxWidth>(
            valueListenable: MangaSettings.readerMaxWidth,
            builder: (context, currentWidth, _) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MangaReaderMaxWidth.values.map((w) {
                  final isSelected = w == currentWidth;
                  return ChoiceChip(
                    label: Text(w.label),
                    selected: isSelected,
                    selectedColor: palette.primaryColor.withValues(alpha: 0.25),
                    backgroundColor: fieldColor,
                    labelStyle: TextStyle(
                      color: isSelected ? palette.primaryColor : inkSoft,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w500,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? palette.primaryColor.withValues(alpha: 0.6)
                          : hairline,
                    ),
                    onSelected: (selected) {
                      if (selected) MangaSettings.setReaderMaxWidth(w);
                    },
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 16),

          // Reader Background Color
          Text(
            'Reader Background Atmosphere',
            style: TextStyle(
              color: labelColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<MangaReaderBackground>(
            valueListenable: MangaSettings.readerBackground,
            builder: (context, currentBg, _) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MangaReaderBackground.values.map((b) {
                  final isSelected = b == currentBg;
                  return ChoiceChip(
                    avatar: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: b.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white30),
                      ),
                    ),
                    label: Text(b.label),
                    selected: isSelected,
                    selectedColor: palette.primaryColor.withValues(alpha: 0.25),
                    backgroundColor: fieldColor,
                    labelStyle: TextStyle(
                      color: isSelected ? palette.primaryColor : inkSoft,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w500,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? palette.primaryColor.withValues(alpha: 0.6)
                          : hairline,
                    ),
                    onSelected: (selected) {
                      if (selected) MangaSettings.setReaderBackground(b);
                    },
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 16),

          // Control Bar Style
          Text(
            'Control Toolbar Style',
            style: TextStyle(
              color: labelColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<MangaControlBarStyle>(
            valueListenable: MangaSettings.readerControlBarStyle,
            builder: (context, currentStyle, _) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MangaControlBarStyle.values.map((s) {
                  final isSelected = s == currentStyle;
                  return ChoiceChip(
                    label: Text(s.label),
                    selected: isSelected,
                    selectedColor: palette.primaryColor.withValues(alpha: 0.25),
                    backgroundColor: fieldColor,
                    labelStyle: TextStyle(
                      color: isSelected ? palette.primaryColor : inkSoft,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w500,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? palette.primaryColor.withValues(alpha: 0.6)
                          : hairline,
                    ),
                    onSelected: (selected) {
                      if (selected) MangaSettings.setReaderControlBarStyle(s);
                    },
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 16),

          // Page Gap slider (for webtoon mode)
          ValueListenableBuilder<double>(
            valueListenable: MangaSettings.pageGap,
            builder: (context, gap, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Vertical Page Gap',
                        style: TextStyle(
                          color: labelColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${gap.round()} px',
                        style: TextStyle(
                          color: palette.primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: palette.primaryColor,
                      inactiveTrackColor: hairline,
                      thumbColor: palette.primaryColor,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: gap,
                      min: 0,
                      max: 24,
                      divisions: 12,
                      onChanged: (val) => MangaSettings.setPageGap(val),
                    ),
                  ),
                ],
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.showPageDeck,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Show Page Deck / Thumbnail Previews',
                  style: TextStyle(color: ink, fontSize: 13.5),
                ),
                subtitle: Text(
                  'Interactive visual tray of thumbnail previews for instant page jumping',
                  style: TextStyle(color: inkSoft, fontSize: 11.5),
                ),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setShowPageDeck(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.showPageScrubber,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Show Page Scrubber Slider',
                  style: TextStyle(color: ink, fontSize: 13.5),
                ),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setShowPageScrubber(val),
              );
            },
          ),

          ValueListenableBuilder<bool>(
            valueListenable: MangaSettings.enableNextChapterDeck,
            builder: (context, show, _) {
              return SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Enable Next Chapter Preview Card Deck',
                  style: TextStyle(color: ink, fontSize: 13.5),
                ),
                subtitle: Text(
                  'Rich glass deck card at the end of each chapter with chapter art and direct launch',
                  style: TextStyle(color: inkSoft, fontSize: 11.5),
                ),
                value: show,
                activeColor: palette.primaryColor,
                onChanged: (val) => MangaSettings.setEnableNextChapterDeck(val),
              );
            },
          ),
        ],
      ),
    );
  }
}
