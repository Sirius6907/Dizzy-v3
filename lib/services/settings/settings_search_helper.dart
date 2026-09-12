import 'package:flutter/material.dart';

/// Polish P8 — in-settings search in ONE place (pure logic + entries).
///
/// Done rule: koi setting 3 taps se door nahi
/// (search icon → type → tap result).
class SettingSearchEntry {
  final String title;
  final String subtitle;
  final String keywords;
  final IconData icon;
  final WidgetBuilder open;

  const SettingSearchEntry({
    required this.title,
    required this.subtitle,
    this.keywords = '',
    required this.icon,
    required this.open,
  });
}

abstract final class SettingsSearchHelper {
  const SettingsSearchHelper._();

  /// True when [query] matches title/subtitle/keywords (case-insensitive).
  /// Empty query matches everything (shows full list).
  static bool matches(String query, SettingSearchEntry entry) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay =
        '${entry.title} ${entry.subtitle} ${entry.keywords}'.toLowerCase();
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  static List<SettingSearchEntry> filter(
    String query,
    List<SettingSearchEntry> entries,
  ) =>
      entries.where((e) => matches(query, e)).toList();
}
