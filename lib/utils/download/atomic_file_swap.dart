import 'dart:io';

/// Moves [source] onto [targetPath] without ever leaving the user with neither
/// file. The previous target is moved aside to `.bak` first and restored if the
/// swap fails (AV lock, disk full, cross-device). Windows rename cannot
/// overwrite an existing file, hence the two steps.
Future<void> promoteFile(File source, String targetPath) async {
  final target = File(targetPath);
  final bak = File('$targetPath.bak');
  if (await bak.exists()) await bak.delete();
  final hadOld = await target.exists();
  if (hadOld) await target.rename(bak.path);
  try {
    await source.rename(targetPath);
  } catch (_) {
    if (hadOld && !await target.exists()) {
      try {
        await bak.rename(targetPath);
      } catch (_) {}
    }
    rethrow;
  }
  if (hadOld && await bak.exists()) {
    try {
      await bak.delete();
    } catch (_) {}
  }
}
