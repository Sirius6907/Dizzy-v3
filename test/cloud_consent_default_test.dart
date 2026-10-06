import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/cloud/cloud_auth_service.dart';

/// Crash-report consent defaults (Plan Phase 3.1).
///
/// Product rule for Dizzy: defaults ON with an Easy English off switch —
/// a fresh install must report tech errors to the admin dashboard without
/// the user hunting through settings. An explicit user choice (off) must
/// still survive a restart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh install: crash reporting consent defaults to ON', () async {
    SharedPreferences.setMockInitialValues({});
    await CloudAuthService.init();
    expect(
      CloudAuthService.consentCrash.value,
      isTrue,
      reason: 'Dizzy defaults ON — crashes reach the admin dashboard '
          'without any setup step.',
    );
  });

  test('user opted out: consent stays OFF across restart', () async {
    SharedPreferences.setMockInitialValues({'consent_crash_v1': false});
    await CloudAuthService.init();
    expect(CloudAuthService.consentCrash.value, isFalse);
  });
}
