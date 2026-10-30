import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/taste/taste_event_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TasteEventService.resetForTest();
  });

  tearDown(() {
    TasteEventService.resetForTest();
  });

  test('events queue while personalisation consent is off', () async {
    var sent = 0;
    TasteEventService.configureForTest(
      consent: () => false,
      sender: (rows) async {
        sent += rows.length;
        return true;
      },
    );

    for (var i = 0; i < 5; i++) {
      TasteEventService.record(
        TasteEventKind.play,
        entityType: 'movie',
        entityId: 'tmdb:$i',
        title: 'Title $i',
        lang: 'hi',
      );
    }
    await TasteEventService.flush();

    expect(sent, 0, reason: 'consent off means nothing leaves the device');
    expect(TasteEventService.debugQueueLength, 5);
  });

  test('consent on: a full batch is sent and the queue clears', () async {
    final sentRows = <Map<String, dynamic>>[];
    TasteEventService.configureForTest(
      consent: () => true,
      sender: (rows) async {
        sentRows.addAll(rows);
        return true;
      },
    );

    for (var i = 0; i < TasteEventService.batchSize; i++) {
      TasteEventService.record(
        TasteEventKind.play,
        entityType: 'movie',
        entityId: 'tmdb:$i',
        title: 'Title $i',
        lang: i.isEven ? 'hi' : 'en',
        genres: const ['Action'],
      );
    }
    await TasteEventService.flush();

    expect(sentRows, hasLength(TasteEventService.batchSize));
    expect(TasteEventService.debugQueueLength, 0);
    final row = sentRows.first;
    expect(row['kind'], 'play');
    expect(row['entity_type'], 'movie');
    expect(row['entity_id'], 'tmdb:0');
    expect(row['genres'], ['Action']);
  });

  test('partial batches go out on a manual flush', () async {
    var batches = 0;
    TasteEventService.configureForTest(
      consent: () => true,
      sender: (rows) async {
        batches++;
        return true;
      },
    );

    TasteEventService.record(
      TasteEventKind.search,
      entityType: 'search',
      title: 'pathaan',
    );
    await TasteEventService.flush();

    expect(batches, 1);
    expect(TasteEventService.debugQueueLength, 0);
  });

  test('a failed send keeps the events for the next attempt', () async {
    var fail = true;
    TasteEventService.configureForTest(
      consent: () => true,
      sender: (rows) async => !fail,
    );

    TasteEventService.record(
      TasteEventKind.view,
      entityType: 'movie',
      entityId: 'tmdb:9',
      title: 'Something',
    );
    await TasteEventService.flush();
    expect(TasteEventService.debugQueueLength, 1);

    fail = false;
    await TasteEventService.flush();
    expect(TasteEventService.debugQueueLength, 0);
  });

  test('offline queue is capped, oldest events dropped first', () async {
    TasteEventService.configureForTest(
      consent: () => false,
      sender: (rows) async => true,
    );

    for (var i = 0; i < TasteEventService.maxQueued + 15; i++) {
      TasteEventService.record(
        TasteEventKind.view,
        entityType: 'movie',
        entityId: 'tmdb:$i',
        title: 'T$i',
      );
    }

    expect(TasteEventService.debugQueueLength, TasteEventService.maxQueued);
    final ids = TasteEventService.debugQueuedEntityIds;
    expect(ids.first, 'tmdb:15');
    expect(ids.last, 'tmdb:${TasteEventService.maxQueued + 14}');
  });

  test('a sender that throws never surfaces an error', () async {
    TasteEventService.configureForTest(
      consent: () => true,
      sender: (rows) async => throw StateError('network down'),
    );

    TasteEventService.record(
      TasteEventKind.play,
      entityType: 'movie',
      entityId: 'tmdb:1',
      title: 'Boom',
    );

    await expectLater(TasteEventService.flush(), completes);
    expect(TasteEventService.debugQueueLength, 1);
  });
}
