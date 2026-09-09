import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WP-P0: stable 7-digit device code per install (DIZ-4820193).
/// Random, not a fingerprint. Reinstall = new code. All failures are soft.
class DeviceIdService {
  static const keyDeviceCode = 'diz_device_code_v1';

  static final ValueNotifier<String?> deviceCode = ValueNotifier<String?>(null);

  /// 7 digits, no leading zero (range 1000000-9999999).
  static bool validCode(String? code) =>
      code != null && RegExp(r'^[1-9]\d{6}$').hasMatch(code);

  static String generateCode([Random? random]) {
    final r = random ?? Random.secure();
    return (1000000 + r.nextInt(9000000)).toString();
  }

  static String displayCode(String code) => 'DIZ-$code';

  static Future<String> initialize([Random? random]) async {
    if (validCode(deviceCode.value)) return deviceCode.value!;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(keyDeviceCode);
    if (validCode(stored)) {
      deviceCode.value = stored;
      return stored!;
    }
    final fresh = generateCode(random);
    await prefs.setString(keyDeviceCode, fresh);
    deviceCode.value = fresh;
    return fresh;
  }

  /// Pure helper for collision-retry unit tests: picks the first candidate
  /// not present in [taken]. Returns null after exhausting [candidates].
  static String? pickUniqueCode(
      List<String> candidates, Set<String> taken) {
    for (final c in candidates) {
      if (validCode(c) && !taken.contains(c)) return c;
    }
    return null;
  }
}
