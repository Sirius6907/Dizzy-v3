import 'package:flutter/material.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_card.dart';
import '../../widgets/common/offline_aware_scaffold.dart';

/// Download Settings — pause, resume, and location management.
class DownloadSettingsPage extends StatelessWidget {
  const DownloadSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OfflineAwareScaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1017),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Downloads',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              DizzyTactileCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Download Settings',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Manage where files are saved and how downloads behave.',
                      style: TextStyle(
                          color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    _buildSettingRow(
                      Icons.storage_rounded,
                      const Color(0xFF00C2FF),
                      'Save location',
                      'Your device storage',
                      Icons.chevron_right_rounded,
                    ),
                    const SizedBox(height: 8),
                    _buildSettingRow(
                      Icons.pause_circle_outline_rounded,
                      const Color(0xFFF59E0B),
                      'Auto-pause on weak net',
                      'Downloads pause when your connection is poor',
                      Icons.chevron_right_rounded,
                    ),
                    const SizedBox(height: 8),
                    _buildSettingRow(
                      Icons.play_circle_fill_rounded,
                      const Color(0xFF10B981),
                      'Resume on reconnect',
                      'Downloads continue when the net comes back',
                      Icons.chevron_right_rounded,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingRow(
    IconData icon,
    Color iconColor,
    String title,
    String subtitle,
    IconData trailing,
  ) {
    return DizzyTactileCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(trailing, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }
}
