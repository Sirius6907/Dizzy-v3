import 'package:flutter/material.dart';

import '../../pages/legal/legal_page.dart';
import '../../services/cloud/cloud_auth_service.dart';
import '../../services/heartbeat/heartbeat_service.dart';
import '../../services/legal/legal_acceptance_service.dart';
import '../../services/legal/legal_terms.dart';
import '../prism/prism_button.dart';

/// v1.3.7 "One Tap" (2026-11-26) — the single consent gate.
///
/// This replaced the old four-switch sheet. The old design asked people to make
/// five separate decisions before they had seen a single movie, and most left
/// everything off, which meant a crash on their phone was invisible and the
/// app could not be fixed. The new deal is one honest paragraph, one button,
/// everything on, and Settings → Privacy as the place to take any of it back —
/// turning a switch off there still stops that upload immediately.
///
/// Because it is mandatory it is also not dismissible: [HomePage] shows it with
/// `isDismissible: false` / `enableDrag: false`, and this widget has no close
/// affordance and no decline button. The only way out is Accept — so every
/// write below is best-effort and the sheet closes even if storage fails. A
/// gate that traps someone because a preference write threw is worse than a
/// gate that asks again next launch.
///
/// Re-prompt: [LegalTerms.version] moves and this opens again for people who
/// already use the app. It says plainly that accepting switches all five back
/// on, including ones they had turned off. That warning is not optional copy:
/// it is the truth about what the button does.
class ConsentOnboardingSheet extends StatefulWidget {
  const ConsentOnboardingSheet({super.key});

  @override
  State<ConsentOnboardingSheet> createState() => _ConsentOnboardingSheetState();
}

class _ConsentOnboardingSheetState extends State<ConsentOnboardingSheet> {
  bool _saving = false;

  /// True when this is a re-prompt for new wording, not a first run.
  bool get _isUpdate =>
      CloudAuthService.onboarded.value && LegalAcceptanceService.needsAcceptance;

  /// Every step here is soft: a failed local write must never leave someone
  /// stuck on a screen with no second button.
  Future<void> _safely(Future<void> Function() step) async {
    try {
      await step();
    } catch (e) {
      debugPrint('[Consent] step failed (soft): $e');
    }
  }

  Future<void> _accept() async {
    if (_saving) return;
    setState(() => _saving = true);

    // One tap, all five on. The order matters: consent first (so the services
    // start collecting under it), then the onboarded flag, then the legal
    // record (which also queues an offline retry if the server is unreachable).
    await _safely(
      () => CloudAuthService.setConsent(
        telemetry: true,
        genrePrefs: true,
        crash: true,
        watchParty: true,
      ),
    );
    await _safely(() => HeartbeatService.instance.setConsent(true));
    await _safely(CloudAuthService.setOnboarded);
    await _safely(LegalAcceptanceService.accept);

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(scheme),
                    const SizedBox(height: 18),
                    _lead(scheme),
                    const SizedBox(height: 18),
                    _why(
                      scheme,
                      Icons.healing_rounded,
                      'Troubleshooting',
                      'When Dizzy crashes, it sends the kind of problem and the '
                          'screen it happened on — never your files and never a '
                          'link. That one line is the difference between a bug '
                          'that gets fixed and a bug nobody ever hears about.',
                    ),
                    _why(
                      scheme,
                      Icons.monitor_heart_rounded,
                      'Monitoring',
                      'A small heartbeat says this phone is still here and which '
                          'version it runs, and app experience data adds the '
                          'install, version and platform. Together they show '
                          'whether a release is healthy on real phones or '
                          'quietly failing on one model at 2 a.m.',
                    ),
                    _why(
                      scheme,
                      Icons.dns_rounded,
                      'Backend operations',
                      'Taste preferences keep the smart rows worth looking at, '
                          'and Watch Party consent is what lets voice and rooms '
                          'work at all. Both need the server to know a little '
                          'about what you enjoy and who you are watching with.',
                    ),
                    const SizedBox(height: 6),
                    _straightAnswer(scheme),
                    if (_isUpdate) ...[
                      const SizedBox(height: 14),
                      _rePrompt(scheme),
                    ],
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            _footer(scheme),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            'assets/icon.png',
            width: 46,
            height: 46,
            filterQuality: FilterQuality.medium,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'One tap to keep Dizzy running',
            style: TextStyle(
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _lead(ColorScheme scheme) {
    return Text(
      'Dizzy is free, has no ads, and is built by one person. The five things '
      'below are how it gets fixed, watched over and kept online. Accepting '
      'turns all five on in a single tap, and Settings → Privacy lets you turn '
      'any of them off again whenever you want.',
      style: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 14,
        height: 1.5,
      ),
    );
  }

  Widget _why(
    ColorScheme scheme,
    IconData icon,
    String title,
    String body,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: 0.12),
            ),
            child: Icon(icon, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The one paragraph that had to be written carefully: `user_events` stores
  /// the name of what you play, add, rate and search for, so "never a title"
  /// (the old wording) was a lie. Say it plainly, once.
  Widget _straightAnswer(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Straight answer on titles',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Taste preferences include the titles you play, add to your list, '
            'rate and search for, with their genre, language and a timestamp — '
            'the title is what makes a recommendation possible. Your files, '
            'messages, contacts, location, advertising ID and anything from '
            'the 18+ section still never leave the phone.',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rePrompt(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.tertiary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: scheme.tertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You agreed to an older version of this text. Accepting again '
              'switches all five back on — including any you turned off '
              'before. If you want one off, turn it off in Settings → '
              'Privacy right after this.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrismButton(
            label: 'Accept Terms & Privacy',
            icon: Icons.check_rounded,
            accent: true,
            expanded: true,
            onPressed: _saving ? null : _accept,
          ),
          const SizedBox(height: 2),
          TextButton(
            onPressed: _saving
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LegalPage()),
                  ),
            child: Text(
              'Read the full Terms & Privacy (v${LegalTerms.version})',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
