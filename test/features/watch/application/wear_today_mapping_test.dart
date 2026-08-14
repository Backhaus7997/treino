import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/watch/application/wear_today_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

/// Un slot mínimo. Los campos de periodización se pasan por parámetro porque
/// son justo lo que se está probando.
RoutineSlot _slot(
  String nombre, {
  int targetSets = 3,
  List<int> activeWeeks = const [],
  List<List<SetSpec>> weeklySets = const [],
}) =>
    RoutineSlot(
      exerciseId: nombre.toLowerCase(),
      exerciseName: nombre,
      muscleGroup: 'chest',
      targetSets: targetSets,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 60,
      activeWeeks: activeWeeks,
      weeklySets: weeklySets,
    );

({Routine routine, RoutineDay day, int dayNumber, int weekNumber}) _hoy({
  required List<RoutineSlot> slots,
  int numWeeks = 1,
  int weekNumber = 0,
  String dayName = 'Empuje',
  String routineName = 'Full Body 3 días',
}) {
  final day = RoutineDay(dayNumber: 1, name: dayName, slots: slots);
  return (
    routine: Routine(
      id: 'r1',
      name: routineName,
      level: ExperienceLevel.beginner,
      days: [day],
      numWeeks: numWeeks,
    ),
    day: day,
    dayNumber: 1,
    weekNumber: weekNumber,
  );
}

void main() {
  group('lo básico', () {
    test('pasa el día, la rutina y la periodización', () {
      final w = wearTodaysWorkoutFrom(
        _hoy(slots: [_slot('Sentadilla')], numWeeks: 4, weekNumber: 2),
      );

      expect(w.dayName, 'Empuje');
      expect(w.routineName, 'Full Body 3 días');
      expect(w.numWeeks, 4);
      // 0-based de punta a punta. El +1 lo hace la pantalla; convertirlo acá
      // mostraría la semana corrida.
      expect(w.weekNumber, 2);
    });

    test('el nombre sale del slot, sin tocar el catálogo de ejercicios', () {
      // exerciseName está denormalizado en la rutina (ADR-2). Si esto se
      // resolviera por exerciseId haría falta el catálogo entero en la muñeca.
      final w = wearTodaysWorkoutFrom(
        _hoy(slots: [_slot('Press de banca'), _slot('Remo con barra')]),
      );

      expect(
        [for (final e in w.exercises) e.name],
        ['Press de banca', 'Remo con barra'],
      );
      expect(w.exerciseCount, 2);
    });

    test('sin periodización, las series salen de los campos legacy', () {
      final w = wearTodaysWorkoutFrom(
        _hoy(slots: [_slot('Sentadilla', targetSets: 4)]),
      );

      expect(w.exercises.single.setCount, 4);
    });
  });

  group('periodización — lo que nunca corrió en un reloj', () {
    test('un ejercicio ausente en esta semana NO se lista', () {
      // activeWeeks [0, 2]: en la semana 1 este ejercicio no existe. Listarlo
      // le mostraría al atleta en la muñeca algo que no tiene que hacer.
      final slots = [
        _slot('Sentadilla'),
        _slot('Peso muerto', activeWeeks: const [0, 2]),
      ];

      final semana0 = wearTodaysWorkoutFrom(
        _hoy(slots: slots, numWeeks: 3, weekNumber: 0),
      );
      final semana1 = wearTodaysWorkoutFrom(
        _hoy(slots: slots, numWeeks: 3, weekNumber: 1),
      );

      expect([for (final e in semana0.exercises) e.name],
          ['Sentadilla', 'Peso muerto']);
      expect([for (final e in semana1.exercises) e.name], ['Sentadilla']);
    });

    test('las series salen de la SEMANA, no de targetSets', () {
      // targetSets dice 3, pero el plan prescribe 2 en la semana 0 y 5 en la 1.
      // Usar targetSets daría el número equivocado en las dos.
      final slot = _slot(
        'Press militar',
        targetSets: 3,
        weeklySets: const [
          [SetSpec(reps: 10), SetSpec(reps: 10)],
          [
            SetSpec(reps: 8),
            SetSpec(reps: 8),
            SetSpec(reps: 8),
            SetSpec(reps: 6),
            SetSpec(reps: 6),
          ],
        ],
      );

      expect(
        wearTodaysWorkoutFrom(_hoy(slots: [slot], numWeeks: 2, weekNumber: 0))
            .exercises
            .single
            .setCount,
        2,
      );
      expect(
        wearTodaysWorkoutFrom(_hoy(slots: [slot], numWeeks: 2, weekNumber: 1))
            .exercises
            .single
            .setCount,
        5,
      );
    });

    test('una semana de descarga autorizada como vacía da cero series', () {
      // `[]` autorizado NO cae al fallback: es una descarga real. El ejercicio
      // sigue presente —no está excluido por activeWeeks— pero sin series.
      final slot = _slot(
        'Sentadilla',
        targetSets: 4,
        weeklySets: const [
          [SetSpec(reps: 10)],
          <SetSpec>[],
        ],
      );

      final w = wearTodaysWorkoutFrom(
        _hoy(slots: [slot], numWeeks: 2, weekNumber: 1),
      );

      expect(w.exercises.single.name, 'Sentadilla');
      expect(w.exercises.single.setCount, 0);
    });

    test('una semana fuera de rango cae al comportamiento de siempre', () {
      final slot = _slot(
        'Sentadilla',
        targetSets: 4,
        weeklySets: const [
          [SetSpec(reps: 10)]
        ],
      );

      final w = wearTodaysWorkoutFrom(
        _hoy(slots: [slot], numWeeks: 2, weekNumber: 7),
      );

      expect(w.exercises.single.setCount, 4);
    });
  });

  test('un día sin slots da una lista vacía, no una excepción', () {
    final w = wearTodaysWorkoutFrom(_hoy(slots: const []));

    expect(w.exercises, isEmpty);
    expect(w.exerciseCount, 0);
  });
}
