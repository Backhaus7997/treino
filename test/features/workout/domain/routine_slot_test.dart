import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

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

  // ── Phase-1: new fields + effectiveSets ──────────────────────────────────

  group('RoutineSlot — new fields (Phase 1)', () {
    test('SCENARIO-052: round-trip with explicit sets list', () {
      const slot = RoutineSlot(
        exerciseId: 'bench-press',
        exerciseName: 'Bench Press',
        muscleGroup: 'chest',
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 12,
        restSeconds: 90,
        exerciseMode: ExerciseMode.reps,
        repMode: RepMode.range,
        sets: [
          SetSpec(
              type: SetType.warmup, weightKg: 40.0, repsMin: 10, repsMax: 15),
          SetSpec(
              type: SetType.normal, weightKg: 80.0, repsMin: 8, repsMax: 12),
          SetSpec(
              type: SetType.normal, weightKg: 80.0, repsMin: 8, repsMax: 12),
        ],
      );

      final json = slot.toJson();
      final decoded = RoutineSlot.fromJson(json);

      expect(decoded.exerciseMode, equals(ExerciseMode.reps));
      expect(decoded.repMode, equals(RepMode.range));
      expect(decoded.sets, hasLength(3));
      expect(decoded.sets.first.type, equals(SetType.warmup));
      expect(decoded, equals(slot));
    });

    test('SCENARIO-053: exerciseMode and repMode serialize as name strings',
        () {
      const slot = RoutineSlot(
        exerciseId: 'plank',
        exerciseName: 'Plank',
        muscleGroup: 'core',
        targetSets: 3,
        targetRepsMin: 0,
        targetRepsMax: 0,
        restSeconds: 30,
        exerciseMode: ExerciseMode.duration,
        repMode: RepMode.single,
      );

      final json = slot.toJson();
      expect(json['exerciseMode'], equals('duration'));
      expect(json['repMode'], equals('single'));
    });
  });

  group('RoutineSlot.effectiveSets', () {
    test('SCENARIO-054: returns sets when sets is non-empty', () {
      const slot = RoutineSlot(
        exerciseId: 'squat',
        exerciseName: 'Squat',
        muscleGroup: 'quads',
        targetSets: 1,
        targetRepsMin: 5,
        targetRepsMax: 5,
        restSeconds: 120,
        sets: [
          SetSpec(type: SetType.normal, weightKg: 100.0, reps: 5),
          SetSpec(type: SetType.normal, weightKg: 100.0, reps: 5),
        ],
      );

      final effective = slot.effectiveSets;
      expect(effective, hasLength(2));
      expect(effective.first.weightKg, closeTo(100.0, 0.001));
    });

    test(
        'SCENARIO-055: synthesizes N rows from legacy targetSets/targetRepsMin/Max '
        'when sets is empty', () {
      const slot = RoutineSlot(
        exerciseId: 'row',
        exerciseName: 'Barbell Row',
        muscleGroup: 'back',
        targetSets: 3,
        targetRepsMin: 6,
        targetRepsMax: 10,
        restSeconds: 90,
        targetWeightKg: 70.0,
      );

      final effective = slot.effectiveSets;
      expect(effective, hasLength(3));
      for (final s in effective) {
        expect(s.repsMin, equals(6));
        expect(s.repsMax, equals(10));
        expect(s.weightKg, closeTo(70.0, 0.001));
      }
    });

    test(
        'SCENARIO-056: synthesizes duration rows when legacy durationSeconds is set',
        () {
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

      final effective = slot.effectiveSets;
      expect(effective, hasLength(3));
      for (final s in effective) {
        expect(s.durationSeconds, equals(60));
      }
    });

    test(
        'SCENARIO-057: synthesizes uniform rows from single-element targetReps',
        () {
      const slot = RoutineSlot(
        exerciseId: 'curl',
        exerciseName: 'Bicep Curl',
        muscleGroup: 'biceps',
        targetSets: 4,
        targetRepsMin: 10,
        targetRepsMax: 10,
        restSeconds: 60,
        targetReps: [10],
      );

      final effective = slot.effectiveSets;
      expect(effective, hasLength(4));
      for (final s in effective) {
        expect(s.reps, equals(10));
      }
    });

    test('SCENARIO-058: synthesizes per-set rows from multi-element targetReps',
        () {
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

      final effective = slot.effectiveSets;
      expect(effective, hasLength(3));
      expect(effective[0].reps, equals(6));
      expect(effective[1].reps, equals(8));
      expect(effective[2].reps, equals(10));
    });

    test(
        'SCENARIO-059: legacy JSON doc (no sets/exerciseMode/repMode keys) '
        'deserializes with defaults and effectiveSets works', () {
      final legacyJson = <String, dynamic>{
        'exerciseId': 'deadlift',
        'exerciseName': 'Deadlift',
        'muscleGroup': 'back',
        'targetSets': 4,
        'targetRepsMin': 3,
        'targetRepsMax': 5,
        'restSeconds': 180,
        'targetWeightKg': 120.0,
      };

      final slot = RoutineSlot.fromJson(legacyJson);

      // Defaults applied
      expect(slot.exerciseMode, equals(ExerciseMode.reps));
      expect(slot.repMode, equals(RepMode.single));
      expect(slot.sets, isEmpty);

      // effectiveSets synthesizes from legacy fields
      final effective = slot.effectiveSets;
      expect(effective, hasLength(4));
      expect(effective.first.repsMin, equals(3));
      expect(effective.first.repsMax, equals(5));
      expect(effective.first.weightKg, closeTo(120.0, 0.001));
    });

    test('SCENARIO-060: targetSets 0 clamps to 1 in effectiveSets', () {
      const slot = RoutineSlot(
        exerciseId: 'x',
        exerciseName: 'X',
        muscleGroup: 'arms',
        targetSets: 0, // edge case
        targetRepsMin: 10,
        targetRepsMax: 10,
        restSeconds: 60,
      );

      expect(slot.effectiveSets, hasLength(1));
    });
  });

  group('RoutineSlot.effectiveExerciseMode + effectiveRepMode', () {
    test(
        'SCENARIO-061: effectiveExerciseMode returns duration for legacy durationSeconds',
        () {
      const slot = RoutineSlot(
        exerciseId: 'plank',
        exerciseName: 'Plank',
        muscleGroup: 'core',
        targetSets: 3,
        targetRepsMin: 0,
        targetRepsMax: 0,
        restSeconds: 30,
        durationSeconds: 45,
      );

      expect(slot.effectiveExerciseMode, equals(ExerciseMode.duration));
    });

    test(
        'SCENARIO-062: effectiveRepMode returns range when targetRepsMin != targetRepsMax',
        () {
      const slot = RoutineSlot(
        exerciseId: 'squat',
        exerciseName: 'Squat',
        muscleGroup: 'quads',
        targetSets: 3,
        targetRepsMin: 6,
        targetRepsMax: 10,
        restSeconds: 90,
      );

      expect(slot.effectiveRepMode, equals(RepMode.range));
    });
  });
}
