import 'package:shared_preferences/shared_preferences.dart';

/// Phase K2 — download preferences (Easy English switches in Settings).
class DownloadPrefs {
  DownloadPrefs._();

  static const String kWifiOnly = 'download_wifi_only';

  /// Defaults ON: starting a multi-GB download on cellular is the mistake
  /// users notice only after the bill, so we hold it back until asked.
  static Future<bool> get wifiOnly async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kWifiOnly) ?? true;
  }

  static Future<void> setWifiOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kWifiOnly, value);
  }
}
