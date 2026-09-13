import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/utils/perf/performance_mode.dart';

void main() {
  setUp(PerformanceMode.resetForTest);

  group('PerformanceMode.applyLevel', () {
    test('normal keeps visuals on', () {
      PerformanceMode.applyLevel(PerfLevel.normal);
      expect(PerformanceMode.ambientAllowed.value, true);
      expect(PerformanceMode.glassAllowed.value, true);
    });

    test('caution freezes ambient, keeps glass', () {
      PerformanceMode.applyLevel(PerfLevel.caution);
      expect(PerformanceMode.ambientAllowed.value, false);
      expect(PerformanceMode.glassAllowed.value, true);
    });

    test('critical kills ambient + glass', () {
      PerformanceMode.applyLevel(PerfLevel.critical);
      expect(PerformanceMode.ambientAllowed.value, false);
      expect(PerformanceMode.glassAllowed.value, false);
    });

    test('smooth mode forces visuals off at every level', () {
      PerformanceMode.setSmoothMode(true);
      PerformanceMode.applyLevel(PerfLevel.normal);
      expect(PerformanceMode.ambientAllowed.value, false);
      expect(PerformanceMode.glassAllowed.value, false);
    });

    test('smooth mode off restores level visuals', () {
      PerformanceMode.setSmoothMode(true);
      PerformanceMode.setSmoothMode(false);
      expect(PerformanceMode.ambientAllowed.value, true);
      expect(PerformanceMode.glassAllowed.value, true);
    });
  });
}
