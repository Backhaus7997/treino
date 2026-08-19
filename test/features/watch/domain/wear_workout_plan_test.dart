import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/watch/domain/wear_workout_plan.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

RoutineSlot _slot(
  String nombre, {
  int targetSets = 3,
  int restSeconds = 60,
  int? supersetGroup,
  List<int> activeWeeks = const [],
  List<List<SetSpec>> weeklySets = const [],
}) =>
    RoutineSlot(
      supersetGroup: supersetGroup,
      exerciseId: nombre.toLowerCase().replaceAll(' ', '-'),
      exerciseName: nombre,
      muscleGroup: 'back',
      targetSets: targetSets,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: restSeconds,
      activeWeeks: activeWeeks,
      weeklySets: weeklySets,
    );

Routine _routine({required List<RoutineDay> days, int numWeeks = 1}) => Routine(
      id: 'r1',
      name: 'Fuerza Base',
      level: ExperienceLevel.beginner,
      days: days,
      numWeeks: numWeeks,
    );

void main() {
  test('trae exerciseId, nombre, series y descanso de cada slot', () {
    final plan = wearWorkoutPlanFrom(
      routine: _routine(days: [
        RoutineDay(dayNumber: 1, name: 'Tirón', slots: [
          _slot('Dominadas', targetSets: 4, restSeconds: 120),
          _slot('Curl', targetSets: 3, restSeconds: 45),
        ]),
      ]),
      dayNumber: 1,
      weekNumber: 0,
    )!;

    expect(plan.routineId, 'r1');
    expect(plan.dayName, 'Tirón');
    expect(plan.dayNumber, 1);
    expect(
        [for (final e in plan.exercises) e.exerciseId], ['dominadas', 'curl']);
    // Sin exerciseId no se puede escribir la serie: es media identidad.
    expect(plan.exercises.first.exerciseName, 'Dominadas');
    expect([for (final e in plan.exercises) e.restSeconds], [120, 45]);
    expect(plan.plannedSets, [4, 3]);
  });

  group('la posición la manda quien llama', () {
    test('resuelve el día pedido, NO el primero ni "el que tocaría hoy"', () {
      // El bug más caro del lado Apple (HANDOFF §4.4): el reloj adoptaba el
      // entreno del teléfono pero calculaba el día por su cuenta, así que cada
      // dispositivo miraba un día distinto y las series se escribían con los
      // ejercicios equivocados.
      final routine = _routine(days: [
        RoutineDay(dayNumber: 1, name: 'Empuje', slots: [_slot('Press')]),
        RoutineDay(dayNumber: 2, name: 'Tirón', slots: [_slot('Remo')]),
        RoutineDay(dayNumber: 3, name: 'Pierna', slots: [_slot('Sentadilla')]),
      ]);

      final plan = wearWorkoutPlanFrom(
        routine: routine,
        dayNumber: 2,
        weekNumber: 0,
      )!;

      expect(plan.dayName, 'Tirón');
      expect(plan.exercises.single.exerciseName, 'Remo');
    });

    test('un día que no existe devuelve null, no un plan vacío', () {
      final plan = wearWorkoutPlanFrom(
        routine: _routine(days: [
          RoutineDay(dayNumber: 1, name: 'Empuje', slots: [_slot('Press')]),
        ]),
        dayNumber: 7,
        weekNumber: 0,
      );

      // Arrancar un entreno vacío sería peor que no arrancarlo.
      expect(plan, isNull);
    });
  });

  group('periodización', () {
    test('un ejercicio ausente en la semana no entra al plan', () {
      final days = [
        RoutineDay(dayNumber: 1, name: 'Tirón', slots: [
          _slot('Dominadas'),
          _slot('Peso muerto', activeWeeks: const [0, 2]),
        ]),
      ];

      final sem0 = wearWorkoutPlanFrom(
          routine: _routine(days: days, numWeeks: 3),
          dayNumber: 1,
          weekNumber: 0)!;
      final sem1 = wearWorkoutPlanFrom(
          routine: _routine(days: days, numWeeks: 3),
          dayNumber: 1,
          weekNumber: 1)!;

      expect([for (final e in sem0.exercises) e.exerciseName],
          ['Dominadas', 'Peso muerto']);
      expect([for (final e in sem1.exercises) e.exerciseName], ['Dominadas']);
      // Y el cursor tiene que ver la lista de ESA semana, no la del plan entero.
      expect(sem1.plannedSets, [3]);
    });

    test('las series salen de la semana pedida, no de targetSets', () {
      final slot = _slot(
        'Press militar',
        targetSets: 3,
        weeklySets: const [
          [SetSpec(reps: 10), SetSpec(reps: 10)],
          [
            SetSpec(reps: 8),
            SetSpec(reps: 8),
            SetSpec(reps: 8),
            SetSpec(reps: 6)
          ],
        ],
      );
      final days = [
        RoutineDay(dayNumber: 1, name: 'Empuje', slots: [slot])
      ];

      expect(
        wearWorkoutPlanFrom(
                routine: _routine(days: days, numWeeks: 2),
                dayNumber: 1,
                weekNumber: 0)!
            .plannedSets,
        [2],
      );
      expect(
        wearWorkoutPlanFrom(
                routine: _routine(days: days, numWeeks: 2),
                dayNumber: 1,
                weekNumber: 1)!
            .plannedSets,
        [4],
      );
    });

    test('una semana de descarga autorizada como vacía da cero series', () {
      // El ejercicio SIGUE en el plan —no está excluido por activeWeeks— pero
      // sin series. `firstUnfinishedExerciseIndex` lo cuenta como completo, que
      // es lo que evita que el cursor se trabe ahí.
      final slot = _slot(
        'Sentadilla',
        targetSets: 4,
        weeklySets: const [
          [SetSpec(reps: 10)],
          <SetSpec>[],
        ],
      );

      final plan = wearWorkoutPlanFrom(
        routine: _routine(
          days: [
            RoutineDay(dayNumber: 1, name: 'Pierna', slots: [slot])
          ],
          numWeeks: 2,
        ),
        dayNumber: 1,
        weekNumber: 1,
      )!;

      expect(plan.exercises.single.exerciseName, 'Sentadilla');
      expect(plan.plannedSets, [0]);
    });

    test('una semana fuera de rango se clampea al plan, no mezcla semanas', () {
      // Un doc viejo, o una rutina a la que le sacaron semanas.
      final slot = _slot(
        'Sentadilla',
        targetSets: 9,
        weeklySets: const [
          [SetSpec(reps: 10)],
          [SetSpec(reps: 8), SetSpec(reps: 8)],
        ],
      );

      final plan = wearWorkoutPlanFrom(
        routine: _routine(
          days: [
            RoutineDay(dayNumber: 1, name: 'Pierna', slots: [slot])
          ],
          numWeeks: 2,
        ),
        dayNumber: 1,
        weekNumber: 7,
      )!;

      expect(plan.weekNumber, 1, reason: 'clampeada a la última real');
      expect(plan.plannedSets, [2]);
    });
  });

  test('un día sin slots da un plan sin ejercicios, no una excepción', () {
    final plan = wearWorkoutPlanFrom(
      routine: _routine(
          days: [const RoutineDay(dayNumber: 1, name: 'Vacío', slots: [])]),
      dayNumber: 1,
      weekNumber: 0,
    )!;

    expect(plan.exercises, isEmpty);
    expect(plan.plannedSets, isEmpty);
  });

  group('superseries', () {
    test('el plan se trae el supersetGroup de cada slot', () {
      // Sin esto el reloj no puede distinguir una superserie de tres ejercicios
      // sueltos, y avanza A1→A2→A3 en vez de 1a→1b→1c.
      final plan = wearWorkoutPlanFrom(
        routine: _routine(days: [
          RoutineDay(dayNumber: 1, name: 'Empuje', slots: [
            _slot('Press', supersetGroup: 1),
            _slot('Aperturas', supersetGroup: 1),
            _slot('Remo'),
          ]),
        ]),
        dayNumber: 1,
        weekNumber: 0,
      )!;

      expect(plan.supersetGroups, [1, 1, null]);
    });

    test('los grupos quedan alineados con plannedSets aunque falten semanas',
        () {
      // Un ejercicio ausente esta semana no entra al plan, así que el grupo
      // tampoco: si se desalinearan, el bloque agruparía ejercicios equivocados.
      final plan = wearWorkoutPlanFrom(
        routine: _routine(
          numWeeks: 2,
          days: [
            RoutineDay(dayNumber: 1, name: 'Empuje', slots: [
              _slot('Press', supersetGroup: 1),
              _slot('Aperturas', supersetGroup: 1, activeWeeks: const [0]),
              _slot('Remo', supersetGroup: 2),
            ]),
          ],
        ),
        dayNumber: 1,
        weekNumber: 1,
      )!;

      expect([for (final e in plan.exercises) e.exerciseId], ['press', 'remo']);
      expect(plan.supersetGroups, [1, 2]);
      expect(plan.supersetGroups.length, plan.plannedSets.length);
    });
  });
}
