import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/scraper/sites/movy.dart';

void main() {
  // Live third-party site: skip while it answers empty (site-side outage
  // or API move — not an app regression). Un-skip after recovery.
  test('MovyScraper decrypts live stream ciphertext', skip: 'Live movy site answering empty since Sep 2026 (site-side).', () async {
    final scraper = MovyScraper();
    final streams = await scraper.scrape(
      type: 'movie',
      title: 'Fight Club',
      year: 1999,
      imdbId: 'tt0137523',
    );

    print('Movy scraped streams count: ${streams.length}');
    for (final s in streams) {
      print(' - ${s.title}: ${s.url}');
    }

    expect(streams.isNotEmpty, true);
  });
}
