/// F3 — the 4-digit lock on someone's private lists.
///
/// Pure rules, nothing stored. A child-proof lock, not a bank vault: four
/// digits, hashed with SHA-256 exactly like the profile PIN, with a short
/// wait after a few wrong tries so guessing is pointless.
///
/// We are explicit about what this is NOT: it is not encryption and it does
/// not hide anything from a determined person with the device in hand. It
/// stops the "borrowed phone, see my list" case, which is the real one.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Why an unlock attempt was refused — the UI maps each to an Easy
/// English line, never to a raw reason.
enum PinFailure { wrong, lockedOut, notSet }

/// The outcome of a lock or unlock check.
class PinCheck {
  final bool ok;
  final PinFailure? failure;

  const PinCheck.ok() : ok = true, failure = null;
  const PinCheck.fail(this.failure) : ok = false;

  /// True when the caller should say "too many tries, wait a bit".
  bool get isLockedOut => failure == PinFailure.lockedOut;
}

abstract final class PinLockPolicy {
  /// A short code has to be easy to read aloud and easy to type on a TV
  /// remote: digits only, no O/0 or I/1 confusion, no 4/5 ambiguity.
  static const int length = 4;

  /// Wrong tries before the wait starts.
  static const int freeTries = 3;

  /// How long the lock stays shut after [freeTries] misses.
  static const Duration lockout = Duration(minutes: 2);

  /// Digits only, exactly [length] of them.
  static final RegExp _shape = RegExp('^\\d{$length}\$');

  /// True when [raw] is a usable 4-digit code.
  static bool isValid(String raw) => _shape.hasMatch(raw.trim());

  /// SHA-256 of a code. The raw code is never stored, never logged, and
  /// never leaves this file.
  static String? hash(String raw) {
    final clean = raw.trim();
    if (!isValid(clean)) return null;
    return sha256.convert(utf8.encode(clean)).toString();
  }

  /// True when [candidate] matches [storedHash]. An empty/unset lock is
  /// "unlocked" — a person with no lock is never locked out of their own
  /// list.
  static bool matches(String candidate, String? storedHash) {
    if (storedHash == null || storedHash.isEmpty) return true;
    final h = hash(candidate);
    return h != null && h == storedHash;
  }

  /// Whether the lock is shut right now.
  ///
  /// [firstMissAt] is when the current run of wrong tries started, and
  /// [misses] is how many have happened. A run younger than [freeTries]
  /// is not locked out yet.
  static bool isLockedOut({
    required int misses,
    required DateTime? firstMissAt,
    DateTime? now,
  }) {
    if (misses < freeTries) return false;
    if (firstMissAt == null) return false;
    final ref = now ?? DateTime.now();
    return ref.difference(firstMissAt) < lockout;
  }

  /// The full check for one unlock attempt.
  static PinCheck unlock({
    required String candidate,
    required String? storedHash,
    required int misses,
    required DateTime? firstMissAt,
    DateTime? now,
  }) {
    // No lock set means there is nothing to be locked out of — a person
    // with no code is never blocked from their own lists.
    if (storedHash == null || storedHash.isEmpty) return const PinCheck.ok();
    if (isLockedOut(misses: misses, firstMissAt: firstMissAt, now: now)) {
      return const PinCheck.fail(PinFailure.lockedOut);
    }
    if (matches(candidate, storedHash)) return const PinCheck.ok();
    return const PinCheck.fail(PinFailure.wrong);
  }

  /// What the miss counter becomes after one wrong try.
  ///
  /// A correct code resets the run, so an old lockout never sticks to
  /// someone who types the right number afterwards.
  static (int, DateTime?) afterMiss({
    required int misses,
    required DateTime? firstMissAt,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    if (misses == 0 || firstMissAt == null) return (1, at);
    return (misses + 1, firstMissAt);
  }

  /// After a correct code.
  static (int, DateTime?) afterHit() => (0, null);
}
