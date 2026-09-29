import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/continue_watching/progress_merge.dart';
import 'package:dizzy/services/my_list/custom_list_policy.dart';
import 'package:dizzy/services/my_list/pin_lock_policy.dart';
import 'package:dizzy/services/profiles/device_merge_policy.dart';

/// F3 — My Dizzy. The rules a person trusts their history with.
void main() {
  final t0 = DateTime(2026, 3, 1, 12);
  final t1 = DateTime(2026, 3, 2, 12);
  final t2 = DateTime(2026, 3, 3, 12);

  MediaProgress row(
    String profile,
    String media, {
    int pos = 0,
    int total = 3600,
    DateTime? at,
  }) =>
      MediaProgress(
        key: MediaProgress.forProfile(profile, media),
        positionSeconds: pos,
        totalDurationSeconds: total,
        lastWatchedAt: at ?? t0,
        meta: const {'title': 'X'},
      );

  group('progress merge — max progress wins', () {
    test('a farther position wins even when it is older', () {
      final ahead = row('p1', 'tt1', pos: 900, at: t0);
      final behind = row('p1', 'tt1', pos: 120, at: t2);
      final winner = ProgressMerge.resolve(behind, ahead);
      expect(winner.positionSeconds, 900);
    });

    test('a later position wins even when it is newer', () {
      final ahead = row('p1', 'tt1', pos: 120, at: t2);
      final behind = row('p1', 'tt1', pos: 900, at: t0);
      final winner = ProgressMerge.resolve(behind, ahead);
      expect(winner.positionSeconds, 900);
    });

    test('progress never moves backwards across a whole merge', () {
      final local = {'p1::tt1': row('p1', 'tt1', pos: 800, at: t2)};
      final remote = {'p1::tt1': row('p1', 'tt1', pos: 100, at: t0)};
      final (merged, report) = ProgressMerge.merge(local, remote);
      expect(merged['p1::tt1']!.positionSeconds, 800);
      expect(report.advanced, 0);
      expect(report.kept, 1);
    });

    test('a behind device pulls the canonical row forward', () {
      final local = {'p1::tt1': row('p1', 'tt1', pos: 100, at: t0)};
      final remote = {'p1::tt1': row('p1', 'tt1', pos: 800, at: t1)};
      final (merged, report) = ProgressMerge.merge(local, remote);
      expect(merged['p1::tt1']!.positionSeconds, 800);
      expect(report.advanced, 1);
    });

    test('a row only one side has is added, not skipped', () {
      final local = {'p1::tt1': row('p1', 'tt1', pos: 10)};
      final remote = {'p1::tt2': row('p1', 'tt2', pos: 20)};
      final (merged, report) = ProgressMerge.merge(local, remote);
      expect(merged.keys, containsAll(<String>['p1::tt1', 'p1::tt2']));
      expect(report.added, 1);
      // tt1 lived only here: nothing happened to it, so it is not counted
      // as something that "came back".
      expect(report.total, 1);
    });

    test('newer metadata wins while progress stays at the max', () {
      final older = MediaProgress(
        key: 'p1::tt1',
        positionSeconds: 10,
        totalDurationSeconds: 0,
        lastWatchedAt: t0,
        meta: const {'title': 'Old'},
      );
      final newer = MediaProgress(
        key: 'p1::tt1',
        positionSeconds: 50,
        totalDurationSeconds: 0,
        lastWatchedAt: t2,
        meta: const {'title': 'New'},
      );
      final winner = ProgressMerge.resolve(older, newer);
      expect(winner.positionSeconds, 50);
      expect(winner.meta['title'], 'New');
      expect(winner.lastWatchedAt, t2);
    });

    test('a known length beats an unknown one', () {
      final known = row('p1', 'tt1', pos: 60, total: 3600);
      final unknown = MediaProgress(
        key: 'p1::tt1',
        positionSeconds: 20,
        totalDurationSeconds: 0,
        lastWatchedAt: t0,
      );
      expect(ProgressMerge.resolve(unknown, known).totalDurationSeconds, 3600);
    });

    test('a negative position is treated as zero, never as a rewind', () {
      final bad = row('p1', 'tt1', pos: -50);
      final good = row('p1', 'tt1', pos: 30);
      expect(ProgressMerge.resolve(bad, good).positionSeconds, 30);
    });

    test('a corrupt key is dropped and the readable row survives', () {
      final rows = {
        'p1::tt1': row('p1', 'tt1', pos: 60),
        'broken-key': MediaProgress(
          key: 'broken-key',
          positionSeconds: 999,
          totalDurationSeconds: 3600,
          lastWatchedAt: t2,
        ),
      };
      final kept = ProgressMerge.forProfile(rows, 'p1');
      expect(kept.length, 1);
      expect(kept.first.key, 'p1::tt1');
    });

    test('a mismatched incoming key is ignored, never re-keyed', () {
      final local = {'p1::tt1': row('p1', 'tt1')};
      // Filed under p1::tt1 but carrying a p2 key: a corrupt row.
      final mislabeled = {
        'p1::tt1': MediaProgress(
          key: 'p2::tt9',
          positionSeconds: 500,
          totalDurationSeconds: 3600,
          lastWatchedAt: t2,
        ),
      };
      final (merged, report) = ProgressMerge.merge(local, mislabeled);
      expect(merged['p1::tt1']!.positionSeconds, 0);
      expect(report.added, 0);
      expect(report.kept, 1);
    });

    test('per-profile isolation: one profile never sees the other', () {
      final rows = {
        'p1::tt1': row('p1', 'tt1', pos: 10, at: t2),
        'p2::tt1': row('p2', 'tt1', pos: 20, at: t1),
      };
      final mine = ProgressMerge.forProfile(rows, 'p1');
      expect(mine.length, 1);
      expect(mine.first.positionSeconds, 10);
    });

    test('reinstall restore: a fresh device rebuilds the same rows', () {
      final before = {
        'p1::tt1': row('p1', 'tt1', pos: 300, at: t1),
        'p1::tt2': row('p1', 'tt2', pos: 42, at: t0),
      };
      // New phone: empty storage, then the cloud copy arrives.
      final (after, report) =
          ProgressMerge.merge(<String, MediaProgress>{}, before);
      expect(after.keys.toSet(), before.keys.toSet());
      expect(after['p1::tt1']!.positionSeconds, 300);
      expect(report.added, 2);
    });

    test('an empty account restores to an empty state, not an error', () {
      final (merged, report) =
          ProgressMerge.merge(<String, MediaProgress>{}, <String, MediaProgress>{});
      expect(merged, isEmpty);
      expect(report.total, 0);
    });

    test('row cap keeps the most recently touched rows', () {
      final many = <String, MediaProgress>{
        for (var i = 0; i < ProgressMerge.maxRows + 25; i++)
          'p1::tt$i': row('p1', 'tt$i', pos: i, at: t0.add(Duration(minutes: i))),
      };
      final capped = ProgressMerge.merge(many, const {}).$1;
      expect(capped.length, ProgressMerge.maxRows);
      expect(capped.containsKey('p1::tt${ProgressMerge.maxRows + 24}'), isTrue);
    });
  });

  group('custom lists — per person', () {
    List<CustomList> seed() => [
          CustomList(id: 'l1', name: 'Weekend', itemKeys: const [], createdAt: t0, updatedAt: t0),
          CustomList(id: 'l2', name: 'Road Trip', itemKeys: const [], createdAt: t0, updatedAt: t0),
        ];

    test('create puts the new list first with a clean name', () {
      final made = CustomListPolicy.create(seed(), id: 'l3', name: '  Late   Night  ');
      expect(made, isNotNull);
      expect(made!.first.name, 'Late Night');
      expect(made.first.length, 0);
      expect(made.length, 3);
    });

    test('create refuses a blank name', () {
      expect(CustomListPolicy.create(seed(), id: 'l3', name: '    '), isNull);
    });

    test('create refuses a duplicate name regardless of case', () {
      expect(
        CustomListPolicy.create(seed(), id: 'l3', name: 'weekend'),
        isNull,
      );
    });

    test('create refuses past the cap', () {
      var many = seed();
      for (var i = 0; i < CustomListPolicy.maxLists; i++) {
        many = CustomListPolicy.create(many, id: 'x$i', name: 'List $i') ?? many;
      }
      expect(CustomListPolicy.canCreate(many), isFalse);
      expect(CustomListPolicy.create(many, id: 'y', name: 'One More'), isNull);
    });

    test('rename keeps position and items', () {
      final renamed = CustomListPolicy.rename(
        [
          ...seed(),
          CustomList(id: 'l1', name: 'Weekend', itemKeys: const ['a'], createdAt: t0, updatedAt: t0),
        ],
        id: 'l1',
        name: 'Lazy Sunday',
        now: t2,
      );
      expect(renamed, isNotNull);
      expect(renamed!.first.id, 'l1');
      expect(renamed.first.name, 'Lazy Sunday');
    });

    test('rename refuses to collide with a sibling list', () {
      expect(
        CustomListPolicy.rename(seed(), id: 'l1', name: 'Road Trip'),
        isNull,
      );
    });

    test('delete removes only the named list', () {
      final after = CustomListPolicy.delete(seed(), 'l1');
      expect(after.length, 1);
      expect(after.first.id, 'l2');
    });

    test('adding the same title twice is a no-op', () {
      final once = CustomListPolicy.addItem(
        seed(),
        listId: 'l1',
        itemKey: 'imdb:tt1',
      )!;
      final twice = CustomListPolicy.addItem(once, listId: 'l1', itemKey: 'imdb:tt1');
      expect(twice, isNull);
      expect(once.first.length, 1);
    });

    test('remove drops the key and leaves a missing one alone', () {
      final withItem = CustomListPolicy.addItem(
        seed(),
        listId: 'l1',
        itemKey: 'imdb:tt1',
      )!;
      final removed = CustomListPolicy.removeItem(
        withItem,
        listId: 'l1',
        itemKey: 'imdb:tt1',
      );
      expect(removed.first.length, 0);
      final again = CustomListPolicy.removeItem(
        removed,
        listId: 'l1',
        itemKey: 'imdb:tt1',
      );
      expect(again.first.length, 0);
    });

    test('a corrupt stored list is dropped, siblings survive', () {
      final parsed = <CustomList?>[
        CustomList.fromJson({'id': '', 'name': 'Broken'}),
        CustomList.fromJson({'id': 'ok', 'name': 'Fine', 'itemKeys': ['', 'a']}),
        CustomList.fromJson({'id': 'x'}),
      ].whereType<CustomList>().toList();
      expect(parsed.length, 1);
      expect(parsed.first.name, 'Fine');
      expect(parsed.first.itemKeys, <String>['a']);
    });
  });

  group('PIN lock', () {
    test('a 4-digit code hashes; a bad one does not', () {
      expect(PinLockPolicy.isValid('1234'), isTrue);
      expect(PinLockPolicy.isValid('123'), isFalse);
      expect(PinLockPolicy.isValid('12a4'), isFalse);
      expect(PinLockPolicy.hash('1234'), isNotNull);
      expect(PinLockPolicy.hash('12'), isNull);
    });

    test('hash is deterministic and never returns the raw code', () {
      final h = PinLockPolicy.hash('1234')!;
      expect(h, PinLockPolicy.hash('1234'));
      expect(h.contains('1234'), isFalse);
    });

    test('the right code opens, the wrong one does not', () {
      final h = PinLockPolicy.hash('1234')!;
      expect(
        PinLockPolicy.unlock(
          candidate: '1234',
          storedHash: h,
          misses: 0,
          firstMissAt: null,
        ).ok,
        isTrue,
      );
      expect(
        PinLockPolicy.unlock(
          candidate: '9999',
          storedHash: h,
          misses: 0,
          firstMissAt: null,
        ).failure,
        PinFailure.wrong,
      );
    });

    test('a person with no lock is never locked out', () {
      expect(
        PinLockPolicy.unlock(
          candidate: '',
          storedHash: null,
          misses: 99,
          firstMissAt: t0,
          now: t0,
        ).ok,
        isTrue,
      );
    });

    test('three wrong tries lock the pad for two minutes', () {
      final start = t2;
      final locked = PinLockPolicy.isLockedOut(
        misses: 3,
        firstMissAt: start,
        now: start.add(const Duration(seconds: 10)),
      );
      expect(locked, isTrue);
      final open = PinLockPolicy.isLockedOut(
        misses: 3,
        firstMissAt: start,
        now: start.add(const Duration(minutes: 3)),
      );
      expect(open, isFalse);
    });

    test('a correct code clears an old lockout run', () {
      final (misses, first) = PinLockPolicy.afterHit();
      expect(misses, 0);
      expect(first, isNull);
    });
  });

  group('device merge — short code + union', () {
    test('a generated code always passes its own validation', () {
      for (final seed in [1, 7, 99, 12345, 987654321]) {
        final code = DeviceMergePolicy.codeFromSeed(seed);
        expect(DeviceMergePolicy.isValidCode(code), isTrue);
        expect(code.length, DeviceMergePolicy.codeLength);
      }
    });

    test('a code never uses look-alike characters', () {
      for (final ch in DeviceMergePolicy.alphabet.split('')) {
        expect('01OISBZL'.contains(ch), isFalse);
      }
    });

    test('typed codes are cleaned and invalid ones refused', () {
      expect(DeviceMergePolicy.normalizeCode(' ac-def '), 'ACDEF');
      expect(DeviceMergePolicy.isValidCode('ACDEF6'), isTrue);
      expect(DeviceMergePolicy.isValidCode('ACDEF'), isFalse);
      expect(DeviceMergePolicy.isValidCode('ACDEF!'), isFalse);
      // A look-alike letter is invalid, not silently "helped" into a digit.
      expect(DeviceMergePolicy.isValidCode('4B34CA'), isFalse);
      expect(DeviceMergePolicy.normalizeCode('4B34CA'), '4B34CA');
    });

    test('a code goes stale after its window', () {
      expect(DeviceMergePolicy.isFresh(t0, now: t0.add(const Duration(minutes: 5))), isTrue);
      expect(DeviceMergePolicy.isFresh(t0, now: t0.add(const Duration(minutes: 20))), isFalse);
      expect(DeviceMergePolicy.isFresh(t0, now: t0.subtract(const Duration(minutes: 1))), isFalse);
    });

    test('union never overwrites and is idempotent', () {
      final a = {'x', 'y'};
      final b = {'y', 'z'};
      final once = DeviceMergePolicy.union(a, b);
      expect(once.toSet(), {'x', 'y', 'z'});
      final twice = DeviceMergePolicy.union(once, b);
      expect(twice.toSet(), once.toSet());
    });

    test('merging maps adds only missing keys', () {
      final local = {'a': 'local-a'};
      final remote = {'a': 'remote-a', 'b': 'remote-b'};
      final (merged, gained) = DeviceMergePolicy.mergeMaps(local, remote);
      expect(merged['a'], 'local-a');
      expect(merged['b'], 'remote-b');
      expect(gained, 1);
      // Running it again changes nothing.
      final (again, gainedAgain) = DeviceMergePolicy.mergeMaps(merged, remote);
      expect(again, merged);
      expect(gainedAgain, 0);
    });

    test('an empty account merge reports zero, not a failure', () {
      final r = DeviceMergePolicy.fromServer(const {});
      expect(r.totalAdded, 0);
      expect(r.alreadyMerged, isFalse);
      expect(r.summaryLine, isNotEmpty);
      expect(r.summaryLine, isNot(contains('Exception')));
    });

    test('server counts parse from strings and clamp negatives', () {
      final r = DeviceMergePolicy.fromServer({
        'watchlist_added': '12',
        'history_added': -3,
        'friends_added': 2,
        'already_merged': true,
      });
      expect(r.watchlistAdded, 12);
      expect(r.historyAdded, 0);
      expect(r.friendsAdded, 2);
      expect(r.alreadyMerged, isTrue);
      expect(r.summaryLine, contains('already used'));
    });

    test('summary uses real numbers in Easy English', () {
      expect(
        const DeviceMergeResult(watchlistAdded: 1).summaryLine,
        '1 thing came back with you.',
      );
      expect(
        const DeviceMergeResult(watchlistAdded: 7, friendsAdded: 3).summaryLine,
        '10 things came back with you.',
      );
    });
  });
}
