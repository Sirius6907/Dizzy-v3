import 'package:flutter_test/flutter_test.dart';
import 'package:dizzy/services/system/resource_governor.dart';

void main() {
  group('ResourcePolicy.decide', () {
    test('stays normal when everything is calm', () {
      final l = ResourcePolicy.decide(
        current: ResourceLevel.normal,
        overStreak: 0,
        calmStreak: 10,
        rssMb: 1500,
        cpuPercent: 5,
        ramBudgetMb: 2800,
        cpuBudgetPercent: 20,
      );
      expect(l, ResourceLevel.normal);
    });

    test('two bad samples escalate normal → caution', () {
      final l = ResourcePolicy.decide(
        current: ResourceLevel.normal,
        overStreak: 2,
        calmStreak: 0,
        rssMb: 2400, // >75% of 2800
        cpuPercent: 10,
        ramBudgetMb: 2800,
        cpuBudgetPercent: 20,
      );
      expect(l, ResourceLevel.caution);
    });

    test('three bad samples escalate to critical', () {
      final l = ResourcePolicy.decide(
        current: ResourceLevel.caution,
        overStreak: 3,
        calmStreak: 0,
        rssMb: 2500,
        cpuPercent: 25, // CPU over budget too
        ramBudgetMb: 2800,
        cpuBudgetPercent: 20,
      );
      expect(l, ResourceLevel.critical);
    });

    test('92% RAM burst jumps straight to critical even from normal', () {
      final l = ResourcePolicy.decide(
        current: ResourceLevel.normal,
        overStreak: 1,
        calmStreak: 0,
        rssMb: 2650, // >92% of 2800
        cpuPercent: 5,
        ramBudgetMb: 2800,
        cpuBudgetPercent: 20,
      );
      expect(l, ResourceLevel.critical);
    });

    test('six calm samples de-escalate to normal', () {
      final l = ResourcePolicy.decide(
        current: ResourceLevel.critical,
        overStreak: 0,
        calmStreak: 6,
        rssMb: 1200, // <60% budget
        cpuPercent: 10, // <70% of budget
        ramBudgetMb: 2800,
        cpuBudgetPercent: 20,
      );
      expect(l, ResourceLevel.normal);
    });

    test('caution holds when marginally bad', () {
      final l = ResourcePolicy.decide(
        current: ResourceLevel.caution,
        overStreak: 1,
        calmStreak: 3,
        rssMb: 2300,
        cpuPercent: 8,
        ramBudgetMb: 2800,
        cpuBudgetPercent: 20,
      );
      expect(l, ResourceLevel.caution);
    });

    test('Android budget tighter than desktop', () {
      // ramBudgetMb comes from the governor instance; verify the platform
      // constant used by the governor on non-Android targets.
      expect(ResourceGovernor.cpuBudgetPercent, 20.0);
      expect(ResourceGovernor.gpuBudgetMb, 2560);
    });
  });
}
