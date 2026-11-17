import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dizzy/services/iptv/cricket_priority.dart';
import 'package:dizzy/services/iptv/hardcoded_channels.dart';
import 'package:dizzy/services/iptv/iptv_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CricketPriority.parseOrder', () {
    test('accepts a bare JSON array', () {
      expect(CricketPriority.parseOrder('["star_sports_1", "sports18_1"]'), [
        'star_sports_1',
        'sports18_1',
      ]);
    });

    test('accepts the object form with a channels key', () {
      expect(
        CricketPriority.parseOrder(
          '{"channels": ["willow_cricket"], "label": "INDIA LIVE"}',
        ),
        ['willow_cricket'],
      );
    });

    test('accepts the order, ids and priority aliases', () {
      for (final key in const ['order', 'ids', 'priority']) {
        expect(CricketPriority.parseOrder('{"$key": ["sony_ten_1"]}'), [
          'sony_ten_1',
        ], reason: 'alias $key should be honoured');
      }
    });

    test('normalises case and trims whitespace', () {
      expect(CricketPriority.parseOrder('[" Star_Sports_1 ", "DD_SPORTS"]'), [
        'star_sports_1',
        'dd_sports',
      ]);
    });

    test('drops duplicates while keeping the first position', () {
      expect(
        CricketPriority.parseOrder(
          '["star_sports_2", "star_sports_1", "STAR_SPORTS_2"]',
        ),
        ['star_sports_2', 'star_sports_1'],
      );
    });

    test('drops empty entries', () {
      expect(CricketPriority.parseOrder('["", "  ", "willow_cricket"]'), [
        'willow_cricket',
      ]);
    });

    test('returns empty for garbage so the caller falls back', () {
      for (final raw in const ['', '   ', 'not json', '{', '42', '"text"']) {
        expect(
          CricketPriority.parseOrder(raw),
          isEmpty,
          reason: 'raw "$raw" must not yield a pin order',
        );
      }
    });

    test('returns empty when the object has no list field', () {
      expect(CricketPriority.parseOrder('{"label": "LIVE"}'), isEmpty);
    });
  });

  group('CricketPriority.parseLabel', () {
    test('reads the label from the object form', () {
      expect(
        CricketPriority.parseLabel('{"channels": [], "label": " INDIA LIVE "}'),
        'INDIA LIVE',
      );
    });

    test('returns null for a bare array', () {
      expect(CricketPriority.parseLabel('["star_sports_1"]'), isNull);
    });

    test('returns null for a missing or blank label', () {
      expect(CricketPriority.parseLabel('{"channels": []}'), isNull);
      expect(CricketPriority.parseLabel('{"label": "   "}'), isNull);
      expect(CricketPriority.parseLabel('{"label": 7}'), isNull);
    });

    test('returns null for garbage', () {
      expect(CricketPriority.parseLabel('not json'), isNull);
      expect(CricketPriority.parseLabel(''), isNull);
    });
  });

  group('CricketPriority.choosePin', () {
    const order = ['star_sports_1', 'sports18_1', 'dd_sports'];

    test('returns null when nothing is available', () {
      final pin = CricketPriority.choosePin(order: order, available: const {});
      expect(pin, isNull);
    });

    test('picks the first available channel in ranked order', () {
      final pin = CricketPriority.choosePin(
        order: order,
        available: const {'star_sports_1': false, 'sports18_1': true},
      );
      expect(pin?.channel.id, 'sports18_1');
      expect(pin?.label, CricketPriority.defaultLabel);
    });

    test('honours a config-supplied label', () {
      final pin = CricketPriority.choosePin(
        order: order,
        available: const {'dd_sports': true},
        label: 'INDIA vs AUS',
      );
      expect(pin?.channel.id, 'dd_sports');
      expect(pin?.label, 'INDIA vs AUS');
    });

    test('skips ids that are not in the catalog', () {
      final pin = CricketPriority.choosePin(
        order: const ['made_up_channel', 'sports18_1'],
        available: const {'made_up_channel': true, 'sports18_1': true},
      );
      expect(pin?.channel.id, 'sports18_1');
    });

    test('returns null when only unknown ids are available', () {
      final pin = CricketPriority.choosePin(
        order: const ['made_up_channel'],
        available: const {'made_up_channel': true},
      );
      expect(pin, isNull);
    });

    test('equality is by channel id and label', () {
      const a = CricketPin(
        channel: HardcodedChannel(
          id: 'dd_sports',
          name: 'DD Sports',
          short: 'DD',
          category: 'Cricket',
          keywords: ['dd sports'],
          gradient: [],
        ),
        label: 'LIVE',
      );
      const b = CricketPin(
        channel: HardcodedChannel(
          id: 'dd_sports',
          name: 'DD Sports',
          short: 'DD',
          category: 'Cricket',
          keywords: ['dd sports'],
          gradient: [],
        ),
        label: 'LIVE',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          const CricketPin(
            channel: HardcodedChannel(
              id: 'dd_sports',
              name: 'DD Sports',
              short: 'DD',
              category: 'Cricket',
              keywords: ['dd sports'],
              gradient: [],
            ),
            label: 'OTHER',
          ),
        ),
      );
    });
  });

  group('shipped cricket defaults', () {
    test('every default order id exists in the catalog', () {
      for (final id in CricketPriority.defaultOrder) {
        expect(
          HardcodedChannels.byId(id),
          isNotNull,
          reason: 'defaultOrder id "$id" is missing from the catalog',
        );
      }
    });

    test('every default order id belongs to the Cricket category', () {
      for (final id in CricketPriority.defaultOrder) {
        expect(
          HardcodedChannels.byId(id)?.category,
          'Cricket',
          reason: '"$id" must be grouped under Cricket',
        );
      }
    });

    test('the Cricket category ships the whole priority pool', () {
      final cricket = HardcodedChannels.byCategory('Cricket');
      expect(
        cricket.length,
        greaterThanOrEqualTo(CricketPriority.defaultOrder.length),
      );
      for (final id in CricketPriority.defaultOrder) {
        expect(cricket.any((c) => c.id == id), isTrue);
      }
    });

    test('the cricket category is a visible section by default', () {
      expect(
        IptvSettings.defaultCategories,
        contains('Cricket & India Matches'),
      );
    });
  });

  group('IptvSettings category migration', () {
    test('fresh install gets the cricket section', () async {
      SharedPreferences.setMockInitialValues({});
      await IptvSettings.initialize();
      expect(
        IptvSettings.visibleCategories.value,
        contains('Cricket & India Matches'),
      );
    });

    test('existing install keeps its list and gains cricket once', () async {
      const saved = ['Premier Live Broadcasts', 'Motorsport'];
      SharedPreferences.setMockInitialValues({
        'iptv_visible_categories': saved,
      });
      await IptvSettings.initialize();

      final cats = IptvSettings.visibleCategories.value;
      expect(cats, containsAll(saved));
      expect(cats, contains('Cricket & India Matches'));

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('iptv_visible_categories'),
        contains('Cricket & India Matches'),
      );
      expect(prefs.getInt('iptv_category_schema'), 2);
    });

    test('hiding cricket after the migration sticks', () async {
      SharedPreferences.setMockInitialValues({
        'iptv_visible_categories': ['Premier Live Broadcasts'],
        'iptv_category_schema': 2,
      });
      await IptvSettings.initialize();
      expect(
        IptvSettings.visibleCategories.value,
        isNot(contains('Cricket & India Matches')),
      );
    });

    test('migration does not duplicate an already-present section', () async {
      SharedPreferences.setMockInitialValues({
        'iptv_visible_categories': [
          'Premier Live Broadcasts',
          'Cricket & India Matches',
        ],
      });
      await IptvSettings.initialize();
      final cats = IptvSettings.visibleCategories.value;
      expect(cats.where((c) => c == 'Cricket & India Matches').length, 1);
    });
  });
}
