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

    test('SCENARIO-046: supersetGroup roundtrip preserves value', () {
      const slot = RoutineSlot(
        exerciseId: 'pull-up',
        exerciseName: 'Pull Up',
        muscleGroup: 'back',
        targetSets: 3,
        targetRepsMin: 6,
        targetRepsMax: 10,
        restSeconds: 90,
        supersetGroup: 2,
      );

      final json = slot.toJson();
      final decoded = RoutineSlot.fromJson(json);

      expect(decoded.supersetGroup, equals(2));
      expect(decoded, equals(slot));
    });

    test(
        'SCENARIO-047: legacy map without supersetGroup deserializes with null '
        '(backward-compatible)', () {
      // Simulates a Firestore doc written before supersetGroup was added.
      final legacyMap = <String, dynamic>{
        'exerciseId': 'squat',
        'exerciseName': 'Squat',
        'muscleGroup': 'legs',
        'targetSets': 4,
        'targetRepsMin': 5,
        'targetRepsMax': 8,
        'restSeconds': 150,
      };

      final slot = RoutineSlot.fromJson(legacyMap);

      expect(slot.supersetGroup, isNull,
          reason: 'old docs must decode with supersetGroup: null');
    });

    // ── New field round-trips (targetReps + durationSeconds) ─────────────────

    test('SCENARIO-048: targetReps uniform roundtrip', () {
      const slot = RoutineSlot(
        exerciseId: 'curl',
        exerciseName: 'Bicep Curl',
        muscleGroup: 'biceps',
        targetSets: 3,
        targetRepsMin: 10,
        targetRepsMax: 10,
        restSeconds: 60,
        targetReps: [10],
      );

      final json = slot.toJson();
      final decoded = RoutineSlot.fromJson(json);

      expect(decoded.targetReps, equals([10]));
      expect(decoded.durationSeconds, isNull);
      expect(decoded, equals(slot));
    });

    test('SCENARIO-049: targetReps per-set sequence roundtrip', () {
      const slot = RoutineSlot(
        exerciseId: 'press',
        exerciseName: 'Bench Press',
        muscleGroup: 'chest',
        targetSets: 3,
        targetRepsMin: 6,
        targetRepsMax: 10,
        restSeconds: 90,
        targetReps: [6, 8, 10],
      );

      final json = slot.toJson();
      final decoded = RoutineSlot.fromJson(json);

      expect(decoded.targetReps, equals([6, 8, 10]));
      expect(decoded, equals(slot));
    });

    test('SCENARIO-050: durationSeconds roundtrip (time-based exercise)', () {
      const slot = RoutineSlot(
        exerciseId: 'plank',
        exerciseName: 'Plank',
        muscleGroup: 'core',
        targetSets: 3,
        targetRepsMin: 0,
        targetRepsMax: 0,
        restSeconds: 30,
        durationSeconds: 60,
      );

      final json = slot.toJson();
      final decoded = RoutineSlot.fromJson(json);

      expect(decoded.durationSeconds, equals(60));
      expect(decoded.targetReps, equals(<int>[]));
      expect(decoded, equals(slot));
    });

    test(
        'SCENARIO-051: legacy doc without targetReps/durationSeconds deserializes '
        'to defaults ([] and null)', () {
      final legacyMap = <String, dynamic>{
        'exerciseId': 'row',
        'exerciseName': 'Barbell Row',
        'muscleGroup': 'back',
        'targetSets': 4,
        'targetRepsMin': 6,
        'targetRepsMax': 10,
        'restSeconds': 120,
      };

      final slot = RoutineSlot.fromJson(legacyMap);

      expect(slot.targetReps, equals(<int>[]),
          reason: 'missing targetReps key → empty list default');
      expect(slot.durationSeconds, isNull,
          reason: 'missing durationSeconds key → null default');
    });
  });
}
