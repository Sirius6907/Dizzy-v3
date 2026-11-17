import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/iptv/hardcoded_channels.dart';
import 'package:dizzy/services/iptv/iptv_settings.dart';
import 'package:dizzy/widgets/iptv/iptv_hero_carousel.dart';

Widget _host(IptvHeroCarousel carousel) {
  return MaterialApp(
    home: Scaffold(body: SizedBox(height: 520, child: carousel)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Keep the auto-rotate timer out of the way; each test pumps by hand.
    IptvSettings.heroAutoRotate.value = false;
  });

  testWidgets('pinned slide renders the cricket priority badge', (
    tester,
  ) async {
    final cricket = HardcodedChannels.byId('star_sports_1')!;
    final other = HardcodedChannels.byId('espn')!;

    await tester.pumpWidget(
      _host(
        IptvHeroCarousel(
          channels: [cricket, other],
          priorityChannelId: cricket.id,
          priorityLabel: 'INDIA CRICKET LIVE',
          onWatchNow: (_) {},
          onSourcesTap: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('INDIA CRICKET LIVE'), findsOneWidget);
    expect(find.byIcon(Icons.sports_cricket_rounded), findsOneWidget);
    // The shipped LIVE pill is still there alongside it.
    expect(find.text('LIVE BROADCAST'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without a pin the badges are the shipped ones', (tester) async {
    final cricket = HardcodedChannels.byId('star_sports_1')!;

    await tester.pumpWidget(
      _host(
        IptvHeroCarousel(
          channels: [cricket],
          onWatchNow: (_) {},
          onSourcesTap: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('LIVE BROADCAST'), findsOneWidget);
    expect(find.byIcon(Icons.sports_cricket_rounded), findsNothing);
    expect(find.text('INDIA CRICKET LIVE'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a blank label falls back to the default badge text', (
    tester,
  ) async {
    final cricket = HardcodedChannels.byId('willow_cricket')!;

    await tester.pumpWidget(
      _host(
        IptvHeroCarousel(
          channels: [cricket],
          priorityChannelId: cricket.id,
          priorityLabel: '   ',
          onWatchNow: (_) {},
          onSourcesTap: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('CRICKET PRIORITY'), findsOneWidget);
    expect(find.byIcon(Icons.sports_cricket_rounded), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
