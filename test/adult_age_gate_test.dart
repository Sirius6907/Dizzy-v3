import 'package:dizzy/services/adult/adult_section_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AdultSectionGate.debugReset();
    await AdultSectionGate.ensureLoaded();
  });

  group('age maths (pure)', () {
    const nowYear = 2026;

    test('exactly 18 is an adult', () {
      expect(
        AdultSectionGate.evaluateYears(nowYear - 18, nowYear: nowYear),
        AgeGateResult.granted,
      );
    });

    test('17 is underage', () {
      expect(
        AdultSectionGate.evaluateYears(nowYear - 17, nowYear: nowYear),
        AgeGateResult.underage,
      );
      expect(
        AdultSectionGate.isAdultYear(nowYear - 17, nowYear: nowYear),
        isFalse,
      );
    });

    test('future year is invalid, not underage', () {
      expect(
        AdultSectionGate.evaluateYears(nowYear + 1, nowYear: nowYear),
        AgeGateResult.invalidYear,
      );
      expect(
        AdultSectionGate.isPlausibleYear(nowYear + 1, nowYear: nowYear),
        isFalse,
      );
    });

    test('absurdly old year is invalid', () {
      expect(
        AdultSectionGate.evaluateYears(nowYear - 121, nowYear: nowYear),
        AgeGateResult.invalidYear,
      );
      // 120 years old is the outer believable bound.
      expect(
        AdultSectionGate.isPlausibleYear(nowYear - 120, nowYear: nowYear),
        isTrue,
      );
    });

    test('a newborn is plausible but not an adult', () {
      expect(
        AdultSectionGate.isPlausibleYear(nowYear, nowYear: nowYear),
        isTrue,
      );
      expect(
        AdultSectionGate.evaluateYears(nowYear, nowYear: nowYear),
        AgeGateResult.underage,
      );
    });

    test('kids profile is never granted', () {
      expect(
        AdultSectionGate.evaluateYears(1990, nowYear: nowYear, kids: true),
        AgeGateResult.kidsProfile,
      );
    });
  });

  group('local confirm can only be earned', () {
    test('boots locked even with a saved admin allow', () async {
      await AdultSectionGate.applyServerAllow(true);
      expect(AdultSectionGate.localConfirmed.value, isFalse);
      expect(AdultSectionGate.visible.value, isFalse);
    });

    test('setLocalConfirmed(true) is a no-op', () async {
      await AdultSectionGate.setLocalConfirmed(true);
      expect(AdultSectionGate.localConfirmed.value, isFalse);
      expect(AdultSectionGate.birthYear.value, isNull);
    });

    test('valid birth year unlocks and persists per device', () async {
      final result = await AdultSectionGate.submitBirthYear(1990);

      expect(result, AgeGateResult.granted);
      expect(AdultSectionGate.localConfirmed.value, isTrue);
      expect(AdultSectionGate.birthYear.value, 1990);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('adult_heaven_local_18_v1'), isTrue);
      expect(prefs.getInt('adult_heaven_birth_year_v1'), 1990);

      // Survives a cold start.
      AdultSectionGate.debugReset();
      await AdultSectionGate.ensureLoaded();
      expect(AdultSectionGate.localConfirmed.value, isTrue);
      expect(AdultSectionGate.birthYear.value, 1990);
    });

    test('still needs the admin lock after the age gate passes', () async {
      await AdultSectionGate.submitBirthYear(1990);
      expect(AdultSectionGate.visible.value, isFalse);

      await AdultSectionGate.applyServerAllow(true);
      expect(AdultSectionGate.visible.value, isTrue);

      await AdultSectionGate.applyServerAllow(false);
      expect(AdultSectionGate.visible.value, isFalse);
    });

    test('turning the gate off forgets the birth year', () async {
      await AdultSectionGate.submitBirthYear(1990);
      await AdultSectionGate.setLocalConfirmed(false);

      expect(AdultSectionGate.localConfirmed.value, isFalse);
      expect(AdultSectionGate.birthYear.value, isNull);
      expect(AdultSectionGate.attemptsLeft.value, AdultSectionGate.maxAttempts);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('adult_heaven_local_18_v1'), isFalse);
      expect(prefs.getInt('adult_heaven_birth_year_v1'), isNull);
    });
  });

  group('underage cooling-off', () {
    test('invalid year does not burn an attempt', () async {
      final before = AdultSectionGate.attemptsLeft.value;
      final result = await AdultSectionGate.submitBirthYear(1800);

      expect(result, AgeGateResult.invalidYear);
      expect(AdultSectionGate.attemptsLeft.value, before);
    });

    test('five underage tries lock the gate for 24h', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      for (var i = 1; i <= 4; i++) {
        final r = await AdultSectionGate.submitBirthYear(
          2010,
          nowMs: now,
          nowYear: 2026,
        );
        expect(r, AgeGateResult.underage, reason: 'attempt $i');
      }
      expect(AdultSectionGate.attemptsLeft.value, 1);

      final fifth = await AdultSectionGate.submitBirthYear(
        2010,
        nowMs: now,
        nowYear: 2026,
      );
      expect(fifth, AgeGateResult.lockedOut);
      expect(AdultSectionGate.attemptsLeft.value, 0);
      expect(AdultSectionGate.lockRemaining(nowMs: now),
          AdultSectionGate.lockDuration);

      // Even the correct year is refused during the cooling-off.
      expect(
        await AdultSectionGate.submitBirthYear(1990, nowMs: now),
        AgeGateResult.lockedOut,
      );
      expect(AdultSectionGate.localConfirmed.value, isFalse);
    });

    test('lockout survives a cold start', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < AdultSectionGate.maxAttempts; i++) {
        await AdultSectionGate.submitBirthYear(
          2010,
          nowMs: now,
          nowYear: 2026,
        );
      }

      AdultSectionGate.debugReset();
      await AdultSectionGate.ensureLoaded();

      expect(AdultSectionGate.attemptsLeft.value, 0);
      expect(AdultSectionGate.isLockedOut(), isTrue);
      expect(
        await AdultSectionGate.submitBirthYear(1990),
        AgeGateResult.lockedOut,
      );
    });

    test('cooling-off expiry restores a full set of attempts', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < AdultSectionGate.maxAttempts; i++) {
        await AdultSectionGate.submitBirthYear(
          2010,
          nowMs: now,
          nowYear: 2026,
        );
      }

      final after = now + AdultSectionGate.lockDuration.inMilliseconds + 1;

      // An underage year after the cooldown behaves like attempt 1 again.
      expect(
        await AdultSectionGate.submitBirthYear(
          2010,
          nowMs: after,
          nowYear: 2026,
        ),
        AgeGateResult.underage,
      );
      expect(AdultSectionGate.attemptsLeft.value,
          AdultSectionGate.maxAttempts - 1);

      // And a valid year unlocks normally.
      expect(
        await AdultSectionGate.submitBirthYear(
          1990,
          nowMs: after,
          nowYear: 2026,
        ),
        AgeGateResult.granted,
      );
      expect(AdultSectionGate.attemptsLeft.value,
          AdultSectionGate.maxAttempts);
    });

    test('success clears earlier failures', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await AdultSectionGate.submitBirthYear(
        2010,
        nowMs: now,
        nowYear: 2026,
      );
      expect(AdultSectionGate.attemptsLeft.value,
          AdultSectionGate.maxAttempts - 1);

      await AdultSectionGate.submitBirthYear(1990, nowMs: now);
      expect(AdultSectionGate.attemptsLeft.value,
          AdultSectionGate.maxAttempts);
      expect(AdultSectionGate.isLockedOut(nowMs: now), isFalse);
    });
  });

  group('private mode', () {
    test('defaults to on', () async {
      expect(AdultSectionGate.privateMode.value, isTrue);

      AdultSectionGate.debugReset();
      await AdultSectionGate.ensureLoaded();
      expect(AdultSectionGate.privateMode.value, isTrue);
    });

    test('toggle persists per device', () async {
      await AdultSectionGate.setPrivateMode(false);
      expect(AdultSectionGate.privateMode.value, isFalse);

      AdultSectionGate.debugReset();
      await AdultSectionGate.ensureLoaded();
      expect(AdultSectionGate.privateMode.value, isFalse);
    });
  });
}
