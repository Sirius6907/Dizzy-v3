import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dizzy/design/prism_tokens.dart';
import '../../services/adult/adult_section_gate.dart';
import '../adult/adult_heaven_page.dart';
import '../../widgets/common/offline_aware_scaffold.dart';
import '../../widgets/prism/prism_card.dart';

import '../../services/cloud/cloud_auth_service.dart';
import '../../services/heartbeat/heartbeat_service.dart';
import '../../services/cloud/cloud_client.dart';
import '../../services/legal/legal_acceptance_service.dart';
import '../../services/legal/legal_terms.dart';
import '../../services/theme/app_theme_service.dart';
import '../legal/legal_page.dart';

/// S2 (v1.1.9): Settings → Privacy. Device identity + consent toggles + delete button.
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    // 18+ Heaven gate boots closed — reflect persisted state.
    AdultSectionGate.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    return OfflineAwareScaffold(
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
          'Privacy & Account',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              _sectionTitle('Device identity'),
              ValueListenableBuilder<bool>(
                valueListenable: CloudAuthService.signedIn,
                builder: (context, signedIn, _) => GestureDetector(
                  onTap: () => HapticFeedback.selectionClick(),
                  child: PrismCard(
                    margin: EdgeInsets.zero,
                    padding: EdgeInsets.zero,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.devices_rounded,
                            color: palette.primaryColor,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  signedIn ? 'Cloud connected' : 'Offline mode',
                                  style: TextStyle(color: ink, fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  signedIn
                                      ? 'Sync, backup & watch parties active. ${_shortDeviceId(CloudAuthService.anonId)}'
                                      : 'All features work offline. Sync disabled.',
                                  style: TextStyle(
                                    color: inkSoft,
                                    fontSize: 12,
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
              const SizedBox(height: 8),
              if (!CloudClient.isConfigured)
                ListTile(
                  leading: const Icon(
                    Icons.cloud_off_rounded,
                    color: Colors.orangeAccent,
                  ),
                  title: Text(
                    'Cloud not configured in this build',
                    style: TextStyle(color: ink),
                  ),
                  subtitle: Text(
                    'Sync & watch parties need a cloud-enabled build.',
                    style: TextStyle(color: inkSoft, fontSize: 12),
                  ),
                ),
              _sectionTitle('Terms & privacy'),
              ValueListenableBuilder<String?>(
                valueListenable: LegalAcceptanceService.acceptedVersion,
                builder: (context, accepted, _) {
                  final pending = accepted != LegalTerms.version;
                  return ValueListenableBuilder<DateTime?>(
                    valueListenable: LegalAcceptanceService.acceptedAt,
                    builder: (context, at, __) => ListTile(
                      leading: Icon(
                        pending
                            ? Icons.gavel_rounded
                            : Icons.verified_user_rounded,
                        color: pending
                            ? (isLight
                                  ? PrismAccent.starTextLight
                                  : Colors.orangeAccent)
                            : (isLight
                                  ? PrismAccent.successTextLight
                                  : Colors.greenAccent),
                      ),
                      title: Text(
                        pending
                            ? 'Terms & Privacy updated'
                            : 'Terms & Privacy',
                        style: TextStyle(color: ink),
                      ),
                      subtitle: Text(
                        pending
                            ? 'Version ${LegalTerms.version} needs your agreement. Tap to read and agree.'
                            : 'Accepted v$accepted on ${LegalAcceptanceService.describeAcceptedAt(at)}.',
                        style: TextStyle(color: inkSoft, fontSize: 12),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: inkSoft,
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const LegalPage()),
                        );
                        // The page can accept on the way out; re-read so the
                        // row is honest the moment it is visible again.
                        if (mounted) setState(() {});
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              _sectionTitle('What Dizzy may collect'),
              ValueListenableBuilder<bool>(
                valueListenable: CloudAuthService.consentTelemetry,
                builder: (context, v, _) => SwitchListTile(
                  title: Text(
                    'App experience data',
                    style: TextStyle(color: ink),
                  ),
                  subtitle: Text(
                    'Install, version, platform. No watch titles.',
                    style: TextStyle(color: inkSoft, fontSize: 12),
                  ),
                  value: v,
                  onChanged: (nv) => CloudAuthService.setConsent(telemetry: nv),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: CloudAuthService.consentGenrePrefs,
                builder: (context, v, _) => SwitchListTile(
                  title: Text(
                    'Taste preferences',
                    style: TextStyle(color: ink),
                  ),
                  subtitle: Text(
                    'Genre scores (action:0.8). Never raw history.',
                    style: TextStyle(color: inkSoft, fontSize: 12),
                  ),
                  value: v,
                  onChanged: (nv) =>
                      CloudAuthService.setConsent(genrePrefs: nv),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: CloudAuthService.consentCrash,
                builder: (context, v, _) => SwitchListTile(
                  title: Text('Crash counts', style: TextStyle(color: ink)),
                  subtitle: Text(
                    'Counts only. No personal data.',
                    style: TextStyle(color: inkSoft, fontSize: 12),
                  ),
                  value: v,
                  onChanged: (nv) => CloudAuthService.setConsent(crash: nv),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: HeartbeatService.instance.consentNotifier,
                builder: (context, v, _) => SwitchListTile(
                  title: Text(
                    'Live activity for admins',
                    style: TextStyle(color: ink),
                  ),
                  subtitle: Text(
                    'Online now, what you\'re playing (watch / listen / read), and voice presence. Off keeps only last-seen time. Never titles, names or files.',
                    style: TextStyle(color: inkSoft, fontSize: 12),
                  ),
                  value: v,
                  onChanged: (nv) => HeartbeatService.instance.setConsent(nv),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: CloudAuthService.consentWatchParty,
                builder: (context, v, _) => SwitchListTile(
                  title: Text(
                    'Watch Party voice & rooms',
                    style: TextStyle(color: ink),
                  ),
                  subtitle: Text(
                    'Mic via LiveKit + room membership. Needed for party voice.',
                    style: TextStyle(color: inkSoft, fontSize: 12),
                  ),
                  value: v,
                  onChanged: (nv) =>
                      CloudAuthService.setConsent(watchParty: nv),
                ),
              ),
              const SizedBox(height: 8),
              _sectionTitle('18+ Heaven (adults only)'),
              ValueListenableBuilder<bool>(
                valueListenable: AdultSectionGate.localConfirmed,
                builder: (context, unlocked, _) =>
                    ValueListenableBuilder<int>(
                      valueListenable: AdultSectionGate.lockedUntilMs,
                      builder: (context, _, __) {
                        final cooling = AdultSectionGate.isLockedOut();
                        final attempts = AdultSectionGate.attemptsLeft.value;
                        final year = AdultSectionGate.birthYear.value;
                        final cooldown = AdultSectionGate.describeCooldown(
                          AdultSectionGate.lockRemaining(),
                        );
                        return ListTile(
                          leading: Icon(
                            unlocked
                                ? Icons.verified_rounded
                                : cooling
                                ? Icons.lock_clock_rounded
                                : Icons.no_adult_content_rounded,
                            color: unlocked
                                ? (isLight
                                      ? PrismAccent.successTextLight
                                      : Colors.greenAccent)
                                : cooling
                                ? (isLight
                                      ? PrismAccent.starTextLight
                                      : Colors.orangeAccent)
                                : (isLight
                                      ? PrismAccent.text(isLight)
                                      : Colors.white54),
                          ),
                          title: Text(
                            unlocked
                                ? 'Adult section unlocked'
                                : cooling
                                ? 'Cooling-off — $cooldown left'
                                : 'Verify your age (18+)',
                            style: TextStyle(color: ink),
                          ),
                          subtitle: Text(
                            unlocked
                                ? 'Birth year ${year ?? '—'} confirmed on this device. Admin allow is still required.'
                                : cooling
                                ? 'Too many underage attempts. The gate stays shut for 24h, then you get $attempts fresh attempts.'
                                : 'Enter your birth year — $attempts ${attempts == 1 ? 'try' : 'tries'} left before a 24h lock. Admin allow is still required, and kids profiles stay locked.',
                            style: TextStyle(color: inkSoft, fontSize: 12),
                          ),
                          trailing: unlocked
                              ? TextButton(
                                  onPressed: _lockAdultSection,
                                  child: const Text('Lock'),
                                )
                              : FilledButton(
                                  onPressed: cooling ? null : _verifyAge,
                                  child: Text(cooling ? 'Locked' : 'Verify'),
                                ),
                        );
                      },
                    ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: AdultSectionGate.privateMode,
                builder: (context, hidden, _) => SwitchListTile(
                  title: Text('Private mode', style: TextStyle(color: ink)),
                  subtitle: Text(
                    'Labels the Settings entry "Late Night" and blocks screenshots and the recents preview while the 18+ screen is open.',
                    style: TextStyle(color: inkSoft, fontSize: 12),
                  ),
                  value: hidden,
                  onChanged: AdultSectionGate.setPrivateMode,
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: AdultSectionGate.adminAllowed,
                builder: (context, allowed, _) => ListTile(
                  leading: Icon(
                    allowed
                        ? Icons.verified_user_rounded
                        : Icons.hourglass_empty_rounded,
                    color: allowed
                        ? (isLight
                              ? PrismAccent.successTextLight
                              : Colors.greenAccent)
                        : (isLight
                              ? PrismAccent.starTextLight
                              : Colors.orangeAccent),
                  ),
                  title: Text(
                    'Admin allow status',
                    style: TextStyle(color: ink),
                  ),
                  subtitle: Text(
                    allowed
                        ? 'This device is allowed by your admin.'
                        : 'Not allowed yet — ask your admin to allow this device.',
                    style: TextStyle(color: inkSoft, fontSize: 12),
                  ),
                  trailing: TextButton(
                    onPressed: () =>
                        unawaited(AdultSectionGate.refreshFromServer()),
                    child: const Text('Check again'),
                  ),
                ),
              ),
              // v1.4.2: once the triple lock is open, the section gets a real
              // entry point on the page that reports the unlock — the disguised
              // Settings tile ("Late Night" while private mode is on) is far
              // too easy to miss.
              ValueListenableBuilder<bool>(
                valueListenable: AdultSectionGate.visible,
                builder: (context, open, _) {
                  if (!open) return const SizedBox.shrink();
                  return ListTile(
                    leading: const Icon(
                      Icons.local_fire_department_rounded,
                      color: Color(0xFFE50914),
                    ),
                    title: Text(
                      'Open 18+ Heaven',
                      style: TextStyle(color: ink),
                    ),
                    subtitle: Text(
                      'Adult-only shelves, one tap away. Also in Settings as '
                      '"Late Night" while private mode is on.',
                      style: TextStyle(color: inkSoft, fontSize: 12),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: inkSoft,
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AdultHeavenPage(),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              _sectionTitle('Danger zone'),
              ListTile(
                leading: Icon(
                  Icons.delete_forever_rounded,
                  color: isLight ? PrismAccent.text(isLight) : Colors.redAccent,
                ),
                title: Text(
                  'Delete my cloud data',
                  style: TextStyle(color: ink),
                ),
                subtitle: Text(
                  'Removes consents, taste scores, backups, profiles, rooms, chat & legal acceptance. This device stays registered so admin blocks hold. Local app untouched.',
                  style: TextStyle(color: inkSoft, fontSize: 12),
                ),
                trailing: _deleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.chevron_right_rounded, color: inkSoft),
                onTap: _deleting
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Delete cloud data?'),
                            content: const Text(
                              'This cannot be undone. Your local app keeps working.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        setState(() => _deleting = true);
                        final done = await CloudAuthService.deleteCloudData();
                        setState(() => _deleting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                done
                                    ? 'Cloud data deleted.'
                                    : 'Delete failed — try later.',
                              ),
                            ),
                          );
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Birth-year dialog → the ONLY path that can open the local lock.
  Future<void> _verifyAge() async {
    final year = await showDialog<int>(
      context: context,
      builder: (_) => const _BirthYearDialog(),
    );
    if (year == null || !mounted) return;

    final result = await AdultSectionGate.submitBirthYear(year);
    if (!mounted) return;
    unawaited(AdultSectionGate.refreshFromServer());

    final open = AdultSectionGate.visible.value;
    String message;
    switch (result) {
      case AgeGateResult.granted:
        message = open
            ? '18+ Heaven unlocked ✓'
            : 'Age confirmed. Waiting for admin allow on this device.';
      case AgeGateResult.underage:
        final left = AdultSectionGate.attemptsLeft.value;
        message = left == 1
            ? 'You must be ${AdultSectionGate.minAge}+ to continue. 1 try left before a 24h lock.'
            : 'You must be ${AdultSectionGate.minAge}+ to continue. $left tries left before a 24h lock.';
      case AgeGateResult.lockedOut:
        final left = AdultSectionGate.describeCooldown(
          AdultSectionGate.lockRemaining(),
        );
        message = 'Too many underage attempts. Try again in $left.';
      case AgeGateResult.kidsProfile:
        message = 'Kids profiles can never open the 18+ section.';
      case AgeGateResult.invalidYear:
        message = 'That birth year does not look right.';
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _lockAdultSection() async {
    await AdultSectionGate.setLocalConfirmed(false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Adult section locked. Birth year forgotten on this device.'),
      ),
    );
  }

  Widget _sectionTitle(String t) {
    final isLight = AppThemeService.currentPalette.value.isLight;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
      child: Text(
        t,
        style: TextStyle(
          color: isLight ? PrismLight.inkSoft : Colors.white70,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  /// Short device tag for the status line. Crash-safe: never throws on
  /// short/unexpected ids (old substring(0,8) assumed ≥8 chars).
  String _shortDeviceId(String? id) {
    if (id == null || id.isEmpty) return 'Device ID: —…';
    final head = id.length >= 8 ? id.substring(0, 8) : id;
    return 'Device ID: $head…';
  }
}

/// Birth-year prompt. Returns the entered year, or null on cancel.
///
/// Only structurally impossible input (non-numeric, out of the plausible
/// range) is rejected here — an underage year is handed back to
/// [AdultSectionGate.submitBirthYear] so the attempt is counted and the
/// cooling-off can engage.
class _BirthYearDialog extends StatefulWidget {
  const _BirthYearDialog();

  @override
  State<_BirthYearDialog> createState() => _BirthYearDialogState();
}

class _BirthYearDialogState extends State<_BirthYearDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final year = int.tryParse(_controller.text.trim());
    if (year == null) {
      setState(() => _error = 'Enter a four-digit year.');
      return;
    }
    if (!AdultSectionGate.isPlausibleYear(year)) {
      setState(
        () => _error =
            'Enter a year between ${DateTime.now().year - AdultSectionGate.maxAge} and ${DateTime.now().year}.',
      );
      return;
    }
    Navigator.pop(context, year);
  }

  @override
  Widget build(BuildContext context) {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    return AlertDialog(
      title: const Text('Confirm your age'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The 18+ section is adults only. Enter your birth year — it is stored on this device only and is never uploaded.',
            style: TextStyle(color: inkSoft, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 4,
            style: TextStyle(color: ink),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Birth year',
              errorText: _error,
              counterText: '',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Confirm')),
      ],
    );
  }
}
