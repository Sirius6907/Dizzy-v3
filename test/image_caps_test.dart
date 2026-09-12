import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/utils/perf/image_caps.dart';

/// Polish P14: backdrop ≤960 / logo ≤400 frozen — OOM zero on 3GB.
void main() {
  group('ImageCaps', () {
    test('P23 contract frozen', () {
      expect(ImageCaps.kBackdrop, 960);
      expect(ImageCaps.kLogo, 400);
      expect(ImageCaps.kBackdrop, lessThanOrEqualTo(960));
    });

    test('card + thumb ladder ascending', () {
      expect(ImageCaps.kThumb, lessThan(ImageCaps.kCardW));
      expect(ImageCaps.kCardW, lessThan(ImageCaps.kBackdrop));
      expect(ImageCaps.kCardH, 750);
    });

    test('capWidth clamps strays', () {
      expect(ImageCaps.capWidth(1280), 960);
      expect(ImageCaps.capWidth(1920), 960);
      expect(ImageCaps.capWidth(500), 500);
      expect(ImageCaps.capWidth(100), ImageCaps.kThumb);
    });
  });
}
