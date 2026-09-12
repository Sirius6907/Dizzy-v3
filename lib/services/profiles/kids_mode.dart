import 'package:flutter/material.dart';

/// Polish P15 — kids mode recognition in ONE place.
///
/// Done rule: bacche wala profile kholte hi pehchana jaye.
/// Kids profiles get a gold ring + cub badge everywhere avatars show.
/// (Full light-theme pass stays follow-up — app is dark-first.)
abstract final class KidsMode {
  const KidsMode._();

  /// Kids accent — warm gold, never the adult brand purple.
  static const Color kKidsAccent = Color(0xFFFFC107);

  /// Badge shown on kids avatars.
  static const String kKidsBadge = '🧒';

  /// Short identity line under the profile name.
  static String subtitle({required bool isKids, required bool hasPin}) {
    final who = isKids ? 'Kids profile' : 'Profile';
    final lock = hasPin ? 'PIN protected' : 'No PIN';
    return '$who · $lock';
  }

  /// Easy-English hello on profile switch.
  static String hello(String name, {required bool isKids}) =>
      isKids ? 'Hi $name! Pick something fun.' : 'Hi $name!';

  /// Avatar ring color — gold for kids, transparent otherwise.
  static Color ring({required bool isKids}) =>
      isKids ? kKidsAccent : Colors.transparent;
}
