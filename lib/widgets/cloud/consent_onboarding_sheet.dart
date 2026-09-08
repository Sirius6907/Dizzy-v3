import 'package:flutter/material.dart';

import '../../services/cloud/cloud_auth_service.dart';

/// S2 (v1.1.9): first-launch privacy consent. All OFF by default.
/// Shown once; changeable anytime in Settings → Privacy.
class ConsentOnboardingSheet extends StatefulWidget {
  const ConsentOnboardingSheet({super.key});

  @override
  State<ConsentOnboardingSheet> createState() => _ConsentOnboardingSheetState();
}

class _ConsentOnboardingSheetState extends State<ConsentOnboardingSheet> {
  bool _telemetry = false;
  bool _genrePrefs = true; // recommended: powers Because-You-Watched sync
  bool _crash = true; // recommended: crash counts only, no stack PII

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('🔒 Your privacy, your call',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 8),
            const Text(
              'Dizzy works 100% without an account. '
              'Help improve the app by sharing privacy-safe data. '
              'Everything is optional — change anytime in Settings → Privacy.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 12),
            _toggle(
              'App experience data',
              'Install, version, platform (e.g. android, 1.1.9). No watch titles.',
              _telemetry,
              (v) => setState(() => _telemetry = v),
            ),
            _toggle(
              'Taste preferences (recommended)',
              'Genre scores like action:0.8 — never raw watch history. Powers smart rows.',
              _genrePrefs,
              (v) => setState(() => _genrePrefs = v),
            ),
            _toggle(
              'Crash counts (recommended)',
              'How often the app crashes. No personal data, no stack traces.',
              _crash,
              (v) => setState(() => _crash = v),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  await CloudAuthService.setConsent(
                    telemetry: _telemetry,
                    genrePrefs: _genrePrefs,
                    crash: _crash,
                  );
                  await CloudAuthService.setOnboarded();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Continue'),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () async {
                  await CloudAuthService.setConsent(
                    telemetry: false,
                    genrePrefs: false,
                    crash: false,
                  );
                  await CloudAuthService.setOnboarded();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Skip — keep everything off',
                    style: TextStyle(color: Colors.white60)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(
      String title, String sub, bool val, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(sub,
          style: const TextStyle(color: Colors.white60, fontSize: 12)),
      value: val,
      onChanged: onChanged,
    );
  }
}
