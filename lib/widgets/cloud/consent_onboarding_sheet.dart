import 'package:flutter/material.dart';

import '../../services/cloud/cloud_auth_service.dart';
import '../prism/prism_button.dart';
import '../prism/prism_chip.dart';

/// S2 (v1.1.9): first-launch privacy consent. All OFF by default.
/// Shown once; changeable anytime in Settings → Privacy.
class ConsentOnboardingSheet extends StatefulWidget {
  const ConsentOnboardingSheet({super.key});

  @override
  State<ConsentOnboardingSheet> createState() => _ConsentOnboardingSheetState();
}

class _ConsentOnboardingSheetState extends State<ConsentOnboardingSheet> {
  // WP-P5: all OFF by default, as the header promises. No "recommended" pre-on.
  bool _telemetry = false;
  bool _genrePrefs = false;
  bool _crash = false;
  bool _watchParty = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
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
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Your privacy, your call',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Dizzy works without an account. Help improve it by sharing '
              'privacy-safe data. Everything is optional — change it anytime '
              'in Settings → Privacy.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 12),
            _toggle(
              Icons.analytics_rounded,
              'App experience data',
              'Install, version, platform (e.g. android, 1.1.9). No watch titles.',
              _telemetry,
              (v) => setState(() => _telemetry = v),
            ),
            _toggle(
              Icons.movie_rounded,
              'Taste preferences',
              'Genre scores like action:0.8 — never raw watch history. Powers smart rows.',
              _genrePrefs,
              (v) => setState(() => _genrePrefs = v),
            ),
            _toggle(
              Icons.bug_report_rounded,
              'Help fix bugs',
              'Sends problem type only (like "slow internet"). No titles, no links. Off = nothing leaves your phone.',
              _crash,
              (v) => setState(() => _crash = v),
            ),
            _toggle(
              Icons.group_rounded,
              'Watch Party voice & rooms',
              'Mic audio via LiveKit + room membership. Off = parties stay solo.',
              _watchParty,
              (v) => setState(() => _watchParty = v),
            ),
            const SizedBox(height: 16),
            Center(
              child: PrismButton(
                label: 'Save my choices',
                icon: Icons.check_rounded,
                accent: true,
                onPressed: () async {
                  await CloudAuthService.setConsent(
                    telemetry: _telemetry,
                    genrePrefs: _genrePrefs,
                    crash: _crash,
                    watchParty: _watchParty,
                  );
                  await CloudAuthService.setOnboarded();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: PrismButton(
                label: 'Decline all',
                icon: Icons.block_rounded,
                small: true,
                onPressed: () async {
                  // v1.2.0-P1 (T1.6): explicit Decline All — all flags OFF,
                  // marked onboarded, sheet closes, never nags again.
                  await CloudAuthService.setConsent(
                    telemetry: false,
                    genrePrefs: false,
                    crash: false,
                    watchParty: false,
                  );
                  await CloudAuthService.setOnboarded();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(
    IconData icon,
    String title,
    String sub,
    bool val,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PrismToggleRow(
        icon: icon,
        title: title,
        subtitle: sub,
        value: val,
        onChanged: onChanged,
      ),
    );
  }
}
