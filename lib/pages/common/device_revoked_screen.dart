import 'package:flutter/material.dart';

import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_button.dart';

import '../settings/privacy_settings_page.dart';
import '../../widgets/common/notify.dart';

/// Phase C — revoked-device notice screen (decision locked 2026-09-30).
///
/// Shown when `device_boot` reports revoked=true for THIS device. Never a
/// silent logout, never a crash-loop: the device is blocked with one clear
/// Easy-English line and one path forward (link again / contact support).
/// Offline → gate never fires (fail-soft: last-known state only).
class DeviceRevokedScreen extends StatelessWidget {
  const DeviceRevokedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      color: DizzyGlow.red.withValues(alpha: 0.12),
                      border:
                          Border.all(color: DizzyGlow.red, width: 2),
                    ),
                    child: const Icon(
                      Icons.phonelink_lock_rounded,
                      color: DizzyGlow.red,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: DizzySpace.lg),
                  const Text(
                    'This device was removed',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: DizzyVoid.bone,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: DizzySpace.sm),
                  const Text(
                    'Someone removed this phone from the account. '
                    'Link again to continue watching where you left off.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
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
                    onTap: () {
                      // Re-link path: Privacy page holds the Phone/Email
                      // OTP link flow that merges data back in.
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PrivacySettingsPage(),
                        ),
                      );
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.link_rounded,
                            color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Link this device again',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: DizzySpace.sm),
                  DizzyTactileButton(
                    width: double.infinity,
                    height: 44,
                    onTap: () {
                      DizzyNotify.show(
                        context,
                        'If this was a mistake, ask the account owner to '
                        'add this phone back from their admin dashboard.',
                        tone: NotifyTone.info,
                      );
                    },
                    child: const Text(
                      'Why am I seeing this?',
                      style: TextStyle(
                        color: DizzyVoid.ash,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
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
}
