import 'package:flutter/material.dart';

import '../../services/cloud/cloud_auth_service.dart';
import '../../services/cloud/cloud_client.dart';
import '../../services/theme/app_theme_service.dart';

/// S2 (v1.1.9): Settings → Privacy. Device identity + consent toggles + delete button.
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1017),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Privacy & Account',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
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
                builder: (context, signedIn, _) => ListTile(
                  leading: Icon(Icons.devices_rounded,
                      color: palette.primaryColor),
                  title: Text(
                      signedIn ? 'Cloud connected' : 'Offline mode',
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    signedIn
                        ? 'Sync, backup & watch parties active. Device ID: ${CloudAuthService.anonId?.substring(0, 8) ?? '—'}…'
                        : 'All features work offline. Sync disabled.',
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (!CloudClient.isConfigured)
                const ListTile(
                  leading: Icon(Icons.cloud_off_rounded,
                      color: Colors.orangeAccent),
                  title: Text('Cloud not configured in this build',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                      'Sync & watch parties need a cloud-enabled build.',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                ),
              _sectionTitle('What Dizzy may collect'),
              ValueListenableBuilder<bool>(
                valueListenable: CloudAuthService.consentTelemetry,
                builder: (context, v, _) => SwitchListTile(
                  title: const Text('App experience data',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      'Install, version, platform. No watch titles.',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                  value: v,
                  onChanged: (nv) =>
                      CloudAuthService.setConsent(telemetry: nv),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: CloudAuthService.consentGenrePrefs,
                builder: (context, v, _) => SwitchListTile(
                  title: const Text('Taste preferences',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      'Genre scores (action:0.8). Never raw history.',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                  value: v,
                  onChanged: (nv) =>
                      CloudAuthService.setConsent(genrePrefs: nv),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: CloudAuthService.consentCrash,
                builder: (context, v, _) => SwitchListTile(
                  title: const Text('Crash counts',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Counts only. No personal data.',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                  value: v,
                  onChanged: (nv) =>
                      CloudAuthService.setConsent(crash: nv),
                ),
              ),
              const SizedBox(height: 8),
              _sectionTitle('Danger zone'),
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded,
                    color: Colors.redAccent),
                title: const Text('Delete my cloud data',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                    'Removes installs, consents, scores, backups, profiles. Local app untouched.',
                    style:
                        TextStyle(color: Colors.white60, fontSize: 12)),
                trailing: _deleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_right_rounded,
                        color: Colors.white60),
                onTap: _deleting
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Delete cloud data?'),
                            content: const Text(
                                'This cannot be undone. Your local app keeps working.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('Delete')),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        setState(() => _deleting = true);
                        final done =
                            await CloudAuthService.deleteCloudData();
                        setState(() => _deleting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(done
                                    ? 'Cloud data deleted.'
                                    : 'Delete failed — try later.')),
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

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 13)),
      );
}
