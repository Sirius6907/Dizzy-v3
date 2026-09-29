/// F2 — the storage-cleanup sheet: the only place a download gets trashed.
///
/// Two rules from the brief live in this file's shape:
///
///  - "Kabhi silent delete nahi" — nothing happens until a tap. The sheet
///    opens with a list of *offers*; the worst thing that can happen
///    without input is that the user sees a suggestion.
///  - "1-tap undo 7 din" — every delete leaves a live undo, and the sheet
///    keeps showing it for the whole window with a real countdown, so the
///    user knows exactly how long they have.
///
/// The sheet never deletes for them. [onTrash] and [onUndo] are callbacks
/// the downloads page supplies, so the widget has no filesystem access and
/// the "ask first" property is structural rather than a promise in a
/// comment.
library;

import 'package:flutter/material.dart';

import '../../services/download/download_trash.dart';
import '../../services/download/offline_hub_service.dart';
import '../../services/download/storage_sweep.dart';

class StorageSweepSheet extends StatelessWidget {
  final List<StorageSweepSuggestion> suggestions;
  final List<TrashEntry> undoable;
  final void Function(StorageSweepSuggestion) onTrash;
  final void Function(String taskId) onUndo;
  final VoidCallback onDismiss;

  const StorageSweepSheet({
    super.key,
    required this.suggestions,
    required this.undoable,
    required this.onTrash,
    required this.onUndo,
    required this.onDismiss,
  });

  /// Show the sheet when there is anything to say, and stay silent when
  /// there is not. Called from the downloads page on open.
  static Future<void> maybeShow(
    BuildContext context, {
    List<StorageSweepSuggestion>? suggestions,
    List<TrashEntry>? undoable,
  }) async {
    final pending = suggestions ?? OfflineHubService.instance.storageSuggestions.value;
    final undos = undoable ?? const <TrashEntry>[];
    if (pending.isEmpty && undos.isEmpty) return;
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StorageSweepSheet(
        suggestions: pending,
        undoable: undos,
        onTrash: (s) async {
          Navigator.of(sheetContext).pop();
          await OfflineHubService.instance.trashSuggested(s);
          if (context.mounted) await maybeShow(context);
        },
        onUndo: (taskId) async {
          Navigator.of(sheetContext).pop();
          await OfflineHubService.instance.undoTrash(taskId);
          if (context.mounted) await maybeShow(context);
        },
        onDismiss: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final reclaimable =
        suggestions.fold<int>(0, (sum, s) => sum + s.bytes);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                kStorageTightTitle,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                kStorageTightBody,
                style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Freeing ${_bytes(reclaimable)} once the undo time is up.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
              if (suggestions.isNotEmpty) const SizedBox(height: 12),
              for (final suggestion in suggestions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text(
                    suggestion.task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    suggestion.reclaimLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: FilledButton(
                    onPressed: () => onTrash(suggestion),
                    child: const Text('Delete'),
                  ),
                ),
              if (undoable.isNotEmpty) ...[
                const Divider(height: 24),
                const Text(
                  'Recently deleted',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                for (final entry in undoable)
                  _UndoRow(entry: entry, now: now, onUndo: onUndo),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onDismiss,
                  child: const Text('Not now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _bytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 2)} ${units[unit]}';
  }
}

class _UndoRow extends StatelessWidget {
  final TrashEntry entry;
  final DateTime now;
  final void Function(String taskId) onUndo;

  const _UndoRow({
    required this.entry,
    required this.now,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = entry.undoRemaining(now: now);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.restore_rounded),
      title: Text(
        _nameOf(entry.originalPath),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        remaining == null
            ? kStorageUndoExpired
            : 'Undo available for ${_days(remaining)} more',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: OutlinedButton(
        onPressed: remaining == null ? null : () => onUndo(entry.taskId),
        child: const Text(kStorageUndoLabel),
      ),
    );
  }

  /// File name only — the sheet shows what was deleted, not the full path
  /// of every folder the app has ever written to.
  static String _nameOf(String path) {
    final cut = path.lastIndexOf(RegExp(r'[/\\]'));
    return cut == -1 ? path : path.substring(cut + 1);
  }

  static String _days(Duration remaining) {
    if (remaining.inDays >= 1) return '${remaining.inDays} day(s)';
    final hours = remaining.inHours;
    if (hours >= 1) return '$hours hour(s)';
    return '${remaining.inMinutes} minute(s)';
  }
}
