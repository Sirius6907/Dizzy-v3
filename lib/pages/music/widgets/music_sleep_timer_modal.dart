import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/music/music_sleep_timer_service.dart';
import '../../../widgets/common/performance_liquid_lens.dart';
import 'music_hoverable.dart';

class MusicSleepTimerModal extends StatefulWidget {
  const MusicSleepTimerModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const MusicSleepTimerModal(),
    );
  }

  @override
  State<MusicSleepTimerModal> createState() => _MusicSleepTimerModalState();
}

class _MusicSleepTimerModalState extends State<MusicSleepTimerModal> {
  final sleepService = MusicSleepTimerService.instance;

  @override
  void initState() {
    super.initState();
    sleepService.isActive.addListener(_onUpdate);
    sleepService.remainingSeconds.addListener(_onUpdate);
  }

  @override
  void dispose() {
    sleepService.isActive.removeListener(_onUpdate);
    sleepService.remainingSeconds.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isActive = sleepService.isActive.value;
    final isEndOfTrack = sleepService.stopAtEndOfTrack.value;

    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.sheet,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F121C).withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C5CFF).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bedtime_rounded, color: Color(0xFFB57CFF), size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sleep Timer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Audio fades out softly without waking you',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
                const Spacer(),
                if (isActive)
                  TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      sleepService.cancelTimer();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sleep timer turned off'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: const Text('Turn Off', style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Active Banner
            if (isActive) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C5CFF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF7C5CFF).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_bottom_rounded, color: Color(0xFF7C5CFF), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEndOfTrack
                                ? 'Pausing at the end of this song'
                                : 'Pausing playback in ${sleepService.formattedRemaining}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Gentle 20-second volume fade enabled ✨',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Presets List
            _buildTimerTile(
              label: 'End of this track',
              subtitle: 'Finishes current song and stops',
              icon: Icons.skip_next_rounded,
              duration: null,
              isEndSong: true,
            ),
            const SizedBox(height: 6),
            _buildTimerTile(label: '5 minutes', duration: const Duration(minutes: 5)),
            const SizedBox(height: 6),
            _buildTimerTile(label: '15 minutes', duration: const Duration(minutes: 15)),
            const SizedBox(height: 6),
            _buildTimerTile(label: '30 minutes', duration: const Duration(minutes: 30)),
            const SizedBox(height: 6),
            _buildTimerTile(label: '45 minutes', duration: const Duration(minutes: 45)),
            const SizedBox(height: 6),
            _buildTimerTile(label: '1 hour', duration: const Duration(hours: 1)),
          ],
        ),
      ),
    );
  }

  Widget _buildTimerTile({
    required String label,
    Duration? duration,
    String? subtitle,
    IconData? icon,
    bool isEndSong = false,
  }) {
    return MusicHoverable(
      scaleFactor: 1.02,
      child: InkWell(
        onTap: () {
          HapticFeedback.mediumImpact();
          if (isEndSong) {
            sleepService.startEndOfTrackTimer();
          } else if (duration != null) {
            sleepService.startTimer(duration);
          }
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF7C5CFF),
              content: Text('Sleep timer set: $label 🌙'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon ?? Icons.timer_outlined, color: Colors.white54, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
