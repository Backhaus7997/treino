import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';
import 'package:treino/features/coach_hub/data/periodized_excel_parser.dart';
import 'package:treino/features/coach_hub/data/periodized_routine_mapper.dart';
import 'package:treino/features/coach_hub/domain/periodized_plan.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

import 'periodized_test_helpers.dart';

List<MatcherExercise> _catalog() => [
      MatcherExercise(id: 'a', name: 'Ejercicio A', muscleGroup: 'legs'),
      MatcherExercise(id: 'b', name: 'Ejercicio B', muscleGroup: 'core'),
      MatcherExercise(id: 'c', name: 'Ejercicio C'),
      MatcherExercise(
          id: 'rom', name: 'Peso muerto rumano con barra', muscleGroup: 'legs'),
    ];

PeriodizedPlan _plan(List<List<Object?>> rows) {
  final r = parsePeriodizedExcel(programa(rows));
  expect(r.errors, isEmpty, reason: '${r.diagnostics}');
  return r.plan!;
}

void main() {
  test('cada componente de la superserie pasa por el matcher por separado', () {
    final plan = _plan([
      header1(weeks: 1),
      [
        1,
        'Ejercicio A + Ejercicio inventado + Peso muerto con barra',
        90,
        '3x8+8+8'
      ],
    ]);
    final m = matchPeriodizedPlan(plan, _catalog());
    expect(m.matches, hasLength(3));
    final keys = m.matches.keys.toList();
    expect(m.matches[keys[0]]!.exercise?.id, 'a'); // exacto
    expect(m.matches[keys[1]]!.exercise, isNull); // sin candidato
    expect(m.matches[keys[1]]!.suggestion, isNull);
    // #1455: "con barra" sin "rumano" NO adivina la variante.
    expect(m.matches[keys[2]]!.exercise, isNull);
    expect(m.matches[keys[2]]!.suggestion?.id, isNot('rom'));
    expect(m.needsReview, [keys[1], keys[2]]);
    expect(m.autoAssigned.keys, [keys[0]]);
  });

  test('con componentes sin asignar el mapper se niega', () {
    final plan = _plan([
      header1(weeks: 1),
      [1, 'Ejercicio A + Ejercicio B', 90, '3x8+8'],
    ]);
    final m = matchPeriodizedPlan(plan, [_catalog().first]);
    expect(
      () => mapPeriodizedPlanToRoutine(plan, m.autoAssigned,
          routineId: 'r', routineName: 'n', level: ExperienceLevel.beginner),
      throwsArgumentError,
    );
    expect(unresolvedKeys(plan, m.autoAssigned), hasLength(1));
  });

  test('asignación manual de un componente sin match', () {
    final plan = _plan([
      header1(weeks: 1),
      [1, 'Cosa rara', 90, '3x8'],
    ]);
    final key = matchPeriodizedPlan(plan, _catalog()).needsReview.single;
    final routine = mapPeriodizedPlanToRoutine(
      plan,
      {key: _catalog().first},
      routineId: 'r',
      routineName: 'n',
      level: ExperienceLevel.beginner,
    );
    final slot = routine.days.single.slots.single;
    expect(slot.exerciseId, 'a');
    expect(slot.exerciseName, 'Ejercicio A');
    expect(slot.muscleGroup, 'legs');
  });

  test('6 columnas con 4 cargadas: la rutina sale con numWeeks 4', () {
    final plan = _plan([
      header1(weeks: 6),
      [1, 'Ejercicio A', 90, '3x8', '3x9', '3x10', '3x11'],
    ]);
    final routine = mapPeriodizedPlanToRoutine(
      plan,
      matchPeriodizedPlan(plan, _catalog()).autoAssigned,
      routineId: 'r',
      routineName: 'n',
      level: ExperienceLevel.beginner,
    );
    expect(routine.numWeeks, 4);
    expect(routine.days.single.slots.single.weeklySets, hasLength(4));
  });

  test('plan de una semana: weeklySets vacío y legacy en sets', () {
    final plan = _plan([
      header1(weeks: 1),
      [1, 'Ejercicio A', 90, '3x8'],
    ]);
    final routine = mapPeriodizedPlanToRoutine(
      plan,
      matchPeriodizedPlan(plan, _catalog()).autoAssigned,
      routineId: 'r',
      routineName: 'n',
      level: ExperienceLevel.beginner,
    );
    expect(routine.numWeeks, 1);
    final slot = routine.days.single.slots.single;
    expect(slot.weeklySets, isEmpty);
    expect(slot.sets, List.filled(3, const SetSpec(reps: 8)));
    expect(slot.targetSets, 3);
  });

  test('dos superseries del mismo día: grupos distintos y estables', () {
    final plan = _plan([
      header1(weeks: 1),
      [1, 'Ejercicio A + Ejercicio B', 90, '3x8+8'],
      [2, 'Ejercicio C', 60, '3x8'],
      [3, 'Ejercicio A + Ejercicio C', 120, '3x8+8'],
    ]);
    Map<ExerciseKey, MatcherExercise> assign() =>
        matchPeriodizedPlan(plan, _catalog()).autoAssigned;
    final slots = mapPeriodizedPlanToRoutine(plan, assign(),
            routineId: 'r', routineName: 'n', level: ExperienceLevel.beginner)
        .days
        .single
        .slots;
    expect(slots.map((s) => s.supersetGroup), [1, 1, null, 2, 2]);
    expect(slots.map((s) => s.restSeconds), [0, 90, 60, 0, 120]);
    final again = mapPeriodizedPlanToRoutine(plan, assign(),
            routineId: 'r', routineName: 'n', level: ExperienceLevel.beginner)
        .days
        .single
        .slots;
    expect(
        again.map((s) => s.supersetGroup), slots.map((s) => s.supersetGroup));
  });

  test(
      'un ejercicio que mezcla distancia y reps toma un solo modo '
      '(distancia gana) y las series del otro tipo quedan sin dato', () {
    final plan = _plan([
      header1(weeks: 2),
      [1, 'Ejercicio A', 90, '3x8', '20m'],
    ]);
    final slot = mapPeriodizedPlanToRoutine(
      plan,
      matchPeriodizedPlan(plan, _catalog()).autoAssigned,
      routineId: 'r',
      routineName: 'n',
      level: ExperienceLevel.beginner,
    ).days.single.slots.single;
    expect(slot.exerciseMode, ExerciseMode.distance);
    expect(slot.weeklySets[0], List.filled(3, const SetSpec()));
    expect(slot.weeklySets[1], [const SetSpec(distanceMeters: 20)]);
  });

  test('fallo en reps: legacy con 0 y sin reps en el SetSpec', () {
    final plan = _plan([
      header1(weeks: 2),
      [1, 'Ejercicio A', 90, '2xmax', '3x8'],
    ]);
    final slot = mapPeriodizedPlanToRoutine(
      plan,
      matchPeriodizedPlan(plan, _catalog()).autoAssigned,
      routineId: 'r',
      routineName: 'n',
      level: ExperienceLevel.beginner,
    ).days.single.slots.single;
    expect(slot.sets, List.filled(2, const SetSpec(type: SetType.failure)));
    expect(slot.targetReps, [0, 0]);
    expect(slot.weeklySets[1], List.filled(3, const SetSpec(reps: 8)));
  });

  group('campos legacy desde la primera semana con datos', () {
    List<RoutineSlot> slotsOf(List<List<Object?>> rows) {
      final plan = _plan(rows);
      return mapPeriodizedPlanToRoutine(
        plan,
        matchPeriodizedPlan(plan, _catalog()).autoAssigned,
        routineId: 'r',
        routineName: 'n',
        level: ExperienceLevel.beginner,
      ).days.single.slots;
    }

    RoutineSlot slotOf(List<List<Object?>> rows) => slotsOf(rows).first;

    test('reps: SEMANA 1 vacía y 2-3 con reps leen la semana 2', () {
      final slot = slotOf([
        header1(weeks: 3),
        [1, 'Ejercicio A', 90, null, '3x8', '4x10'],
      ]);
      expect(slot.sets, List.filled(3, const SetSpec(reps: 8)));
      expect(slot.targetSets, 3);
      expect(slot.targetReps, [8, 8, 8]);
      expect(slot.targetRepsMin, 8);
      expect(slot.targetRepsMax, 8);
      // weeklySets queda intacto: la semana 0 conserva su placeholder.
      expect(slot.weeklySets, hasLength(3));
      expect(slot.weeklySets[0], const [SetSpec()]);
      expect(slot.weeklySets[1], List.filled(3, const SetSpec(reps: 8)));
    });

    test('duración: SEMANA 1 vacía lee la duración de la semana 2', () {
      final slot = slotOf([
        header1(weeks: 3),
        [1, 'Ejercicio A', 90, null, "8'", "10'"],
      ]);
      expect(slot.exerciseMode, ExerciseMode.duration);
      expect(slot.durationSeconds, 480);
      expect(slot.sets, const [SetSpec(durationSeconds: 480)]);
      expect(slot.weeklySets[0], const [SetSpec()]);
    });

    test('distancia: SEMANA 1 vacía lee la distancia de la semana 2', () {
      final slot = slotOf([
        header1(weeks: 3),
        [1, 'Ejercicio A', 90, null, '2x20m', '4x30m'],
      ]);
      expect(slot.exerciseMode, ExerciseMode.distance);
      expect(slot.sets, List.filled(2, const SetSpec(distanceMeters: 20)));
      expect(slot.targetSets, 2);
      expect(slot.weeklySets[0], const [SetSpec()]);
    });

    test('sin datos en ninguna semana: queda la semana 1 como antes', () {
      final slot = slotOf([
        header1(weeks: 3),
        [1, 'Ejercicio A', 90, null, null, null],
        [2, 'Ejercicio B', 90, '3x8', '3x8', '3x8'],
      ]);
      expect(slot.sets, const [SetSpec()]);
      expect(slot.targetSets, 1);
      expect(slot.targetReps, [0]);
      expect(slot.durationSeconds, isNull);
    });
  });

  // El Excel nunca trae pesos ni rangos, pero el import de PDF sí: el mapper
  // los tiene que conservar (antes se perdían en `_coerce`).
  group('pesos y rangos', () {
    RoutineSlot slotFrom(List<List<SetSpec>> weeks) {
      final plan = PeriodizedPlan(numWeeks: weeks.length, days: [
        PeriodizedDay(dayNumber: 1, rows: [
          PeriodizedRow(position: 1, number: 1, restSeconds: 90, exercises: [
            PeriodizedExercise(component: 0, rawName: 'x', weeks: weeks),
          ]),
        ]),
      ]);
      const key = (dayNumber: 1, row: 1, component: 0);
      return mapPeriodizedPlanToRoutine(plan, {key: _catalog().first},
              routineId: 'r', routineName: 'n', level: ExperienceLevel.beginner)
          .days
          .single
          .slots
          .single;
    }

    test('reps fijas con peso: conserva weightKg y targetWeightKg', () {
      final slot = slotFrom([
        const [SetSpec(reps: 8, weightKg: 60), SetSpec(reps: 6, weightKg: 70)],
        const [SetSpec(reps: 8, weightKg: 62.5)],
      ]);
      expect(slot.repMode, RepMode.single);
      expect(slot.sets, const [
        SetSpec(reps: 8, weightKg: 60),
        SetSpec(reps: 6, weightKg: 70),
      ]);
      expect(slot.weeklySets[1], const [SetSpec(reps: 8, weightKg: 62.5)]);
      expect(slot.targetWeightKg, 60);
      expect(slot.targetReps, [8, 6]);
      expect([slot.targetRepsMin, slot.targetRepsMax], [6, 8]);
    });

    test('rango: RepMode.range, repsMin/repsMax y sin targetReps', () {
      final slot = slotFrom([
        const [
          SetSpec(repsMin: 8, repsMax: 10, weightKg: 60),
          SetSpec(repsMin: 6, repsMax: 8, weightKg: 65),
        ],
        const [SetSpec(repsMin: 10, repsMax: 12)],
      ]);
      expect(slot.repMode, RepMode.range);
      expect(slot.sets, const [
        SetSpec(repsMin: 8, repsMax: 10, weightKg: 60),
        SetSpec(repsMin: 6, repsMax: 8, weightKg: 65),
      ]);
      expect(slot.weeklySets[1], const [SetSpec(repsMin: 10, repsMax: 12)]);
      expect([slot.targetRepsMin, slot.targetRepsMax], [6, 10]);
      expect(slot.targetReps, isEmpty);
      expect(slot.targetWeightKg, 60);
    });

    test('rango en una semana y reps fijas en otra: las fijas pasan a N-N', () {
      final slot = slotFrom([
        const [SetSpec(reps: 5, weightKg: 80)],
        const [SetSpec(repsMin: 8, repsMax: 10)],
      ]);
      expect(slot.repMode, RepMode.range);
      expect(slot.sets, const [SetSpec(repsMin: 5, repsMax: 5, weightKg: 80)]);
      expect(slot.weeklySets[1], const [SetSpec(repsMin: 8, repsMax: 10)]);
    });

    test('rango a medias: se completa con el otro extremo, nunca invertido',
        () {
      final slot = slotFrom([
        const [SetSpec(repsMin: 8), SetSpec(repsMax: 12)],
      ]);
      expect(slot.sets, const [
        SetSpec(repsMin: 8, repsMax: 8),
        SetSpec(repsMin: 12, repsMax: 12),
      ]);
      expect([slot.targetRepsMin, slot.targetRepsMax], [8, 12]);
    });
  });
}
