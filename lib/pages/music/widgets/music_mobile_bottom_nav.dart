import 'package:flutter/material.dart';
import '../../../widgets/common/performance_liquid_lens.dart';

class MusicMobileBottomNav extends StatelessWidget {
  final String activeTab;
  final Function(String) onTabSelected;

  const MusicMobileBottomNav({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.dock,
      child: Container(
        height: 60 + bottomInset,
        padding: EdgeInsets.only(bottom: bottomInset),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0E17).withValues(alpha: 0.95),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem('Home', Icons.home_rounded),
            _navItem('Browse', Icons.explore_rounded),
            _navItem('Radio', Icons.radio_rounded),
            _navItem('Library', Icons.library_music_rounded),
          ],
        ),
      ),
    );
  }

  Widget _navItem(String label, IconData icon) {
    final isSelected = activeTab == label;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTabSelected(label),
        child: SizedBox(
          height: 60,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFF7C5CFF) : Colors.white54,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

