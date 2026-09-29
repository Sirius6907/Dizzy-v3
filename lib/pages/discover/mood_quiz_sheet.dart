import 'package:flutter/material.dart';

import '../../design/dizzy_tactile.dart';
import '../../design/dizzy_tokens.dart';
import '../../services/ai/mood_quiz_policy.dart';
import '../../services/ai/mood_quiz_service.dart';
import '../../services/discover/discover_copy.dart';
import '../../widgets/common/notify.dart';
import '../../widgets/tactile/dizzy_tactile_card.dart';

/// F5 — the mood quiz, asked in place.
///
/// Three taps and the evening is sorted. The person can see their answers
/// and change any of them; nothing is submitted anywhere, and the picks are
/// built locally, so this works with no signal and no account.
///
/// This widget only asks and draws. Every decision — which questions, when
/// the button unlocks, what the picks say — belongs to [MoodQuizPolicy].
class MoodQuizSheet extends StatefulWidget {
  const MoodQuizSheet({super.key});

  /// Show the sheet and return the completed profile, or `null` if the
  /// person backed out without finishing.
  static Future<MoodProfile?> show(BuildContext context) {
    return showModalBottomSheet<MoodProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MoodQuizSheet(),
    );
  }

  @override
  State<MoodQuizSheet> createState() => _MoodQuizSheetState();
}

class _MoodQuizSheetState extends State<MoodQuizSheet> {
  final _service = MoodQuizService.instance;

  @override
  void initState() {
    super.initState();
    _service.answers.addListener(_onAnswersChanged);
  }

  @override
  void dispose() {
    _service.answers.removeListener(_onAnswersChanged);
    super.dispose();
  }

  void _onAnswersChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pick(String questionId, String optionId) async {
    await _service.answer(questionId, optionId);
  }

  void _done() {
    final p = _service.profile;
    if (p == null) {
      DizzyNotify.show(context, MoodQuizPolicy.actionLabel(_service.answers.value));
      return;
    }
    Navigator.of(context).pop(p);
  }

  @override
  Widget build(BuildContext context) {
    final answers = _service.answers.value;
    final ready = MoodQuizPolicy.isComplete(answers);

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        // Not const: DizzyEdge.hairline is a theme-aware getter.
        decoration: BoxDecoration(
          color: DizzyVoid.voidA,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(DizzyRadius.xl)),
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
            const Text(
              DiscoverCopy.quizRailTitle,
              style: TextStyle(
                color: DizzyVoid.bone,
                fontSize: DizzyType.title,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: DizzySpace.xxs),
            Text(
              MoodQuizPolicy.progressLine(answers),
              style: const TextStyle(color: DizzyVoid.ash, fontSize: DizzyType.body),
            ),
            const SizedBox(height: DizzySpace.md),
            for (final q in MoodQuizPolicy.questions) ...[
              _QuestionCard(
                question: q,
                answers: answers,
                labelFor: _service.optionLabel,
                onPick: (optionId) => _pick(q.id, optionId),
              ),
              const SizedBox(height: DizzySpace.sm),
            ],
            const SizedBox(height: DizzySpace.xs),
            _ReadyButton(
              label: MoodQuizPolicy.actionLabel(answers),
              ready: ready,
              onTap: _done,
            ),
            const SizedBox(height: DizzySpace.sm),
            Center(
              child: TextButton(
                onPressed: () async {
                  await _service.reset();
                },
                child: const Text(
                  'Start over',
                  style: TextStyle(color: DizzyVoid.ash, fontSize: DizzyType.caption),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final MoodQuestion question;
  final Map<String, String> answers;
  final String Function(String questionId, String optionId) labelFor;
  final ValueChanged<String> onPick;

  const _QuestionCard({
    required this.question,
    required this.answers,
    required this.labelFor,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final selected = answers[question.id];

    return DizzyTactileCard(
      padding: const EdgeInsets.all(DizzySpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.prompt,
            style: const TextStyle(
              color: DizzyVoid.bone,
              fontSize: DizzyType.subtitle,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: DizzySpace.sm),
          Wrap(
            spacing: DizzySpace.xs,
            runSpacing: DizzySpace.xs,
            children: [
              for (final optionId in question.options)
                _OptionChip(
                  label: labelFor(question.id, optionId),
                  selected: selected == optionId,
                  onTap: () => onPick(optionId),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DizzyRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? primary.withValues(alpha: 0.22)
                : DizzyVoid.surface2,
            borderRadius: BorderRadius.circular(DizzyRadius.pill),
            border: Border.all(
              color: selected ? primary : DizzyEdge.hairline.color,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? DizzyVoid.bone : DizzyVoid.ash,
              fontSize: DizzyType.body,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadyButton extends StatelessWidget {
  final String label;
  final bool ready;
  final VoidCallback onTap;

  const _ReadyButton({
    required this.label,
    required this.ready,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: ready ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: ready ? primary : DizzyVoid.surface2,
          foregroundColor: ready ? Colors.white : DizzyVoid.ash,
          padding: const EdgeInsets.symmetric(vertical: DizzySpace.md),
          shape: RoundedRectangleBorder(
            borderRadius: DizzyRadius.mdAll,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
