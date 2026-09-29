import 'package:flutter/material.dart';

import '../../design/dizzy_tactile.dart';
import '../../design/dizzy_tokens.dart';
import '../../services/calendar/reminder_schedule.dart';
import '../../services/calendar/reminder_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../widgets/common/notify.dart';
import '../../widgets/tactile/dizzy_tactile_card.dart';

/// F5 — "Tell me when the next one is on."
///
/// A person follows an episode, gets one quiet nudge before it airs, and can
/// take it back with the same tap. No account: the follow list lives on this
/// phone, which is also the phone that shows the alert.
///
/// The screen shows what is scheduled and nothing more — no settings maze,
/// no toggle grid. Following something is one tap; stopping it is the same
/// tap on the same row.
class RemindersSheet extends StatefulWidget {
  const RemindersSheet({super.key});

  /// Show the sheet. Returns nothing: the person came to look, not to
  /// configure.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const RemindersSheet(),
    );
  }

  @override
  State<RemindersSheet> createState() => _RemindersSheetState();
}

class _RemindersSheetState extends State<RemindersSheet> {
  final _service = ReminderService.instance;

  @override
  void initState() {
    super.initState();
    _service.follows.addListener(_onFollowsChanged);
    _service.schedule.addListener(_onFollowsChanged);
  }

  @override
  void dispose() {
    _service.follows.removeListener(_onFollowsChanged);
    _service.schedule.removeListener(_onFollowsChanged);
    super.dispose();
  }

  void _onFollowsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle(FollowedShow show) async {
    final on = await _service.toggle(show);
    if (!mounted) return;
    DizzyNotify.show(
      context,
      on ? ReminderCopy.saved : 'Alert removed for ${show.showTitle}.',
      tone: on ? NotifyTone.success : NotifyTone.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final follows = _service.follows.value;
    final next = _service.next;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        decoration: BoxDecoration(
          color: DizzyVoid.voidA,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(DizzyRadius.xl),
          ),
          // Not const: DizzyEdge.hairline is a theme-aware getter.
          border: Border(top: DizzyEdge.hairline),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            DizzySpace.md,
            DizzySpace.md,
            DizzySpace.md,
            DizzySpace.lg,
          ),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: DizzyVoid.ash.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: DizzySpace.md),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    ReminderCopy.title,
                    style: TextStyle(
                      color: DizzyVoid.bone,
                      fontSize: DizzyType.title,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  follows.isEmpty
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_active_outlined,
                  color: follows.isEmpty ? DizzyVoid.ash : palette.primaryColor,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: DizzySpace.xxs),
            Text(
              ReminderCopy.nextLine(next),
              style: const TextStyle(
                color: DizzyVoid.ash,
                fontSize: DizzyType.body,
              ),
            ),
            const SizedBox(height: DizzySpace.md),
            if (follows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: DizzySpace.lg),
                child: Text(
                  ReminderCopy.empty,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: DizzyVoid.ash,
                    fontSize: DizzyType.body,
                  ),
                ),
              )
            else ...[
              Text(
                ReminderCopy.following(follows.length),
                style: const TextStyle(
                  color: DizzyVoid.ash,
                  fontSize: DizzyType.caption,
                ),
              ),
              const SizedBox(height: DizzySpace.xs),
              for (final f in follows)
                Padding(
                  padding: const EdgeInsets.only(bottom: DizzySpace.xs),
                  child: _FollowRow(
                    show: f,
                    scheduled: next != null && next.id == f.key,
                    onToggle: () => _toggle(f),
                  ),
                ),
              const SizedBox(height: DizzySpace.xs),
              Text(
                ReminderCopy.saved,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: DizzyVoid.ash.withValues(alpha: 0.7),
                  fontSize: DizzyType.caption,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FollowRow extends StatelessWidget {
  final FollowedShow show;
  final bool scheduled;
  final VoidCallback onToggle;

  const _FollowRow({
    required this.show,
    required this.scheduled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;

    return DizzyTactileCard(
      padding: const EdgeInsets.symmetric(
        horizontal: DizzySpace.md,
        vertical: DizzySpace.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  show.showTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: DizzyVoid.bone,
                    fontSize: DizzyType.body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${ReminderSchedule.episodeCode(show.season, show.episode)} · '
                  '${show.leadMinutes} min before',
                  style: const TextStyle(
                    color: DizzyVoid.ash,
                    fontSize: DizzyType.caption,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DizzySpace.xs),
          Semantics(
            button: true,
            label: 'Stop alert for ${show.showTitle}',
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(DizzyRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: scheduled
                      ? palette.primaryColor.withValues(alpha: 0.18)
                      : DizzyVoid.surface2,
                  borderRadius: BorderRadius.circular(DizzyRadius.pill),
                  border: Border.all(
                    color: scheduled ? palette.primaryColor : DizzyEdge.hairline.color,
                  ),
                ),
                child: Text(
                  scheduled ? ReminderCopy.on : ReminderCopy.off,
                  style: TextStyle(
                    color: scheduled ? DizzyVoid.bone : DizzyVoid.ash,
                    fontSize: DizzyType.caption,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
