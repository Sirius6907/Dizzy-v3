import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/theme/app_theme_service.dart';

/// Phase UX4 — First-Time Guided Onboarding & Superpower Cards
/// Interactive 3-slide carousel highlighting Dizzy's core capabilities.
class OnboardingSuperpowerSheet extends StatefulWidget {
  const OnboardingSuperpowerSheet({super.key});

  static const String _prefKey = 'has_seen_superpower_onboarding_v1_2';

  static Future<bool> shouldShow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(_prefKey) ?? false);
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);
    } catch (_) {}
  }

  static Future<void> maybeShow(BuildContext context) async {
    if (!context.mounted) return;
    final needShow = await shouldShow();
    if (!needShow || !context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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

  final List<_SuperpowerSlide> _slides = const [
    _SuperpowerSlide(
      emoji: '🎬',
      title: 'Everything in One Place',
      subtitle: 'Unlimited entertainment without boundaries',
      description:
          'Stream top movies, trending series, seasonal anime, and Spotify-level music — all in one clean, ad-free app.',
      badges: ['4K & HD Movies', 'Anime with AniList', '30M+ Songs'],
      gradientColors: [Color(0xFF7C5CFF), Color(0xFF00E5FF)],
    ),
    _SuperpowerSlide(
      emoji: '🎧',
      title: 'Lossless Audio & Zero Ads',
      subtitle: 'Studio sound quality made simple',
      description:
          'Enjoy Hi-Res FLAC music, offline downloads, synced karaoke lyrics, and a custom 5-band studio equalizer.',
      badges: ['Studio FLAC', 'Karaoke Lyrics', 'Offline Downloads'],
      gradientColors: [Color(0xFF00E5FF), Color(0xFF10B981)],
    ),
    _SuperpowerSlide(
      emoji: '👥',
      title: 'Watch & Listen Together',
      subtitle: 'Real-time sync rooms with friends',
      description:
          'Create private rooms in one tap. Play movies or songs together with friends in perfect sync, anytime, anywhere.',
      badges: ['1-Tap Room Code', 'Zero Drift Sync', 'Voice & Chat'],
      gradientColors: [Color(0xFFFF2A85), Color(0xFFF59E0B)],
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
          color: const Color(0xFF10131A),
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
            // Slide content
            SizedBox(
              height: 380,
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return _buildSlide(slide, theme);
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
                      _currentPage == _slides.length - 1 ? 'Get Started 🚀' : 'Next →',
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

  Widget _buildSlide(_SuperpowerSlide slide, AppThemePalette theme) {
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
          const SizedBox(height: 4),

          // Subtitle
          Text(
            slide.subtitle,
            style: TextStyle(
              color: theme.primaryColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Description
          Text(
            slide.description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13.5,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),

          // Highlight Chips
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

class _SuperpowerSlide {
  final String emoji;
  final String title;
  final String subtitle;
  final String description;
  final List<String> badges;
  final List<Color> gradientColors;

  const _SuperpowerSlide({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.badges,
    required this.gradientColors,
  });
}
