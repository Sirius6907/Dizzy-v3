import 'package:flutter/material.dart';

import '../../services/theme/app_theme_service.dart';
import '../../services/updater/app_updater_service.dart';

/// UX10 — Release Notes Studio: beautiful "What's New" modal.
///
/// - Background check via [AppUpdaterService.checkForUpdates].
/// - Feature breakdown: release notes split into clean bullet cards.
/// - 1-tap update (opens download page) or Later (dismiss version).
/// - Easy English only.
class ReleaseNotesStudio extends StatefulWidget {
  final UpdateInfo updateInfo;

  const ReleaseNotesStudio({super.key, required this.updateInfo});

  /// Checks in background; shows the studio only when an update exists.
  /// Returns true when the sheet was shown.
  static Future<bool> checkAndShow(BuildContext context) async {
    try {
      final info =
          await AppUpdaterService().checkForUpdates();
      if (info == null || !context.mounted) return false;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ReleaseNotesStudio(updateInfo: info),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  State<ReleaseNotesStudio> createState() => _ReleaseNotesStudioState();
}

class _ReleaseNotesStudioState extends State<ReleaseNotesStudio> {
  bool _busy = false;

  List<String> _breakdown(String notes) {
    final lines = notes
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final bullets = <String>[];
    for (final l in lines) {
      final clean = l.replaceFirst(RegExp(r'^[-*•\d.)\s]+'), '').trim();
      if (clean.isEmpty) continue;
      if (clean.length > 140) {
        bullets.add('${clean.substring(0, 137)}…');
      } else {
        bullets.add(clean);
      }
      if (bullets.length >= 8) break;
    }
    if (bullets.isEmpty) bullets.add('Faster, smoother, and more stable.');
    return bullets;
  }

  Future<void> _updateNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AppUpdaterService()
          .openDownloadPage(widget.updateInfo.downloadUrl);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _later() async {
    await AppUpdaterService.dismissVersion(
        widget.updateInfo.latestVersion);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final info = widget.updateInfo;
    final bullets = _breakdown(info.releaseNotes);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0F121C),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: palette.primaryColor
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.rocket_launch_rounded,
                      color: palette.primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'What’s New',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'v${info.currentVersion} → v${info.latestVersion}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final b in bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: palette.primaryColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          b,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize:
                            const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _later,
                      child: const Text('Later'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            palette.primaryColor,
                        foregroundColor: Colors.black,
                        minimumSize:
                            const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _busy ? null : _updateNow,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(
                              Icons.download_rounded),
                      label: Text(
                        _busy ? 'Opening…' : 'Update now',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Free update. Your list and downloads stay safe.',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
