import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/prism_shadows.dart';
import '../../design/prism_tokens.dart';
import '../../services/theme/app_theme_service.dart';
import '../../widgets/common/offline_aware_scaffold.dart';

/// Two clay themes, one page. No wallpaper engine, no accent studio, no
/// per-screen style knobs — picking a look should take one tap.
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemePalette>(
      valueListenable: AppThemeService.currentPalette,
      builder: (context, palette, _) {
        final isLight = palette.isLight;
        final ink = isLight ? PrismLight.ink : PrismDark.ink;
        final inkSoft = isLight ? PrismLight.inkSoft : PrismDark.inkSoft;
        return OfflineAwareScaffold(
          backgroundColor: palette.scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: palette.appBarBackgroundColor,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
              tooltip: 'Back',
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Appearance',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                children: [
                  Text(
                    'Choose a clay',
                    style: TextStyle(
                      color: ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Soft clay surfaces, glass edges, real depth. Text stays '
                    'black on light clay and white on dark clay.',
                    style: TextStyle(color: inkSoft, fontSize: 13.5, height: 1.45),
                  ),
                  const SizedBox(height: 22),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 520;
                      final cards = AppThemeService.palettes
                          .map(
                            (option) => _ClayOption(
                              option: option,
                              selected: option.id == palette.id,
                              onTap: () {
                                if (option.id == palette.id) return;
                                HapticFeedback.selectionClick();
                                AppThemeService.setPalette(option);
                              },
                            ),
                          )
                          .toList(growable: false);
                      if (!wide) {
                        return Column(
                          children: [
                            cards[0],
                            const SizedBox(height: 16),
                            cards[1],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: cards[0]),
                          const SizedBox(width: 16),
                          Expanded(child: cards[1]),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'THEME APPLIES EVERYWHERE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: inkSoft.withValues(alpha: 0.7),
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _note(
                    Icons.contrast_rounded,
                    'High-contrast body text',
                    'Every screen follows the same rule, so nothing washes '
                    'out in a bright room or disappears at night.',
                    palette,
                  ),
                  const SizedBox(height: 10),
                  _note(
                    Icons.layers_rounded,
                    'One surface language',
                    'Cards, sheets, dialogs and the dock all sit on the same '
                    'clay, so the app reads as one piece.',
                    palette,
                  ),
                  const SizedBox(height: 10),
                  _note(
                    Icons.movie_filter_rounded,
                    'Cinema screens stay dark',
                    'The video and music players keep their own dark chrome — '
                    'controls never compete with the picture.',
                    palette,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _note(
    IconData icon,
    String title,
    String body,
    AppThemePalette palette,
  ) {
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : PrismDark.ink;
    final inkSoft = isLight ? PrismLight.inkSoft : PrismDark.inkSoft;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isLight ? PrismLight.raisedTop : PrismDark.raised,
        borderRadius: BorderRadius.circular(PrismRadius.md),
        border: Border.all(
          color: isLight ? PrismLight.borderSubtle : PrismDark.borderSubtle,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: inkSoft),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(color: inkSoft, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A live miniature of the theme: clay background, two raised tiles, a glass
/// pill and real body text in that theme's ink.
class _ClayOption extends StatefulWidget {
  final AppThemePalette option;
  final bool selected;
  final VoidCallback onTap;

  const _ClayOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_ClayOption> createState() => _ClayOptionState();
}

class _ClayOptionState extends State<_ClayOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final previewLight = option.isLight;
    final ink = previewLight ? PrismLight.ink : PrismDark.ink;
    final inkSoft = previewLight ? PrismLight.inkSoft : PrismDark.inkSoft;
    final selected = widget.selected;
    final accent = option.primaryColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: PrismMotion.standard,
          curve: PrismMotion.curve,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: option.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(PrismRadius.lg),
            border: Border.all(
              color: selected
                  ? accent
                  : (previewLight
                        ? PrismLight.borderSubtle
                        : PrismDark.borderSubtle),
              width: selected ? 2 : 1,
            ),
            boxShadow: PrismShadows.raised(
              isLight: previewLight,
              scale: _hovered ? 0.85 : 0.7,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Miniature app surface.
              Container(
                height: 132,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: previewLight ? PrismLight.raisedTop : PrismDark.raised,
                  borderRadius: BorderRadius.circular(PrismRadius.md),
                  boxShadow: PrismShadows.resting(
                    isLight: previewLight,
                    scale: 0.55,
                  ),
                  gradient: PrismShadows.surfaceGradient(previewLight),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Now playing',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: previewLight
                                ? PrismLight.sunken.withValues(alpha: 0.8)
                                : PrismDark.sunken,
                            borderRadius: BorderRadius.circular(PrismRadius.pill),
                            border: Border.all(
                              color: previewLight
                                  ? PrismLight.borderSubtle
                                  : PrismDark.borderSubtle,
                            ),
                          ),
                          child: Text(
                            '4K',
                            style: TextStyle(
                              color: inkSoft,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      'Aa',
                      style: TextStyle(
                        color: ink,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Body text stays crisp on every surface.',
                      maxLines: 2,
                      style: TextStyle(
                        color: inkSoft,
                        fontSize: 9.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.name,
                          style: TextStyle(
                            color: previewLight
                                ? PrismLight.ink
                                : PrismDark.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          previewLight ? 'Black text · soft daylight' : 'White text · deep night',
                          style: TextStyle(
                            color: previewLight
                                ? PrismLight.inkSoft
                                : PrismDark.inkSoft,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: PrismMotion.micro,
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? accent : Colors.transparent,
                      border: Border.all(
                        color: selected
                            ? accent
                            : (previewLight
                                  ? PrismLight.borderSubtle
                                  : PrismDark.borderSubtle),
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
