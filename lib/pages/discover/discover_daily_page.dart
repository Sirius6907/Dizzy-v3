import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/dizzy_tactile.dart';
import '../../design/dizzy_tokens.dart';
import '../../services/ai/mood_quiz_policy.dart';
import '../../services/ai/mood_quiz_service.dart';
import '../../services/calendar/reminder_schedule.dart';
import '../../services/calendar/reminder_service.dart';
import '../../services/calendar/tv_calendar_service.dart';
import '../../services/continue_watching/continue_watching_service.dart';
import '../../services/discover/discover_copy.dart';
import '../../services/discover/discover_service.dart';
import '../../services/share/native_share.dart';
import '../../services/stats/wrap_year.dart';
import '../../services/theme/app_theme_service.dart';
import '../../widgets/common/notify.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/movie/movie_card.dart';
import '../../widgets/tactile/dizzy_tactile_card.dart';
import '../music/music_page.dart';
import 'mood_quiz_sheet.dart';
import 'reminders_sheet.dart';
import 'wrap_card.dart';

/// F5 — Discover Daily.
///
/// The screen a person opens when they do not know what to watch. It answers
/// four questions in one scroll, in this order:
///
///   1. *Because you watched X* — rails from local history, free and instant.
///   2. Smart Mix — the music mixes, named here but generated in one place.
///   3. Your mood — three taps, then tonight is sorted.
///   4. New episode alerts and the year in stories.
///
/// No account is asked for anywhere on this screen, and nothing is submitted
/// to a server to draw a single rail.
class DiscoverDailyPage extends StatefulWidget {
  const DiscoverDailyPage({super.key});

  @override
  State<DiscoverDailyPage> createState() => _DiscoverDailyPageState();
}

class _DiscoverDailyPageState extends State<DiscoverDailyPage> {
  final _discover = DiscoverService.instance;
  final _quiz = MoodQuizService.instance;
  final _reminders = ReminderService.instance;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    await Future.wait([
      _quiz.initialize(),
      _reminders.initialize(),
      _discover.build(),
    ]);

    // Reminders need the calendar rows before they can say *when* an alert
    // fires, so the schedule is built after the follow list is read.
    await _refreshReminderSchedule();

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    _discover.invalidate();
    await _discover.build(forceRefresh: true);
    await _refreshReminderSchedule();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = _discover.error.value;
    });
  }

  /// Pull today's and tomorrow's airings and rebuild the alert schedule.
  Future<void> _refreshReminderSchedule() async {
    if (_reminders.follows.value.isEmpty) {
      _reminders.rebuildSchedule(airings: const [], now: DateTime.now());
      return;
    }

    final service = TvCalendarService.instance;
    final today = DateTime.now();
    final airings = <CalendarAiring>[];

    for (var d = 0; d < 2; d++) {
      final day = DateTime(today.year, today.month, today.day + d);
      try {
        final entries = await service.getEpisodesForDay(day);
        for (final e in entries) {
          airings.add(CalendarAiring(
            showTitle: e.showTitle,
            season: e.seasonNumber,
            episode: e.episodeNumber,
            episodeTitle: e.episodeTitle,
            airsAt: e.airDateTimeLocal,
          ));
        }
      } catch (e) {
        // A calendar miss must never break Discover: the alert simply has no
        // fire time yet, and the person still sees everything else.
        debugPrint('[DiscoverDaily] calendar day $d unavailable: $e');
      }
    }

    _reminders.rebuildSchedule(airings: airings, now: DateTime.now());
  }

  Future<void> _takeQuiz() async {
    final profile = await MoodQuizSheet.show(context);
    if (profile == null || !mounted) return;
    _showTonightPicks(profile);
  }

  void _showTonightPicks(MoodProfile profile) {
    final lines = MoodQuizPolicy.pickLines(_quiz.picksFor(profile));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TonightSheet(
        title: MoodQuizPolicy.resultTitle(profile),
        subtitle: MoodQuizPolicy.resultLine(profile),
        lines: lines,
      ),
    );
  }

  Future<void> _shareWrap(String text) async {
    final shared = await NativeShare.shareText(text);
    if (!mounted) return;
    if (shared) {
      DizzyNotify.show(context, 'Wrap shared.', tone: NotifyTone.success);
      return;
    }
    // The share sheet is not available everywhere (desktop falls back), so
    // the clipboard is the real answer, not a failure message.
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      DizzyNotify.show(context, 'Wrap copied.', tone: NotifyTone.success);
    } catch (_) {
      if (!mounted) return;
      DizzyNotify.show(context, 'Wrap is on screen above.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final sections = _discover.sections.value;

    return Scaffold(
      backgroundColor: DizzyVoid.voidA,
      appBar: AppBar(
        backgroundColor: DizzyVoid.voidB,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          DiscoverCopy.title,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: DizzyType.title,
            color: DizzyVoid.bone,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Column(
                      children: [
                        SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        SizedBox(height: DizzySpace.sm),
                        Text(
                          DiscoverCopy.loading,
                          style: TextStyle(
                            color: DizzyVoid.ash,
                            fontSize: DizzyType.body,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : ListView(
                padding: EdgeInsets.only(
                  bottom: 40 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  _header(),
                  if (_error != null) _errorCard(),
                  for (final s in sections) _section(s, palette.primaryColor),
                  _quizCard(),
                  _reminderCard(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DizzySpace.md,
                      DizzySpace.md,
                      DizzySpace.md,
                      0,
                    ),
                    child: WrapCard(
                      wrap: YearlyWrap.fromItems(
                        ContinueWatchingService.activeItems.value,
                      ),
                      onShare: _shareWrap,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _header() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        DizzySpace.md,
        DizzySpace.md,
        DizzySpace.md,
        DizzySpace.sm,
      ),
      child: Text(
        DiscoverCopy.tagline,
        style: TextStyle(
          color: DizzyVoid.ash,
          fontSize: DizzyType.body,
        ),
      ),
    );
  }

  Widget _errorCard() {
    final line = _error ?? DiscoverCopy.railError(null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DizzySpace.md,
        0,
        DizzySpace.md,
        DizzySpace.sm,
      ),
      child: DizzyTactileCard(
        padding: const EdgeInsets.all(DizzySpace.md),
        child: Row(
          children: [
            Expanded(
              child: Text(
                line,
                style: const TextStyle(
                  color: DizzyVoid.ash,
                  fontSize: DizzyType.body,
                ),
              ),
            ),
            const SizedBox(width: DizzySpace.xs),
            TextButton(
              onPressed: _refresh,
              child: const Text(DiscoverCopy.emptyAction),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(DiscoverSection s, Color primary) {
    final sizing = MovieCardSizing.fromWidth(MediaQuery.sizeOf(context).width);

    if (s.isMusic) {
      return _musicStrip(s, primary, sizing);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: s.title, subtitle: s.subtitle),
        const SizedBox(height: DizzySpace.sm),
        SizedBox(
          height: sizing.totalHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: sizing.sidePadding),
            itemCount: s.movies.length,
            separatorBuilder: (_, __) => SizedBox(width: sizing.spacing),
            itemBuilder: (_, i) => SizedBox(
              width: sizing.cardWidth,
              child: MovieCard(movie: s.movies[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _musicStrip(DiscoverSection s, Color primary, MovieCardSizing sizing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: s.title, subtitle: s.subtitle),
        const SizedBox(height: DizzySpace.sm),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: sizing.sidePadding),
            itemCount: s.mixes.length,
            separatorBuilder: (_, __) => const SizedBox(width: DizzySpace.sm),
            itemBuilder: (_, i) {
              final mix = s.mixes[i];
              return _MixCard(
                mix: mix,
                primary: primary,
                onTap: () => _openMix(mix),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openMix(DiscoverMix mix) async {
    if (mix.trackCount <= 0) {
      _toast(DiscoverCopy.musicEmpty);
      return;
    }
    // The mix is generated and played by the music page, which is the only
    // place in the app that knows how to start a track.
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MusicPage()),
    );
  }

  void _toast(String line) {
    if (!mounted) return;
    DizzyNotify.show(context, line);
  }

  Widget _quizCard() {
    final answers = _quiz.answers.value;
    final profile = _quiz.profile;
    final palette = AppThemeService.currentPalette.value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DizzySpace.md,
        DizzySpace.md,
        DizzySpace.md,
        0,
      ),
      child: DizzyTactileCard(
        padding: const EdgeInsets.all(DizzySpace.md),
        borderColor: profile != null
            ? palette.primaryColor.withValues(alpha: 0.35)
            : DizzyEdge.hairline.color,
        onTap: _takeQuiz,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              profile != null
                  ? MoodQuizPolicy.resultTitle(profile)
                  : DiscoverCopy.quizRailTitle,
              style: const TextStyle(
                color: DizzyVoid.bone,
                fontSize: DizzyType.subtitle,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: DizzySpace.xxs),
            Text(
              profile != null
                  ? MoodQuizPolicy.resultLine(profile)
                  : MoodQuizPolicy.progressLine(answers),
              style: const TextStyle(
                color: DizzyVoid.ash,
                fontSize: DizzyType.body,
              ),
            ),
            const SizedBox(height: DizzySpace.sm),
            Text(
              profile != null ? 'Change my picks' : DiscoverCopy.quizAction,
              style: TextStyle(
                color: palette.primaryColor,
                fontSize: DizzyType.body,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reminderCard() {
    final follows = _reminders.follows.value;
    final next = _reminders.next;
    final palette = AppThemeService.currentPalette.value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DizzySpace.md,
        DizzySpace.sm,
        DizzySpace.md,
        0,
      ),
      child: DizzyTactileCard(
        padding: const EdgeInsets.all(DizzySpace.md),
        onTap: () => RemindersSheet.show(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    ReminderCopy.title,
                    style: TextStyle(
                      color: DizzyVoid.bone,
                      fontSize: DizzyType.subtitle,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  follows.isEmpty
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_active_outlined,
                  size: 18,
                  color: follows.isEmpty ? DizzyVoid.ash : palette.primaryColor,
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
            if (follows.isEmpty) ...[
              const SizedBox(height: DizzySpace.xxs),
              Text(
                DiscoverCopy.remindersAction,
                style: TextStyle(
                  color: palette.primaryColor,
                  fontSize: DizzyType.caption,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MixCard extends StatelessWidget {
  final DiscoverMix mix;
  final Color primary;
  final VoidCallback onTap;

  const _MixCard({
    required this.mix,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: DizzyTactileCard(
        padding: const EdgeInsets.all(DizzySpace.sm),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(Icons.graphic_eq_rounded, color: primary, size: 18),
                const SizedBox(width: 6),
                Text(
                  '${mix.trackCount}',
                  style: TextStyle(
                    color: primary,
                    fontSize: DizzyType.caption,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DizzySpace.xs),
            Text(
              mix.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: DizzyVoid.bone,
                fontSize: DizzyType.body,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              mix.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: DizzyVoid.ash,
                fontSize: DizzyType.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TonightSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<String> lines;

  const _TonightSheet({
    required this.title,
    required this.subtitle,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        // Not const: DizzyEdge.hairline is a theme-aware getter.
        decoration: BoxDecoration(
          color: DizzyVoid.voidA,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(DizzyRadius.xl),
          ),
          border: Border(top: DizzyEdge.hairline),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(DizzySpace.md),
          children: [
            Text(
              title,
              style: const TextStyle(
                color: DizzyVoid.bone,
                fontSize: DizzyType.title,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: DizzySpace.xxs),
            Text(
              subtitle,
              style: const TextStyle(
                color: DizzyVoid.ash,
                fontSize: DizzyType.body,
              ),
            ),
            const SizedBox(height: DizzySpace.md),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: DizzySpace.xs),
                child: DizzyTactileCard(
                  padding: const EdgeInsets.all(DizzySpace.sm),
                  child: Text(
                    line,
                    style: const TextStyle(
                      color: DizzyVoid.bone,
                      fontSize: DizzyType.body,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
