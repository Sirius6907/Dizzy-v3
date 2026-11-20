import 'package:flutter/material.dart';

import '../../pages/legal/legal_page.dart';
import '../../services/cloud/cloud_auth_service.dart';
import '../../services/legal/legal_acceptance_service.dart';
import '../../services/legal/legal_terms.dart';
import '../prism/prism_button.dart';
import '../prism/prism_chip.dart';

/// S2 (v1.1.9): first-launch privacy consent. All OFF by default.
/// Shown once; changeable anytime in Settings → Privacy.
///
/// v1.4.3: the sheet now also carries the legal agreement. The checkbox is
/// required for both buttons — using the app is a choice you make once, while
/// the four switches above stay entirely optional. Re-opened automatically
/// when [LegalTerms.version] moves past what this install already agreed to,
/// which is why the toggles start from the saved values rather than from OFF:
/// a re-prompt must never silently wipe someone's choices.
class ConsentOnboardingSheet extends StatefulWidget {
  const ConsentOnboardingSheet({super.key});

  @override
  State<ConsentOnboardingSheet> createState() => _ConsentOnboardingSheetState();
}

class _ConsentOnboardingSheetState extends State<ConsentOnboardingSheet> {
  late bool _telemetry;
  late bool _genrePrefs;
  late bool _crash;
  late bool _watchParty;
  bool _agreed = false;
  bool _saving = false;

  /// True when this is a re-prompt for new wording, not a first run.
  bool get _isUpdate =>
      CloudAuthService.onboarded.value && LegalAcceptanceService.needsAcceptance;

  @override
  void initState() {
    super.initState();
    // WP-P5: first run is all OFF — the defaults in CloudAuthService are what
    // decide, so a re-prompt keeps whatever the person already chose.
    _telemetry = CloudAuthService.consentTelemetry.value;
    _genrePrefs = CloudAuthService.consentGenrePrefs.value;
    _crash = CloudAuthService.consentCrash.value;
    _watchParty = CloudAuthService.consentWatchParty.value;
    _agreed = !LegalAcceptanceService.needsAcceptance;
  }

  Future<void> _finish({
    required bool telemetry,
    required bool genrePrefs,
    required bool crash,
    required bool watchParty,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    await CloudAuthService.setConsent(
      telemetry: telemetry,
      genrePrefs: genrePrefs,
      crash: crash,
      watchParty: watchParty,
    );
    await CloudAuthService.setOnboarded();
    await LegalAcceptanceService.accept();
    if (mounted) Navigator.pop(context);
  }

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
              _isUpdate ? 'We updated our privacy text' : 'Your privacy, your call',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isUpdate
                  ? 'Dizzy works without an account. Nothing new is collected '
                        'without your say-so — but the wording changed, so please '
                        'read it and agree again. Your switches below are kept.'
                  : 'Dizzy works without an account. Help improve it by sharing '
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
            const SizedBox(height: 6),
            const Divider(height: 20),
            _agreement(scheme),
            const SizedBox(height: 14),
            Center(
              child: PrismButton(
                label: _isUpdate ? 'Save & agree' : 'Save my choices',
                icon: Icons.check_rounded,
                accent: true,
                onPressed: _canFinish
                    ? () => _finish(
                        telemetry: _telemetry,
                        genrePrefs: _genrePrefs,
                        crash: _crash,
                        watchParty: _watchParty,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: PrismButton(
                label: 'Decline all',
                icon: Icons.block_rounded,
                small: true,
                onPressed: _canFinish
                    ? () => _finish(
                        telemetry: false,
                        genrePrefs: false,
                        crash: false,
                        watchParty: false,
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canFinish => _agreed && !_saving;

  Widget _agreement(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _agreed = !_agreed),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Checkbox(
                    value: _agreed,
                    onChanged: (v) => setState(() => _agreed = v ?? false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'I agree to the Terms & Privacy (v${LegalTerms.version}). '
                      'The switches above are still optional.',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LegalPage()),
            ),
            icon: const Icon(Icons.description_outlined, size: 16),
            label: const Text('Read it'),
          ),
        ),
      ],
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
