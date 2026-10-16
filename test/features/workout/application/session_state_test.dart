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

    // ── QA-WKT-005: un día sin trabajo NO es "completado" ────────────────────
    test(
        'QA-WKT-005: isFullyCompleted = false con día sin slots (0 sets no '
        'debe contar como workout completado)', () {
      final state = SessionState(
        session: makeSession(),
        day: makeDay(slots: const []),
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      // `every` sobre lista vacía da `true`; el guard de trabajo-planificado
      // debe forzar `false` para que TERMINAR no quede habilitado al instante
      // y la sesión de 0 sets no infle workoutsCount/racha.
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

    // ── live-set-editing PR1: plannedSetsFor resolver (AD-1) ──────────────────

    group('plannedSetsFor', () {
      test(
          '[AD-1] returns plan count (effectiveSetsForWeek.length) when '
          'setCountOverride is empty', () {
        final slot = makeSlot(exerciseId: 'e1', targetSets: 3);
        final day = makeDay(slots: [slot]);
        final state = SessionState(
          session: makeSession(),
          day: day,
          setLogs: const [],
          currentExerciseIndex: 0,
          elapsedSeconds: 0,
        );
        expect(state.plannedSetsFor(slot), equals(3));
      });

      test(
          '[AD-1] returns the override value when present, ignoring the plan '
          'count entirely (plan=3, override=5 -> 5)', () {
        final slot = makeSlot(exerciseId: 'e1', targetSets: 3);
        final day = makeDay(slots: [slot]);
        final state = SessionState(
          session: makeSession(),
          day: day,
          setLogs: const [],
          currentExerciseIndex: 0,
          elapsedSeconds: 0,
          setCountOverride: const {'e1': 5},
        );
        expect(state.plannedSetsFor(slot), equals(5));
      });
    });

    // ── live-set-editing PR1: [SITE-1] isFullyCompleted honors override ──────

    test(
        '[SITE-1][AD-5] isFullyCompleted returns false when an exercise has '
        'an added-beyond-plan set pending (3 logged, override=4)', () {
      final slot = makeSlot(exerciseId: 'e1', targetSets: 3);
      final day = makeDay(slots: [slot]);
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
        setCountOverride: const {'e1': 4},
      );
      expect(state.isFullyCompleted, isFalse);
    });

    // ── live-set-editing PR1: [SITE-2] isExerciseDone honors override ───────

    test(
        '[SITE-2][AD-5] isExerciseDone returns true at a reduced override '
        'count (override=2, both remaining logged) and completedExerciseCount '
        'reflects it', () {
      final slot = makeSlot(exerciseId: 'e1', targetSets: 3);
      final day = makeDay(slots: [slot]);
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
        setCountOverride: const {'e1': 2},
      );
      expect(state.isExerciseDone('e1'), isTrue);
      expect(state.completedExerciseCount, equals(1));
    });

    // ── copyWith / == / hashCode cover setCountOverride ──────────────────────

    test(
        '[AD-1] copyWith updates setCountOverride and leaves other fields intact',
        () {
      final day = makeDay();
      final original = SessionState(
        session: makeSession(),
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      final copy = original.copyWith(setCountOverride: const {'e1': 4});
      expect(copy.setCountOverride, equals(const {'e1': 4}));
      expect(copy.currentExerciseIndex, equals(original.currentExerciseIndex));
      expect(original.setCountOverride, equals(const {}));
    });

    test(
        '[AD-1] == and hashCode treat equal setCountOverride maps as equal '
        'regardless of insertion order', () {
      final day = makeDay();
      final session = makeSession();
      final a = SessionState(
        session: session,
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
        setCountOverride: const {'e1': 4, 'e2': 2},
      );
      final b = SessionState(
        session: session,
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
        setCountOverride: const {'e2': 2, 'e1': 4},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('[AD-1] == is false when setCountOverride differs', () {
      final day = makeDay();
      final session = makeSession();
      final a = SessionState(
        session: session,
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
        setCountOverride: const {'e1': 4},
      );
      final b = SessionState(
        session: session,
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      expect(a == b, isFalse);
    });
  });

  // ── #1511 — terminar igual: cuánto se hizo y si cuenta ────────────────────
  group('SessionState — progreso y "terminar igual" (#1511)', () {
    SessionState build({
      required List<int> planned,
      required List<int> done,
      Map<String, int> override = const {},
    }) {
      final slots = [
        for (var i = 0; i < planned.length; i++)
          makeSlot(
            exerciseId: 'e$i',
            exerciseName: 'Ejercicio $i',
            targetSets: planned[i],
          ),
      ];
      final logs = [
        for (var i = 0; i < done.length; i++)
          for (var n = 1; n <= done[i]; n++)
            makeSetLog(exerciseId: 'e$i', setNumber: n, id: 'l-$i-$n'),
      ];
      return SessionState(
        session: makeSession(),
        day: makeDay(slots: slots),
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
        setCountOverride: override,
      );
    }

    test('plannedSetsTotal / doneSetsTotal / completionRatio', () {
      final s = build(planned: [3, 3], done: [3, 0]);
      expect(s.plannedSetsTotal, 6);
      expect(s.doneSetsTotal, 3);
      expect(s.completionRatio, 0.5);
    });

    test('sin series hechas: ratio 0 y no cuenta', () {
      final s = build(planned: [3, 3], done: [0, 0]);
      expect(s.doneSetsTotal, 0);
      expect(s.completionRatio, 0);
      expect(s.countsAsWorkoutIfFinished, isFalse);
    });

    test('una serie extra en un ejercicio no tapa la que falta en otro', () {
      // e0 tiene 5 logs de 3 planificadas; e1 no hizo ninguna. Sin el tope por
      // slot serían 5 de 6 (83 %) cuando en realidad se hizo la mitad.
      final s = build(planned: [3, 3], done: [5, 0]);
      expect(s.doneSetsTotal, 3);
      expect(s.completionRatio, 0.5);
    });

    test('el piso es inclusivo: 50 % cuenta, por debajo no', () {
      expect(build(planned: [4], done: [2]).countsAsWorkoutIfFinished, isTrue);
      expect(build(planned: [4], done: [1]).countsAsWorkoutIfFinished, isFalse);
      expect(
        build(planned: [3], done: [1]).countsAsWorkoutIfFinished,
        isFalse,
        reason: '1/3 = 33 %',
      );
    });

    test('una sesión completa cuenta', () {
      expect(build(planned: [2, 2], done: [2, 2]).countsAsWorkoutIfFinished,
          isTrue);
    });

    test('un día sin trabajo planificado nunca cuenta (QA-WKT-005)', () {
      final s = build(planned: const [], done: const []);
      expect(s.completionRatio, 0);
      expect(s.countsAsWorkoutIfFinished, isFalse);
    });

    test('respeta el override de series agregadas/quitadas en la sesión', () {
      // El atleta agregó una serie a e0 (3 → 4): ahora son 4 + 3 = 7 planificadas.
      final s = build(planned: [3, 3], done: [4, 0], override: {'e0': 4});
      expect(s.plannedSetsTotal, 7);
      expect(s.doneSetsTotal, 4);
    });

    test('missingSets lista sólo los slots con series pendientes', () {
      final s = build(planned: [3, 3, 2], done: [3, 1, 0]);
      expect(s.missingSets.map((m) => (m.slot.exerciseId, m.done, m.planned)),
          [('e1', 1, 3), ('e2', 0, 2)]);
    });

    test('missingSets vacío cuando la sesión está completa', () {
      expect(build(planned: [2], done: [2]).missingSets, isEmpty);
    });
  });
}
