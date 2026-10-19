// Filtro duro de EXPLORAR (#1561) compuesto con nivel, orden por afinidad y
// búsqueda de texto — la cadena completa tal cual la arma PlantillasTab.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/template_preferences_providers.dart';
import 'package:treino/features/workout/application/unified_templates_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_goal.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/template_preferences.dart';

RoutineSlot _slot(String id, String muscle) => RoutineSlot(
      exerciseId: 'e-$id-$muscle',
      exerciseName: 'Ejercicio $muscle',
      muscleGroup: muscle,
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 60,
    );

Routine _r(
  String id, {
  required int days,
  int? minutes,
  List<RoutineGoal> goals = const [],
  ExperienceLevel level = ExperienceLevel.beginner,
  List<String> muscles = const ['chest', 'triceps'],
}) =>
    Routine(
      id: id,
      name: 'Plantilla $id',
      level: level,
      estimatedMinutesPerDay: minutes,
      goals: goals,
      days: [
        for (var i = 0; i < days; i++)
          RoutineDay(
            dayNumber: i + 1,
            name: 'Día ${i + 1}',
            slots: [for (final m in muscles) _slot(id, m)],
          ),
      ],
    );

final _sistema = [
  _r('push3', days: 3, minutes: 75, goals: const [RoutineGoal.health]),
  _r('bro5', days: 5, minutes: 75, goals: const [RoutineGoal.health]),
  _r('ppl6', days: 6, minutes: 75, goals: const [RoutineGoal.health]),
  _r('corta3', days: 3, minutes: 30, muscles: const ['chest', 'triceps']),
  _r('full4', days: 4, minutes: 60, level: ExperienceLevel.advanced),
  _r('pierna2', days: 2, minutes: 45, muscles: const ['quads']),
];

// Comunidad/PF: sin minutos cargados y sin objetivos (publicadas antes de
// #635). `pf3` tiene series, así que el estimador de #1562 le calcula 16 min
// por día; `pfvacia` no tiene nada que estimar — desconocido, nunca excluida
// por minutos.
final _comunidad = [
  _r('pf3', days: 3),
  _r('pfvacia', days: 3, muscles: const []),
];

Future<ProviderContainer> _pump({
  TemplatePreferences prefs = const TemplatePreferences(),
  ExperienceLevel? level,
  String query = '',
}) async {
  final container = ProviderContainer(overrides: [
    routinesProvider.overrideWith((ref) async => _sistema),
    currentAthleteLinkProvider.overrideWith((ref) => Stream.value(null)),
    communityTemplatesProvider.overrideWith((ref) => _comunidad),
    athleteTemplatePreferencesProvider.overrideWithValue(prefs),
  ]);
  addTearDown(container.dispose);
  container.read(routinesLevelFilterProvider.notifier).state = level;
  container.read(templatesSearchQueryProvider.notifier).state = query;
  container.listen(searchedUnifiedTemplatesProvider, (_, __) {});
  await container.read(routinesProvider.future);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return container;
}

List<String> _ids(ProviderContainer c) => [
      for (final e in c.read(searchedUnifiedTemplatesProvider).requireValue)
        e.routine.id,
    ];

void main() {
  group('días × minutos', () {
    test('con 3 días no aparece una de 5 ni una de 6', () async {
      final c = await _pump(prefs: const TemplatePreferences(daysPerWeek: 3));
      final ids = _ids(c);
      expect(ids, isNot(contains('bro5')));
      expect(ids, isNot(contains('ppl6')));
      expect(ids, unorderedEquals(['push3', 'corta3', 'pf3', 'pfvacia']));
    });

    test('barrido de días 2–6: sólo las de esa cantidad', () async {
      for (final d in [2, 3, 4, 5, 6]) {
        final c = await _pump(prefs: TemplatePreferences(daysPerWeek: d));
        final esperado = [
          for (final r in [..._comunidad, ..._sistema])
            if (r.days.length == d) r.id,
        ];
        expect(_ids(c), unorderedEquals(esperado), reason: '$d días');
      }
    });

    test(
        '3 días · 75 min: la de 30 min sale, la de comunidad se juzga por '
        'su estimación y la que no tiene dato se queda', () async {
      final c = await _pump(
        prefs: const TemplatePreferences(daysPerWeek: 3, minutesPerSession: 75),
      );
      // pf3 estima 16 min: no es "75 o más".
      expect(_ids(c), unorderedEquals(['push3', 'pfvacia']));
    });

    test('sólo minutos: 30 → ±15', () async {
      final c = await _pump(
        prefs: const TemplatePreferences(minutesPerSession: 30),
      );
      // 30 y 45 entran; 60/75 no; pf3 estima 16 (a 14 de 30) entra; sin
      // estimación posible (pfvacia) entra.
      expect(_ids(c), unorderedEquals(['corta3', 'pierna2', 'pf3', 'pfvacia']));
    });
  });

  group('objetivo y foco NO filtran, sólo ordenan', () {
    test('objetivo y zona sin días/minutos: se ve todo el catálogo', () async {
      final c = await _pump(
        prefs: const TemplatePreferences(
          goals: [RoutineGoal.sport],
          priorityMuscleGroups: ['back'],
        ),
      );
      expect(_ids(c), hasLength(_sistema.length + _comunidad.length));
    });

    test('con 3 días, el objetivo ordena: la que lo cubre va primero',
        () async {
      final c = await _pump(
        prefs: const TemplatePreferences(
          daysPerWeek: 3,
          goals: [RoutineGoal.health],
        ),
      );
      expect(_ids(c).first, 'push3');
      expect(_ids(c), hasLength(4));
    });
  });

  group('combinado con nivel y texto', () {
    test('nivel × días: 4 días + avanzado', () async {
      final c = await _pump(
        prefs: const TemplatePreferences(daysPerWeek: 4),
        level: ExperienceLevel.advanced,
      );
      expect(_ids(c), ['full4']);
    });

    test('nivel × días sin intersección ⇒ vacío', () async {
      final c = await _pump(
        prefs: const TemplatePreferences(daysPerWeek: 3),
        level: ExperienceLevel.advanced,
      );
      expect(_ids(c), isEmpty);
    });

    test(
        'texto con y sin relleno: "pecho y triceps", "triceps", "pecho" '
        'respetan los días', () async {
      for (final q in ['pecho y triceps', 'triceps', 'pecho']) {
        final c = await _pump(
          prefs: const TemplatePreferences(daysPerWeek: 3),
          query: q,
        );
        final ids = _ids(c);
        expect(ids, isNot(contains('bro5')), reason: q);
        expect(ids, isNot(contains('ppl6')), reason: q);
        expect(ids, containsAll(['push3', 'pf3']), reason: q);
        expect(ids, isNot(contains('pierna2')), reason: q);
      }
    });

    test('el caso del issue: 3 días · 75 min · salud + "pecho y triceps"',
        () async {
      final c = await _pump(
        prefs: const TemplatePreferences(
          daysPerWeek: 3,
          minutesPerSession: 75,
          goals: [RoutineGoal.health],
        ),
        query: 'pecho y triceps',
      );
      // pf3 estima 16 min y sale; pfvacia no tiene ejercicios: el texto la
      // descarta.
      expect(_ids(c), ['push3']);
    });
  });

  group('motivo del vacío (templatesEmptyReasonProvider)', () {
    TemplatesEmptyReason? reason(ProviderContainer c) =>
        c.read(templatesEmptyReasonProvider);

    test('con resultados no hay motivo', () async {
      final c = await _pump(prefs: const TemplatePreferences(daysPerWeek: 3));
      expect(reason(c), isNull);
    });

    test('vacío por NIVEL aunque haya filtro duro: no se ofrece "Ver todas"',
        () async {
      final c = await _pump(
        prefs: const TemplatePreferences(daysPerWeek: 3),
        level: ExperienceLevel.intermediate,
      );
      expect(_ids(c), isEmpty);
      expect(reason(c), TemplatesEmptyReason.level);
      expect(reason(c)!.canLiftPreferenceFilter, isFalse);
    });

    test('vacío por TEXTO aunque haya filtro duro: no se ofrece "Ver todas"',
        () async {
      final c = await _pump(
        prefs: const TemplatePreferences(daysPerWeek: 3),
        query: 'zzzz',
      );
      expect(_ids(c), isEmpty);
      expect(reason(c), TemplatesEmptyReason.search);
      expect(reason(c)!.canLiftPreferenceFilter, isFalse);
    });

    test('vacío por DÍAS: el nivel solo deja algo, los días lo vacían',
        () async {
      final c = await _pump(
        prefs: const TemplatePreferences(daysPerWeek: 6),
        level: ExperienceLevel.advanced,
      );
      expect(_ids(c), isEmpty);
      expect(reason(c), TemplatesEmptyReason.days);
      expect(reason(c)!.canLiftPreferenceFilter, isTrue);
    });

    test('vacío por MINUTOS: se culpa a los minutos, no a los días', () async {
      final c = await _pump(
        prefs: const TemplatePreferences(minutesPerSession: 30),
        level: ExperienceLevel.advanced,
      );
      expect(_ids(c), isEmpty);
      expect(reason(c), TemplatesEmptyReason.minutes);
    });

    test('días y minutos tienen cada uno resultados, pero no juntos', () async {
      final c = await _pump(
        prefs: const TemplatePreferences(daysPerWeek: 4, minutesPerSession: 30),
      );
      expect(_ids(c), isEmpty);
      expect(reason(c), TemplatesEmptyReason.daysAndMinutes);
      expect(reason(c)!.canLiftPreferenceFilter, isTrue);
    });

    test('nivel Y texto, y la pill sola ya vacía: se culpa al nivel', () async {
      final c = await _pump(
        prefs: const TemplatePreferences(daysPerWeek: 3),
        level: ExperienceLevel.intermediate,
        query: 'pecho',
      );
      expect(reason(c), TemplatesEmptyReason.level);
    });

    test('días y minutos vacían CADA UNO solos: se nombran los días', () async {
      final c = await _pump(
        prefs: const TemplatePreferences(daysPerWeek: 6, minutesPerSession: 30),
        level: ExperienceLevel.advanced,
      );
      expect(reason(c), TemplatesEmptyReason.days);
    });

    test('con el filtro levantado, el vacío vuelve a ser de nivel', () async {
      final c = await _pump(
        prefs: const TemplatePreferences(daysPerWeek: 3),
        level: ExperienceLevel.intermediate,
      );
      c.read(templatesPreferenceFilterLiftedProvider.notifier).state = true;
      expect(reason(c), TemplatesEmptyReason.level);
    });
  });

  group('combinación vacía y salida', () {
    test('2 días + 30 min ⇒ vacío, filtro activo; levantarlo muestra todo',
        () async {
      final c = await _pump(
        prefs: const TemplatePreferences(daysPerWeek: 6, minutesPerSession: 30),
      );
      expect(_ids(c), isEmpty);
      expect(c.read(templatesPreferenceFilterActiveProvider), isTrue);

      c.read(templatesPreferenceFilterLiftedProvider.notifier).state = true;
      expect(c.read(templatesPreferenceFilterActiveProvider), isFalse);
      expect(_ids(c), hasLength(_sistema.length + _comunidad.length));
    });

    test('levantar conserva nivel y texto', () async {
      final c = await _pump(
        prefs: const TemplatePreferences(daysPerWeek: 6),
        level: ExperienceLevel.advanced,
      );
      expect(_ids(c), isEmpty);
      c.read(templatesPreferenceFilterLiftedProvider.notifier).state = true;
      expect(_ids(c), ['full4']);
    });

    test('sin días/minutos el filtro no está activo', () async {
      final c = await _pump(
        prefs: const TemplatePreferences(goals: [RoutineGoal.health]),
      );
      expect(c.read(templatesPreferenceFilterActiveProvider), isFalse);
    });
  });
}
