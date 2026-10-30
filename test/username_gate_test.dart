import 'package:dizzy/services/social/username_gate_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UsernameGatePolicy.decide', () {
    test('skips the gate when the server already has a username row', () {
      expect(
        UsernameGatePolicy.decide(cloudReady: true, hasUsername: true),
        UsernameGate.notNeeded,
      );
    });

    test('asks when the server confirms there is no username row', () {
      expect(
        UsernameGatePolicy.decide(cloudReady: true, hasUsername: false),
        UsernameGate.needed,
      );
    });

    test('stays undecided when the lookup failed (null is not "no")', () {
      expect(
        UsernameGatePolicy.decide(cloudReady: true, hasUsername: null),
        UsernameGate.undecided,
      );
    });

    test('stays undecided when cloud is not ready', () {
      expect(
        UsernameGatePolicy.decide(cloudReady: false, hasUsername: false),
        UsernameGate.undecided,
      );
    });
  });

  group('UsernameGatePolicy.returningUser', () {
    test('offers the old name when this device belonged to another guest', () {
      final r = UsernameGatePolicy.returningUser(
        currentUid: 'new-uid',
        previousUid: 'old-uid',
        previousUsername: 'rahul',
      );
      expect(r, isNotNull);
      expect(r!.userId, 'old-uid');
      expect(r.username, 'rahul');
    });

    test('does not offer anything for the same account', () {
      expect(
        UsernameGatePolicy.returningUser(
          currentUid: 'same-uid',
          previousUid: 'same-uid',
          previousUsername: 'rahul',
        ),
        isNull,
      );
    });

    test('does not offer a welcome back without a name', () {
      expect(
        UsernameGatePolicy.returningUser(
          currentUid: 'new-uid',
          previousUid: 'old-uid',
          previousUsername: '  ',
        ),
        isNull,
      );
    });

    test('does not offer a welcome back without a previous owner', () {
      expect(
        UsernameGatePolicy.returningUser(
          currentUid: 'new-uid',
          previousUid: null,
          previousUsername: 'rahul',
        ),
        isNull,
      );
    });

    test('does not offer a welcome back when the session is unknown', () {
      expect(
        UsernameGatePolicy.returningUser(
          currentUid: null,
          previousUid: 'old-uid',
          previousUsername: 'rahul',
        ),
        isNull,
      );
    });
  });

  group('UsernameGatePolicy.localProblem', () {
    test('flags empty input', () {
      expect(UsernameGatePolicy.localProblem(''), UsernameProblem.empty);
      expect(UsernameGatePolicy.localProblem('   '), UsernameProblem.empty);
    });

    test('flags names shorter than 3 characters', () {
      expect(UsernameGatePolicy.localProblem('ab'), UsernameProblem.tooShort);
    });

    test('flags names longer than 20 characters', () {
      expect(
        UsernameGatePolicy.localProblem('a' * 21),
        UsernameProblem.tooLong,
      );
    });

    test('flags spaces and unsupported characters', () {
      expect(UsernameGatePolicy.localProblem('ravi kumar'), UsernameProblem.badChars);
      expect(UsernameGatePolicy.localProblem('rahul!'), UsernameProblem.badChars);
      expect(UsernameGatePolicy.localProblem('राहुल'), UsernameProblem.badChars);
    });

    test('accepts letters, digits and underscore', () {
      expect(UsernameGatePolicy.localProblem('rahul'), isNull);
      expect(UsernameGatePolicy.localProblem('rahul_07'), isNull);
      expect(UsernameGatePolicy.localProblem('abc'), isNull);
      expect(UsernameGatePolicy.localProblem('a' * 20), isNull);
    });

    test('accepts uppercase input because it is normalised to lowercase', () {
      expect(UsernameGatePolicy.localProblem('Rahul'), isNull);
      expect(UsernameGatePolicy.normalize('  Rahul '), 'rahul');
    });

    test('normalize lowercases and trims but keeps underscores', () {
      expect(UsernameGatePolicy.normalize('  Ravi_Kumar  '), 'ravi_kumar');
    });
  });

  group('UsernameGatePolicy.canDefer', () {
    test('never offers "later" before two real failures', () {
      expect(UsernameGatePolicy.canDefer(0), isFalse);
      expect(UsernameGatePolicy.canDefer(1), isFalse);
      expect(UsernameGatePolicy.canDefer(2), isTrue);
      expect(UsernameGatePolicy.canDefer(3), isTrue);
    });
  });
}
