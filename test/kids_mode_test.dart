import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/profiles/kids_mode.dart';

/// Polish P15: kids profile instantly recognizable.
void main() {
  group('KidsMode', () {
    test('kids accent is warm gold', () {
      expect(KidsMode.kKidsAccent, const Color(0xFFFFC107));
      expect(KidsMode.kKidsBadge, '🧒');
    });

    test('subtitle names kids + lock state', () {
      expect(
        KidsMode.subtitle(isKids: true, hasPin: false),
        'Kids profile · No PIN',
      );
      expect(
        KidsMode.subtitle(isKids: true, hasPin: true),
        'Kids profile · PIN protected',
      );
      expect(
        KidsMode.subtitle(isKids: false, hasPin: false),
        'Profile · No PIN',
      );
    });

    test('hello is Easy English', () {
      expect(KidsMode.hello('Ashu', isKids: true),
          'Hi Ashu! Pick something fun.');
      expect(KidsMode.hello('Ashu', isKids: false), 'Hi Ashu!');
    });

    test('ring only for kids', () {
      expect(KidsMode.ring(isKids: true), KidsMode.kKidsAccent);
      expect(KidsMode.ring(isKids: false), Colors.transparent);
    });
  });
}
