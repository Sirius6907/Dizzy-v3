import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/stats/wrap_copy.dart';

/// Polish P19: Wrap cheers stay warm, never techy.
void main() {
  group('WrapCopy', () {
    test('hours cheer tiers', () {
      expect(WrapCopy.hoursCheer(0), contains('one tap'));
      expect(WrapCopy.hoursCheer(30), contains('Warming up'));
      expect(WrapCopy.hoursCheer(300), contains('cozy'));
      expect(WrapCopy.hoursCheer(1000), contains('binge legend'));
      expect(WrapCopy.hoursCheer(5000), contains('pocket'));
    });

    test('streak line tiers', () {
      expect(WrapCopy.streakLine(0), contains('daily'));
      expect(WrapCopy.streakLine(1), contains('lit'));
      expect(WrapCopy.streakLine(7), contains('7-day streak'));
    });

    test('empty taste invites, never blames', () {
      expect(WrapCopy.emptyTaste(), contains('taste profile builds'));
      expect(WrapCopy.emptyTaste(), isNot(contains('error')));
    });
  });
}
