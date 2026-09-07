import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/stream/stream_probe_race.dart';

StreamSource _src(String name, {String addon = 'test'}) {
  return StreamSource(
    name: name,
    url: 'https://example.com/$name.mp4',
    addonName: addon,
  );
}

void main() {
  test('first alive source wins even when a dead source was offered first',
      () async {
    // Dead probe takes 3s (would serialize-kill old pipeline); alive 50ms.
    final race = StreamProbeRace(
      probeFn: (s) async {
        if (s.name == 'dead') {
          await Future.delayed(const Duration(milliseconds: 300));
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 50));
        return true;
      },
    );

    race.offer(_src('dead'));
    race.offer(_src('alive-fast'));

    final winner = await race.winner;
    expect(winner, isNotNull);
    expect(winner!.name, 'alive-fast');

    race.close();
  });

  test('winner is null when all sources are dead', () async {
    final race = StreamProbeRace(probeFn: (_) async => false);

    race.offer(_src('a'));
    race.offer(_src('b'));

    // Give probes a tick, then close like onDone would.
    await Future.delayed(const Duration(milliseconds: 20));
    race.close();

    final winner = await race.winner;
    expect(winner, isNull);
  });

  test('verified sources continue arriving after winner (for manual list)',
      () async {
    final batches = <List<StreamSource>>[];
    final race = StreamProbeRace(
      probeFn: (_) async => true,
      onVerifiedBatch: batches.add,
      batchDelay: const Duration(milliseconds: 10),
    );

    race.offer(_src('a'));
    await Future.delayed(const Duration(milliseconds: 30));
    expect(batches.length, 1); // first batch flushed
    expect(batches.first.length, 1);

    race.offer(_src('b')); // after winner — still lands in UI list
    await Future.delayed(const Duration(milliseconds: 30));
    expect(race.verifiedSources.length, 2);

    // winner was first source
    final winner = await race.winner;
    expect(winner!.name, 'a');

    race.close();
  });

  test('probe concurrency is bounded — 100 offers never exceed cap',
      () async {
    var peakConcurrent = 0;
    var running = 0;
    final race = StreamProbeRace(
      probeFn: (_) async {
        running++;
        if (running > peakConcurrent) peakConcurrent = running;
        await Future.delayed(const Duration(milliseconds: 40));
        running--;
        return false; // all dead → no winner, queue keeps draining
      },
    );

    // Bomb 100 sources at once — old code launched 100 concurrent probes.
    for (var i = 0; i < 100; i++) {
      race.offer(_src('s$i'));
    }
    await Future.delayed(const Duration(milliseconds: 800));
    expect(peakConcurrent, lessThanOrEqualTo(StreamProbeRace.maxConcurrentProbes));
    race.close(); // settle winner with no alive source found
    expect(await race.winner, isNull);
  });

  test('probe exceptions are swallowed and treated as dead', () async {
    final race = StreamProbeRace(
      probeFn: (_) async => throw Exception('network exploded'),
    );
    race.offer(_src('boom'));
    await Future.delayed(const Duration(milliseconds: 20));
    race.close();
    expect(await race.winner, isNull);
  });

  test('offer after close is ignored', () async {
    final race = StreamProbeRace(probeFn: (_) async => true);
    race.close();
    race.offer(_src('late'));
    // No crash, no winner mutation.
    expect(race.verifiedSources, isEmpty);
    expect(await race.winner, isNull);
  });
}
