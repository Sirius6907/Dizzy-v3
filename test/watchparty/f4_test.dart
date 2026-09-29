import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/watchparty/late_join_policy.dart';
import 'package:dizzy/services/watchparty/media_card_intent.dart';
import 'package:dizzy/services/watchparty/queue_vote_policy.dart';
import 'package:dizzy/services/watchparty/room_invite.dart';
import 'package:dizzy/services/watchparty/watch_sync_engine.dart';

/// F4 — Together Cinema. The rules that make a room feel easy.
void main() {
  group('queue voting — add / move / remove', () {
    List<QueueEntry> seed() => QueueVotePolicy.applyAll(const [], [
          const QueueOp(type: QueueOpType.add, itemId: 'a', voterId: 'u1', seq: 1),
          const QueueOp(type: QueueOpType.add, itemId: 'b', voterId: 'u2', seq: 2),
        ]);

    test('adding a title queues it with the tapper as first voter', () {
      final q = QueueVotePolicy.apply(
        const [],
        const QueueOp(type: QueueOpType.add, itemId: 'tt1', voterId: 'u1', seq: 1),
      );
      expect(q.length, 1);
      expect(q.first.itemId, 'tt1');
      expect(q.first.votes, 1);
    });

    test('adding the same title again is a vote, not a duplicate', () {
      final q = QueueVotePolicy.apply(
        seed(),
        const QueueOp(type: QueueOpType.add, itemId: 'a', voterId: 'u2', seq: 3),
      );
      expect(q.where((e) => e.itemId == 'a').length, 1);
      expect(q.firstWhere((e) => e.itemId == 'a').votes, 2);
    });

    test('one person cannot vote twice for the same title', () {
      final once = QueueVotePolicy.apply(
        seed(),
        const QueueOp(type: QueueOpType.add, itemId: 'a', voterId: 'u1', seq: 3),
      );
      expect(once.firstWhere((e) => e.itemId == 'a').votes, 1);
    });

    test('the most-wanted title is next', () {
      final q = QueueVotePolicy.apply(
        seed(),
        const QueueOp(type: QueueOpType.add, itemId: 'a', voterId: 'u3', seq: 3),
      );
      expect(QueueVotePolicy.next(q)?.itemId, 'a');
      expect(QueueVotePolicy.tally(q)['a'], 2);
    });

    test('a tie never flickers between phones', () {
      final q = seed();
      expect(QueueVotePolicy.next(q)?.itemId, 'a');
      // Reversing the input order lands on the same answer.
      final reversed = QueueVotePolicy.applyAll(const [], [
        const QueueOp(type: QueueOpType.add, itemId: 'b', voterId: 'u2', seq: 2),
        const QueueOp(type: QueueOpType.add, itemId: 'a', voterId: 'u1', seq: 1),
      ]);
      expect(QueueVotePolicy.next(reversed)?.itemId, 'a');
    });

    test('move reorders and clamps out-of-range targets', () {
      final moved = QueueVotePolicy.apply(
        seed(),
        const QueueOp(
          type: QueueOpType.move,
          itemId: 'b',
          voterId: 'u1',
          seq: 4,
          index: 0,
        ),
      );
      expect(moved.map((e) => e.itemId).toList(), ['b', 'a']);

      final clampedHigh = QueueVotePolicy.apply(
        seed(),
        const QueueOp(
          type: QueueOpType.move,
          itemId: 'a',
          voterId: 'u1',
          seq: 5,
          index: 99,
        ),
      );
      expect(clampedHigh.map((e) => e.itemId).toList(), ['b', 'a']);

      // Negative target: invalid op, list unchanged (never throws).
      final clampedLow = QueueVotePolicy.apply(
        seed(),
        const QueueOp(
          type: QueueOpType.move,
          itemId: 'b',
          voterId: 'u1',
          seq: 6,
          index: -5,
        ),
      );
      expect(clampedLow.map((e) => e.itemId).toList(), ['a', 'b']);
    });

    test('remove drops the title; removing a stranger is harmless', () {
      final gone = QueueVotePolicy.apply(
        seed(),
        const QueueOp(type: QueueOpType.remove, itemId: 'a', voterId: 'u1', seq: 7),
      );
      expect(gone.map((e) => e.itemId), ['b']);

      final noop = QueueVotePolicy.apply(
        gone,
        const QueueOp(type: QueueOpType.remove, itemId: 'zzz', voterId: 'u1', seq: 8),
      );
      expect(noop.map((e) => e.itemId), ['b']);
    });

    test('the op-log is order-independent by seq', () {
      final ops = [
        const QueueOp(type: QueueOpType.add, itemId: 'c', voterId: 'u3', seq: 3),
        const QueueOp(type: QueueOpType.add, itemId: 'a', voterId: 'u1', seq: 1),
        const QueueOp(type: QueueOpType.add, itemId: 'b', voterId: 'u2', seq: 2),
      ];
      final forward = QueueVotePolicy.applyAll(const [], ops);
      final backward = QueueVotePolicy.applyAll(const [], ops.reversed.toList());
      expect(forward.map((e) => e.itemId).toList(),
          backward.map((e) => e.itemId).toList());
    });

    test('an invalid op is refused, not half-applied', () {
      final before = seed();
      final blank = QueueVotePolicy.apply(
        before,
        const QueueOp(type: QueueOpType.add, itemId: '', voterId: 'u1', seq: 1),
      );
      expect(blank.length, before.length);
      final negative = QueueVotePolicy.apply(
        before,
        const QueueOp(
          type: QueueOpType.move,
          itemId: 'a',
          voterId: 'u1',
          seq: 1,
          index: -1,
        ),
      );
      expect(negative, before);
    });

    test('the queue is capped and never overfills', () {
      var q = const <QueueEntry>[];
      for (var i = 0; i < QueueVotePolicy.maxItems + 10; i++) {
        q = QueueVotePolicy.apply(
          q,
          QueueOp(type: QueueOpType.add, itemId: 't$i', voterId: 'u1', seq: i),
        );
      }
      expect(q.length, QueueVotePolicy.maxItems);
    });

    test('ops and entries round-trip, dropping corrupt rows', () {
      final op = QueueOp.fromJson(const {
        'type': 'add',
        'itemId': 'tt9',
        'index': 0,
        'voterId': 'u1',
        'seq': 4,
      });
      expect(op, isNotNull);
      expect(op!.itemId, 'tt9');
      expect(op.toJson()['type'], 'add');

      expect(QueueOp.fromJson(const {'type': 'nope', 'itemId': 'a', 'voterId': 'u'}), isNull);
      expect(QueueOp.fromJson(const {'type': 'add', 'itemId': '', 'voterId': 'u'}), isNull);

      final entries = QueueVotePolicy.decodeList([
        {'itemId': 'ok', 'title': 'Fine', 'voters': ['u1', '', 'u1']},
        {'title': 'No id'},
        'garbage',
      ]);
      expect(entries.length, 1);
      expect(entries.first.voters, {'u1'});
    });

    test('the summary line uses real numbers and Easy English', () {
      expect(QueueVotePolicy.summaryLine(const []), 'Nobody picked anything yet.');
      expect(QueueVotePolicy.summaryLine(seed()),
          '2 titles are waiting. Most wanted plays next.');
    });
  });

  group('late join — land where everyone else is', () {
    WatchSyncMessage msg({
      int positionMs = 600000,
      int sentAt = 1000,
      bool playing = true,
      String title = 'Dune',
    }) =>
        WatchSyncMessage(
          version: 2,
          mediaRef: 'imdb:tt1160419',
          mediaTitle: title,
          positionMs: positionMs,
          hostSentAtMs: sentAt,
          playing: playing,
        );

    test('a guest who is behind seeks to the host position', () {
      final plan = LateJoinPolicy.planFor(msg(positionMs: 600000, sentAt: 1000), nowMs: 1000);
      expect(plan.seekMs, 600000);
      expect(plan.alreadyInSync, isFalse);
    });

    test('in-flight time is added, so a slow join still lands in sync', () {
      final plan = LateJoinPolicy.planFor(
        msg(positionMs: 600000, sentAt: 1000),
        nowMs: 6000,
      );
      // 600s + 5s of travel.
      expect(plan.seekMs, 605000);
    });

    test('a guest already close is left alone', () {
      final plan = LateJoinPolicy.planFor(
        msg(positionMs: 600000, sentAt: 1000),
        guestPositionMs: 600500,
        guestPlaying: true,
        nowMs: 1000,
      );
      expect(plan.seekMs, isNull);
      expect(plan.alreadyInSync, isTrue);
    });

    test('a far-behind guest gets the catching-up line', () {
      final plan = LateJoinPolicy.planFor(
        msg(positionMs: 600000, sentAt: 1000),
        guestPositionMs: 0,
        nowMs: 1000,
      );
      expect(plan.showCatchingUp, isTrue);
      expect(
        LateJoinPolicy.arrivalLine(plan, memberCount: 3),
        'Jumping you to where Dune is right now.',
      );
    });

    test('a near guest gets the quiet line', () {
      final plan = LateJoinPolicy.planFor(
        msg(positionMs: 600000, sentAt: 1000),
        guestPositionMs: 600200,
        guestPlaying: true,
        nowMs: 1000,
      );
      expect(plan.showCatchingUp, isFalse);
      expect(
        LateJoinPolicy.arrivalLine(plan, memberCount: 3),
        'You are in. Watching Dune.',
      );
    });

    test('pause state follows the host on arrival', () {
      final plan = LateJoinPolicy.planFor(
        msg(playing: false, positionMs: 600000, sentAt: 1000),
        guestPositionMs: 0,
        guestPlaying: true,
        nowMs: 1000,
      );
      expect(plan.play, isFalse);
    });

    test('an idle room never says catching up', () {
      final plan = LateJoinPolicy.planForIdleRoom();
      expect(plan.showCatchingUp, isFalse);
      expect(plan.seekMs, 0);
      expect(
        LateJoinPolicy.arrivalLine(plan, memberCount: 2),
        'You are in. They are picking what to play.',
      );
    });

    test('arrival copy is Easy English — no codes or tech words', () {
      final plan = LateJoinPolicy.planFor(msg(), guestPositionMs: 0, nowMs: 1000);
      final line = LateJoinPolicy.arrivalLine(plan, memberCount: 4);
      for (final banned in ['Exception', 'null', 'E_', 'stack']) {
        expect(line.contains(banned), isFalse, reason: 'leaked "$banned"');
      }
    });
  });

  group('DM media card — tap to join in sync', () {
    const movie = MediaCardRef(mediaId: 'tt1160419', title: 'Dune', mediaType: 'movie');
    const song = MediaCardRef(mediaId: '42', title: 'Blue', mediaType: 'music');
    const novel = MediaCardRef(mediaId: '99', title: 'Piranesi', mediaType: 'book');
    const ep = MediaCardRef(
      mediaId: '1396',
      title: 'Breaking Bad',
      mediaType: 'series',
      season: 1,
      episode: 3,
    );

    test('media types map to watch / listen / read', () {
      expect(movie.mode, SyncMode.watch);
      expect(song.mode, SyncMode.listen);
      expect(novel.mode, SyncMode.read);
      expect(ep.mode, SyncMode.watch);
    });

    test('an unknown media type falls back to watch', () {
      const odd = MediaCardRef(mediaId: '1', title: 'X', mediaType: 'something-else');
      expect(odd.mode, SyncMode.watch);
    });

    test('the intent carries the mode the card chose', () {
      final intent = MediaCardIntent.of(song);
      expect(intent.mode, SyncMode.listen);
      expect(intent.actionLineFor(intent.mode), 'Listen with them');
      expect(MediaCardIntent.of(movie).actionLineFor(SyncMode.watch), 'Watch with them');
      expect(MediaCardIntent.of(novel).actionLineFor(SyncMode.read), 'Read with them');
    });

    test('the media ref matches what the party engine already speaks', () {
      expect(movie.toMediaRef(), 'imdb:tt1160419');
      expect(ep.toMediaRef(), 'tmdb:tv:1396:S1:E3');
      expect(song.toMediaRef(), 'tmdb:movie:42');
    });

    test('an empty id is dropped rather than rendered as a blank card', () {
      expect(MediaCardRef.fromJson(const {'title': 'No id'}), isNull);
      expect(
        MediaCardRef.fromJson(const {'mediaId': 'tt1', 'title': 'Ok'})?.title,
        'Ok',
      );
    });

    test('the modal header is never empty', () {
      expect(MediaCardIntent.of(movie).modalTitle, 'Watch "Dune" together');
      expect(
        const MediaCardIntent(
          card: MediaCardRef(mediaId: '1', title: '', mediaType: 'movie'),
          mode: SyncMode.watch,
        ).modalTitle,
        'Join your friend',
      );
    });
  });

  group('room invite — one tap, no dead ends', () {
    const invite = RoomInvite(
      roomCode: 'K3MQ7X',
      mediaTitle: 'Dune',
      hostName: 'Rhea',
    );

    test('the code comes first so it survives truncation', () {
      final msg = invite.message;
      expect(msg.contains('K3MQ7X'), isTrue);
      expect(msg.indexOf('K3MQ7X'), lessThan(msg.indexOf('Rhea')));
    });

    test('a pass is included only when the room has one', () {
      expect(const RoomInvite(roomCode: 'ABC123').message.contains('Pass'), isFalse);
      expect(
        const RoomInvite(roomCode: 'ABC123', pass: '123456').message,
        contains('Pass: 123456'),
      );
    });

    test('the spoken line is the code and nothing else', () {
      expect(invite.spokenLine, 'Room code is K3MQ7X.');
    });

    test('result copy is Easy English for every outcome', () {
      for (final r in ShareResult.values) {
        final line = RoomInviteService.resultLine(r);
        expect(line.isNotEmpty, isTrue);
        expect(line.contains('Exception'), isFalse);
      }
      expect(RoomInviteService.resultLine(ShareResult.failed),
          'Code is on screen. Read it out loud.');
    });
  });

  group('guest auto-open — a code is the only tap', () {
    test('an open room opens straight away', () {
      final d = GuestAutoOpenPolicy.decide(roomCode: 'K3MQ7X', pass: null, hasMedia: true);
      expect(d.openNow, isTrue);
      expect(d.prewarm, isTrue);
    });

    test('a locked room asks for the pass first', () {
      final d = GuestAutoOpenPolicy.decide(roomCode: 'K3MQ7X', pass: '123456', hasMedia: true);
      expect(d.openNow, isFalse);
      expect(d.prewarm, isFalse);
      expect(d.line, contains('pass'));
    });

    test('an empty room opens without pretending something is playing', () {
      final d = GuestAutoOpenPolicy.decide(roomCode: 'K3MQ7X', pass: null, hasMedia: false);
      expect(d.openNow, isTrue);
      expect(d.prewarm, isFalse);
      expect(d.line, isNull);
    });

    test('a bad code is refused with a line, not a silent failure', () {
      final d = GuestAutoOpenPolicy.decide(roomCode: '  ', pass: null, hasMedia: true);
      expect(d.openNow, isFalse);
      expect(d.line, isNotNull);
      expect(d.line, isNotEmpty);
    });

    test('a guest already in the room is not re-announced', () {
      const m = WatchSyncMessage(
        version: 2,
        mediaRef: 'imdb:tt1',
        positionMs: 0,
        hostSentAtMs: 0,
        playing: true,
      );
      expect(GuestAutoOpenPolicy.shouldAnnounce(m, alreadyInRoom: true), isFalse);
      expect(GuestAutoOpenPolicy.shouldAnnounce(m, alreadyInRoom: false), isTrue);
    });
  });
}
