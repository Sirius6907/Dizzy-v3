import 'package:flutter/material.dart';
import 'package:dizzy/design/dizzy_tactile.dart';

import '../../services/guide/guide_service.dart';
import '../../services/theme/app_theme_service.dart';

/// P7 — Onboarding 2.0: a 30-second welcome tour, shown once.
///
/// Five slides, one job each, Easy English only. The "seen" flag lives in
/// [GuideService] so Settings → Help → "Show guides again" can replay it
/// alongside the feature cards, and so the v1 flag migrates without a
/// second re-tour.
class OnboardingSuperpowerSheet extends StatefulWidget {
  const OnboardingSuperpowerSheet({super.key});

  static Future<bool> shouldShow() => GuideService.shouldShow(GuideService.onboardingKey);

  static Future<void> markSeen() => GuideService.markSeen(GuideService.onboardingKey);

  static Future<void> maybeShow(BuildContext context) async {
    if (!context.mounted) return;
    await GuideService.migrateLegacyKeys();
    if (!context.mounted) return;
    final needShow = await shouldShow();
    if (!needShow || !context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) => const OnboardingSuperpowerSheet(),
    );
  }

  @override
  State<OnboardingSuperpowerSheet> createState() => _OnboardingSuperpowerSheetState();
}

class _OnboardingSuperpowerSheetState extends State<OnboardingSuperpowerSheet> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  /// Five slides, five promises, thirty seconds.
  static const List<_TourSlide> _slides = [
    _TourSlide(
      emoji: '🗂️',
      title: 'Everything in one place',
      line: 'Movies, shows, music, books and live TV.',
      badges: ['Movies', 'Shows', 'Music', 'Books'],
      gradientColors: [Color(0xFF7C5CFF), Color(0xFF00E5FF)],
    ),
    _TourSlide(
      emoji: '🎧',
      title: 'Music that sounds right',
      line: 'Studio sound, equaliser and words that sing along.',
      badges: ['Studio sound', 'Sing along'],
      gradientColors: [Color(0xFF00E5FF), Color(0xFF10B981)],
    ),
    _TourSlide(
      emoji: '👯',
      title: 'Watch together',
      line: 'Share a code, friends join, everyone follows you.',
      badges: ['One code', 'Chat and talk'],
      gradientColors: [Color(0xFFFF2A85), Color(0xFFF59E0B)],
    ),
    _TourSlide(
      emoji: '✈️',
      title: 'Works without internet',
      line: 'Save what you like, watch it on a plane.',
      badges: ['Save for later', 'Ready offline'],
      gradientColors: [Color(0xFF7C3AED), Color(0xFF3B82F6)],
    ),
    _TourSlide(
      emoji: '🔒',
      title: 'Yours alone',
      line: 'No account needed. Nothing leaves your phone.',
      badges: ['No sign-up', 'Just for you'],
      gradientColors: [Color(0xFF10B981), Color(0xFF7C5CFF)],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onFinish() async {
    await OnboardingSuperpowerSheet.markSeen();
    if (mounted) Navigator.of(context).pop();
  }

  void _onNext() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _onFinish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeService.currentPalette.value;
    final isDesktop = MediaQuery.sizeOf(context).width > 700;

    return Center(
      child: Container(
        width: 600,
        margin: EdgeInsets.symmetric(
          horizontal: isDesktop ? 32 : 16,
          vertical: 24,
        ),
        decoration: BoxDecoration(
          color: DizzyVoid.surface1,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.primaryColor.withValues(alpha: 0.2),
              blurRadius: 40,
              spreadRadius: 2,
            ),
            const BoxShadow(
              color: Color(0x99000000),
              blurRadius: 40,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Eyebrow header
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Text(
                'WELCOME',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
            ),
            // Slide content
            SizedBox(
              height: 380,
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemBuilder: (context, index) {
                  return _buildSlide(_slides[index]);
                },
              ),
            ),

            // Indicator dots and Action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _onFinish,
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  // Dots
                  Row(
                    children: List.generate(_slides.length, (idx) {
                      final active = idx == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: active ? theme.primaryColor : Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),

                  // Next / Get Started button
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _onNext,
                    child: Text(
                      _currentPage == _slides.length - 1 ? 'Explore Dizzy' : 'Next',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(_TourSlide slide) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 16),
      child: Column(
        children: [
          // Emoji badge with glowing gradient ring
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: slide.gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: slide.gradientColors.first.withValues(alpha: 0.35),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: Text(
                slide.emoji,
                style: const TextStyle(fontSize: 38),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            slide.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // One line, one job.
          Text(
            slide.line,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 14.5,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),

          // Highlight chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: slide.badges.map((badge) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _TourSlide {
  final String emoji;
  final String title;
  final String line;
  final List<String> badges;
  final List<Color> gradientColors;

  const _TourSlide({
    required this.emoji,
    required this.title,
    required this.line,
    required this.badges,
    required this.gradientColors,
  });
}
