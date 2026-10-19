import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/unified_templates_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_goal.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/template_preferences.dart';

RoutineSlot _slot(String muscleGroup) => RoutineSlot(
      exerciseId: 'e',
      exerciseName: 'e',
      muscleGroup: muscleGroup,
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 90,
    );

Routine _routine(
  String id, {
  int days = 3,
  int? minutes,
  List<RoutineGoal> goals = const [],
  String zone = 'chest',
}) =>
    Routine(
      id: id,
      name: id,
      split: 'Full Body',
      level: ExperienceLevel.beginner,
      estimatedMinutesPerDay: minutes,
      goals: goals,
      days: [
        for (var i = 0; i < days; i++)
          RoutineDay(dayNumber: i + 1, name: 'D', slots: [_slot(zone)]),
      ],
    );

UserProfile _profile(TemplatePreferences? prefs) => UserProfile(
      uid: 'athlete-1',
      email: 'a@t.com',
      displayName: 'A',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      templatePreferences: prefs,
    );

Future<List<String>> _rankedIds(
  List<Routine> catalog,
  TemplatePreferences? prefs,
) async {
  final container = ProviderContainer(overrides: [
    routinesProvider.overrideWith((ref) async => catalog),
    currentAthleteLinkProvider.overrideWith((ref) => Stream.value(null)),
    userProfileProvider.overrideWith((ref) => Stream.value(_profile(prefs))),
  ]);
  addTearDown(container.dispose);
  container.listen(rankedUnifiedTemplatesProvider, (_, __) {});
  await container.read(routinesProvider.future);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return container
          .read(rankedUnifiedTemplatesProvider)
          .valueOrNull
          ?.map((e) => e.routine.id)
          .toList() ??
      const [];
}

void main() {
  group('rankedUnifiedTemplatesProvider', () {
    test('sin preferencias devuelve la lista intacta', () async {
      // Quien saltó el cuestionario ve la grilla como venía. El provider
      // devuelve el AsyncValue de entrada sin siquiera puntuar.
      final ids = await _rankedIds(
        [_routine('a'), _routine('b'), _routine('c')],
        null,
      );
      expect(ids, ['a', 'b', 'c']);
    });

    test('el objetivo filtra: no declarar y otro objetivo quedan afuera',
        () async {
      final ids = await _rankedIds(
        [
          _routine('no-declara'),
          _routine('otro-objetivo', goals: const [RoutineGoal.sport]),
          _routine('matchea', goals: const [RoutineGoal.aesthetics]),
        ],
        const TemplatePreferences(goals: [RoutineGoal.aesthetics]),
      );
      expect(ids, ['matchea']);
    });

    test(
        'con dos objetivos, la que cubre los dos va antes que la que cubre uno',
        () async {
      final ids = await _rankedIds(
        [
          _routine('uno', goals: const [RoutineGoal.aesthetics]),
          _routine(
            'los-dos',
            goals: const [RoutineGoal.aesthetics, RoutineGoal.sport],
          ),
        ],
        const TemplatePreferences(
          goals: [RoutineGoal.aesthetics, RoutineGoal.sport],
        ),
      );
      expect(ids, ['los-dos', 'uno'],
          reason: 'filtra por al menos uno y ordena por cuántos cubre');
    });

    test('el orden es ESTABLE ante empates', () async {
      // Tres plantillas idénticas para el scoring: el orden tiene que ser el
      // de entrada, y el mismo en cada lectura. `List.sort` no garantiza
      // estabilidad en Dart, así que sin el desempate por posición estas
      // podrían intercambiarse entre rebuilds y la grilla bailaría sola.
      final catalog = [_routine('x'), _routine('y'), _routine('z')];
      const prefs = TemplatePreferences(daysPerWeek: 3);

      final primera = await _rankedIds(catalog, prefs);
      final segunda = await _rankedIds(catalog, prefs);

      expect(primera, ['x', 'y', 'z']);
      expect(segunda, primera);
    });

    test('objetivo y zona que ninguna cumple vacían la grilla', () async {
      final ids = await _rankedIds(
        [
          _routine('ppl',
              days: 3, minutes: 60, goals: const [RoutineGoal.health]),
          _routine('full', days: 3, minutes: 55),
        ],
        const TemplatePreferences(
          goals: [RoutineGoal.sport],
          priorityMuscleGroups: ['back'],
        ),
      );
      expect(ids, isEmpty);
    });

    test('días y minutos filtran: 2 días · 30 min no deja ninguna', () async {
      final ids = await _rankedIds(
        [
          _routine('ppl',
              days: 3, minutes: 60, goals: const [RoutineGoal.health]),
          _routine('full', days: 3, minutes: 55),
        ],
        const TemplatePreferences(
          daysPerWeek: 2,
          minutesPerSession: 30,
          goals: [RoutineGoal.sport],
          priorityMuscleGroups: ['back'],
        ),
      );
      expect(ids, isEmpty);
    });
  });
}
