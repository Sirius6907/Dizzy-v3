import 'package:flutter/material.dart';

import '../../services/guide/guide_service.dart';

/// v1.2.0-T2.6: reusable swipeable guide card (Easy English only).
/// Big icon + 1-line easy text + Next/Skip. Skip = never show again.
class GuideStep {
  final String icon;
  final String title;
  final String line;
  const GuideStep({required this.icon, required this.title, required this.line});
}

class GuideCard extends StatefulWidget {
  final String guideKey;
  final List<GuideStep> steps;
  const GuideCard({super.key, required this.guideKey, required this.steps});

  /// Show on first open only. Call from initState (post-frame).
  static Future<void> maybeShow(
    BuildContext context,
    String guideKey,
    List<GuideStep> steps,
  ) async {
    if (!context.mounted) return;
    if (!await GuideService.shouldShow(guideKey)) return;
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF141A26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: GuideCard(guideKey: guideKey, steps: steps),
      ),
    );
  }

  @override
  State<GuideCard> createState() => _GuideCardState();
}

class _GuideCardState extends State<GuideCard> {
  final _ctrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await GuideService.markSeen(widget.guideKey);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.steps.length;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 220,
            child: PageView.builder(
              controller: _ctrl,
              itemCount: total,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final s = widget.steps[i];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.icon, style: const TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text(
                      s.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.line,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              total,
              (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _page == i ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _page == i
                      ? const Color(0xFF7C5CFF)
                      : Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: _dismiss,
                child: const Text(
                  'Skip',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C5CFF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  if (_page == total - 1) {
                    _dismiss();
                  } else {
                    _ctrl.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                },
                child: Text(_page == total - 1 ? 'Got it' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// v1.2.0-T2.6: preset guide contents (Easy English, max ~10 words/line).
class AppGuides {
  static const watchParty = [
    GuideStep(
      icon: '👥',
      title: 'Watch Together',
      line: 'Tap Play, friends join with your code.',
    ),
    GuideStep(
      icon: '🔢',
      title: 'Share the code',
      line: 'Send the big code on WhatsApp.',
    ),
    GuideStep(
      icon: '▶️',
      title: 'Play together',
      line: 'Host plays, all screens follow auto.',
    ),
    GuideStep(
      icon: '💬',
      title: 'Chat and talk',
      line: 'Chat here. Tap mic to speak.',
    ),
  ];

  static const downloads = [
    GuideStep(
      icon: '⬇️',
      title: 'Save to watch offline',
      line: 'Pick quality, tap Save. Easy.',
    ),
    GuideStep(
      icon: '📶',
      title: 'Auto pause on mobile data',
      line: 'Saves data. Resumes on WiFi.',
    ),
    GuideStep(
      icon: '▶️',
      title: 'Watch anytime',
      line: 'Open Downloads, tap Play. No net.',
    ),
  ];

  static const cloudSync = [
    GuideStep(
      icon: '☁️',
      title: 'Auto save',
      line: 'Your list saves by itself.',
    ),
    GuideStep(
      icon: '📱',
      title: 'Same everywhere',
      line: 'Phone and laptop stay in sync.',
    ),
  ];

  static const sourcesHealth = [
    GuideStep(
      icon: '🟢',
      title: 'Green means good',
      line: 'Green sources play fast.',
    ),
    GuideStep(
      icon: '🔴',
      title: 'Red means resting',
      line: 'Red takes a break. App skips it.',
    ),
    GuideStep(
      icon: '🔄',
      title: 'Tap Retry to wake',
      line: 'Tap Retry, we check again.',
    ),
  ];

  static const subtitles = [
    GuideStep(
      icon: '💬',
      title: 'Words on screen',
      line: 'Pick a style you can read easy.',
    ),
    GuideStep(
      icon: '👀',
      title: 'See preview',
      line: 'Preview shows how it looks.',
    ),
  ];
}
