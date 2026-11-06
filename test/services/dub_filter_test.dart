import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/models/stream/stream_model.dart';
import 'package:dizzy/services/stream/dub_filter.dart';

StreamSource mkSrc(String name, {String? title, String? description}) =>
    StreamSource(
      addonName: 'TestAddon',
      name: name,
      title: title,
      description: description,
      url: 'https://example.com/stream',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('filterByDubMode', () {
    test('english mode (hindi=false) returns sources unchanged', () {
      final sources = [mkSrc('VidSrc'), mkSrc('MeowTV Hindiv3')];
      final out = filterByDubMode(sources, hindi: false, mediaTitle: 'Movie');
      expect(out.length, 2);
      expect(out, same(sources));
    });

    test('hindi mode keeps only hindi-tagged sources', () {
      final sources = [
        mkSrc('VidSrc Pro 1080p'),
        mkSrc('MeowTV Hindiv3 1080p'),
        mkSrc('Rivestream Hindicast'),
        mkSrc('Vidoza Server 2'),
      ];
      final out = filterByDubMode(sources, hindi: true, mediaTitle: 'Movie');
      expect(out.length, 2);
      expect(
        out.map((s) => s.name),
        containsAll(['MeowTV Hindiv3 1080p', 'Rivestream Hindicast']),
      );
    });

    test('hindi mode with zero hindi sources returns empty list', () {
      final sources = [mkSrc('VidSrc'), mkSrc('Vidoza Server')];
      final out = filterByDubMode(sources, hindi: true, mediaTitle: 'Movie');
      expect(out, isEmpty);
    });

    test('hindi subs label is NOT treated as hindi audio', () {
      final sources = [mkSrc('SuperStream — Hindi Subs 1080p')];
      final out = filterByDubMode(sources, hindi: true, mediaTitle: 'Movie');
      expect(out, isEmpty);
    });

    test('Bollywood alone is not proof of Hindi audio', () {
      final sources = [mkSrc('Classic Bollywood Collection 720p')];
      final out = filterByDubMode(sources, hindi: true, mediaTitle: 'Movie');
      expect(out, isEmpty);
    });

    test('Hindi filter rejects regional and unspecified audio', () {
      final hindi = mkSrc('Hindi English Dual Audio');
      final sources = [
        mkSrc('Tamil'),
        mkSrc('Telugu'),
        mkSrc('Malayalam Kannada Punjabi Marathi Bengali'),
        mkSrc('Multi Audio'),
        mkSrc('Dual Audio'),
        mkSrc('Original audio'),
        mkSrc('Unknown'),
        mkSrc('English'),
        hindi,
      ];
      expect(
        filterByDubMode(sources, hindi: true, mediaTitle: 'Movie'),
        [hindi],
      );
    });

    test('hindi tag in description is detected', () {
      final sources = [
        mkSrc('Generic Server', description: '1080p WEB-DL Hindi Dual Audio'),
      ];
      final out = filterByDubMode(sources, hindi: true, mediaTitle: 'Movie');
      expect(out.length, 1);
    });

    test('mediaTitle containing "hindi" does not tag all sources', () {
      // The media title is stripped from detection text, so a movie named
      // e.g. "Hindi Medium" must not make every source count as hindi.
      final sources = [
        mkSrc('VidSrc Pro 1080p', title: 'Hindi Medium 1080p'),
      ];
      final out = filterByDubMode(
        sources,
        hindi: true,
        mediaTitle: 'Hindi Medium',
      );
      expect(out, isEmpty);
    });

    test('empty input returns empty output', () {
      final out = filterByDubMode([], hindi: true, mediaTitle: 'Movie');
      expect(out, isEmpty);
    });
  });
}
