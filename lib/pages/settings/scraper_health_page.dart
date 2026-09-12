import 'package:flutter/material.dart';

import '../../services/cloud/remote_config_service.dart';
import '../../services/scraper/scraper_quarantine_service.dart';
import '../../services/scraper/stream_scraper.dart';
import '../../widgets/guide/guide_card.dart';

/// v1.2.0-P2 (T2.1): Sources health dashboard.
///
/// Non-tech copy rules: NEVER say "scraper" / "quarantine" in the UI.
/// User words only: "Sources", "Working", "Resting", "Off", "Retry".
class ScraperHealthPage extends StatefulWidget {
  const ScraperHealthPage({super.key});

  @override
  State<ScraperHealthPage> createState() => _ScraperHealthPageState();
}

class _ScraperHealthPageState extends State<ScraperHealthPage> {
  List<StreamScraper> _sources = [];

  @override
  void initState() {
    super.initState();
    _reload();
    RemoteConfigService.revision.addListener(_reload);
    // v1.2.0-T2.6: first-time Sources guide (skipable, never nags).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GuideCard.maybeShow(context, 'sources_health', AppGuides.sourcesHealth);
    });
  }

  @override
  void dispose() {
    RemoteConfigService.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    final list = List<StreamScraper>.of(ScraperManager.instance.scrapers);
    list.sort((a, b) => ScraperQuarantineService.displayNameFor(a.name)
        .toLowerCase()
        .compareTo(
            ScraperQuarantineService.displayNameFor(b.name).toLowerCase()));
    if (mounted) setState(() => _sources = list);
  }

  void _retry(String name) {
    ScraperQuarantineService.markSuccess(name);
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Trying ${ScraperQuarantineService.displayNameFor(name)} again.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var working = 0;
    var resting = 0;
    var off = 0;
    for (final s in _sources) {
      if (RemoteConfigService.isKilled(s.name)) {
        off++;
      } else if (ScraperQuarantineService.isQuarantined(s.name)) {
        resting++;
      } else {
        working++;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1017),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Sources',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: _sources.isEmpty
              ? _emptyState()
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _introCard(working, resting, off),
                    const SizedBox(height: 16),
                    for (final s in _sources) _sourceTile(s),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('📡', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('Sources are loading...',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            'Open any movie first. Then come back here.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _reload,
            child: const Text('Check again'),
          ),
        ],
      ),
    );
  }

  Widget _introCard(int working, int resting, int off) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          const Color(0xFF10B981).withValues(alpha: 0.22),
          const Color(0xFF8B5CF6).withValues(alpha: 0.10),
        ]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.30)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('📡 Where do videos come from?',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900)),
          SizedBox(height: 6),
          Text(
            'Dizzy finds videos from many Sources. Green means working. Orange means resting. Grey means off for now.',
            style: TextStyle(color: Colors.white70, fontSize: 13.5),
          ),
        ],
      ),
    );
  }

  Widget _sourceTile(StreamScraper s) {
    final brand = ScraperQuarantineService.displayNameFor(s.name);
    final killed = RemoteConfigService.isKilled(s.name);
    final resting = !killed && ScraperQuarantineService.isQuarantined(s.name);

    final Color dot;
    final String label;
    final String sub;
    Color? labelColor;
    if (killed) {
      dot = Colors.white24;
      label = 'Off';
      sub = 'Off for now. It will return soon.';
      labelColor = Colors.white38;
    } else if (resting) {
      dot = Colors.amber;
      label = 'Resting';
      sub = 'This Source is taking a break. Tap Retry to try now.';
      labelColor = Colors.amber;
    } else {
      dot = const Color(0xFF10B981);
      label = 'Working';
      sub = s.isTorrentScraper
          ? 'Torrent Source. Needs P2P turned on.'
          : 'Ready to find videos.';
      labelColor = const Color(0xFF10B981);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(brand,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800)),
                    ),
                    Text(label,
                        style: TextStyle(
                            color: labelColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          if (resting) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _retry(s.name),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
