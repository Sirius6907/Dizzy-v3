import 'dart:async';

import 'package:dizzy/services/media/tap_gate.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase L4 — "one tap, one action".
///
/// A phone delivers a tap twice (press + release near-miss) and impatient
/// fingers add a third. These tests pin the three behaviours the transport
/// and Live TV surfaces depend on: duplicates inside the window are dropped,
/// single-flight work cannot start twice, and a coalesced tap lands exactly
/// once after the current work finishes.
void main() {
  late DateTime now;
  late TapGate gate;
  late int calls;

  setUp(() {
    now = DateTime(2026, 11, 18, 12);
    gate = TapGate(
      window: const Duration(milliseconds: 300),
      clock: () => now,
    );
    calls = 0;
  });

  tearDown(() => gate.dispose());

  Future<void> advance(Duration by) async {
    now = now.add(by);
    await Future<void>.delayed(Duration.zero);
  }

  group('window', () {
    test('first tap runs and a duplicate inside the window is dropped', () async {
      expect(await gate.run('toggle', () async => calls++), isTrue);
      expect(calls, 1);

      now = now.add(const Duration(milliseconds: 120));
      expect(await gate.run('toggle', () async => calls++), isFalse);
      expect(calls, 1);
    });

    test('a tap after the window runs again', () async {
      await gate.run('toggle', () async => calls++);
      await advance(const Duration(milliseconds: 301));

      expect(await gate.run('toggle', () async => calls++), isTrue);
      expect(calls, 2);
    });

    test('the window is per key, so next is not blocked by toggle', () async {
      await gate.run('toggle', () async => calls++);
      expect(await gate.run('next', () async => calls++), isTrue);
      expect(calls, 2);
    });

    test('an explicit window overrides the gate default', () async {
      const long = Duration(seconds: 1);
      await gate.run('next', () async => calls++, window: long);
      now = now.add(const Duration(milliseconds: 400));

      // 400 ms is past the 300 ms default but inside the 1 s override.
      expect(await gate.run('next', () async => calls++, window: long), isFalse);
      expect(calls, 1);
    });
  });

  group('single flight', () {
    test('a tap while work runs is dropped when not coalescing', () async {
      final release = Completer<void>();
      final first = gate.run('toggle', () async {
        calls++;
        await release.future;
      });

      // Let the first action reach its await.
      await Future<void>.delayed(Duration.zero);
      expect(await gate.run('toggle', () async => calls++), isFalse);

      release.complete();
      expect(await first, isTrue);
      expect(calls, 1);
    });

    test('busy flips true while running and back to false after', () async {
      final release = Completer<void>();
      expect(gate.busy.value, isFalse);

      final run = gate.run('next', () async {
        calls++;
        await release.future;
      });
      await Future<void>.delayed(Duration.zero);
      expect(gate.busy.value, isTrue);

      release.complete();
      await run;
      expect(gate.busy.value, isFalse);
    });

    test('coalescing keeps only the newest tap and runs it once', () async {
      final release = Completer<void>();
      var skipped = 0;

      final first = gate.run('next', () async {
        await release.future;
      }, coalesce: true);

      await Future<void>.delayed(Duration.zero);

      // Three impatient taps while the first switch buffers.
      expect(
        await gate.run('next', () async => skipped++, coalesce: true),
        isTrue,
      );
      expect(
        await gate.run('next', () async => skipped++, coalesce: true),
        isTrue,
      );
      expect(skipped, 0);

      release.complete();
      await first;

      // Only the last queued action ran — one step forward, not three.
      expect(skipped, 1);
      expect(gate.isBusy, isFalse);
    });

    test('a coalesced tap is cleared even when the work throws', () async {
      var ran = 0;
      await expectLater(
        gate.run('next', () async {
          ran++;
          throw StateError('stream died');
        }, coalesce: true),
        throwsStateError,
      );

      expect(ran, 1);
      expect(gate.isBusy, isFalse);
      expect(gate.busy.value, isFalse);

      // A failure must not wedge the gate: the next tap still goes through.
      now = now.add(const Duration(seconds: 1));
      expect(await gate.run('next', () async => ran++, coalesce: true), isTrue);
      expect(ran, 2);
    });
  });

  group('lifecycle', () {
    test('dispose during in-flight work does not touch the notifier', () async {
      final release = Completer<void>();
      final run = gate.run('source', () async {
        calls++;
        await release.future;
      });

      await Future<void>.delayed(Duration.zero);
      gate.dispose();
      release.complete();

      // No "used after dispose" exception from the trailing busy reset.
      await run;
      expect(calls, 1);
    });

    test('reset clears the window and the lock', () async {
      final release = Completer<void>();
      final run = gate.run('next', () async => release.future);
      await Future<void>.delayed(Duration.zero);

      gate.reset();
      expect(gate.isBusy, isFalse);
      expect(gate.busy.value, isFalse);

      release.complete();
      await run;

      expect(await gate.run('next', () async => calls++), isTrue);
      expect(calls, 1);
    });
  });
}
