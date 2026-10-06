import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dizzy/design/dizzy_tactile.dart';
import '../../services/errors/app_error_log.dart';
import '../../services/updater/app_updater_service.dart';
import '../../services/updater/update_prefs.dart';
import '../../services/updater/update_state_machine.dart';
import '../../services/updater/update_stager.dart';
import '../../widgets/updater/release_notes_studio.dart';

class UpdatesSettingsPage extends StatefulWidget {
  const UpdatesSettingsPage({super.key});

  @override
  State<UpdatesSettingsPage> createState() => _UpdatesSettingsPageState();
}

class _UpdatesSettingsPageState extends State<UpdatesSettingsPage> {
  bool _isCheckingForUpdates = false;
  bool _autoDownload = false;
  bool _wifiOnly = true;

  // ── Phase 3.3 dev probe ────────────────────────────────────────────
  // Five taps on the installed-version line (within 2s each) queue a
  // synthetic report through the real AppErrorLog pipeline, so the
  // crash -> admin-dashboard path can be proven live (~10s) without
  // crashing anything. Hidden by design; harmless if never tapped.
  int _probeTaps = 0;
  DateTime? _probeAt;

  Future<void> _devProbeTap() async {
    final now = DateTime.now();
    if (_probeAt == null ||
        now.difference(_probeAt!) > const Duration(seconds: 2)) {
      _probeTaps = 0;
    }
    _probeAt = now;
    _probeTaps += 1;
    if (_probeTaps < 5) return;
    _probeTaps = 0;
    await AppErrorLog.log(
      code: 'E_PROBE',
      screen: 'dev_probe',
      detail: 'manual_probe',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Test report sent. It shows up in about 10 seconds.'),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadStagingPrefs();
  }

  Future<void> _loadStagingPrefs() async {
    final auto = await UpdatePrefs.autoDownload;
    final wifi = await UpdatePrefs.wifiOnly;
    if (mounted) {
      setState(() {
        _autoDownload = auto;
        _wifiOnly = wifi;
      });
    }
  }

  /// I2: silent staged download honouring the Wi-Fi-only gate.
  Future<void> _stageNow() async {
    try {
      final info = await AppUpdaterService().checkForUpdates(
        ignoreDismissed: true,
      );
      if (info == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Dizzy is up to date!'),
              backgroundColor: Color(0xFF7C5CFF),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      await UpdateStager.stage(
        info.downloadUrl,
        info.latestVersion,
        expectedSha256: info.sha256,
        requireWifi: _wifiOnly,
      );
    } catch (e) {
      debugPrint('[UpdatesPage] stage failed: $e');
    }
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    setState(() {
      _isCheckingForUpdates = true;
    });

    try {
      final updater = AppUpdaterService();
      final updateInfo = await updater.checkForUpdates(ignoreDismissed: true);

      if (!context.mounted) return;

      if (updateInfo != null) {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => ReleaseNotesStudio(updateInfo: updateInfo),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dizzy is up to date!'),
            backgroundColor: Color(0xFF7C5CFF),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking updates: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingForUpdates = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DizzyVoid.voidA,
      appBar: AppBar(
        backgroundColor: DizzyVoid.voidB,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'App Updates & System',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              // Header description
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  'Keep Dizzy up to date with the latest features, security patches, and performance improvements.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Colors.white.withValues(alpha: 0.5),
                    height: 1.4,
                  ),
                ),
              ),

              // Version & Check update card
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  final version = snapshot.hasData
                      ? snapshot.data!.version
                      : '1.1.3';
                  final buildNumber = snapshot.hasData
                      ? snapshot.data!.buildNumber
                      : '14';
                  final appName = snapshot.hasData
                      ? snapshot.data!.appName
                      : 'Dizzy';

                  return Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: DizzyVoid.surface1,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF7C5CFF).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF7C5CFF,
                                ).withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.system_update_rounded,
                                color: Color(0xFF7C5CFF),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    appName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  GestureDetector(
                                    onTap: _devProbeTap,
                                    behavior: HitTestBehavior.opaque,
                                    child: Text(
                                      'Installed Version: v$version (Build $buildNumber)',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isCheckingForUpdates
                                ? null
                                : () => _checkForUpdates(context),
                            icon: _isCheckingForUpdates
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 18),
                            label: Text(
                              _isCheckingForUpdates
                                  ? 'Checking for updates...'
                                  : 'Check for Updates',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7C5CFF),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // Phase I2: silent staged download controls.
              Text(
                'SMART DOWNLOAD',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.35),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: DizzyVoid.surface1,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _autoDownload,
                      onChanged: (v) {
                        setState(() => _autoDownload = v);
                        UpdatePrefs.setAutoDownload(v);
                      },
                      title: const Text(
                        'Download updates automatically',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'We fetch the update in the background — you just tap Install.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _wifiOnly,
                      onChanged: !_autoDownload
                          ? null
                          : (v) {
                              setState(() => _wifiOnly = v);
                              UpdatePrefs.setWifiOnly(v);
                            },
                      title: const Text(
                        'Wi-Fi only',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Never download on mobile data.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: ValueListenableBuilder<UpdateRunState>(
                        valueListenable: UpdateStateMachine.state,
                        builder: (context, s, _) {
                          if (s == UpdateRunState.downloading) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: ValueListenableBuilder<double>(
                                valueListenable: UpdateStateMachine.progress,
                                builder: (context, p, _) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Downloading… ${(p * 100).round()}%',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.white.withValues(
                                          alpha: 0.6,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: p <= 0 ? null : p,
                                        minHeight: 5,
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.08),
                                        color: const Color(0xFF7C5CFF),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _stageNow,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download update now'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7C5CFF),
                    side: const BorderSide(color: Color(0xFF7C5CFF)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Release Channel Info
              Text(
                'RELEASE CHANNELS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.35),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),

              _buildInfoTile(
                icon: Icons.verified_rounded,
                title: 'Official Stable Channel',
                subtitle:
                    'Direct GitHub release distribution with automated checksum verification.',
              ),
              const SizedBox(height: 10),
              _buildInfoTile(
                icon: Icons.security_rounded,
                title: 'Seamless In-App Patching',
                subtitle:
                    'Downloads and applies executable updates directly without manual file downloads.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DizzyVoid.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white70, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
