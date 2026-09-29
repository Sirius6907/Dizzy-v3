/// F5 — the mood quiz, asked and answered without leaving Discover.
///
/// The decisions are [MoodQuizPolicy]'s. This file only stores the answers
/// (on the phone, no account) and hands the same `moodGuidance` string to the
/// recommendation quiz that already exists, so there is exactly one quiz
/// pipeline in the app rather than two that drift apart.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mood_quiz_policy.dart';

/// Stores the three answers and the profile they make.
class MoodQuizService {
  MoodQuizService._();
  static final MoodQuizService instance = MoodQuizService._();

  static const String _storageKey = 'mood_quiz_answers_v1';

  final ValueNotifier<Map<String, String>> answers =
      ValueNotifier<Map<String, String>>(const {});

  static bool _loaded = false;

  /// The profile, or `null` while the quiz is unfinished.
  MoodProfile? get profile => MoodQuizPolicy.profileFrom(answers.value);

  bool get isComplete => profile != null;

  Future<void> initialize() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final out = <String, String>{};
      decoded.forEach((k, v) {
        final key = k.toString();
        // Only keep keys the current quiz still asks about, so an old saved
        // quiz can never satisfy a question that no longer exists.
        final known = MoodQuizPolicy.questions.any((q) => q.id == key);
        if (!known) return;
        out[key] = v.toString();
      });
      answers.value = out;
    } catch (_) {
      answers.value = const {};
    }
  }

  /// Record one answer. An unknown question id is ignored rather than stored:
  /// a typo must not quietly create a fourth question.
  Future<void> answer(String questionId, String optionId) async {
    final known = MoodQuizPolicy.questions.any((q) => q.id == questionId);
    if (!known) return;
    final next = Map<String, String>.from(answers.value);
    next[questionId] = optionId;
    answers.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(next));
    } catch (e) {
      debugPrint('[MoodQuizService] save failed: $e');
    }
  }

  /// Clear the quiz so the button says "take the quiz" again.
  Future<void> reset() async {
    answers.value = const {};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      debugPrint('[MoodQuizService] reset failed: $e');
    }
  }

  /// Tonight's picks. Local and free: a person on a train with no signal
  /// still gets real titles instead of a spinner that never resolves.
  List<MoodPick> picksFor(MoodProfile p) => MoodQuizPolicy.localPicksFor(p);

  /// The string the existing recommendation quiz already accepts.
  String guidanceFor(MoodProfile p) => MoodQuizPolicy.guidanceFor(p);

  /// Label under the option for [questionId].
  String optionLabel(String questionId, String optionId) {
    for (final m in Mood.values) {
      if (m.name == optionId) return m.label;
    }
    for (final b in TimeBudget.values) {
      if (b.name == optionId) return b.label;
    }
    for (final c in Company.values) {
      if (c.name == optionId) return c.label;
    }
    return optionId;
  }
}
