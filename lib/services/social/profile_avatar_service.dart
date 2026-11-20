import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional profile photo — chosen by the person, stored on this device,
/// never uploaded. Picking is always cancellable: every failure path
/// returns a short line the caller can show or ignore, and a missing photo
/// simply falls back to the initials monogram.
abstract final class ProfileAvatarService {
  static const String _keyPath = 'profile_avatar_path_v1';

  /// Nothing bigger than this gets copied — a phone wallpaper is not an
  /// avatar, and a 40 MB PNG would stall the picker for no reason.
  static const int maxBytes = 8 * 1024 * 1024;

  /// Extensions we accept. Both spellings of JPEG because people have both
  /// and the OS tells them apart.
  static const List<String> allowedExtensions = ['jpg', 'jpeg', 'png'];

  /// Current photo path, or null when the person uses the monogram.
  /// Read by every avatar in the app so a change lands everywhere at once.
  static final ValueNotifier<String?> path = ValueNotifier<String?>(null);

  static bool get hasPhoto => (path.value ?? '').isNotEmpty;

  static File? get file {
    final value = path.value;
    if (value == null || value.isEmpty) return null;
    return File(value);
  }

  /// Boot read. A file the OS already cleaned up is dropped quietly so the
  /// avatar never shows a broken image icon.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_keyPath)?.trim() ?? '';
      if (saved.isEmpty) return;
      if (await File(saved).exists()) {
        path.value = saved;
      } else {
        await prefs.remove(_keyPath);
      }
    } catch (e) {
      debugPrint('[ProfileAvatar] initialize failed: $e');
    }
  }

  /// Opens the device picker (.jpg / .jpeg / .png) and saves the choice.
  ///
  /// Returns null when it worked or when the person simply closed the
  /// picker; returns an Easy-English line only when something went wrong.
  static Future<String?> pick() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        withData: false,
      );
      final picked = result?.files.isNotEmpty == true
          ? result!.files.single
          : null;
      final source = picked?.path;
      if (source == null || source.isEmpty) return null;

      final ext = p.extension(source).replaceFirst('.', '').toLowerCase();
      if (!allowedExtensions.contains(ext)) {
        return 'That file is not a .jpg or .png picture.';
      }

      final original = File(source);
      if (!await original.exists()) return "Couldn't read that picture.";

      final bytes = await original.length();
      if (bytes > maxBytes) return 'That picture is too big — pick one under 8 MB.';

      final docs = await getApplicationDocumentsDirectory();
      final target = p.join(docs.path, 'dizzy_avatar.$ext');

      // Same-name copy: clear the old file first so a .png replacing a
      // .jpg cannot leave two avatars behind on disk.
      await clearFiles(except: target);
      await original.copy(target);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPath, target);
      path.value = null;
      path.value = target;
      return null;
    } catch (e) {
      debugPrint('[ProfileAvatar] pick failed: $e');
      return "Couldn't open the picker. Try again.";
    }
  }

  /// Back to the monogram. Also deletes the copied file.
  static Future<void> remove() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyPath);
    } catch (e) {
      debugPrint('[ProfileAvatar] remove pref failed: $e');
    }
    path.value = null;
    await clearFiles();
  }

  /// Deletes every avatar copy this service may have written, keeping
  /// [except] when the caller is about to rewrite that exact path.
  @visibleForTesting
  static Future<void> clearFiles({String? except}) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      for (final ext in allowedExtensions) {
        final candidate = p.join(docs.path, 'dizzy_avatar.$ext');
        if (except != null && p.equals(candidate, except)) continue;
        final f = File(candidate);
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      debugPrint('[ProfileAvatar] clearFiles failed: $e');
    }
  }
}

/// Deterministic monogram source: the first letter of the name, or a
/// person glyph when there is no name at all.
String avatarInitial(String? username) {
  final clean = (username ?? '')
      .trim()
      .replaceAll('@', '')
      .replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (clean.isEmpty) return '?';
  return clean.substring(0, 1).toUpperCase();
}
