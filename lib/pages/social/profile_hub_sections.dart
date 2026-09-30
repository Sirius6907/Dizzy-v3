import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_button.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_card.dart';

import 'package:dizzy/services/cloud/announcement_service.dart';
import 'package:dizzy/services/cloud/cloud_client.dart';
import 'package:dizzy/services/cloud/remote_config_service.dart';
import 'package:dizzy/services/device/device_id_service.dart';
import 'package:dizzy/services/guide/guide_service.dart';

import '../settings/about_settings_page.dart';
import '../settings/appearance_settings_page.dart';
import '../settings/download_settings_page.dart';
import '../settings/privacy_settings_page.dart';
import '../settings/updates_settings_page.dart';
import '../../widgets/common/notify.dart';

/// Phase B (Profile Hub): sections under the profile header.
///
/// IA (plan §2b): My devices / Updates / Notifications / Privacy /
/// Background / Notices / App shortcuts. Every cloud call fails soft —
/// offline shows empty states, never an error. Admin badge comes from a
/// `admins` self-read (RLS), cached in a static notifier so the header
/// chip and this widget share one query.
class ProfileHubSections extends StatefulWidget {
  const ProfileHubSections({super.key});

  /// Shared admin flag — set once by the first sections load.
  static final ValueNotifier<bool> isAdmin = ValueNotifier<bool>(false);

  @override
  State<ProfileHubSections> createState() => _ProfileHubSectionsState();
}

class _ProfileHubSectionsState extends State<ProfileHubSections> {
  List<Map<String, dynamic>> _devices = [];
  bool _devicesLoaded = false;

  // Local prefs (Easy English toggles — Phase J/K wire real behavior).
  bool _notifDm = true;
  bool _notifFriend = true;
  bool _notifRoom = true;
  bool _bgAudio = true;
  bool _bgDownload = true;
  bool _bgVoice = true;

  static const _kNotifDm = 'hub_notif_dm_v1';
  static const _kNotifFriend = 'hub_notif_friend_v1';
  static const _kNotifRoom = 'hub_notif_room_v1';
  static const _kBgAudio = 'hub_bg_audio_v1';
  static const _kBgDownload = 'hub_bg_download_v1';
  static const _kBgVoice = 'hub_bg_voice_v1';

  @override
  void initState() {
    super.initState();
    _loadAdmin();
    _loadDevices();
    _loadPrefs();
  }

  Future<void> _loadAdmin() async {
    if (!CloudClient.isReady) return;
    final uid = CloudClient.db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await CloudClient.db
          .from('admins')
          .select('user_id')
          .eq('user_id', uid)
          .limit(1);
      ProfileHubSections.isAdmin.value = (rows as List).isNotEmpty;
    } catch (_) {
      // Fail-soft: no badge, never an error.
    }
  }

  Future<void> _loadDevices() async {
    if (!CloudClient.isReady) {
      if (mounted) setState(() => _devicesLoaded = true);
      return;
    }
    final uid = CloudClient.db.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _devicesLoaded = true);
      return;
    }
    try {
      final rows = await CloudClient.db
          .from('devices')
          .select(
              'device_id,device_code,platform,app_version,last_seen_at,revoked_at')
          .eq('user_id', uid)
          .order('last_seen_at', ascending: false)
          .limit(20);
      if (!mounted) return;
      setState(() {
        _devices = rows
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        _devicesLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _devicesLoaded = true);
    }
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _notifDm = p.getBool(_kNotifDm) ?? true;
        _notifFriend = p.getBool(_kNotifFriend) ?? true;
        _notifRoom = p.getBool(_kNotifRoom) ?? true;
        _bgAudio = p.getBool(_kBgAudio) ?? true;
        _bgDownload = p.getBool(_kBgDownload) ?? true;
        _bgVoice = p.getBool(_kBgVoice) ?? true;
      });
    } catch (_) {}
  }

  Future<void> _setPref(String key, bool v, void Function(bool) apply) async {
    apply(v);
    setState(() {});
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, v);
    } catch (_) {}
  }

  // ── Devices ─────────────────────────────────────────────────────

  String get _myCode => DeviceIdService.deviceCode.value ?? '';

  bool _isThisDevice(Map<String, dynamic> d) =>
      (d['device_code'] ?? '').toString().trim() == _myCode;

  void _showDevicesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: DizzyVoid.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(DizzySpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'My devices',
                style: TextStyle(
                  color: DizzyVoid.bone,
                  fontSize: DizzyType.title,
                  fontWeight: DizzyType.wBold,
                ),
              ),
              const SizedBox(height: DizzySpace.xs),
              const Text(
                'Every phone or PC signed in to your account. Remove one and it must be linked again to continue.',
                style: TextStyle(color: DizzyVoid.ash, fontSize: 13),
              ),
              const SizedBox(height: DizzySpace.md),
              if (!_devicesLoaded)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: DizzySpace.lg),
                  child: Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: DizzyGlow.beam),
                  ),
                )
              else if (_devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: DizzySpace.lg),
                  child: Center(
                    child: Text(
                      'No devices yet — open Dizzy on another phone to see it here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: DizzyVoid.ash, fontSize: 13),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _devices.length,
                    itemBuilder: (_, i) {
                      final d = _devices[i];
                      final mine = _isThisDevice(d);
                      final revoked = d['revoked_at'] != null;
                      final seen =
                          DateTime.tryParse(d['last_seen_at']?.toString() ?? '');
                      return DizzyTactileCard(
                        margin: const EdgeInsets.only(bottom: DizzySpace.sm),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              (d['platform'] ?? '').toString() == 'android'
                                  ? Icons.phone_android_rounded
                                  : Icons.computer_rounded,
                              color: DizzyVoid.ash,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        DeviceIdService.displayCode(
                                            (d['device_code'] ?? '').toString()),
                                        style: const TextStyle(
                                          color: DizzyVoid.bone,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (mine)
                                        _chip('This device', DizzyGlow.beam),
                                      if (revoked)
                                        _chip('Removed', DizzyGlow.red),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${d['app_version'] ?? 'unknown'}'
                                    '${seen != null ? ' · last seen ${_ago(seen)}' : ''}',
                                    style: const TextStyle(
                                        color: DizzyVoid.ash, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            if (!mine && !revoked)
                              DizzyTactileButton(
                                height: 30,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                                onTap: () async {
                                  final ok = await DizzyDialogs.confirm(
                                    ctx,
                                    title: 'Remove this device?',
                                    line:
                                        'It will be signed out. To use Dizzy there again, link it with a code.',
                                    confirmLabel: 'Remove',
                                    danger: true,
                                  );
                                  if (!ok || ctx.mounted != true) return;
                                  try {
                                    await CloudClient.db
                                        .from('devices')
                                        .update({
                                          'revoked_at':
                                              DateTime.now().toIso8601String(),
                                        })
                                        .eq('device_id', d['device_id']);
                                    if (!ctx.mounted) return;
                                    DizzyNotify.show(ctx, 'Device removed.',
                                        tone: NotifyTone.success);
                                    await _loadDevices();
                                    if (mounted) setState(() {});
                                  } catch (_) {
                                    if (!ctx.mounted) return;
                                    DizzyNotify.show(
                                        ctx,
                                        "Couldn't remove that device — check net.",
                                        tone: NotifyTone.warn);
                                  }
                                },
                                child: const Text(
                                  'Remove',
                                  style: TextStyle(
                                    color: DizzyGlow.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: color.withValues(alpha: 0.15),
          border: Border.fromBorderSide(BorderSide(color: color, width: 0.5)),
        ),
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );

  static String _ago(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // ── Sheets: Notifications / Background ──────────────────────────

  void _showToggleSheet({
    required String title,
    required String line,
    required List<({String label, String hint, bool value, void Function(bool) set})>
        toggles,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DizzyVoid.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(DizzySpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: DizzyVoid.bone,
                  fontSize: DizzyType.title,
                  fontWeight: DizzyType.wBold,
                ),
              ),
              const SizedBox(height: DizzySpace.xs),
              Text(line,
                  style: const TextStyle(color: DizzyVoid.ash, fontSize: 13)),
              const SizedBox(height: DizzySpace.sm),
              for (final t in toggles)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.label,
                      style: const TextStyle(
                          color: DizzyVoid.bone, fontSize: 14)),
                  subtitle: Text(t.hint,
                      style: const TextStyle(
                          color: DizzyVoid.ash, fontSize: 11)),
                  value: t.value,
                  activeThumbColor: DizzyGlow.beam,
                  onChanged: (v) {
                    t.set(v);
                    setSheet(() {});
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Builders ────────────────────────────────────────────────────

  Widget _sectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return DizzyTactileCard(
      margin: const EdgeInsets.only(bottom: DizzySpace.sm),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: DizzyGlow.beam, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      color: DizzyVoid.bone,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: DizzyVoid.ash, fontSize: 11.5)),
                ],
              ],
            ),
          ),
          trailing ??
              const Icon(Icons.chevron_right_rounded,
                  color: DizzyVoid.ash, size: 20),
        ],
      ),
    );
  }

  Widget _groupLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: DizzySpace.sm, bottom: DizzySpace.xs),
        child: Text(
          text,
          style: const TextStyle(
            color: DizzyVoid.ash,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('MY STUFF'),
        _sectionCard(
          icon: Icons.devices_rounded,
          title: 'My devices',
          subtitle: 'Phones & PCs on your account · tap to remove one',
          onTap: _showDevicesSheet,
        ),
        _sectionCard(
          icon: Icons.system_update_alt_rounded,
          title: 'Updates',
          subtitle: 'Check for the latest Dizzy version',
          onTap: () => _go(context, const UpdatesSettingsPage()),
        ),
        _groupLabel('PING ME'),
        _sectionCard(
          icon: Icons.notifications_none_rounded,
          title: 'Notifications',
          subtitle: 'Direct messages, friend requests, room invites',
          onTap: () => _showToggleSheet(
            title: 'Notifications',
            line: 'Choose what may pop up while Dizzy is open.',
            toggles: [
              (
                label: 'Direct messages',
                hint: 'New chats from friends',
                value: _notifDm,
                set: (v) => _setPref(_kNotifDm, v, (x) => _notifDm = x),
              ),
              (
                label: 'Friend requests',
                hint: 'Someone wants to add you',
                value: _notifFriend,
                set: (v) => _setPref(_kNotifFriend, v, (x) => _notifFriend = x),
              ),
              (
                label: 'Room invites',
                hint: 'Watch Together invitations',
                value: _notifRoom,
                set: (v) => _setPref(_kNotifRoom, v, (x) => _notifRoom = x),
              ),
            ],
          ),
        ),
        _groupLabel('KEEP RUNNING'),
        _sectionCard(
          icon: Icons.battery_saver_outlined,
          title: 'Background',
          subtitle: 'Music, downloads & voice when Dizzy is minimized',
          onTap: () => _showToggleSheet(
            title: 'Background',
            line: 'All ON keeps things alive when you switch apps. Battery '
                'saver settings on your phone may still pause them.',
            toggles: [
              (
                label: 'Music keeps playing',
                hint: 'Controls stay on your lock screen',
                value: _bgAudio,
                set: (v) => _setPref(_kBgAudio, v, (x) => _bgAudio = x),
              ),
              (
                label: 'Downloads continue',
                hint: 'Finish files while you are in another app',
                value: _bgDownload,
                set: (v) => _setPref(_kBgDownload, v, (x) => _bgDownload = x),
              ),
              (
                label: 'Voice stays on',
                hint: 'Watch Together mic keeps working when minimized',
                value: _bgVoice,
                set: (v) => _setPref(_kBgVoice, v, (x) => _bgVoice = x),
              ),
            ],
          ),
        ),
        _groupLabel('SAFETY & PRIVACY'),
        _sectionCard(
          icon: Icons.lock_outline_rounded,
          title: 'Privacy',
          subtitle: 'What Dizzy may collect · delete my cloud data',
          onTap: () => _go(context, const PrivacySettingsPage()),
        ),
        _groupLabel('NOTICES'),
        _buildNotices(),
        _groupLabel('APP SHORTCUTS'),
        _sectionCard(
          icon: Icons.palette_outlined,
          title: 'Appearance',
          subtitle: 'Theme, layout & feel',
          onTap: () => _go(context, const AppearanceSettingsPage()),
        ),
        _sectionCard(
          icon: Icons.download_rounded,
          title: 'Downloads',
          subtitle: 'Save location & behavior',
          onTap: () => _go(context, const DownloadSettingsPage()),
        ),
        _sectionCard(
          icon: Icons.help_outline_rounded,
          title: 'Help',
          subtitle: 'Show the guide cards again',
          onTap: () async {
            await GuideService.resetAll(
              [...GuideService.allKeys, GuideService.onboardingKey],
            );
            if (context.mounted) {
              DizzyNotify.show(context, 'Guides will show again as you go.',
                  tone: NotifyTone.success);
            }
          },
        ),
        _sectionCard(
          icon: Icons.info_outline_rounded,
          title: 'About Dizzy',
          subtitle: 'Version & credits',
          onTap: () => _go(context, const AboutSettingsPage()),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: ProfileHubSections.isAdmin,
          builder: (context, admin, _) => admin
              ? _sectionCard(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Admin Console',
                  subtitle: 'Open the fleet dashboard',
                  onTap: () async {
                    final uri = Uri.parse(
                        'https://thriving-salamander-3620d1.netlify.app');
                    try {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    } catch (_) {
                      if (context.mounted) {
                        DizzyNotify.show(
                            context, "Couldn't open the dashboard — check net.",
                            tone: NotifyTone.warn);
                      }
                    }
                  },
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// Notices = server notice text + active announcements (dismissable).
  Widget _buildNotices() {
    return ValueListenableBuilder<int>(
      valueListenable: RemoteConfigService.revision,
      builder: (context, _, __) {
        final notice = RemoteConfigService.activeNotice;
        return ValueListenableBuilder<List<AppAnnouncement>>(
          valueListenable: AnnouncementService.active,
          builder: (context, list, _) {
            if (notice.isEmpty && list.isEmpty) {
              return _sectionCard(
                icon: Icons.campaign_outlined,
                title: 'Notices',
                subtitle: 'No notices right now.',
                onTap: () {},
                trailing: const SizedBox.shrink(),
              );
            }
            return Column(
              children: [
                if (notice.isNotEmpty)
                  _sectionCard(
                    icon: Icons.campaign_outlined,
                    title: 'Important notice',
                    subtitle: notice,
                    onTap: () {},
                    trailing: const SizedBox.shrink(),
                  ),
                for (final a in list)
                  DizzyTactileCard(
                    margin: const EdgeInsets.only(bottom: DizzySpace.sm),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.notifications_active_outlined,
                            color: DizzyGlow.gold, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.title,
                                style: const TextStyle(
                                    color: DizzyVoid.bone,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700),
                              ),
                              if (a.body.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(a.body,
                                    style: const TextStyle(
                                        color: DizzyVoid.ash,
                                        fontSize: 12)),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              size: 16, color: DizzyVoid.ash),
                          onPressed: () => AnnouncementService.dismiss(a.id),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _go(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

/// Admin chip for the profile header — reads the shared notifier set by
/// [ProfileHubSections] (single `admins` self-read, RLS-gated).
class ProfileHubAdminBadge extends StatelessWidget {
  const ProfileHubAdminBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ProfileHubSections.isAdmin,
      builder: (context, admin, _) {
        if (!admin) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: DizzyGlow.gold.withValues(alpha: 0.15),
              border: const Border.fromBorderSide(
                  BorderSide(color: DizzyGlow.gold, width: 0.5)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_user_rounded,
                    size: 12, color: DizzyGlow.gold),
                SizedBox(width: 4),
                Text(
                  'ADMIN',
                  style: TextStyle(
                    color: DizzyGlow.gold,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
