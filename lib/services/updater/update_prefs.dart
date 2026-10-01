import 'package:shared_preferences/shared_preferences.dart';

/// Phase I2/I3 — update preferences + last-seen release info (what's new).
class UpdatePrefs {
  UpdatePrefs._();

  static const String keyAutoDownload = 'update_auto_download';
  static const String keyWifiOnly = 'update_wifi_only';
  static const String keyLastNotesVersion = 'update_last_notes_version';
  static const String keyLastNotes = 'update_last_notes';
  static const String keyLastNotesDate = 'update_last_notes_date';

  /// Silent staged download when a newer version is offered.
  static Future<bool> get autoDownload async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(keyAutoDownload) ?? false;
  }

  static Future<void> setAutoDownload(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(keyAutoDownload, v);
  }

  /// Never stage over metered/cellular data.
  static Future<bool> get wifiOnly async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(keyWifiOnly) ?? true;
  }

  static Future<void> setWifiOnly(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(keyWifiOnly, v);
  }

  /// Caches the newest release notes so the Hub can render "What's new"
  /// without a network round-trip.
  static Future<void> rememberRelease({
    required String version,
    required String notes,
    required String publishedAt,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(keyLastNotesVersion, version);
    await p.setString(keyLastNotes, notes);
    await p.setString(keyLastNotesDate, publishedAt);
  }

  static Future<({String version, String notes, String date})?>
  lastRelease() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(keyLastNotesVersion);
    if (v == null) return null;
    return (
      version: v,
      notes: p.getString(keyLastNotes) ?? '',
      date: p.getString(keyLastNotesDate) ?? '',
    );
  }
}
