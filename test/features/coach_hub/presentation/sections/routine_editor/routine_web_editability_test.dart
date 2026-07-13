// Unit tests for isRoutineWebEditable — the gate that keeps the simple web
// editor from silently truncating periodized / superset routines authored in
// the mobile app.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/routine_editor/routine_web_editability.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

RoutineSlot _slot({
  int? supersetGroup,
  List<List<SetSpec>> weeklySets = const [],
  List<int> activeWeeks = const [],
  ExerciseMode exerciseMode = ExerciseMode.reps,
  RepMode repMode = RepMode.single,
  int targetRepsMin = 8,
  int targetRepsMax = 8,
  String? notes,
  List<SetSpec> sets = const [SetSpec(reps: 8, weightKg: 50)],
}) =>
    RoutineSlot(
      exerciseId: 'e1',
      exerciseName: 'Ex',
      muscleGroup: 'chest',
      targetSets: 1,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      restSeconds: 60,
      supersetGroup: supersetGroup,
      weeklySets: weeklySets,
      activeWeeks: activeWeeks,
      exerciseMode: exerciseMode,
      repMode: repMode,
      notes: notes,
      sets: sets,
    );

Routine _routine({int numWeeks = 1, RoutineSlot? slot}) => Routine(
      id: 'r',
      name: 'R',
      level: ExperienceLevel.beginner,
      source: RoutineSource.trainerAssigned,
      numWeeks: numWeeks,
      days: [
        RoutineDay(dayNumber: 1, name: 'D1', slots: [slot ?? _slot()]),
      ],
    );

void main() {
  group('isRoutineWebEditable', () {
    test('a plain single-week reps routine is editable', () {
      expect(isRoutineWebEditable(_routine()), isTrue);
    });

    test('a routine with no days is editable (nothing to truncate)', () {
      expect(
        isRoutineWebEditable(const Routine(
          id: 'r',
          name: 'R',
          level: ExperienceLevel.beginner,
          source: RoutineSource.trainerAssigned,
          days: [],
        )),
        isTrue,
      );
    });

    test('numWeeks > 1 → not editable', () {
      expect(isRoutineWebEditable(_routine(numWeeks: 2)), isFalse);
    });

    test('a superset slot → not editable', () {
      expect(
        isRoutineWebEditable(_routine(slot: _slot(supersetGroup: 1))),
        isFalse,
      );
    });

    test('per-week periodization (weeklySets) → not editable', () {
      expect(
        isRoutineWebEditable(_routine(
            slot: _slot(weeklySets: const [
          [SetSpec(reps: 8)]
        ]))),
        isFalse,
      );
    });

    test('a presence mask (activeWeeks) → not editable', () {
      expect(
        isRoutineWebEditable(_routine(slot: _slot(activeWeeks: const [0]))),
        isFalse,
      );
    });

    test('duration-based exercise → not editable', () {
      expect(
        isRoutineWebEditable(
            _routine(slot: _slot(exerciseMode: ExerciseMode.duration))),
        isFalse,
      );
    });

    test('different reps per set (12/10/8) IS editable — not a real range', () {
      // The bug this guards against: targetRepsMin != targetRepsMax made the
      // old effectiveRepMode heuristic report "range", wrongly blocking a
      // simple web-authored routine with varying per-set reps.
      expect(
        isRoutineWebEditable(_routine(
            slot: _slot(sets: const [
          SetSpec(reps: 12),
          SetSpec(reps: 10),
          SetSpec(reps: 8),
        ]))),
        isTrue,
      );
    });

    test('a rep-range set (repsMin/repsMax) IS editable (Fase 1)', () {
      expect(
        isRoutineWebEditable(_routine(
            slot: _slot(sets: const [SetSpec(repsMin: 8, repsMax: 12)]))),
        isTrue,
      );
    });

    test('an explicit range rep mode IS editable (Fase 1)', () {
      expect(
        isRoutineWebEditable(_routine(slot: _slot(repMode: RepMode.range))),
        isTrue,
      );
    });

    test('a slot with coaching notes IS editable (Fase 1)', () {
      expect(
        isRoutineWebEditable(_routine(slot: _slot(notes: 'tempo 3-1-1'))),
        isTrue,
      );
    });

    test('a duration set → not editable (Fase 2, still out of scope)', () {
      expect(
        isRoutineWebEditable(
            _routine(slot: _slot(sets: const [SetSpec(durationSeconds: 30)]))),
        isFalse,
      );
    });
  });
}
