import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';
import 'package:treino/features/coach_hub/data/periodized_excel_parser.dart';
import 'package:treino/features/coach_hub/data/periodized_routine_mapper.dart';
import 'package:treino/features/coach_hub/domain/periodized_plan.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
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
}
