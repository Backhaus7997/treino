// Filtro DURO de EXPLORAR: todo lo que el atleta elige filtra. Días exactos,
// minutos "tengo hasta X", objetivo y zonas. Sin dato NO pasa. Ver el dartdoc
// de TemplateAffinity y, contra el catálogo real,
// explorar_filtros_estrictos_test.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_goal.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/template_affinity.dart';
import 'package:treino/features/workout/domain/template_preferences.dart';

RoutineSlot _slot(String muscle) => RoutineSlot(
      exerciseId: muscle,
      exerciseName: muscle,
      muscleGroup: muscle,
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 0,
    );

Routine _routine({
  int days = 3,
  int? minutes,
  List<RoutineGoal> goals = const [],
  List<String> muscles = const [],
}) =>
    Routine(
      id: 'r',
      name: 'R',
      level: ExperienceLevel.beginner,
      estimatedMinutesPerDay: minutes,
      goals: goals,
      days: [
        for (var i = 0; i < days; i++)
          RoutineDay(
            dayNumber: i + 1,
            name: 'D${i + 1}',
            slots: [for (final m in muscles) _slot(m)],
          ),
      ],
    );

/// Sin `estimatedMinutesPerDay` pero con series: el estimador de #1562 tiene
/// de dónde sacar la duración. 3 días de 2 ejercicios × 3 series × 12 reps
/// con 60 s → 16 min por día.
Routine _estimable() => Routine(
      id: 'pf',
      name: 'PF',
      level: ExperienceLevel.beginner,
      days: [
        for (var i = 0; i < 3; i++)
          RoutineDay(
            dayNumber: i + 1,
            name: 'D${i + 1}',
            slots: [
              for (final m in ['chest', 'triceps'])
                _slot(m).copyWith(restSeconds: 60),
            ],
          ),
      ],
    );

bool _fits(Routine r, TemplatePreferences p) =>
    TemplateAffinity.matchesHardFilters(r, p);

void main() {
  group('días: coincidencia exacta', () {
    test('con 3 días una de 5 NO aparece', () {
      const prefs = TemplatePreferences(daysPerWeek: 3);
      expect(_fits(_routine(days: 5), prefs), isFalse);
      expect(_fits(_routine(days: 4), prefs), isFalse);
      expect(_fits(_routine(days: 2), prefs), isFalse);
      expect(_fits(_routine(days: 3), prefs), isTrue);
    });

    test('barrido 2–6: sólo pasa la de la misma cantidad', () {
      for (final wanted in [2, 3, 4, 5, 6]) {
        final prefs = TemplatePreferences(daysPerWeek: wanted);
        for (final have in [2, 3, 4, 5, 6]) {
          expect(_fits(_routine(days: have), prefs), have == wanted,
              reason: 'pide $wanted, la plantilla tiene $have');
        }
      }
    });

    test('plantilla sin días cargados: no se puede afirmar que encaje', () {
      expect(
        _fits(_routine(days: 0), const TemplatePreferences(daysPerWeek: 3)),
        isFalse,
      );
    });
  });

  group('minutos: "tengo hasta X"', () {
    test('el reporte: con 30 min no entra nada de más de 30', () {
      const p30 = TemplatePreferences(minutesPerSession: 30);
      expect(_fits(_routine(minutes: 20), p30), isTrue);
      expect(_fits(_routine(minutes: 30), p30), isTrue, reason: 'borde');
      expect(_fits(_routine(minutes: 31), p30), isFalse);
      expect(_fits(_routine(minutes: 45), p30), isFalse);
    });

    test('45 y 60: lo que dura eso o menos', () {
      for (final cap in [45, 60]) {
        final p = TemplatePreferences(minutesPerSession: cap);
        for (final m in [20, 30, 45, 50, 60, 75, 90]) {
          expect(_fits(_routine(minutes: m), p), m <= cap,
              reason: 'tengo $cap, la plantilla dura $m');
        }
      }
    });

    test('"75 o más" no filtra: con 75+ entra cualquiera', () {
      const p75 = TemplatePreferences(minutesPerSession: 75);
      for (final m in [20, 45, 75, 110]) {
        expect(_fits(_routine(minutes: m), p75), isTrue, reason: '$m');
      }
      expect(TemplateAffinity.hasHardFilters(p75), isFalse);
    });

    test('sin duración posible no pasa: no se puede afirmar que entre', () {
      expect(TemplateAffinity.minutesOf(_routine()), isNull);
      expect(
        _fits(_routine(), const TemplatePreferences(minutesPerSession: 60)),
        isFalse,
      );
    });
  });

  group('minutos sin dato cargado: respaldo del estimador (#1562)', () {
    test('se filtra con la duración estimada de sus series', () {
      expect(TemplateAffinity.minutesOf(_estimable()), 16);
      expect(
        _fits(_estimable(), const TemplatePreferences(minutesPerSession: 30)),
        isTrue,
        reason: '16 min estimados entran en "tengo hasta 30"',
      );
    });

    test('el orden usa la misma estimación que el filtro', () {
      const prefs = TemplatePreferences(minutesPerSession: 30);
      expect(
        TemplateAffinity.score(_estimable(), prefs),
        TemplateAffinity.score(
          _estimable().copyWith(estimatedMinutesPerDay: 16),
          prefs,
        ),
      );
    });
  });

  test('"75 o más" tampoco tiene techo al ORDENAR', () {
    const prefs = TemplatePreferences(minutesPerSession: 75);
    expect(
      TemplateAffinity.score(_routine(minutes: 100), prefs),
      greaterThan(TemplateAffinity.score(_routine(minutes: 70), prefs)),
    );
  });

  group('objetivo: al menos uno de los elegidos', () {
    const prefs = TemplatePreferences(
      goals: [RoutineGoal.sport, RoutineGoal.health],
    );

    test('comparte uno → pasa; ninguno → no', () {
      expect(
        _fits(_routine(goals: const [RoutineGoal.health]), prefs),
        isTrue,
      );
      expect(
        _fits(
          _routine(goals: const [RoutineGoal.aesthetics, RoutineGoal.sport]),
          prefs,
        ),
        isTrue,
      );
      expect(
        _fits(_routine(goals: const [RoutineGoal.aesthetics]), prefs),
        isFalse,
      );
    });

    test('sin objetivos declarados no pasa', () {
      expect(_fits(_routine(), prefs), isFalse);
    });
  });

  group('zonas: ≥ 10 % de los ejercicios en alguna elegida', () {
    const prefs = TemplatePreferences(priorityMuscleGroups: ['glutes']);

    test('justo en el 10 % pasa; por debajo no', () {
      final diez = ['glutes', for (var i = 0; i < 9; i++) 'chest'];
      final menos = ['glutes', for (var i = 0; i < 10; i++) 'chest'];
      expect(_fits(_routine(muscles: diez), prefs), isTrue);
      expect(_fits(_routine(muscles: menos), prefs), isFalse);
    });

    test('alcanza con UNA de las zonas elegidas', () {
      const dos = TemplatePreferences(
        priorityMuscleGroups: ['glutes', 'back'],
      );
      expect(_fits(_routine(muscles: const ['back', 'chest']), dos), isTrue);
      expect(_fits(_routine(muscles: const ['chest', 'biceps']), dos), isFalse);
    });

    test('"cuerpo completo" no cuenta como la zona pedida', () {
      expect(
        _fits(_routine(muscles: const ['full_body', 'chest']), prefs),
        isFalse,
      );
    });

    test('sin ejercicios no pasa', () {
      expect(_fits(_routine(), prefs), isFalse);
    });
  });

  group('combinaciones', () {
    test('tienen que cumplirse TODAS', () {
      const prefs = TemplatePreferences(
        daysPerWeek: 3,
        minutesPerSession: 45,
        goals: [RoutineGoal.health],
        priorityMuscleGroups: ['chest'],
      );
      Routine ok() => _routine(
            days: 3,
            minutes: 40,
            goals: const [RoutineGoal.health],
            muscles: const ['chest'],
          );
      expect(_fits(ok(), prefs), isTrue);
      expect(_fits(ok().copyWith(estimatedMinutesPerDay: 50), prefs), isFalse);
      expect(_fits(ok().copyWith(goals: const [RoutineGoal.sport]), prefs),
          isFalse);
      expect(
        _fits(
          _routine(
            days: 4,
            minutes: 40,
            goals: const [RoutineGoal.health],
            muscles: const ['chest'],
          ),
          prefs,
        ),
        isFalse,
      );
      expect(
        _fits(
          _routine(
            days: 3,
            minutes: 40,
            goals: const [RoutineGoal.health],
            muscles: const ['back'],
          ),
          prefs,
        ),
        isFalse,
      );
    });

    test('preferencias vacías: todo pasa', () {
      expect(
        _fits(_routine(days: 6, minutes: 120), const TemplatePreferences()),
        isTrue,
      );
    });

    test('hasHardFilters: cualquier respuesta salvo "75 o más"', () {
      bool has(TemplatePreferences p) => TemplateAffinity.hasHardFilters(p);
      expect(has(const TemplatePreferences()), isFalse);
      expect(has(const TemplatePreferences(minutesPerSession: 75)), isFalse);
      expect(has(const TemplatePreferences(daysPerWeek: 3)), isTrue);
      expect(has(const TemplatePreferences(minutesPerSession: 30)), isTrue);
      expect(
          has(const TemplatePreferences(goals: [RoutineGoal.health])), isTrue);
      expect(
        has(const TemplatePreferences(priorityMuscleGroups: ['back'])),
        isTrue,
      );
    });
  });
}
