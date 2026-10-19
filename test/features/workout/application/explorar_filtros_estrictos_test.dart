// EXPLORAR: cada combinación de filtros muestra EXACTAMENTE las plantillas
// que cumplen todo lo elegido — ni una de más, ni una de menos.
//
// Contra el catálogo REAL (el JSON que siembra `scripts/seed_templates.js`)
// y la grilla tal cual la arma la app (providers reales). Lo que se espera lo
// calcula un oráculo escrito acá, a mano y sin usar `TemplateAffinity`, para
// que un error en la regla no se pueda "confirmar a sí mismo".
//
// Reglas (decididas por el dueño, ver PR):
//   * días: igual a los elegidos;
//   * minutos: "tengo hasta X" → dura X o menos; "75 o más" no filtra;
//   * objetivo: la plantilla tiene AL MENOS uno de los elegidos;
//   * foco: la plantilla dedica ≥ 10 % de sus ejercicios a AL MENOS una de
//     las zonas elegidas (el mismo umbral que usa la búsqueda por músculo);
//   * nivel y texto, como siempre.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/template_preferences_providers.dart';
import 'package:treino/features/workout/application/unified_templates_providers.dart';
import 'package:treino/features/workout/domain/muscle_group.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_goal.dart';
import 'package:treino/features/workout/domain/template_preferences.dart';
import 'package:treino/features/workout/domain/template_search.dart';

final _prefs =
    StateProvider<TemplatePreferences>((ref) => const TemplatePreferences());

// ── Oráculo ──────────────────────────────────────────────────────────────────

bool _dias(Routine r, int? d) => d == null || r.days.length == d;

bool _minutos(Routine r, int? m) {
  if (m == null || m >= 75) return true;
  final dura = r.estimatedMinutesPerDay;
  return dura != null && dura <= m;
}

bool _objetivo(Routine r, List<RoutineGoal> g) =>
    g.isEmpty || r.goals.any(g.contains);

bool _foco(Routine r, List<MuscleGroup> zonas) {
  if (zonas.isEmpty) return true;
  final slots = [for (final d in r.days) ...d.slots];
  if (slots.isEmpty) return false;
  return zonas.any((z) {
    final n = slots.where((s) => MuscleGroup.fromKey(s.muscleGroup) == z);
    return n.length / slots.length >= 0.10;
  });
}

void main() {
  late List<Routine> catalogo;
  late ProviderContainer c;

  setUpAll(() {
    catalogo = (jsonDecode(
      File('docs/video-catalog-audit/improved-templates.json')
          .readAsStringSync(),
    ) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((t) => Routine.fromJson({...t, 'id': t['id']}))
        .toList();
  });

  setUp(() async {
    c = ProviderContainer(overrides: [
      routinesProvider.overrideWith((ref) async => catalogo),
      currentAthleteLinkProvider.overrideWith((ref) => Stream.value(null)),
      communityTemplatesProvider.overrideWith((ref) => const []),
      athleteTemplatePreferencesProvider
          .overrideWith((ref) => ref.watch(_prefs)),
    ]);
    c.listen(searchedUnifiedTemplatesProvider, (_, __) {});
    await c.read(routinesProvider.future);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() => c.dispose());

  Set<String> grilla({
    required TemplatePreferences prefs,
    ExperienceLevel? nivel,
    String texto = '',
  }) {
    c.read(_prefs.notifier).state = prefs;
    c.read(routinesLevelFilterProvider.notifier).state = nivel;
    c.read(templatesSearchQueryProvider.notifier).state = texto;
    return {
      for (final e in c.read(searchedUnifiedTemplatesProvider).requireValue)
        e.routine.id,
    };
  }

  Set<String> esperado({
    required TemplatePreferences p,
    ExperienceLevel? nivel,
    String texto = '',
  }) {
    final base = [
      for (final r in catalogo)
        if ((nivel == null || r.level == nivel) &&
            _dias(r, p.daysPerWeek) &&
            _minutos(r, p.minutesPerSession) &&
            _objetivo(r, p.goals) &&
            _foco(r, p.priorityGroups))
          r,
    ];
    final filtradas = TemplateSearch.isBlank(texto)
        ? base
        : TemplateSearch.filter(base, texto, (r) => r);
    return {for (final r in filtradas) r.id};
  }

  const dias = <int?>[null, 2, 3, 4, 5, 6];
  const minutos = <int?>[null, 30, 45, 60, 75];
  const objetivos = <List<RoutineGoal>>[
    [],
    [RoutineGoal.health],
    [RoutineGoal.injuryPrevention],
    [RoutineGoal.aesthetics],
    [RoutineGoal.sport],
    [RoutineGoal.wellbeing],
    [RoutineGoal.health, RoutineGoal.wellbeing],
    [RoutineGoal.aesthetics, RoutineGoal.sport],
  ];
  const zonas = <List<MuscleGroup>>[
    [],
    [MuscleGroup.espalda],
    [MuscleGroup.pecho],
    [MuscleGroup.hombros],
    [MuscleGroup.gluteos],
    [MuscleGroup.cuadriceps],
    [MuscleGroup.abdominales],
    [MuscleGroup.gluteos, MuscleGroup.cuadriceps],
  ];
  const niveles = <ExperienceLevel?>[null, ...ExperienceLevel.values];

  TemplatePreferences prefs(
    int? d,
    int? m,
    List<RoutineGoal> g,
    List<MuscleGroup> z,
  ) =>
      TemplatePreferences(
        daysPerWeek: d,
        minutesPerSession: m,
        goals: g,
        priorityMuscleGroups: [for (final x in z) x.key],
      );

  test(
      'el reporte: 30 min nunca muestra una plantilla de más de 30 '
      '(todas las demás combinaciones abiertas)', () {
    final ids = grilla(prefs: const TemplatePreferences(minutesPerSession: 30));
    expect(ids, isNotEmpty);
    for (final r in catalogo.where((r) => ids.contains(r.id))) {
      expect(r.estimatedMinutesPerDay, lessThanOrEqualTo(30), reason: r.id);
    }
  });

  test(
      'cada combinación de días × minutos × objetivo × foco × nivel '
      'muestra exactamente lo que cumple todo', () {
    var combinaciones = 0;
    var vacias = 0;
    for (final d in dias) {
      for (final m in minutos) {
        for (final g in objetivos) {
          for (final z in zonas) {
            for (final n in niveles) {
              final p = prefs(d, m, g, z);
              final real = grilla(prefs: p, nivel: n);
              final ok = esperado(p: p, nivel: n);
              expect(real, ok,
                  reason: 'días=$d min=$m obj=${g.map((x) => x.name)} '
                      'foco=${z.map((x) => x.name)} nivel=${n?.name}');
              combinaciones++;
              if (ok.isEmpty) vacias++;
            }
          }
        }
      }
    }
    // 6 × 5 × 8 × 8 × 4: que el barrido no se achique sin que nadie lo note.
    expect(combinaciones, 7680);
    // Y que el barrido no sea trivial: hay combinaciones vacías y llenas.
    expect(vacias, inInclusiveRange(1, combinaciones - 1));
  });

  test('con búsqueda por texto, la grilla es el filtro ∩ la búsqueda', () {
    const textos = [
      'pecho y triceps',
      'triceps',
      'pecho',
      'sentadilla',
      'gluteos',
      'full body'
    ];
    for (final t in textos) {
      for (final d in dias) {
        for (final m in minutos) {
          for (final g in objetivos) {
            for (final n in niveles) {
              final p = prefs(d, m, g, const []);
              expect(grilla(prefs: p, nivel: n, texto: t),
                  esperado(p: p, nivel: n, texto: t),
                  reason: '"$t" días=$d min=$m '
                      'obj=${g.map((x) => x.name)} nivel=${n?.name}');
            }
          }
        }
      }
    }
  });

  test(
      '"ver todas" levanta TODOS los filtros del cuestionario, '
      'pero no el nivel ni el texto', () {
    final p =
        prefs(2, 30, const [RoutineGoal.sport], const [MuscleGroup.pecho]);
    grilla(prefs: p);
    c.read(templatesPreferenceFilterLiftedProvider.notifier).state = true;
    final ids = {
      for (final e in c.read(searchedUnifiedTemplatesProvider).requireValue)
        e.routine.id,
    };
    expect(ids, hasLength(catalogo.length));
  });
}
