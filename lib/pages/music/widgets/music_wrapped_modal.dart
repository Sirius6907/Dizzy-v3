import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/music/music_stats_service.dart';
import '../../../utils/perf/image_caps.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import 'music_hoverable.dart';

class MusicWrappedModal extends StatefulWidget {
  const MusicWrappedModal({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => const MusicWrappedModal(),
    );
  }

  @override
  State<MusicWrappedModal> createState() => _MusicWrappedModalState();
}

class _MusicWrappedModalState extends State<MusicWrappedModal> {
  int _currentSlide = 0;
  final int _totalSlides = 4;
  final stats = MusicStatsService.instance;

  void _nextSlide() {
    if (_currentSlide < _totalSlides - 1) {
      setState(() => _currentSlide++);
    } else {
      Navigator.pop(context);
    }
  }

  void _prevSlide() {
    if (_currentSlide > 0) {
      setState(() => _currentSlide--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 600;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isMobile ? size.width - 24 : 440,
          maxHeight: 700,
        ),
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: _getSlideGradient(_currentSlide),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 36,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Stack(
                children: [
                  // Tap Zones for Stories Navigation
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _prevSlide,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _nextSlide,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),

                  // Slide Content
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    child: Column(
                      children: [
                        // Top Progress Bar Bars
                        Row(
                          children: List.generate(_totalSlides, (idx) {
                            final isPassed = idx <= _currentSlide;
                            return Expanded(
                              child: Container(
                                height: 3.5,
                                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                                decoration: BoxDecoration(
                                  color: isPassed ? Colors.white : Colors.white24,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 14),

                        // Header Title & Close Button
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome_rounded, color: Colors.amberAccent, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'DIZZY WRAPPED',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Active Slide Body
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: _buildSlideContent(_currentSlide),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  LinearGradient _getSlideGradient(int slide) {
    switch (slide) {
      case 0:
        return const LinearGradient(
          colors: [Color(0xFF7C5CFF), Color(0xFF1E1044)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
      case 1:
        return const LinearGradient(
          colors: [Color(0xFFFF3366), Color(0xFF3B0818)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
      case 2:
        return const LinearGradient(
          colors: [Color(0xFF00D2EF), Color(0xFF072D3A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
      case 3:
      default:
        return const LinearGradient(
          colors: [Color(0xFF1DB954), Color(0xFF093315)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
    }
  }

  Widget _buildSlideContent(int slide) {
    switch (slide) {
      case 0:
        return _buildMinutesSlide();
      case 1:
        return _buildTopSongsSlide();
      case 2:
        return _buildTopArtistsSlide();
      case 3:
      default:
        return _buildPersonaSlide();
    }
  }

  Widget _buildMinutesSlide() {
    final mins = stats.totalMinutes > 0 ? stats.totalMinutes : 42;
    return Column(
      key: const ValueKey('slide_0'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.headphones_rounded, size: 68, color: Colors.white),
        const SizedBox(height: 20),
        const Text(
          'You spent',
          style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          '$mins',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 64,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.5,
          ),
        ),
        const Text(
          'MINUTES LISTENING',
          style: TextStyle(
            color: Colors.amberAccent,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Soundtracked with pristine lossless beats on Dizzy Music.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13.5),
        ),
      ],
    );
  }

  Widget _buildTopSongsSlide() {
    final top = stats.topTracks;
    return Column(
      key: const ValueKey('slide_1'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR TOP TRACKS',
          style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2),
        ),
        const SizedBox(height: 8),
        const Text(
          'On Repeat',
          style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        if (top.isEmpty)
          const Center(
            child: Text(
              'Play more songs to reveal your top chart!',
              style: TextStyle(color: Colors.white54),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: top.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, idx) {
                final track = top[idx];
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '#${idx + 1}',
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: track.coverUrl,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          memCacheWidth: ImageCaps.kThumb,
                          maxWidthDiskCache: ImageCaps.kThumb,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              track.artist,
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${track.playCount} plays',
                        style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTopArtistsSlide() {
    final artists = stats.topArtists;
    return Column(
      key: const ValueKey('slide_2'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'FAVORITE ICONS',
          style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2),
        ),
        const SizedBox(height: 8),
        const Text(
          'Top Artists',
          style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        if (artists.isEmpty)
          const Center(
            child: Text(
              'Listen to artists to build your podium!',
              style: TextStyle(color: Colors.white54),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: artists.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, idx) {
                final a = artists[idx];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '#${idx + 1}',
                        style: const TextStyle(color: Color(0xFF00D2EF), fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          a.key,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${a.value} spins',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildPersonaSlide() {
    final persona = stats.musicalPersona;
    return Column(
      key: const ValueKey('slide_3'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'YOUR MUSIC IDENTITY',
          style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 2),
          ),
          child: const Icon(Icons.stars_rounded, size: 64, color: Color(0xFF1DB954)),
        ),
        const SizedBox(height: 20),
        Text(
          persona,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Your taste defies the ordinary. You dive deep into melodies and rhythm.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 32),

        // Share Button
        MusicHoverable(
          scaleFactor: 1.05,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: 'My Dizzy Music Wrapped 🚀\nPersona: $persona\nTotal Time: ${stats.totalMinutes} mins\nStreamed on Dizzy Music',
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Wrapped summary copied! Ready to share 🎉')),
              );
            },
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('Share My Wrapped', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
