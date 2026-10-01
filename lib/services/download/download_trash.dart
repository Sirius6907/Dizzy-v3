/// F2 — trash: the only way a download is removed, and how undo survives.
///
/// "Delete, with a 1-tap undo for 7 days" has a hard requirement hiding in
/// it: **undo cannot re-create a file it already deleted.** Re-downloading
/// is not undo — it costs the user's data again, needs the source to still
/// be alive, and fails exactly when the user needs it least (they deleted
/// it because the disk was full).
///
/// So a "delete" here is a *move*: the file goes to a `.trash` folder
/// beside the downloads, and a ledger entry remembers where from. The bytes
/// stay on disk until [kStorageUndoWindow] expires, at which point a purge
/// (bounded, and only ever for entries past the window) makes it real.
/// If the user taps Undo inside the window, the file goes back where it
/// was and the download task is restored alongside it.
///
/// This costs disk — the space is not actually free until the window
/// closes. That is the honest trade: a "7-day undo" that frees nothing
/// would be a lie. The cleanup suggestion therefore says what it will
/// reclaim *after* the window, and the purge runs on every entry into the
/// downloads screen so the space comes back on its own.
///
/// Nothing here runs without a user tap. There is no timer that deletes
/// anything the user did not ask to delete; the purge only disposes of
/// entries the user already consented to deleting.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/download/download_task_model.dart';
import '../../utils/download/download_path_helper.dart';
import 'download_service.dart';
import 'storage_sweep.dart';

/// Folder name inside the downloads directory. Leading dot keeps it out of
/// the way of the user's own file browser views.
const String kDownloadTrashFolderName = '.trash';

/// A file waiting out the undo window.
class TrashEntry {
  /// The download task's id — the key the user will see nothing of, but
  /// the handle everything else uses.
  final String taskId;

  /// Where the file was, so Undo can put it back exactly.
  final String originalPath;

  /// Where it is now.
  final String trashPath;

  /// When the user consented to the delete.
  final DateTime trashedAt;

  /// Size at the moment of the move. Real number, used for the "frees X"
  /// line and for the purge summary.
  final int bytes;

  const TrashEntry({
    required this.taskId,
    required this.originalPath,
    required this.trashPath,
    required this.trashedAt,
    required this.bytes,
  });

  bool canUndo({required DateTime now}) =>
      canUndoStorageSweep(trashedAt: trashedAt, now: now);

  Duration? undoRemaining({required DateTime now}) =>
      storageSweepUndoRemaining(trashedAt: trashedAt, now: now);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'taskId': taskId,
        'originalPath': originalPath,
        'trashPath': trashPath,
        'trashedAt': trashedAt.millisecondsSinceEpoch,
        'bytes': bytes,
      };

  static TrashEntry? fromJson(Map<String, dynamic> json) {
    final id = json['taskId'];
    final original = json['originalPath'];
    final trashed = json['trashPath'];
    final at = json['trashedAt'];
    if (id is! String || original is! String || trashed is! String || at is! int) {
      return null;
    }
    return TrashEntry(
      taskId: id,
      originalPath: original,
      trashPath: trashed,
      trashedAt: DateTime.fromMillisecondsSinceEpoch(at),
      bytes: json['bytes'] is int ? json['bytes'] as int : 0,
    );
  }
}

abstract final class DownloadTrash {
  const DownloadTrash._();

  static const _prefsKey = 'dizzy_download_trash_v1';

  /// Ledger cap. Older than [kStorageUndoWindow] entries are already past
  /// their undo, so anything beyond this is a bug, not history.
  static const int maxEntries = 50;

  static List<TrashEntry> _entries = <TrashEntry>[];
  static bool _loaded = false;

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _entries = decoded
              .whereType<Map<String, dynamic>>()
              .map(TrashEntry.fromJson)
              .whereType<TrashEntry>()
              .toList();
        }
      }
    } catch (_) {
      _entries = <TrashEntry>[];
    }
    _loaded = true;
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// Every entry still inside its undo window, newest first.
  static Future<List<TrashEntry>> undoableEntries({DateTime? now}) async {
    await _ensureLoaded();
    final at = now ?? DateTime.now();
    final live = _entries.where((e) => e.canUndo(now: at)).toList()
      ..sort((a, b) => b.trashedAt.compareTo(a.trashedAt));
    return live;
  }

  /// Bytes waiting out the undo window. Shown next to the storage gauge so
  /// the user can see that "deleted" space comes back on its own.
  static Future<int> pendingBytes({DateTime? now}) async {
    final entries = await undoableEntries(now: now);
    return entries.fold<int>(0, (sum, e) => sum + e.bytes);
  }

  /// Move [task]'s file into the trash and drop it from the task list.
  ///
  /// Returns the entry so the caller can offer Undo immediately. The
  /// download task itself is removed (the user asked for it to go), but
  /// its metadata travels with the entry, which is what makes the restore
  /// below able to bring the row back.
  static Future<TrashEntry?> trash(DownloadTask task) async {
    await _ensureLoaded();
    final file = File(task.targetFilePath);
    if (!await file.exists()) {
      // Nothing on disk to protect. Still remove the row: the user asked.
      await DownloadService.instance.deleteDownload(task.id);
      return null;
    }

    final bytes = await file.length();
    final dir = await DownloadPathHelper.getDownloadsDirectoryPath();
    final trashDir = Directory(p.join(dir, kDownloadTrashFolderName));
    if (!await trashDir.exists()) {
      await trashDir.create(recursive: true);
    }
    final target = File(p.join(trashDir.path, p.basename(task.targetFilePath)));

    try {
      // rename is instant when it works and fails across devices, which
      // is a real case here (downloads on external storage). copy+delete
      // is the slow-but-correct fallback; it is on the user-tap path, not
      // on any hot loop.
      await file.rename(target.path);
    } catch (_) {
      try {
        await file.copy(target.path);
        await file.delete();
      } catch (_) {
        // The move failed outright. Do not pretend it succeeded — leave
        // the task alone so the user still has their episode.
        return null;
      }
    }

    final entry = TrashEntry(
      taskId: task.id,
      originalPath: task.targetFilePath,
      trashPath: target.path,
      trashedAt: DateTime.now(),
      bytes: bytes,
    );
    _entries = <TrashEntry>[entry, ..._entries];
    if (_entries.length > maxEntries) {
      _entries = _entries.sublist(0, maxEntries);
    }
    await _persist();

    await DownloadService.instance.deleteDownload(task.id);
    return entry;
  }

  /// Put a trashed file back, still inside the window.
  ///
  /// Returns false once the window has closed or the file has gone — in
  /// both cases the honest answer is "no", not a re-download.
  static Future<bool> undo(String taskId, {DateTime? now}) async {
    await _ensureLoaded();
    final at = now ?? DateTime.now();
    final idx = _entries.indexWhere((e) => e.taskId == taskId);
    if (idx == -1) return false;
    final entry = _entries[idx];
    if (!entry.canUndo(now: at)) {
      await _discard(entry);
      return false;
    }

    final source = File(entry.trashPath);
    if (!await source.exists()) return false;
    final dest = File(entry.originalPath);
    try {
      if (await dest.parent.exists()) {
        await source.rename(dest.path);
      } else {
        await source.copy(dest.path);
        await source.delete();
      }
    } catch (_) {
      return false;
    }
    _entries.removeAt(idx);
    await _persist();
    return true;
  }

  /// Delete trash entries whose undo window has closed.
  ///
  /// Bounded at [_purgeLimit] files per call: this runs when the downloads
  /// screen opens, and a user who has been away for a year must not get a
  /// multi-minute freeze. Whatever is left goes on the next open.
  static const int _purgeLimit = 50;

  /// Returns how many files were actually removed.
  static Future<int> purgeExpired({DateTime? now}) async {
    await _ensureLoaded();
    final at = now ?? DateTime.now();
    final expired = _entries.where((e) => !e.canUndo(now: at)).toList();
    var removed = 0;
    for (final entry in expired.take(_purgeLimit)) {
      if (await _discard(entry)) removed++;
    }
    return removed;
  }

  /// Remove the file and the ledger row. Returns false only when the file
  /// was already gone (the row still goes — the ledger must not drift).
  static Future<bool> _discard(TrashEntry entry) async {
    bool gone = true;
    try {
      final file = File(entry.trashPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      gone = false;
    }
    _entries.removeWhere((e) => e.taskId == entry.taskId);
    await _persist();
    return gone;
  }

  @visibleForTesting
  static void resetForTest() {
    _entries = <TrashEntry>[];
    _loaded = false;
  }
}
