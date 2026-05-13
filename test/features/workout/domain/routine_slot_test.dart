import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';

void main() {
  group('RoutineSlot', () {
    test('SCENARIO-043: required-only roundtrip, nullable fields null', () {
      const slot = RoutineSlot(
        exerciseId: 'bench-press',
        exerciseName: 'Bench Press',
        muscleGroup: 'chest',
        targetSets: 4,
        targetRepsMin: 8,
        targetRepsMax: 12,
        restSeconds: 90,
      );

      final json = slot.toJson();
      final decoded = RoutineSlot.fromJson(json);

      expect(decoded.exerciseId, equals('bench-press'));
      expect(decoded.exerciseName, equals('Bench Press'));
      expect(decoded.muscleGroup, equals('chest'));
      expect(decoded.targetSets, equals(4));
      expect(decoded.targetRepsMin, equals(8));
      expect(decoded.targetRepsMax, equals(12));
      expect(decoded.restSeconds, equals(90));
      expect(decoded.targetWeightKg, isNull);
      expect(decoded.notes, isNull);
      expect(decoded, equals(slot));
    });

    test(
        'SCENARIO-044: roundtrip with targetWeightKg and notes preserves values',
        () {
      const slot = RoutineSlot(
        exerciseId: 'back-squat',
        exerciseName: 'Back Squat',
        muscleGroup: 'quads',
        targetSets: 5,
        targetRepsMin: 3,
        targetRepsMax: 5,
        restSeconds: 180,
        targetWeightKg: 80.5,
        notes: 'tempo 3-1-1',
      );

      final json = slot.toJson();
      final decoded = RoutineSlot.fromJson(json);

      expect(decoded.targetWeightKg, equals(80.5));
      expect(decoded.notes, equals('tempo 3-1-1'));
      expect(decoded, equals(slot));
    });

    test(
        'SCENARIO-045: raw map missing targetWeightKg and notes deserializes with null',
        () {
      final rawMap = <String, dynamic>{
        'exerciseId': 'deadlift',
        'exerciseName': 'Deadlift',
        'muscleGroup': 'back',
        'targetSets': 3,
        'targetRepsMin': 5,
        'targetRepsMax': 5,
        'restSeconds': 120,
      };

      final slot = RoutineSlot.fromJson(rawMap);

      expect(slot.targetWeightKg, isNull);
      expect(slot.notes, isNull);
      expect(slot.exerciseId, equals('deadlift'));
    });
  });
}
