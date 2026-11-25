import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/design/prism_tokens.dart';
import 'package:dizzy/services/theme/app_theme_service.dart';
import 'package:dizzy/widgets/common/notify.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_button.dart';

/// Phase E1 — post-force_after blocking screen, rebuilt as a clay poster
/// (2026-11-26) to match the revoked-device notice instead of looking like a
/// system dialog.
///
/// Only ever reached when remote config carried a deadline that has passed
/// (UpdateGate) — an offline client without config can never get here, so the
/// server cannot brick a device it cannot reach. Android only: the Windows
/// build is a portable ZIP with no updater, so blocking it would be a dead
/// end (see `_enforceForceUpdate` in main.dart).
///
/// Two exits, both honest: the primary button opens the official latest
/// release (the page that actually carries the new APK), and the quiet link
/// below opens the landing page for people who would rather read first. There
/// is no back button — the point is that the old build cannot continue — but
/// there is also no fake urgency and no countdown.
class UpdateRequiredScreen extends StatefulWidget {
  /// The minimum version the server asked for, shown as "Latest".
  final String minVersion;

  const UpdateRequiredScreen({super.key, this.minVersion = ''});

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  static const _downloadUrl =
      'https://github.com/Sirius6907/Dizzy-v3/releases/latest';
  static const _officialUrl = 'https://dizzy-by-sirius.netlify.app';

  String _currentVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _currentVersion = pkg.version);
    } catch (_) {
      // A missing version is cosmetic: the poster still works without it.
    }
  }

  Future<void> _open(String url) async {
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        DizzyNotify.show(
          context,
          'Could not open that page — try again.',
          tone: NotifyTone.warn,
        );
      }
    } catch (_) {
      if (mounted) {
        DizzyNotify.show(
          context,
          'Could not open that page — try again.',
          tone: NotifyTone.warn,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final scheme = Theme.of(context).colorScheme;
    final ink = isLight ? PrismLight.ink : DizzyVoid.bone;
    final inkSoft = isLight ? PrismLight.inkSoft : DizzyVoid.ash;
    final latest = widget.minVersion.trim();

    return PopScope(
      canPop: false, // post-deadline: no back escape, only Update
      child: Scaffold(
        backgroundColor: palette.scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DizzySpace.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
                  decoration: BoxDecoration(
                    color: palette.cardBackgroundColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.7),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isLight ? 0.06 : 0.35,
                        ),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The logo, not an icon glyph — the poster should look
                      // like Dizzy, not like a system error.
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: DizzyGlow.gold.withValues(alpha: 0.30),
                              blurRadius: 30,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Image.asset(
                            'assets/icon.png',
                            width: 88,
                            height: 88,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'DIZZY',
                        style: TextStyle(
                          color: inkSoft,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Update is required to use Dizzy',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ink,
                          fontSize: 22,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Install the new build over this one — your list, your '
                        'progress and your username stay exactly where they '
                        'are. Nothing is deleted.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: inkSoft,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      if (_currentVersion.isNotEmpty || latest.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _versionPill(
                          scheme,
                          inkSoft,
                          _currentVersion,
                          latest,
                        ),
                      ],
                      const SizedBox(height: 20),
                      DizzyTactileButton(
                        width: double.infinity,
                        height: 48,
                        gradient: DizzyGradients.beamButton,
                        onTap: () => _open(_downloadUrl),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.download_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Update now',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () => _open(_officialUrl),
                        child: Text(
                          'Visit official page',
                          style: TextStyle(
                            color: inkSoft,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "You have v1.3.2 · Latest v1.3.7" — plain text, no pun, no guess.
  Widget _versionPill(
    ColorScheme scheme,
    Color inkSoft,
    String current,
    String latest,
  ) {
    final parts = <String>[
      if (current.isNotEmpty) 'You have v$current',
      if (latest.isNotEmpty) 'Latest v$latest',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Text(
        parts.join('  ·  '),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: inkSoft,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
