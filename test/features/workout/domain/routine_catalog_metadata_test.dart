import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/muscle_group.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_goal.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/profile/domain/experience_level.dart';

RoutineSlot _slot(String muscleGroup, {String id = 'e'}) => RoutineSlot(
      exerciseId: id,
      exerciseName: id,
      muscleGroup: muscleGroup,
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 90,
    );

Routine _routine(List<List<String>> daysOfGroups) => Routine(
      id: 'r1',
      name: 'R',
      level: ExperienceLevel.beginner,
      days: [
        for (var i = 0; i < daysOfGroups.length; i++)
          RoutineDay(
            dayNumber: i + 1,
            name: 'D${i + 1}',
            slots: [for (final g in daysOfGroups[i]) _slot(g)],
          ),
      ],
    );

void main() {
  group('Routine.goals — decodificación tolerante', () {
    test('un objetivo desconocido NO rompe el parseo de la rutina', () {
      // El modo de falla que esto previene: un cliente nuevo agrega un goal,
      // y el viejo deja de poder leer la rutina ENTERA — la plantilla no se
      // degrada, desaparece de la grilla.
      final json = {
        'id': 'r1',
        'name': 'R',
        'level': 'beginner',
        'days': <Object?>[],
        'goals': ['health', 'teleportation', 'sport'],
      };

      final routine = Routine.fromJson(json);

      expect(routine.goals, [RoutineGoal.health, RoutineGoal.sport],
          reason: 'lo desconocido se descarta, lo conocido sobrevive');
      expect(routine.name, 'R', reason: 'el resto de la rutina se parsea igual');
    });

    test('goals ausente decodifica como lista vacía, no como null', () {
      // Vacío = NEUTRO para el scoring. Toda plantilla publicada por la
      // comunidad antes de #635 llega así, y son la mayoría del catálogo.
      final routine = Routine.fromJson({
        'id': 'r1',
        'name': 'R',
        'level': 'beginner',
        'days': <Object?>[],
      });

      expect(routine.goals, isEmpty);
    });

    test('el round-trip usa los wireKey, no los nombres del enum', () {
      final routine = _routine([]).copyWith(
        goals: const [RoutineGoal.injuryPrevention],
      );

      expect(routine.toJson()['goals'], ['injury_prevention']);
    });
  });

  group('Routine.primaryMuscleGroups — derivado de los slots', () {
    test('ordena por frecuencia descendente', () {
      final routine = _routine([
        ['chest', 'chest', 'triceps'],
        ['chest', 'triceps', 'back'],
      ]);

      expect(routine.primaryMuscleGroups, [
        MuscleGroup.pecho, // 3
        MuscleGroup.triceps, // 2
        MuscleGroup.espalda, // 1
      ]);
    });

    test('canonicaliza el `fullbody` legacy del catálogo sembrado', () {
      // Las 7 plantillas stock guardan `fullbody`; el enum dice `full_body`.
      // Comparar crudo las dejaría sin zonas.
      expect(
        _routine([
          ['fullbody']
        ]).primaryMuscleGroups,
        [MuscleGroup.cuerpoCompleto],
      );
    });

    test('canonicaliza las etiquetas en español del editor viejo', () {
      expect(
        _routine([
          ['Pecho']
        ]).primaryMuscleGroups,
        [MuscleGroup.pecho],
      );
    });

    test('descarta lo desconocido en vez de contaminar el conteo', () {
      expect(
        _routine([
          ['chest', 'Otro', '', 'chest']
        ]).primaryMuscleGroups,
        [MuscleGroup.pecho],
      );
    });

    test('una rutina sin slots no tiene zonas, y eso es neutro', () {
      expect(_routine([]).primaryMuscleGroups, isEmpty);
      expect(_routine([[]]).primaryMuscleGroups, isEmpty);
    });

    test('los empates resuelven por orden del enum, para ser estables', () {
      final a = _routine([
        ['back', 'chest']
      ]).primaryMuscleGroups;
      final b = _routine([
        ['chest', 'back']
      ]).primaryMuscleGroups;

      expect(a, b, reason: 'el orden de los slots no puede cambiar el ranking');
      expect(a, [MuscleGroup.pecho, MuscleGroup.espalda]);
    });

    test('las claves son el vocabulario que guarda TemplatePreferences', () {
      expect(
        _routine([
          ['chest', 'quads']
        ]).primaryMuscleGroupKeys,
        ['chest', 'quads'],
      );
    });
  });
}
