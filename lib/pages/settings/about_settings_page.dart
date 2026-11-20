import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../design/prism_tokens.dart';
import '../../services/cloud/cloud_auth_service.dart';
import '../../services/device/device_id_service.dart';
import '../../services/errors/app_error_log.dart';
import '../../services/theme/app_theme_service.dart';

class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight
        ? PrismLight.inkSoft
        : Colors.white.withValues(alpha: 0.6);
    final cardBorder = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);

    return Scaffold(
      backgroundColor: palette.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: palette.appBarBackgroundColor,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'About Dizzy',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            children: [
              // App Brand Header with actual 3D Metallic Logo
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: palette.primaryColor.withValues(alpha: 0.28),
                            blurRadius: 28,
                            spreadRadius: 2,
                            offset: const Offset(-2, -2),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 22,
                            offset: const Offset(4, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'assets/icon.png',
                          width: 84,
                          height: 84,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: isLight
                            ? [
                                palette.primaryColor,
                                PrismLight.ink,
                                palette.primaryColor,
                              ]
                            : [
                                Colors.white,
                                palette.silverAccent,
                                const Color(0xFFCBD5E1),
                                palette.primaryColor.withValues(alpha: 0.9),
                              ],
                        stops: isLight ? null : const [0.0, 0.35, 0.70, 1.0],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: Text(
                        'Dizzy',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snapshot) {
                        final version = snapshot.hasData
                            ? snapshot.data!.version
                            : '1.1.5';
                        return Text(
                          'Version $version • by Sirius',
                          style: TextStyle(
                            fontSize: 13,
                            color: isLight
                                ? PrismAccent.starTextLight
                                : palette.amberAccent.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── This device ──────────────────────────────────────────
              // The one thing support always needs and users could never
              // find: the code the admin dashboard files this install under.
              Text(
                'THIS DEVICE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isLight
                      ? PrismLight.inkFaint
                      : palette.silverAccent.withValues(alpha: 0.45),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<String?>(
                valueListenable: DeviceIdService.deviceCode,
                builder: (context, code, _) {
                  final shown = code == null
                      ? '—'
                      : DeviceIdService.displayCode(code);
                  return Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                    decoration: BoxDecoration(
                      color: palette.cardBackgroundColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.fingerprint_rounded,
                          color: palette.primaryColor,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Device code',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: inkSoft,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                shown,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  color: ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy device code',
                          icon: Icon(
                            Icons.copy_rounded,
                            size: 18,
                            color: inkSoft,
                          ),
                          onPressed: code == null
                              ? null
                              : () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: shown),
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Device code copied'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _DiagnosticsTile(palette: palette),

              const SizedBox(height: 32),

              // Developer / Creator Section
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      palette.primaryColor.withValues(alpha: 0.14),
                      palette.silverAccent.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: palette.primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: palette.primaryColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: palette.primaryColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Icon(
                        Icons.code_rounded,
                        color: palette.primaryColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Developed by Sirius',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'github.com/Sirius6907',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: PrismAccent.text(isLight),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Description Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: palette.cardBackgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Universal Entertainment Ecosystem',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Dizzy is an all-in-one entertainment client bringing together movies, TV series, anime, live IPTV, music, manga, and audiobooks into a unified, high-performance interface with custom Liquid Glass visuals and metallic aesthetic.',
                      style: TextStyle(
                        fontSize: 13,
                        color: inkSoft,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Architecture & Core Technologies
              Text(
                'CORE TECHNOLOGIES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isLight
                      ? PrismLight.inkFaint
                      : palette.silverAccent.withValues(alpha: 0.45),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),

              _buildTechTile(
                palette: palette,
                title: 'High-Performance Video Engine',
                subtitle:
                    'Powered by embedded media_kit / libmpv with hardware-accelerated decoding.',
              ),
              const SizedBox(height: 10),
              _buildTechTile(
                palette: palette,
                title: 'Debrid & Multi-Source Scrapers',
                subtitle:
                    'Direct high-speed cloud playback via Real-Debrid, TorBox, and Stremio addons.',
              ),
              const SizedBox(height: 10),
              _buildTechTile(
                palette: palette,
                title: 'Liquid Glass GLSL Shaders',
                subtitle:
                    'Custom real-time optical refraction, lenses, and fluid physics.',
              ),
              const SizedBox(height: 10),
              _buildTechTile(
                palette: palette,
                title: 'Trakt & Cloud Synchronization',
                subtitle:
                    'Cross-platform watchlist, episode tracking, and playback scrobbling.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTechTile({
    required AppThemePalette palette,
    required String title,
    required String subtitle,
  }) {
    final isLight = palette.isLight;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.cardBackgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLight
              ? PrismLight.borderSubtle
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: palette.primaryColor,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: palette.primaryColor.withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isLight ? PrismLight.ink : Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isLight
                        ? PrismLight.inkSoft
                        : Colors.white.withValues(alpha: 0.45),
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

/// "Send diagnostics" — drains the queued error reports right now instead of
/// waiting for the 15-minute timer, and says exactly what happened.
///
/// Exists because a user reporting a bug has no way to know whether anything
/// was actually sent, and a report that is still sitting in the queue is the
/// same as no report at all. The tile shows the real queue depth, so "0
/// waiting" is a fact rather than a reassurance.
class _DiagnosticsTile extends StatefulWidget {
  const _DiagnosticsTile({required this.palette});

  final AppThemePalette palette;

  @override
  State<_DiagnosticsTile> createState() => _DiagnosticsTileState();
}

class _DiagnosticsTileState extends State<_DiagnosticsTile> {
  int? _pending;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final n = await AppErrorLog.pendingCount();
    if (mounted) setState(() => _pending = n);
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    await AppErrorLog.flush();
    final left = await AppErrorLog.pendingCount();
    if (!mounted) return;
    setState(() {
      _sending = false;
      _pending = left;
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          left == 0
              ? 'Diagnostics sent.'
              : 'Still $left waiting — no connection? They will retry.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight
        ? PrismLight.inkSoft
        : Colors.white.withValues(alpha: 0.6);

    return ValueListenableBuilder<bool>(
      valueListenable: CloudAuthService.consentCrash,
      builder: (context, consent, _) {
        final n = _pending;
        final String subtitle;
        if (!consent) {
          subtitle = 'Crash counts are off in Privacy — nothing is sent.';
        } else if (n == null) {
          subtitle = 'Checking the queue…';
        } else if (n == 0) {
          subtitle = 'Nothing waiting. Recent errors were already sent.';
        } else {
          subtitle = '$n report${n == 1 ? '' : 's'} waiting to be sent.';
        }
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.bug_report_rounded,
            color: consent ? palette.primaryColor : inkSoft,
          ),
          title: Text(
            'Send diagnostics',
            style: TextStyle(color: ink, fontSize: 14),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(color: inkSoft, fontSize: 12),
          ),
          trailing: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: !consent || n == 0 ? null : _send,
                  child: const Text('Send now'),
                ),
        );
      },
    );
  }
}
