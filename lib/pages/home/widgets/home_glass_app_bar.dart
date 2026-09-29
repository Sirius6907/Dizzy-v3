import 'package:flutter/material.dart';

import '../../../services/theme/app_theme_service.dart';
import '../../../services/home/home_page_settings.dart';
import '../../../services/player/dub_mode_service.dart';
import '../../ai/wewatch_quiz_page.dart';
import '../../calendar/tv_calendar_page.dart';
import 'package:dizzy/pages/social/instagram_profile_page.dart';

class HomeGlassAppBar extends StatelessWidget {
  final double topPadding;
  final void Function(Offset?) onSearchTap;
  final void Function(Offset?) onSettingsTap;

  const HomeGlassAppBar({super.key,
    required this.topPadding,
    required this.onSearchTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    // Narrow phones (emulator 383px, small devices) pe saare icons +
    // dub pill ek line me fit nahi hote → 223px overflow crash.
    // Compact mode: chhota logo/title, dub me sirf flag, tight buttons.
    final narrow = MediaQuery.sizeOf(context).width < 420;

    return RepaintBoundary(
      child: Container(
        padding: EdgeInsets.only(
          top: topPadding + 10,
          bottom: 14,
          left: narrow ? 12 : 20,
          right: narrow ? 4 : 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              palette.appBarBackgroundColor.withValues(alpha: 0.95),
              palette.appBarBackgroundColor.withValues(alpha: 0.85),
            ],
          ),
          border: Border(
            bottom: BorderSide(
              color: palette.isMetallic
                  ? palette.accentColor.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ),
        child: Row(
          children: [
            // Logo
            Image.asset(
              'assets/icon.png',
              width: narrow ? 28 : 34,
              height: narrow ? 28 : 34,
              fit: BoxFit.contain,
            ),
            SizedBox(width: narrow ? 6 : 10),
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  const Color(0xFFFFFFFF),
                  palette.silverAccent,
                  const Color(0xFFCBD5E1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: Text(
                'Dizzy',
                style: TextStyle(
                  fontSize: narrow ? 17 : 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
            ),
            const Spacer(),
            // AI Taste Profile Quiz
            ValueListenableBuilder<bool>(
              valueListenable: HomePageSettings.enableAiQuiz,
              builder: (context, aiQuizEnabled, _) {
                // Narrow pe ⋮ menu me hai — inline button hatao (overflow fix).
                if (!aiQuizEnabled || narrow) return const SizedBox.shrink();
                final palette = AppThemeService.currentPalette.value;
                return IconButton(
                  icon: Icon(
                    Icons.auto_awesome_rounded,
                    color: palette.primaryColor,
                    size: 22,
                  ),
                  tooltip: 'AI Taste Quiz',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WeWatchQuizPage(),
                      ),
                    );
                  },
                );
              },
            ),
            // TV Shows Airing Calendar
            ValueListenableBuilder<bool>(
              valueListenable: HomePageSettings.enableCalendar,
              builder: (context, calEnabled, _) {
                // Narrow pe ⋮ menu me hai — inline button hatao (overflow fix).
                if (!calEnabled || narrow) return const SizedBox.shrink();
                return IconButton(
                  icon: Icon(
                    Icons.calendar_month_rounded,
                    color: Colors.white.withValues(alpha: 0.75),
                    size: 22,
                  ),
                  tooltip: 'TV Airing Calendar',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TvCalendarPage()),
                    );
                  },
                );
              },
            ),
            // Audio Dub Mode toggle (English / Hindi Dub)
            ValueListenableBuilder<AudioDubMode>(
              valueListenable: DubModeService.mode,
              builder: (context, dubMode, _) {
                // Narrow pe ⋮ menu me hai — inline pill hatao (overflow fix).
                if (narrow) return const SizedBox.shrink();
                final isHindi = dubMode == AudioDubMode.hindi;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => DubModeService.setMode(
                      isHindi ? AudioDubMode.english : AudioDubMode.hindi,
                    ),
                    child: Tooltip(
                      message: isHindi
                          ? 'Hindi Dub mode ON — English pe switch karo'
                          : 'Hindi Dub mode enable karo (Movies & Series)',
                      child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.symmetric(
                        horizontal: narrow ? 7 : 10,
                        vertical: 6,
                      ),
                        decoration: BoxDecoration(
                          color: isHindi
                              ? const Color(0xFFFF9933).withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isHindi
                                ? const Color(
                                    0xFFFF9933,
                                  ).withValues(alpha: 0.65)
                                : Colors.white.withValues(alpha: 0.14),
                            width: 1.1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isHindi ? '🇮🇳' : '🌐',
                              style: const TextStyle(fontSize: 12),
                            ),
                            // Narrow pe sirf flag — text hatao, warna overflow.
                            if (!narrow) ...[
                              const SizedBox(width: 5),
                              Text(
                                isHindi ? 'HINDI DUB' : 'ENGLISH',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  color: isHindi
                                      ? const Color(0xFFFFB366)
                                      : Colors.white.withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // Narrow screens: extra actions ⋮ menu me — Row kabhi overflow
            // nahi karega (no yellow/black stripes). Wide pe sab inline.
            if (narrow)
              PopupMenuButton<int>(
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: Colors.white.withValues(alpha: 0.65),
                  size: 21,
                ),
                tooltip: 'More',
                itemBuilder: (menuCtx) {
                  final items = <PopupMenuEntry<int>>[];
                  if (HomePageSettings.enableAiQuiz.value) {
                    items.add(
                      const PopupMenuItem<int>(
                        value: 0,
                        child: Row(
                          children: [
                            Icon(Icons.auto_awesome_rounded, size: 20),
                            SizedBox(width: 12),
                            Text('AI Taste Quiz'),
                          ],
                        ),
                      ),
                    );
                  }
                  if (HomePageSettings.enableCalendar.value) {
                    items.add(
                      const PopupMenuItem<int>(
                        value: 1,
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month_rounded, size: 20),
                            SizedBox(width: 12),
                            Text('TV Airing Calendar'),
                          ],
                        ),
                      ),
                    );
                  }
                  final isHindi =
                      DubModeService.mode.value == AudioDubMode.hindi;
                  items.add(
                    PopupMenuItem<int>(
                      value: 2,
                      child: Row(
                        children: [
                          Text(
                            isHindi ? '🇮🇳' : '🌐',
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(width: 12),
                          Text(isHindi ? 'Hindi Dub: ON' : 'Hindi Dub: OFF'),
                        ],
                      ),
                    ),
                  );
                  return items;
                },
                onSelected: (value) {
                  if (value == 0) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WeWatchQuizPage(),
                      ),
                    );
                  } else if (value == 1) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TvCalendarPage(),
                      ),
                    );
                  } else {
                    final isHindi =
                        DubModeService.mode.value == AudioDubMode.hindi;
                    DubModeService.setMode(
                      isHindi ? AudioDubMode.english : AudioDubMode.hindi,
                    );
                  }
                },
              ),
            // Search
            Builder(
              builder: (context) {
                return IconButton(
                  visualDensity:
                      narrow ? VisualDensity.compact : VisualDensity.standard,
                  padding: narrow ? EdgeInsets.zero : null,
                  constraints: narrow
                      ? const BoxConstraints(minWidth: 36, minHeight: 36)
                      : null,
                  icon: Icon(
                    Icons.search_rounded,
                    color: Colors.white.withValues(alpha: 0.65),
                    size: narrow ? 22 : 25,
                  ),
                  onPressed: () {
                    final box = context.findRenderObject() as RenderBox?;
                    final offset = box?.localToGlobal(
                      box.size.center(Offset.zero),
                    );
                    onSearchTap(offset);
                  },
                );
              },
            ),
            // Settings
            Builder(
              builder: (context) {
                return IconButton(
                  visualDensity:
                      narrow ? VisualDensity.compact : VisualDensity.standard,
                  padding: narrow ? EdgeInsets.zero : null,
                  constraints: narrow
                      ? const BoxConstraints(minWidth: 36, minHeight: 36)
                      : null,
                  icon: Icon(
                    Icons.settings_rounded,
                    color: Colors.white.withValues(alpha: 0.65),
                    size: narrow ? 21 : 24,
                  ),
                  onPressed: () {
                    final box = context.findRenderObject() as RenderBox?;
                    final offset = box?.localToGlobal(
                      box.size.center(Offset.zero),
                    );
                    onSettingsTap(offset);
                  },
                );
              },
            ),
            // Profile
            IconButton(
              visualDensity:
                  narrow ? VisualDensity.compact : VisualDensity.standard,
              padding: narrow ? EdgeInsets.zero : null,
              constraints: narrow
                  ? const BoxConstraints(minWidth: 36, minHeight: 36)
                  : null,
              icon: Icon(
                Icons.person_rounded,
                color: Colors.white.withValues(alpha: 0.65),
                size: narrow ? 21 : 24,
              ),
              tooltip: 'Profile',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const InstagramProfilePage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Carousel — rotates through a handful of featured titles.
// ─────────────────────────────────────────────────────────────────────────────

