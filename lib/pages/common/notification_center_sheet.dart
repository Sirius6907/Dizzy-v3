import 'package:flutter/material.dart';

import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/design/prism_shadows.dart';
import 'package:dizzy/design/prism_tokens.dart';
import 'package:dizzy/services/theme/app_theme_service.dart';
import 'package:dizzy/services/notification/notification_history.dart';
import 'package:dizzy/services/notification/notification_inbox.dart';
import 'package:dizzy/services/notification/notification_prefs.dart';
import 'package:dizzy/services/notification/notification_service.dart';

/// Phase J3 — the Notification Center: local history (capped at 50) plus
/// the per-type / quiet-hours controls, all in one place.
class NotificationCenterSheet extends StatefulWidget {
  const NotificationCenterSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const NotificationCenterSheet(),
  );

  @override
  State<NotificationCenterSheet> createState() =>
      _NotificationCenterSheetState();
}

class _NotificationCenterSheetState extends State<NotificationCenterSheet> {
  List<InboxItem> _remote = const <InboxItem>[];

  @override
  void initState() {
    super.initState();
    NotificationInbox.load();
    NotificationHistory.fetch().then((rows) {
      if (!mounted) return;
      setState(() => _remote = rows);
    });
    // The saved gate arrives asynchronously — refresh the toggles with it.
    NotificationService.initialize().then((_) {
      if (!mounted) return;
      setState(() => _gateNotifier.value = NotificationService.gate);
    });
  }

  String _when(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today =
        now.year == d.year && now.month == d.month && now.day == d.day;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    if (today) return 'Today $hh:$mm';
    return '${d.day}/${d.month} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final isLight = AppThemeService.currentPalette.value.isLight;
    final ink = isLight ? PrismLight.ink : DizzyVoid.bone;
    final inkSoft = isLight ? PrismLight.inkSoft : DizzyVoid.ash;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        gradient: PrismShadows.surfaceGradient(
          AppThemeService.currentPalette.value.isLight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(DizzyRadius.lg),
          topRight: Radius.circular(DizzyRadius.lg),
        ),
        boxShadow: PrismShadows.floating(
          isLight: AppThemeService.currentPalette.value.isLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: DizzySpace.sm),
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                gradient: PrismShadows.pressedGradient(
                  AppThemeService.currentPalette.value.isLight,
                ),
                borderRadius: BorderRadius.circular(3),
                boxShadow: PrismShadows.pressed(
                  isLight: AppThemeService.currentPalette.value.isLight,
                  scale: 0.5,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(DizzySpace.md),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: DizzyGlow.beam,
                ),
                const SizedBox(width: DizzySpace.sm),
                Text(
                  'Notifications',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    await NotificationInbox.clear();
                    setState(() {});
                  },
                  child: const Text('Clear all'),
                ),
              ],
            ),
          ),

          // ── Controls ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DizzySpace.md),
            child: _controls(),
          ),
          const SizedBox(height: DizzySpace.sm),

          // ── History ───────────────────────────────────────────────────
          Expanded(
            child: ValueListenableBuilder<List<InboxItem>>(
              valueListenable: NotificationInbox.items,
              builder: (context, items, _) {
                final merged = NotificationHistory.merge(
                  items,
                  _remote,
                  clearBeforeMs: NotificationInbox.clearedAtMs,
                );
                if (merged.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(DizzySpace.lg),
                      child: Text(
                        'Nothing yet.\nNew releases, download news and messages\nland here.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: inkSoft,
                          height: 1.5,
                        ),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    DizzySpace.md,
                    0,
                    DizzySpace.md,
                    DizzySpace.lg,
                  ),
                  itemCount: merged.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: DizzySpace.sm),
                  itemBuilder: (context, i) {
                    final it = merged[i];
                    final panel = isLight
                        ? PrismLight.raisedTop
                        : DizzyVoid.voidB.withValues(alpha: 0.85);
                    final well = isLight
                        ? PrismLight.raisedBottom
                        : DizzyVoid.voidB.withValues(alpha: 0.45);
                    final hairline = isLight
                        ? PrismLight.borderSubtle
                        : DizzyVoid.surface3.withValues(alpha: 0.35);
                    return Container(
                      decoration: BoxDecoration(
                        color: it.read ? well : panel,
                        borderRadius: BorderRadius.circular(DizzyRadius.md),
                        border: Border.all(
                          color: it.read
                              ? hairline
                              : (isLight
                                    ? PrismAccent.accent.withValues(alpha: 0.45)
                                    : DizzyGlow.beam.withValues(alpha: 0.35)),
                        ),
                      ),
                      padding: const EdgeInsets.all(DizzySpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _iconFor(it.kind),
                                size: 15,
                                color: it.read
                                    ? inkSoft
                                    : (isLight
                                          ? PrismAccent.text(true)
                                          : DizzyGlow.beam),
                              ),
                              const SizedBox(width: DizzySpace.sm),
                              Expanded(
                                child: Text(
                                  it.title,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: it.read ? inkSoft : ink,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              Text(
                                _when(it.atMs),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: inkSoft),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            it.body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: inkSoft, height: 1.35),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(NotificationKind kind) {
    switch (kind) {
      case NotificationKind.update:
        return Icons.system_update_alt_rounded;
      case NotificationKind.release:
        return Icons.local_movies_rounded;
      case NotificationKind.download:
        return Icons.download_rounded;
      case NotificationKind.social:
        return Icons.forum_rounded;
      case NotificationKind.announcement:
        return Icons.campaign_rounded;
    }
  }

  Widget _controls() {
    return ValueListenableBuilder<NotificationGate>(
      valueListenable: _gateNotifier,
      builder: (context, gate, _) {
        final isLight = AppThemeService.currentPalette.value.isLight;
        final ink = isLight ? PrismLight.ink : DizzyVoid.bone;
        final inkSoft = isLight ? PrismLight.inkSoft : DizzyVoid.ash;
        final well = isLight
            ? PrismLight.raisedBottom
            : DizzyVoid.voidB.withValues(alpha: 0.6);
        final hairline = isLight
            ? PrismLight.borderSubtle
            : DizzyVoid.surface3.withValues(alpha: 0.5);

        return Container(
          decoration: BoxDecoration(
            color: well,
            borderRadius: BorderRadius.circular(DizzyRadius.md),
            border: Border.all(color: hairline),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DizzySpace.sm,
            vertical: 4,
          ),
          child: Column(
            children: [
              for (final kind in NotificationKind.values)
                SwitchListTile.adaptive(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _channelLabel(kind),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: ink),
                  ),
                  value: gate.kindEnabled(kind),
                  onChanged: (v) async {
                    await NotificationService.setKindEnabled(kind, v);
                    _gateNotifier.value = NotificationService.gate;
                  },
                ),
              const Divider(height: DizzySpace.sm),
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Quiet hours (no banners at night)',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: ink),
                ),
                subtitle: Text(
                  gate.quietEnabled
                      ? '${NotificationGate.hhmm(gate.quietStartMinute)} → '
                            '${NotificationGate.hhmm(gate.quietEndMinute)}'
                      : 'Off',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: inkSoft),
                ),
                value: gate.quietEnabled,
                onChanged: (v) async {
                  await NotificationService.setQuietEnabled(v);
                  _gateNotifier.value = NotificationService.gate;
                  setState(() {});
                },
              ),
              if (gate.quietEnabled)
                Padding(
                  padding: const EdgeInsets.only(bottom: DizzySpace.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              _pickTime(gate.quietStartMinute, (m) async {
                                await NotificationService.setQuietWindow(
                                  m,
                                  gate.quietEndMinute,
                                );
                                _gateNotifier.value = NotificationService.gate;
                                setState(() {});
                              }),
                          child: Text(
                            'From ${NotificationGate.hhmm(gate.quietStartMinute)}',
                          ),
                        ),
                      ),
                      const SizedBox(width: DizzySpace.sm),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              _pickTime(gate.quietEndMinute, (m) async {
                                await NotificationService.setQuietWindow(
                                  gate.quietStartMinute,
                                  m,
                                );
                                _gateNotifier.value = NotificationService.gate;
                                setState(() {});
                              }),
                          child: Text(
                            'To ${NotificationGate.hhmm(gate.quietEndMinute)}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _channelLabel(NotificationKind kind) {
    switch (kind) {
      case NotificationKind.update:
        return 'App updates';
      case NotificationKind.release:
        return 'New releases';
      case NotificationKind.download:
        return 'Downloads';
      case NotificationKind.social:
        return 'Friends & messages';
      case NotificationKind.announcement:
        return 'News from Dizzy';
    }
  }

  Future<void> _pickTime(
    int current,
    Future<void> Function(int) onPicked,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null || !mounted) return;
    await onPicked(picked.hour * 60 + picked.minute);
  }
}

/// Shared notifier so the toggles refresh without a global rebuild.
final ValueNotifier<NotificationGate> _gateNotifier =
    ValueNotifier<NotificationGate>(NotificationService.gate);
