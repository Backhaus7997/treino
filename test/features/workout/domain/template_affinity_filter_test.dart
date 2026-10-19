// Filtro DURO de EXPLORAR (#1561): días exactos y minutos ±15. Objetivo y
// foco NO filtran (siguen siendo sólo orden — ver template_affinity_test).

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_goal.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/template_affinity.dart';
import 'package:treino/features/workout/domain/template_preferences.dart';

Routine _routine({
  int days = 3,
  int? minutes,
  List<RoutineGoal> goals = const [],
}) =>
    Routine(
      id: 'r',
      name: 'R',
      level: ExperienceLevel.beginner,
      estimatedMinutesPerDay: minutes,
      goals: goals,
      days: [
        for (var i = 0; i < days; i++)
          RoutineDay(dayNumber: i + 1, name: 'D${i + 1}', slots: const []),
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
                RoutineSlot(
                  exerciseId: m,
                  exerciseName: m,
                  muscleGroup: m,
                  targetSets: 3,
                  targetRepsMin: 8,
                  targetRepsMax: 12,
                  restSeconds: 60,
                ),
            ],
          ),
      ],
    );

bool _fits(Routine r, TemplatePreferences p) =>
    TemplateAffinity.matchesHardFilters(r, p);

void main() {
  group('días: coincidencia exacta', () {
    test('con 3 días una de 5 NO aparece (el bug del issue)', () {
      const prefs = TemplatePreferences(daysPerWeek: 3);
      expect(_fits(_routine(days: 5), prefs), isFalse);
      expect(_fits(_routine(days: 6), prefs), isFalse);
      expect(_fits(_routine(days: 4), prefs), isFalse,
          reason: 'exacto: ni un día de diferencia');
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

    test('plantilla sin días cargados: desconocido no es desajuste', () {
      expect(
        _fits(_routine(days: 0), const TemplatePreferences(daysPerWeek: 3)),
        isTrue,
      );
    });
  });

  group('minutos: ±15', () {
    const prefs = TemplatePreferences(minutesPerSession: 45);

    test('dentro de la tolerancia pasa, fuera no (bordes incluidos)', () {
      expect(_fits(_routine(minutes: 30), prefs), isTrue);
      expect(_fits(_routine(minutes: 45), prefs), isTrue);
      expect(_fits(_routine(minutes: 60), prefs), isTrue);
      expect(_fits(_routine(minutes: 29), prefs), isFalse);
      expect(_fits(_routine(minutes: 61), prefs), isFalse);
      expect(_fits(_routine(minutes: 90), prefs), isFalse);
    });

    test('sin minutos (comunidad/PF) NO se excluye', () {
      expect(_fits(_routine(minutes: null), prefs), isTrue);
      expect(_fits(_routine(minutes: 0), prefs), isTrue);
    });

    test('75 significa "75 o más": sin techo, piso en 60', () {
      const p75 = TemplatePreferences(minutesPerSession: 75);
      expect(_fits(_routine(minutes: 60), p75), isTrue);
      expect(_fits(_routine(minutes: 75), p75), isTrue);
      expect(_fits(_routine(minutes: 110), p75), isTrue);
      expect(_fits(_routine(minutes: 59), p75), isFalse);
    });

    test('30 min: una de 60 no entra', () {
      const p30 = TemplatePreferences(minutesPerSession: 30);
      expect(_fits(_routine(minutes: 60), p30), isFalse);
      expect(_fits(_routine(minutes: 45), p30), isTrue);
    });
  });

  group('minutos sin dato cargado: respaldo del estimador (#1562)', () {
    test('se filtra con la duración estimada de sus series', () {
      expect(TemplateAffinity.minutesOf(_estimable()), 16);
      expect(
        _fits(_estimable(), const TemplatePreferences(minutesPerSession: 75)),
        isFalse,
        reason: '16 min estimados no son "75 o más"',
      );
      expect(
        _fits(_estimable(), const TemplatePreferences(minutesPerSession: 30)),
        isTrue,
        reason: '16 está a 14 de 30: dentro de ±15',
      );
    });

    test('sin series ni minutos no hay estimación y la plantilla pasa', () {
      expect(TemplateAffinity.minutesOf(_routine()), isNull);
      expect(
        _fits(_routine(), const TemplatePreferences(minutesPerSession: 30)),
        isTrue,
      );
    });

    test('el orden usa la misma estimación que el filtro', () {
      const prefs = TemplatePreferences(minutesPerSession: 30);
      final estimada = TemplateAffinity.score(_estimable(), prefs);
      expect(
        estimada,
        TemplateAffinity.score(
          _estimable().copyWith(estimatedMinutesPerDay: 16),
          prefs,
        ),
        reason: 'puntúa igual que si tuviera los 16 min cargados',
      );
      expect(
        estimada,
        isNot(TemplateAffinity.score(_routine(), prefs)),
        reason: 'no es el neutral de una plantilla sin dato',
      );
    });
  });

  test('"75 o más" tampoco tiene techo al ORDENAR', () {
    const prefs = TemplatePreferences(minutesPerSession: 75);
    expect(
      TemplateAffinity.score(_routine(minutes: 100), prefs),
      greaterThan(TemplateAffinity.score(_routine(minutes: 70), prefs)),
      reason: 'el filtro deja entrar la de 100: el orden no puede hundirla',
    );
  });

  group('matchesDays / matchesMinutes por separado', () {
    test('cada dimensión se evalúa sola', () {
      const prefs = TemplatePreferences(daysPerWeek: 3, minutesPerSession: 30);
      final r = _routine(days: 3, minutes: 90);
      expect(TemplateAffinity.matchesDays(r, prefs), isTrue);
      expect(TemplateAffinity.matchesMinutes(r, prefs), isFalse);
      expect(_fits(r, prefs), isFalse);
    });
  });

  group('objetivo y foco NO filtran', () {
    test('objetivo opuesto, sin objetivos y foco distinto pasan', () {
      const prefs = TemplatePreferences(
        goals: [RoutineGoal.sport],
        priorityMuscleGroups: ['back'],
      );
      expect(
        _fits(_routine(goals: const [RoutineGoal.aesthetics]), prefs),
        isTrue,
      );
      expect(_fits(_routine(), prefs), isTrue);
    });
  });

  group('combinaciones', () {
    test('días Y minutos: tienen que cumplirse los dos', () {
      const prefs = TemplatePreferences(daysPerWeek: 3, minutesPerSession: 75);
      expect(_fits(_routine(days: 3, minutes: 75), prefs), isTrue);
      expect(_fits(_routine(days: 5, minutes: 75), prefs), isFalse);
      expect(_fits(_routine(days: 3, minutes: 30), prefs), isFalse);
      expect(_fits(_routine(days: 3), prefs), isTrue);
    });

    test('preferencias vacías: todo pasa', () {
      expect(
        _fits(_routine(days: 6, minutes: 120), const TemplatePreferences()),
        isTrue,
      );
    });

    test('hasHardFilters: sólo días o minutos', () {
      expect(
        TemplateAffinity.hasHardFilters(const TemplatePreferences()),
        isFalse,
      );
      expect(
        TemplateAffinity.hasHardFilters(
          const TemplatePreferences(goals: [RoutineGoal.health]),
        ),
        isFalse,
      );
      expect(
        TemplateAffinity.hasHardFilters(
          const TemplatePreferences(daysPerWeek: 3),
        ),
        isTrue,
      );
      expect(
        TemplateAffinity.hasHardFilters(
          const TemplatePreferences(minutesPerSession: 30),
        ),
        isTrue,
      );
    });
  });
}
