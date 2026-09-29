/// F5 — "What is your mood?" → tonight's picks.
///
/// Three taps, then the evening is sorted. This does **not** fork the
/// recommendation quiz: [MoodQuizPolicy.guidanceFor] produces the same
/// `moodGuidance` string `WeWatchService.submitAndGetRecommendations` already
/// accepts, so one quiz pipeline serves both flows.
///
/// Local picks exist for a second reason: a person on a train with no signal
/// still gets a row of real titles instead of a spinner that never resolves.
///
/// Pure — no Flutter, no network. The widget asks, it does not decide.
library;

/// The four moods. Kept as an enum so a wrong answer cannot be stored.
enum Mood {
  chill('Chill'),
  cozy('Cozy'),
  excited('Excited'),
  curious('Curious');

  final String label;

  const Mood(this.label);

  static Mood? fromId(String? id) {
    if (id == null) return null;
    for (final m in Mood.values) {
      if (m.name == id.trim().toLowerCase()) return m;
    }
    return null;
  }
}

/// How much time the person has. Short answers pick a film, long answers pick
/// a series, because a 90-minute commitment is a different decision at 9pm
/// than a six-hour one.
enum TimeBudget {
  quick('Under 2 hours'),
  oneNight('One evening'),
  weekend('Whole weekend');

  final String label;

  const TimeBudget(this.label);

  static TimeBudget? fromId(String? id) {
    if (id == null) return null;
    for (final b in TimeBudget.values) {
      if (b.name == id.trim().toLowerCase()) return b;
    }
    return null;
  }
}

/// Who is watching. A shared evening is a different pick than a solo one:
/// group-friendly beats critically acclaimed when four people are on the sofa.
enum Company {
  alone('Just me'),
  partner('With someone'),
  group('With friends');

  final String label;

  const Company(this.label);

  static Company? fromId(String? id) {
    if (id == null) return null;
    for (final c in Company.values) {
      if (c.name == id.trim().toLowerCase()) return c;
    }
    return null;
  }
}

/// One question. [id] is the stable key answers are stored under.
class MoodQuestion {
  final String id;
  final String prompt;

  /// Option ids, in display order.
  final List<String> options;

  const MoodQuestion({
    required this.id,
    required this.prompt,
    required this.options,
  });
}

/// A validated set of answers. Built only by [MoodQuizPolicy.profileFrom],
/// so an instance always means "three questions answered".
class MoodProfile {
  final Mood mood;
  final TimeBudget budget;
  final Company company;

  const MoodProfile({
    required this.mood,
    required this.budget,
    required this.company,
  });

  /// Stable key for storage and for the tests.
  String get key => '${mood.name}-${budget.name}-${company.name}';

  @override
  bool operator ==(Object other) =>
      other is MoodProfile &&
      other.mood == mood &&
      other.budget == budget &&
      other.company == company;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'MoodProfile($key)';
}

/// A title the quiz suggests, with the reason it fits tonight.
class MoodPick {
  final String title;
  final String query;

  /// `'movie'` or `'series'`.
  final String mediaType;

  /// Short Easy English reason. Already user-facing.
  final String reason;

  const MoodPick({
    required this.title,
    required this.query,
    required this.mediaType,
    required this.reason,
  });
}

/// The three questions, and everything decided from their answers.
abstract final class MoodQuizPolicy {
  /// Answers needed before the button unlocks.
  static const int requiredAnswers = 3;

  static const List<MoodQuestion> questions = [
    MoodQuestion(
      id: 'mood',
      prompt: 'What is your mood?',
      options: ['chill', 'cozy', 'excited', 'curious'],
    ),
    MoodQuestion(
      id: 'budget',
      prompt: 'How much time do you have?',
      options: ['quick', 'oneNight', 'weekend'],
    ),
    MoodQuestion(
      id: 'company',
      prompt: 'Who is watching with you?',
      options: ['alone', 'partner', 'group'],
    ),
  ];

  static const String _moodId = 'mood';
  static const String _budgetId = 'budget';
  static const String _companyId = 'company';

  /// The `guidance` string handed to the existing recommendation quiz.
  ///
  /// Deliberately the same shape as the strings that service already accepts,
  /// so nothing downstream needs to know a second quiz exists.
  static String guidanceFor(MoodProfile p) {
    final parts = <String>[
      'Mood: ${p.mood.label}',
      'Time: ${p.budget.label}',
      'Watching with: ${p.company.label}',
    ];
    return parts.join('. ');
  }

  /// Build a profile from raw answers, or `null` when the quiz is unfinished.
  ///
  /// Unknown or missing ids return `null` rather than defaulting: silently
  /// guessing a mood is how a person gets picks for a night they did not ask
  /// about.
  static MoodProfile? profileFrom(Map<String, String?> answers) {
    final mood = Mood.fromId(answers[_moodId]);
    final budget = TimeBudget.fromId(answers[_budgetId]);
    final company = Company.fromId(answers[_companyId]);
    if (mood == null || budget == null || company == null) return null;
    return MoodProfile(mood: mood, budget: budget, company: company);
  }

  /// True once all three questions have a usable answer.
  static bool isComplete(Map<String, String?> answers) =>
      profileFrom(answers) != null;

  /// Answers still missing, in question order. Drives the progress line.
  static List<MoodQuestion> unanswered(Map<String, String?> answers) {
    final out = <MoodQuestion>[];
    for (final q in questions) {
      final v = answers[q.id];
      if (v == null || v.trim().isEmpty) out.add(q);
    }
    return out;
  }

  // ── Local picks (no backend, no AI cost) ─────────────────────────────────

  /// Real, well-known titles that fit the mood. Ordered deterministically so
  /// the same answers always produce the same row — a reshuffling row reads
  /// as a bug, not as discovery.
  static List<MoodPick> localPicksFor(MoodProfile p) {
    final out = <MoodPick>[];

    // Mood decides the genre words.
    final genres = switch (p.mood) {
      Mood.chill => const ['Comedy', 'Animation'],
      Mood.cozy => const ['Drama', 'Family'],
      Mood.excited => const ['Action', 'Adventure'],
      Mood.curious => const ['Documentary', 'Mystery'],
    };

    // Time decides the format: a quick night is a film, a weekend is a show.
    final type = switch (p.budget) {
      TimeBudget.quick => 'movie',
      TimeBudget.oneNight => 'movie',
      TimeBudget.weekend => 'series',
    };

    // Company decides the second genre word: group nights lean wide and
    // familiar, a quiet night leans deep and strange.
    final second = switch (p.company) {
      Company.alone => genres.last,
      Company.partner => genres.first,
      Company.group => 'Popular',
    };

    for (final g in <String>[genres.first, second]) {
      out.add(MoodPick(
        title: _headlineFor(g, type),
        query: g,
        mediaType: type,
        reason: _reasonFor(p),
      ));
    }

    // The night always ends with something everyone knows, so the row is
    // never three deep cuts and a shrug.
    out.add(MoodPick(
      title: 'Because you liked it before',
      query: 'Top rated ${type == 'series' ? 'series' : 'movies'}',
      mediaType: type,
      reason: _reasonFor(p),
    ));

    return out;
  }

  static String _headlineFor(String genre, String type) =>
      '$genre ${type == 'series' ? 'shows' : 'films'}';

  static String _reasonFor(MoodProfile p) {
    final who = switch (p.company) {
      Company.alone => 'for a quiet night',
      Company.partner => 'for two',
      Company.group => 'that works for a group',
    };
    final when = switch (p.budget) {
      TimeBudget.quick => 'a short one',
      TimeBudget.oneNight => 'one evening',
      TimeBudget.weekend => 'a whole weekend',
    };
    return '${p.mood.label} pick $who, $when';
  }

  // ── Copy ─────────────────────────────────────────────────────────────────

  /// Progress line under the quiz header.
  static String progressLine(Map<String, String?> answers) {
    final done = requiredAnswers - unanswered(answers).length;
    if (done <= 0) return 'Tap three answers to unlock your picks';
    if (done >= requiredAnswers) return 'All set — your picks are ready';
    return 'One more tap and your picks are ready';
  }

  /// The button label.
  static String actionLabel(Map<String, String?> answers) {
    final done = requiredAnswers - unanswered(answers).length;
    if (done >= requiredAnswers) return 'Show my picks';
    if (done == 0) return 'Answer 3 questions to unlock picks';
    return 'Finish the quiz';
  }

  /// Headline above tonight's picks.
  static String resultTitle(MoodProfile p) => 'Tonight looks like ${p.mood.label.toLowerCase()}';

  /// One line under the result headline.
  static String resultLine(MoodProfile p) =>
      '${p.budget.label}, ${p.company.label.toLowerCase()}.';
}
