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

  // ── Periodization (Model B): effectiveSetsForWeek ─────────────────────────

  group('RoutineSlot.effectiveSetsForWeek', () {
    // Distinct per-week prescriptions so indexing errors are detectable.
    const week0Sets = [
      SetSpec(type: SetType.normal, weightKg: 60.0, reps: 10),
    ];
    const week1Sets = [
      SetSpec(type: SetType.normal, weightKg: 65.0, reps: 8),
      SetSpec(type: SetType.normal, weightKg: 65.0, reps: 8),
    ];
    const week2Sets = [
      SetSpec(type: SetType.normal, weightKg: 70.0, reps: 6),
      SetSpec(type: SetType.failure, weightKg: 72.5, reps: 4),
    ];

    const periodizedSlot = RoutineSlot(
      exerciseId: 'bench-press',
      exerciseName: 'Bench Press',
      muscleGroup: 'chest',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 90,
      weeklySets: [week0Sets, week1Sets, week2Sets],
    );

    test(
        'SCENARIO-PERIOD-001: weeklySets populated and week in range returns '
        'exactly weeklySets[week]', () {
      // Week 0 — single light set.
      final w0 = periodizedSlot.effectiveSetsForWeek(0);
      expect(w0, equals(week0Sets));
      expect(w0, hasLength(1));
      expect(w0.first.weightKg, closeTo(60.0, 0.001));
      expect(w0.first.reps, equals(10));

      // Week 2 — DIFFERENT prescription proves indexing, not just fallback.
      final w2 = periodizedSlot.effectiveSetsForWeek(2);
      expect(w2, equals(week2Sets));
      expect(w2, hasLength(2));
      expect(w2.first.weightKg, closeTo(70.0, 0.001));
      expect(w2.first.reps, equals(6));
      expect(w2.last.type, equals(SetType.failure));
      expect(w2, isNot(equals(w0)));
    });

    test(
        'SCENARIO-PERIOD-002: weeklySets empty falls back to effectiveSets '
        '(legacy synthesis)', () {
      const legacySlot = RoutineSlot(
        exerciseId: 'row',
        exerciseName: 'Barbell Row',
        muscleGroup: 'back',
        targetSets: 3,
        targetRepsMin: 6,
        targetRepsMax: 10,
        restSeconds: 90,
        targetWeightKg: 70.0,
      );

      final forWeek = legacySlot.effectiveSetsForWeek(0);

      expect(forWeek, equals(legacySlot.effectiveSets),
          reason: 'empty weeklySets must defer to legacy synthesis');
      expect(forWeek, hasLength(3));
      for (final s in forWeek) {
        expect(s.repsMin, equals(6));
        expect(s.repsMax, equals(10));
        expect(s.weightKg, closeTo(70.0, 0.001));
      }
    });

    test(
        'SCENARIO-PERIOD-003: week >= weeklySets.length falls back to '
        'effectiveSets without throwing', () {
      // Explicit "never throws" assertion for out-of-range weeks.
      expect(() => periodizedSlot.effectiveSetsForWeek(3), returnsNormally);
      expect(() => periodizedSlot.effectiveSetsForWeek(999), returnsNormally);

      final outOfRange = periodizedSlot.effectiveSetsForWeek(3);
      expect(outOfRange, equals(periodizedSlot.effectiveSets));
    });

    test(
        'SCENARIO-PERIOD-004: negative week falls back to effectiveSets '
        'without throwing', () {
      // Explicit "never throws" assertion for negative weeks.
      expect(() => periodizedSlot.effectiveSetsForWeek(-1), returnsNormally);
      expect(() => periodizedSlot.effectiveSetsForWeek(-42), returnsNormally);

      final negative = periodizedSlot.effectiveSetsForWeek(-1);
      expect(negative, equals(periodizedSlot.effectiveSets));
    });
  });

  // ── Periodization (Model B): weeklySets serialization ─────────────────────

  group('RoutineSlot — weeklySets serialization', () {
    test(
        'SCENARIO-PERIOD-005: empty weeklySets roundtrips to [] and the json '
        'key is present as an empty list', () {
      const slot = RoutineSlot(
        exerciseId: 'curl',
        exerciseName: 'Bicep Curl',
        muscleGroup: 'biceps',
        targetSets: 3,
        targetRepsMin: 10,
        targetRepsMax: 10,
        restSeconds: 60,
      );

      final json = slot.toJson();
      expect(json, contains('weeklySets'));
      expect(json['weeklySets'], isA<List<dynamic>>());
      expect(json['weeklySets'], isEmpty);

      final decoded = RoutineSlot.fromJson(json);
      expect(decoded.weeklySets, equals(<List<SetSpec>>[]));
      expect(decoded, equals(slot));
    });

    test(
        'SCENARIO-PERIOD-005: populated weeklySets roundtrips deeply equal '
        '(per-week, per-set fields)', () {
      const s1 = SetSpec(
          type: SetType.warmup, weightKg: 40.0, repsMin: 10, repsMax: 15);
      const s2 = SetSpec(type: SetType.normal, weightKg: 80.0, reps: 8);
      const s3 = SetSpec(type: SetType.drop, weightKg: 60.0, reps: 12);

      const slot = RoutineSlot(
        exerciseId: 'squat',
        exerciseName: 'Squat',
        muscleGroup: 'quads',
        targetSets: 2,
        targetRepsMin: 8,
        targetRepsMax: 12,
        restSeconds: 120,
        weeklySets: [
          [s1],
          [s2, s3],
        ],
      );

      final json = slot.toJson();
      final decoded = RoutineSlot.fromJson(json);

      expect(decoded.weeklySets, hasLength(2));

      // Week 0 — single warmup set.
      expect(decoded.weeklySets[0], hasLength(1));
      final d1 = decoded.weeklySets[0][0];
      expect(d1.type, equals(SetType.warmup));
      expect(d1.weightKg, closeTo(40.0, 0.001));
      expect(d1.repsMin, equals(10));
      expect(d1.repsMax, equals(15));
      expect(d1, equals(s1));

      // Week 1 — working set + drop set.
      expect(decoded.weeklySets[1], hasLength(2));
      final d2 = decoded.weeklySets[1][0];
      expect(d2.type, equals(SetType.normal));
      expect(d2.weightKg, closeTo(80.0, 0.001));
      expect(d2.reps, equals(8));
      expect(d2, equals(s2));
      final d3 = decoded.weeklySets[1][1];
      expect(d3.type, equals(SetType.drop));
      expect(d3.weightKg, closeTo(60.0, 0.001));
      expect(d3.reps, equals(12));
      expect(d3, equals(s3));

      expect(decoded, equals(slot));
    });

    test(
        'SCENARIO-PERIOD-005: legacy doc without weeklySets key deserializes '
        'to [] (backward-compatible)', () {
      // Simulates a Firestore doc written before weeklySets was added.
      final legacyMap = <String, dynamic>{
        'exerciseId': 'deadlift',
        'exerciseName': 'Deadlift',
        'muscleGroup': 'back',
        'targetSets': 4,
        'targetRepsMin': 3,
        'targetRepsMax': 5,
        'restSeconds': 180,
      };

      final slot = RoutineSlot.fromJson(legacyMap);

      expect(slot.weeklySets, equals(<List<SetSpec>>[]),
          reason: 'old docs must decode with weeklySets: []');
    });
  });
}
