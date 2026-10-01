import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/widgets/common/notify.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_button.dart';

/// Phase E1 — post-force_after blocking screen (Easy English, no tech words).
///
/// Only ever reached when remote config carried a deadline that has passed
/// (UpdateGate) — an offline client without config can never get here, so the
/// server cannot brick a device it cannot reach.
class UpdateRequiredScreen extends StatelessWidget {
  final String minVersion;

  const UpdateRequiredScreen({super.key, this.minVersion = ''});

  static const _downloadUrl =
      'https://github.com/Sirius6907/Dizzy-v3/releases/latest';

  Future<void> _openUpdate(BuildContext context) async {
    try {
      final ok = await launchUrl(
        Uri.parse(_downloadUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        DizzyNotify.show(
          context,
          'Could not open the download page — try again.',
          tone: NotifyTone.warn,
        );
      }
    } catch (_) {
      if (context.mounted) {
        DizzyNotify.show(
          context,
          'Could not open the download page — try again.',
          tone: NotifyTone.warn,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // post-deadline: no back escape, only Update now
      child: Scaffold(
        backgroundColor: DizzyVoid.voidA,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(DizzySpace.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: DizzyGlow.gold.withValues(alpha: 0.12),
                        border: Border.all(color: DizzyGlow.gold, width: 2),
                      ),
                      child: const Icon(
                        Icons.system_update_alt_rounded,
                        color: DizzyGlow.gold,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: DizzySpace.lg),
                    const Text(
                      'Please update Dizzy',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: DizzyVoid.bone,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: DizzySpace.sm),
                    Text(
                      minVersion.isEmpty
                          ? 'This version is old. Update to keep watching — '
                                'your list and progress stay exactly where they are.'
                          : 'This version is old. Update to $minVersion or newer '
                                'to keep watching — your list and progress stay '
                                'exactly where they are.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: DizzyVoid.ash,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: DizzySpace.lg),
                    DizzyTactileButton(
                      width: double.infinity,
                      height: 48,
                      gradient: DizzyGradients.beamButton,
                      onTap: () => _openUpdate(context),
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
