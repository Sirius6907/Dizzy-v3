import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/services/cloud/announcement_service.dart';
import 'package:dizzy/services/cloud/remote_config_service.dart';
import 'package:dizzy/services/updater/update_gate.dart';

/// Phase E1+E4 — single home banner slot above the hero row:
///   1. update-required banner with grace countdown (UpdateGate == banner)
///   2. live announcements (AnnouncementService.active) — per-id dismiss
///   3. activeNotice row — dismissed while the text stays the same
/// Returns SizedBox.shrink() when nothing is showing, so the home layout
/// never changes height in the common case. Dismissals persist in prefs.
class HomeNoticeBanner extends StatefulWidget {
  const HomeNoticeBanner({super.key});

  @override
  State<HomeNoticeBanner> createState() => _HomeNoticeBannerState();
}

class _HomeNoticeBannerState extends State<HomeNoticeBanner> {
  static const _kDismissedAnns = 'dismissed_announcements_v1';
  static const _kDismissedNotice = 'dismissed_notice_v1';

  UpdateGateResult _gate = const UpdateGateResult(UpdateGateLevel.none);
  Set<String> _dismissedAnns = {};
  String _dismissedNotice = '';

  @override
  void initState() {
    super.initState();
    _loadDismissals();
    _refreshGate();
    RemoteConfigService.revision.addListener(_refreshGate);
  }

  @override
  void dispose() {
    RemoteConfigService.revision.removeListener(_refreshGate);
    super.dispose();
  }

  Future<void> _loadDismissals() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kDismissedAnns);
      final Set<String> anns = raw == null
          ? <String>{}
          : (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
      final notice = prefs.getString(_kDismissedNotice) ?? '';
      if (mounted) {
        setState(() {
          _dismissedAnns = anns;
          _dismissedNotice = notice;
        });
      }
    } catch (_) {}
  }

  Future<void> _refreshGate() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final gate = UpdateGate.evaluate(
        currentVersion: pkg.version,
        minVersion: RemoteConfigService.minAppVersion,
        forceAfter: RemoteConfigService.forceAfter,
        now: DateTime.now(),
      );
      if (mounted) setState(() => _gate = gate);
    } catch (_) {}
  }

  Future<void> _dismissAnn(String id) async {
    setState(() => _dismissedAnns = {..._dismissedAnns, id});
    try {
      final prefs = await SharedPreferences.getInstance();
      final keep = _dismissedAnns.take(50).toList();
      await prefs.setString(_kDismissedAnns, jsonEncode(keep));
    } catch (_) {}
  }

  Future<void> _dismissNotice(String text) async {
    setState(() => _dismissedNotice = text);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDismissedNotice, text);
    } catch (_) {}
  }

  Widget _row({
    required Color accent,
    required IconData icon,
    required String text,
    required String sub,
    required VoidCallback onDismiss,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: DizzySpace.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: DizzySpace.md,
        vertical: DizzySpace.sm,
      ),
      decoration: BoxDecoration(
        color: DizzyVoid.surface1.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(DizzyRadius.lg),
        border: Border.all(color: accent.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: DizzySpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    color: DizzyVoid.bone,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: TextStyle(
                      color: DizzyVoid.bone.withValues(alpha: 0.65),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: DizzyVoid.bone.withValues(alpha: 0.6),
            ),
            tooltip: 'Hide',
          ),
        ],
      ),
    );
  }

  String _countdown(Duration d) {
    if (d.inDays > 0) return '${d.inDays} day${d.inDays == 1 ? '' : 's'} left';
    if (d.inHours > 0) {
      return '${d.inHours} hour${d.inHours == 1 ? '' : 's'} left';
    }
    if (d.inMinutes > 0) return '${d.inMinutes} min left';
    return 'moments left';
  }

  @override
  Widget build(BuildContext context) {
    // E4: live rebuild when admin pushes a new announcement.
    return ValueListenableBuilder<List<AppAnnouncement>>(
      valueListenable: AnnouncementService.active,
      builder: (context, _, __) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final children = <Widget>[];

    // 1. Force-update banner with grace countdown (E1). Required updates
    // carry no dismiss button — they stay until the version is updated.
    if (_gate.isBanner) {
      final fa = _gate.forceAfter;
      children.add(
        Container(
          margin: const EdgeInsets.only(bottom: DizzySpace.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: DizzySpace.md,
            vertical: DizzySpace.sm,
          ),
          decoration: BoxDecoration(
            color: DizzyVoid.surface1.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(DizzyRadius.lg),
            border: Border.all(color: DizzyGlow.gold.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.system_update_alt_rounded,
                color: DizzyGlow.gold,
                size: 20,
              ),
              const SizedBox(width: DizzySpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fa == null
                          ? 'Update available — v${_gate.minVersion} or newer'
                          : 'Update to v${_gate.minVersion} — required soon',
                      style: const TextStyle(
                        color: DizzyVoid.bone,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      fa == null
                          ? 'Get the newest version when you can.'
                          : 'In ${_countdown(fa.difference(DateTime.now()))} '
                                'this update becomes required.',
                      style: TextStyle(
                        color: DizzyVoid.bone.withValues(alpha: 0.65),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Live announcements with per-id dismiss (E4).
    final anns = AnnouncementService.active.value
        .where((a) => !_dismissedAnns.contains(a.id))
        .toList();
    for (final a in anns) {
      children.add(
        _row(
          accent: DizzyGlow.beam,
          icon: Icons.campaign_outlined,
          text: a.title,
          sub: a.body,
          onDismiss: () => _dismissAnn(a.id),
        ),
      );
    }

    // 3. activeNotice row — dismiss keyed by text so a NEW notice re-shows.
    final notice = RemoteConfigService.activeNotice;
    if (notice.isNotEmpty && notice != _dismissedNotice) {
      children.add(
        _row(
          accent: DizzyVoid.bone,
          icon: Icons.info_outline_rounded,
          text: notice,
          sub: '',
          onDismiss: () => _dismissNotice(notice),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DizzySpace.md,
        DizzySpace.sm,
        DizzySpace.md,
        0,
      ),
      child: Column(children: children),
    );
  }
}
