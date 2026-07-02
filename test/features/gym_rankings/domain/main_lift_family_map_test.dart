import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gym_rankings/domain/main_lift_family_map.dart';
import 'package:treino/features/workout/domain/set_log.dart';

void main() {
  DateTime t() => DateTime.utc(2026, 5, 18, 10, 0, 0);

  SetLog buildLog({
    required String exerciseId,
    required double weightKg,
    String exerciseName = 'Exercise',
  }) {
    return SetLog(
      id: 'log-1',
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      setNumber: 1,
      reps: 5,
      weightKg: weightKg,
      completedAt: t(),
    );
  }

  group('SCENARIO-RANK-2: kMainLiftFamilies membership', () {
    test('squat-barra matches the squat family', () {
      expect(kMainLiftFamilies[MainLift.squat], contains('squat-barra'));
    });

    test('bench-press-barra matches the bench family', () {
      expect(kMainLiftFamilies[MainLift.bench], contains('bench-press-barra'));
    });

    test(
        'deadlift-barra AND sumo-deadlift-barra both match the deadlift '
        'family', () {
      expect(kMainLiftFamilies[MainLift.deadlift], contains('deadlift-barra'));
      expect(
        kMainLiftFamilies[MainLift.deadlift],
        contains('sumo-deadlift-barra'),
      );
    });

    test('dumbbell/multipower/machine variants do NOT match any family', () {
      final allFamilyIds = kMainLiftFamilies.values.expand((s) => s).toSet();
      expect(allFamilyIds, isNot(contains('squat-multipower')));
      expect(allFamilyIds, isNot(contains('bench-press-mancuerna')));
    });

    test(
        'romanian/stiff-leg deadlift variants do NOT match the deadlift '
        'family (assistance lifts, excluded)', () {
      expect(
        kMainLiftFamilies[MainLift.deadlift],
        isNot(contains('romanian-deadlift-barra')),
      );
      expect(
        kMainLiftFamilies[MainLift.deadlift],
        isNot(contains('stiff-leg-deadlift-barra')),
      );
    });
  });

  group('SCENARIO-RANK-2: familyMaxWeight', () {
    test('returns the max weight among matching logs for squat', () {
      final logs = [
        buildLog(exerciseId: 'squat-barra', weightKg: 100),
        buildLog(exerciseId: 'squat-barra', weightKg: 120),
        buildLog(exerciseId: 'bench-press-barra', weightKg: 999),
      ];

      expect(familyMaxWeight(MainLift.squat, logs), equals(120));
    });

    test('deadlift takes the max across BOTH conventional and sumo', () {
      final logs = [
        buildLog(exerciseId: 'deadlift-barra', weightKg: 140),
        buildLog(exerciseId: 'sumo-deadlift-barra', weightKg: 160),
      ];

      expect(familyMaxWeight(MainLift.deadlift, logs), equals(160));
    });

    test('returns null when no logs match the family', () {
      final logs = [
        buildLog(exerciseId: 'squat-multipower', weightKg: 100),
        buildLog(exerciseId: 'romanian-deadlift-barra', weightKg: 100),
      ];

      expect(familyMaxWeight(MainLift.squat, logs), isNull);
      expect(familyMaxWeight(MainLift.deadlift, logs), isNull);
    });

    test('returns null for an empty log list', () {
      expect(familyMaxWeight(MainLift.bench, const []), isNull);
    });
  });
}
