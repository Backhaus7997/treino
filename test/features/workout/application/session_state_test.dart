// Tests para SessionState — SCENARIO-250..255 + copyWith smoke.
// SCENARIO-037: activeWeek getter + effectiveSetsForWeek on periodized session.
// RED: el archivo de producción no existe todavía.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/application/session_state.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

import 'stub_factories.dart';

void main() {
  group('SessionState', () {
    // ── SCENARIO-250: isFullyCompleted = false cuando no hay logs ────────────
    test('SCENARIO-250: isFullyCompleted = false cuando setLogs está vacío',
        () {
      final day = makeDay(slots: [
        makeSlot(exerciseId: 'e1', targetSets: 3),
        makeSlot(exerciseId: 'e2', targetSets: 4),
      ]);
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      expect(state.isFullyCompleted, isFalse);
    });

    // ── SCENARIO-251: isFullyCompleted = false con completado parcial ────────
    test('SCENARIO-251: isFullyCompleted = false con progreso parcial', () {
      final day = makeDay(slots: [
        makeSlot(exerciseId: 'e1', targetSets: 3),
        makeSlot(exerciseId: 'e2', targetSets: 4),
      ]);
      // e1 tiene 2 de 3 sets
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'),
        makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'),
      ];
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      expect(state.isFullyCompleted, isFalse);
    });

    // ── SCENARIO-252: isFullyCompleted = true cuando todos completos ─────────
    test(
        'SCENARIO-252: isFullyCompleted = true cuando todos los sets están logueados',
        () {
      final day = makeDay(slots: [
        makeSlot(exerciseId: 'e1', targetSets: 3),
        makeSlot(exerciseId: 'e2', targetSets: 2),
      ]);
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'),
        makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'),
        makeSetLog(exerciseId: 'e1', setNumber: 3, id: 'l3'),
        makeSetLog(exerciseId: 'e2', setNumber: 1, id: 'l4'),
        makeSetLog(exerciseId: 'e2', setNumber: 2, id: 'l5'),
      ];
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 1,
        elapsedSeconds: 0,
      );
      expect(state.isFullyCompleted, isTrue);
    });

    // ── SCENARIO-253: isFullyCompleted = true con overshoot ──────────────────
    test(
        'SCENARIO-253: isFullyCompleted = true aunque sets superen el target (overshoot)',
        () {
      final day = makeDay(slots: [
        makeSlot(exerciseId: 'e1', targetSets: 2),
      ]);
      // 3 sets para un target de 2 — sigue siendo completo
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'),
        makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'),
        makeSetLog(exerciseId: 'e1', setNumber: 3, id: 'l3'),
      ];
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      expect(state.isFullyCompleted, isTrue);
    });

    // ── SCENARIO-254: totalVolumeKg acumula correctamente ────────────────────
    test('SCENARIO-254: totalVolumeKg es la suma de reps * weightKg', () {
      final day = makeDay(slots: [
        makeSlot(exerciseId: 'e1', targetSets: 2),
      ]);
      final logs = [
        makeSetLog(
            exerciseId: 'e1', setNumber: 1, reps: 10, weightKg: 60.0, id: 'l1'),
        makeSetLog(
            exerciseId: 'e1', setNumber: 2, reps: 8, weightKg: 65.0, id: 'l2'),
      ];
      // 10*60 + 8*65 = 600 + 520 = 1120
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      expect(state.totalVolumeKg, closeTo(1120.0, 0.001));
    });

    // ── SCENARIO-255: totalVolumeKg = 0 cuando no hay logs ───────────────────
    test('SCENARIO-255: totalVolumeKg = 0.0 cuando setLogs está vacío', () {
      final day = makeDay();
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      expect(state.totalVolumeKg, equals(0.0));
    });

    // ── copyWith smoke ────────────────────────────────────────────────────────
    test(
        'copyWith devuelve nueva instancia con el campo modificado y el resto igual',
        () {
      final day = makeDay();
      final original = SessionState(
        session: makeSession(),
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      final copy = original.copyWith(elapsedSeconds: 42);
      expect(copy.elapsedSeconds, equals(42));
      expect(copy.currentExerciseIndex, equals(original.currentExerciseIndex));
      expect(copy.session, equals(original.session));
      expect(identical(original, copy), isFalse);
    });

    // ── Equality ──────────────────────────────────────────────────────────────
    test('== es verdadero para instancias con los mismos valores', () {
      final day = makeDay();
      final session = makeSession();
      final a = SessionState(
        session: session,
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      final b = SessionState(
        session: session,
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    // ── SCENARIO-037: activeWeek + effectiveSetsForWeek en sesión periodizada ──

    test(
        'SCENARIO-037a: activeWeek returns session.weekNumber (0 for single-week)',
        () {
      final state = SessionState(
        session: makeSession(weekNumber: 0),
        day: makeDay(),
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      expect(state.activeWeek, equals(0));
    });

    test('SCENARIO-037b: activeWeek returns session.weekNumber (1 for week 2)',
        () {
      final state = SessionState(
        session: makeSession(weekNumber: 1),
        day: makeDay(),
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      expect(state.activeWeek, equals(1));
    });

    test(
        'SCENARIO-037c: isFullyCompleted uses effectiveSetsForWeek — '
        'week 1 prescription (2 sets) satisfied by 2 logs even though '
        'legacy targetSets = 3', () {
      // Slot with weeklySets: week0=[3 sets], week1=[2 sets].
      // Session weekNumber=1 → only 2 logs needed.
      final slot = makeSlot(
        exerciseId: 'e1',
        targetSets: 3, // legacy fallback — must NOT be used
        weeklySets: [
          const [SetSpec(reps: 10), SetSpec(reps: 10), SetSpec(reps: 10)],
          const [SetSpec(reps: 8), SetSpec(reps: 8)],
        ],
      );
      final day = makeDay(slots: [slot]);
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1),
        makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'sl2'),
      ];
      final state = SessionState(
        session: makeSession(weekNumber: 1),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      // Week 1 has 2 sets; 2 logs → fully completed.
      expect(state.isFullyCompleted, isTrue);
    });

    test(
        'SCENARIO-037d: isFullyCompleted = false for single-week (week 0) '
        'session when logs are insufficient (backward-compat invariant)', () {
      // Legacy slot — weeklySets empty → falls back to effectiveSets (3 sets).
      final slot = makeSlot(exerciseId: 'e1', targetSets: 3);
      final day = makeDay(slots: [slot]);
      final logs = [makeSetLog(exerciseId: 'e1', setNumber: 1)];
      final state = SessionState(
        session: makeSession(weekNumber: 0),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      expect(state.isFullyCompleted, isFalse);
    });

    test(
        'SCENARIO-037e: isExerciseDone uses week 1 prescription — '
        '2 logs completes week-1 slot (2 sets)', () {
      final slot = makeSlot(
        exerciseId: 'e1',
        targetSets: 4,
        weeklySets: [
          const [
            SetSpec(reps: 10),
            SetSpec(reps: 10),
            SetSpec(reps: 10),
            SetSpec(reps: 10)
          ],
          const [SetSpec(reps: 8), SetSpec(reps: 8)],
        ],
      );
      final day = makeDay(slots: [slot]);
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1),
        makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'sl2'),
      ];
      final state = SessionState(
        session: makeSession(weekNumber: 1),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      expect(state.isExerciseDone('e1'), isTrue);
    });
  });
}
