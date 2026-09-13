import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UX6 — Dynamic Theming: custom hex accent + AMOLED true black + blur slider.
///
/// Pure helpers are unit-testable; notifiers drive the UI live.
abstract final class CustomAccentService {
  static const _keyHex = 'ux6_custom_accent_hex';
  static const _keyAmoled = 'ux6_amoled_true_black';
  static const _keyBlur = 'ux6_backdrop_blur';

  /// Currently active custom accent (null = use palette default).
  static final ValueNotifier<Color?> customAccent =
      ValueNotifier<Color?>(null);

  /// AMOLED true black (pure 0x000000 backgrounds) for OLED battery saving.
  static final ValueNotifier<bool> amoledTrueBlack =
      ValueNotifier<bool>(false);

  /// Backdrop blur intensity 0..24 (default 12).
  static final ValueNotifier<double> backdropBlur =
      ValueNotifier<double>(12.0);

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hex = prefs.getString(_keyHex);
      if (hex != null && hex.isNotEmpty) {
        final c = tryParseHex(hex);
        if (c != null) customAccent.value = c;
      }
      amoledTrueBlack.value = prefs.getBool(_keyAmoled) ?? false;
      backdropBlur.value =
          (prefs.getDouble(_keyBlur) ?? 12.0).clamp(0.0, 24.0);
    } catch (_) {}
  }

  static Future<void> setCustomAccent(Color? c) async {
    customAccent.value = c;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (c == null) {
        await prefs.remove(_keyHex);
      } else {
        await prefs.setString(_keyHex, toHex(c));
      }
    } catch (_) {}
  }

  static Future<void> setAmoled(bool on) async {
    amoledTrueBlack.value = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAmoled, on);
    } catch (_) {}
  }

  static Future<void> setBlur(double v) async {
    final clamped = v.clamp(0.0, 24.0);
    backdropBlur.value = clamped;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyBlur, clamped);
    } catch (_) {}
  }

  /// Parses "#RRGGBB", "RRGGBB", "#AARRGGBB" -> Color. Null when invalid.
  static Color? tryParseHex(String raw) {
    var hex = raw.trim().replaceAll('#', '').replaceAll(' ', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return null;
    return Color(v);
  }

  static String toHex(Color c) {
    final a = (c.a * 255).round() & 0xFF;
    final r = (c.r * 255).round() & 0xFF;
    final g = (c.g * 255).round() & 0xFF;
    final b = (c.b * 255).round() & 0xFF;
    final full =
        '${a.toRadixString(16).padLeft(2, '0')}${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
    // Drop opaque alpha for the short user-facing form.
    if (full.startsWith('ff')) return '#${full.substring(2)}'.toUpperCase();
    return '#$full'.toUpperCase();
  }

  /// Effective scaffold: pure black when AMOLED is ON.
  static Color effectiveScaffold(Color base) =>
      amoledTrueBlack.value ? const Color(0xFF000000) : base;

  static Color effectiveCard(Color base) =>
      amoledTrueBlack.value ? const Color(0xFF0A0A0A) : base;
}
