// Tests for the Hevy-style per-set table helpers in routine_editor_screen.dart.
// Covers:
//   - setChipLabel numbering (via RoutineEditorTestBridge)
//   - isSetValid per-mode rules (via RoutineEditorTestBridge)
//   - buildRoutineSlot legacy-field derivation (via RoutineEditorTestBridge)

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';

void main() {
  // ── kSetTypeLabel (exported from set_enums.dart) ────────────────────────────
  group('kSetTypeLabel chip letters', () {
    test('warmup → W', () => expect(kSetTypeLabel[SetType.warmup], 'W'));
    test('drop → D', () => expect(kSetTypeLabel[SetType.drop], 'D'));
    test('failure → F', () => expect(kSetTypeLabel[SetType.failure], 'F'));
    test('normal → empty string (UI renders number)',
        () => expect(kSetTypeLabel[SetType.normal], ''));
  });

  // ── isSetValid — duration mode ─────────────────────────────────────────────
  group('isSetValid — duration mode', () {
    test('null durationSeconds → invalid', () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.duration,
          repMode: RepMode.single,
          durationSeconds: null,
        ),
        isFalse,
      );
    });

    test('durationSeconds == 0 → invalid', () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.duration,
          repMode: RepMode.single,
          durationSeconds: 0,
        ),
        isFalse,
      );
    });

    test('durationSeconds > 0 → valid', () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.duration,
          repMode: RepMode.single,
          durationSeconds: 30,
        ),
        isTrue,
      );
    });
  });

  // ── isSetValid — reps single mode ──────────────────────────────────────────
  group('isSetValid — reps single mode', () {
    test('null reps → invalid', () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.reps,
          repMode: RepMode.single,
          reps: null,
        ),
        isFalse,
      );
    });

    test('reps == 0 → invalid', () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.reps,
          repMode: RepMode.single,
          reps: 0,
        ),
        isFalse,
      );
    });

    test('reps > 0 → valid (weight is optional)', () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.reps,
          repMode: RepMode.single,
          reps: 10,
        ),
        isTrue,
      );
    });
  });

  // ── isSetValid — reps range mode ───────────────────────────────────────────
  group('isSetValid — reps range mode', () {
    test('null repsMin → invalid', () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.reps,
          repMode: RepMode.range,
          repsMin: null,
          repsMax: 12,
        ),
        isFalse,
      );
    });

    test('repsMin == 0 → invalid', () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.reps,
          repMode: RepMode.range,
          repsMin: 0,
          repsMax: 12,
        ),
        isFalse,
      );
    });

    test('repsMax < repsMin → invalid', () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.reps,
          repMode: RepMode.range,
          repsMin: 10,
          repsMax: 8,
        ),
        isFalse,
      );
    });

    test('repsMin == repsMax > 0 → valid', () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.reps,
          repMode: RepMode.range,
          repsMin: 10,
          repsMax: 10,
        ),
        isTrue,
      );
    });

    test('valid range 8–12 → valid', () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.reps,
          repMode: RepMode.range,
          repsMin: 8,
          repsMax: 12,
        ),
        isTrue,
      );
    });
  });

  // ── buildRoutineSlot — legacy field derivation ─────────────────────────────
  group('buildRoutineSlot legacy fields — reps single mode', () {
    test('targetReps, targetRepsMin/Max, targetSets, targetWeightKg', () {
      final slot = RoutineEditorTestBridge.buildSlotBridge(
        exerciseMode: ExerciseMode.reps,
        repMode: RepMode.single,
        sets: [
          (
            type: SetType.normal,
            weightKg: 80.0,
            reps: 10,
            repsMin: null,
            repsMax: null,
            durationSeconds: null,
          ),
          (
            type: SetType.normal,
            weightKg: 80.0,
            reps: 8,
            repsMin: null,
            repsMax: null,
            durationSeconds: null,
          ),
        ],
      );

      expect(slot.targetSets, 2);
      expect(slot.targetReps, [10, 8]);
      expect(slot.targetRepsMin, 8);
      expect(slot.targetRepsMax, 10);
      expect(slot.targetWeightKg, closeTo(80.0, 0.001));
      expect(slot.durationSeconds, isNull);
    });
  });

  group('buildRoutineSlot legacy fields — reps range mode', () {
    test('targetRepsMin = global min, targetRepsMax = global max', () {
      final slot = RoutineEditorTestBridge.buildSlotBridge(
        exerciseMode: ExerciseMode.reps,
        repMode: RepMode.range,
        sets: [
          (
            type: SetType.normal,
            weightKg: null,
            reps: null,
            repsMin: 6,
            repsMax: 8,
            durationSeconds: null,
          ),
          (
            type: SetType.normal,
            weightKg: null,
            reps: null,
            repsMin: 8,
            repsMax: 12,
            durationSeconds: null,
          ),
        ],
      );

      expect(slot.targetRepsMin, 6);
      expect(slot.targetRepsMax, 12);
      expect(slot.targetReps, isEmpty);
      expect(slot.durationSeconds, isNull);
    });
  });

  group('buildRoutineSlot legacy fields — duration mode', () {
    test('durationSeconds = first set; repsMin/Max = 0; targetReps empty', () {
      final slot = RoutineEditorTestBridge.buildSlotBridge(
        exerciseMode: ExerciseMode.duration,
        repMode: RepMode.single,
        sets: [
          (
            type: SetType.normal,
            weightKg: null,
            reps: null,
            repsMin: null,
            repsMax: null,
            durationSeconds: 45,
          ),
          (
            type: SetType.normal,
            weightKg: null,
            reps: null,
            repsMin: null,
            repsMax: null,
            durationSeconds: 30,
          ),
        ],
      );

      expect(slot.durationSeconds, 45);
      expect(slot.targetRepsMin, 0);
      expect(slot.targetRepsMax, 0);
      expect(slot.targetReps, isEmpty);
    });
  });

  group('buildRoutineSlot — new model fields', () {
    test('sets list is preserved verbatim', () {
      final slot = RoutineEditorTestBridge.buildSlotBridge(
        exerciseMode: ExerciseMode.reps,
        repMode: RepMode.single,
        sets: [
          (
            type: SetType.warmup,
            weightKg: 40.0,
            reps: 15,
            repsMin: null,
            repsMax: null,
            durationSeconds: null,
          ),
          (
            type: SetType.normal,
            weightKg: 80.0,
            reps: 10,
            repsMin: null,
            repsMax: null,
            durationSeconds: null,
          ),
          (
            type: SetType.drop,
            weightKg: 60.0,
            reps: 12,
            repsMin: null,
            repsMax: null,
            durationSeconds: null,
          ),
        ],
      );

      expect(slot.sets.length, 3);
      expect(slot.sets[0].type, SetType.warmup);
      expect(slot.sets[1].type, SetType.normal);
      expect(slot.sets[2].type, SetType.drop);
    });

    test('exerciseMode and repMode are forwarded', () {
      final slot = RoutineEditorTestBridge.buildSlotBridge(
        exerciseMode: ExerciseMode.duration,
        repMode: RepMode.range,
        sets: [
          (
            type: SetType.normal,
            weightKg: null,
            reps: null,
            repsMin: null,
            repsMax: null,
            durationSeconds: 60,
          ),
        ],
      );

      expect(slot.exerciseMode, ExerciseMode.duration);
      expect(slot.repMode, RepMode.range);
    });
  });

  // ── setChipLabel numbering ─────────────────────────────────────────────────
  group('setChipLabel numbering', () {
    test('single normal set → "1"', () {
      expect(
        RoutineEditorTestBridge.chipLabelBridge(
          sets: [SetType.normal],
          index: 0,
        ),
        '1',
      );
    });

    test('warmup before normal → W then 1', () {
      final types = [SetType.warmup, SetType.normal];
      final labels = List.generate(
        types.length,
        (i) => RoutineEditorTestBridge.chipLabelBridge(sets: types, index: i),
      );
      expect(labels, ['W', '1']);
    });

    test('three normal sets → 1, 2, 3', () {
      final types = [SetType.normal, SetType.normal, SetType.normal];
      final labels = List.generate(
        types.length,
        (i) => RoutineEditorTestBridge.chipLabelBridge(sets: types, index: i),
      );
      expect(labels, ['1', '2', '3']);
    });

    test('W, normal, normal, D, normal → W, 1, 2, D, 3', () {
      final types = [
        SetType.warmup,
        SetType.normal,
        SetType.normal,
        SetType.drop,
        SetType.normal,
      ];
      final labels = List.generate(
        types.length,
        (i) => RoutineEditorTestBridge.chipLabelBridge(sets: types, index: i),
      );
      expect(labels, ['W', '1', '2', 'D', '3']);
    });

    test('failure set → F', () {
      expect(
        RoutineEditorTestBridge.chipLabelBridge(
          sets: [SetType.failure],
          index: 0,
        ),
        'F',
      );
    });

    test('drop set does not count toward normal numbering', () {
      final types = [SetType.normal, SetType.drop, SetType.normal];
      final labels = List.generate(
        types.length,
        (i) => RoutineEditorTestBridge.chipLabelBridge(sets: types, index: i),
      );
      expect(labels, ['1', 'D', '2']);
    });
  });

  // ── SetSpec.toSetSpec round-trip through buildSlotBridge ───────────────────
  group('SetSpec weights survive round-trip', () {
    test('weightKg stored as double in RoutineSlot.sets', () {
      final slot = RoutineEditorTestBridge.buildSlotBridge(
        exerciseMode: ExerciseMode.reps,
        repMode: RepMode.single,
        sets: [
          (
            type: SetType.normal,
            weightKg: 102.5,
            reps: 5,
            repsMin: null,
            repsMax: null,
            durationSeconds: null,
          ),
        ],
      );

      expect(slot.sets.first.weightKg, closeTo(102.5, 0.001));
    });
  });
}
