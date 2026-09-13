import '../../../services/music/music_service.dart';
import 'package:flutter/material.dart';
import '../../../services/music/music_player_controller.dart';
import 'music_hoverable.dart';

class MusicSidebar extends StatelessWidget {
  final String activeTab;
  final Function(String) onTabSelected;
  final VoidCallback onShortcutsTap;

  const MusicSidebar({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
    required this.onShortcutsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: const Color(0xFF0C0E17),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(
              children: [
                MusicHoverable(
                  scaleFactor: 1.08,
                  child: IconButton(
                    tooltip: 'Back to Home (Esc)',
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      padding: const EdgeInsets.all(10),
                    ),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C5CFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'MUSIC',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10),
          const SizedBox(height: 8),
          _sidebarActionItem(
            'Exit Music',
            Icons.logout_rounded,
            () => Navigator.maybePop(context),
          ),
          const SizedBox(height: 4),
          _sidebarItem('Home', Icons.home_rounded),
          _sidebarItem('Browse', Icons.explore_rounded),
          _sidebarItem('Radio', Icons.radio_rounded),
          _sidebarItem('Library', Icons.library_music_rounded),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              'AUDIO SOURCE',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          _sidebarAudioSourceSelector(),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: InkWell(
              onTap: onShortcutsTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.keyboard_rounded, color: Colors.white54, size: 18),
                    SizedBox(width: 10),
                    Text(
                      'Shortcuts ( ? )',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarAudioSourceSelector() {
    final player = MusicPlayerController.instance;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final isFlac = player.audioSource == MusicAudioSource.flac;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => player.setAudioSource(MusicAudioSource.flac),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isFlac ? const Color(0xFF00D2EF).withValues(alpha: 0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: isFlac ? Border.all(color: const Color(0xFF00D2EF).withValues(alpha: 0.4)) : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.diamond_rounded, size: 14, color: isFlac ? const Color(0xFF00D2EF) : Colors.white54),
                          const SizedBox(width: 4),
                          Text(
                            'FLAC',
                            style: TextStyle(
                              color: isFlac ? Colors.white : Colors.white60,
                              fontSize: 11,
                              fontWeight: isFlac ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: InkWell(
                    onTap: () => player.setAudioSource(MusicAudioSource.youtube),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: !isFlac ? const Color(0xFFFF3366).withValues(alpha: 0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: !isFlac ? Border.all(color: const Color(0xFFFF3366).withValues(alpha: 0.4)) : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_circle_fill_rounded, size: 14, color: !isFlac ? const Color(0xFFFF3366) : Colors.white54),
                          const SizedBox(width: 4),
                          Text(
                            'YouTube',
                            style: TextStyle(
                              color: !isFlac ? Colors.white : Colors.white60,
                              fontSize: 11,
                              fontWeight: !isFlac ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sidebarActionItem(String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: MusicHoverable(
        scaleFactor: 1.02,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: const Color(0xFF00D2EF),
                  size: 20,
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebarItem(String label, IconData icon) {
    final isSelected = activeTab == label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: MusicHoverable(
        scaleFactor: 1.02,
        child: InkWell(
          onTap: () => onTabSelected(label),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF7C5CFF).withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: isSelected
                  ? Border.all(color: const Color(0xFF7C5CFF).withValues(alpha: 0.4))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? const Color(0xFF7C5CFF) : Colors.white60,
                  size: 20,
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

