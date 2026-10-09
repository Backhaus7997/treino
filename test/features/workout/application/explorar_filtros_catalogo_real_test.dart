// Los filtros de EXPLORAR contra el catálogo REAL de 50 plantillas, el mismo
// JSON que siembra `scripts/seed_templates.js`.
//
// Los tests de `TemplateAffinity` y de los providers usan fixtures de una o
// dos rutinas armadas a mano, y eso prueba la regla, no el catálogo. Lo que
// importa acá es otra pregunta: con lo que de verdad se siembra, ¿la pill de
// nivel muestra lo que dice y la primera tarjeta es la que el atleta pidió?

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/domain/muscle_group.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/unified_templates_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_goal.dart';
import 'package:treino/features/workout/domain/template_preferences.dart';

UserProfile _perfil(TemplatePreferences? prefs) => UserProfile(
      uid: 'athlete-1',
      email: 'a@t.com',
      displayName: 'A',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      templatePreferences: prefs,
    );

/// La grilla tal cual la arma la app: catálogo → pill de nivel → afinidad.
/// Sin coach vinculado ni comunidad, para que lo único en juego sea el
/// catálogo del sistema.
Future<List<Routine>> _grilla(
  List<Routine> catalogo, {
  ExperienceLevel? nivel,
  TemplatePreferences? prefs,
}) async {
  final container = ProviderContainer(overrides: [
    routinesProvider.overrideWith((ref) async => catalogo),
    currentAthleteLinkProvider.overrideWith((ref) => Stream.value(null)),
    communityTemplatesProvider.overrideWith((ref) => const []),
    userProfileProvider.overrideWith((ref) => Stream.value(_perfil(prefs))),
  ]);
  addTearDown(container.dispose);
  container.read(routinesLevelFilterProvider.notifier).state = nivel;
  container.listen(rankedUnifiedTemplatesProvider, (_, __) {});
  await container.read(routinesProvider.future);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return container
          .read(rankedUnifiedTemplatesProvider)
          .valueOrNull
          ?.map((e) => e.routine)
          .toList() ??
      const [];
}

void main() {
  late List<Routine> catalogo;

  setUpAll(() {
    catalogo = (jsonDecode(
      File('docs/video-catalog-audit/improved-templates.json')
          .readAsStringSync(),
    ) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((t) => Routine.fromJson({...t, 'id': t['id']}))
        .toList();
  });

  group('pills de nivel', () {
    test('cada pill muestra exactamente las de su nivel: 15 / 23 / 12',
        () async {
      const esperado = {
        ExperienceLevel.beginner: 15,
        ExperienceLevel.intermediate: 23,
        ExperienceLevel.advanced: 12,
      };
      for (final MapEntry(key: nivel, value: cuantas) in esperado.entries) {
        final grilla = await _grilla(catalogo, nivel: nivel);
        expect(grilla, hasLength(cuantas), reason: nivel.name);
        expect(grilla.every((r) => r.level == nivel), isTrue,
            reason: nivel.name);
      }
      expect(await _grilla(catalogo), hasLength(50),
          reason: 'sin pill elegida se ve el catálogo entero');
    });

    test('principiante gratis, intermedio y avanzado pagas', () async {
      for (final nivel in ExperienceLevel.values) {
        final grilla = await _grilla(catalogo, nivel: nivel);
        final esperado = nivel != ExperienceLevel.beginner;
        for (final r in grilla) {
          expect(r.isPremium, esperado, reason: '${r.id} (${nivel.name})');
        }
      }
    });
  });

  group('orden por el mini-onboarding', () {
    // Los valores que ofrecen las pills del cuestionario
    // (`templates_onboarding_steps.dart`).
    const dias = [2, 3, 4, 5, 6];
    const minutos = [30, 45, 60, 75];

    bool exacta(Routine r, int d, int m, RoutineGoal g) =>
        r.days.length == d &&
        r.estimatedMinutesPerDay == m &&
        r.goals.contains(g);

    test(
        'si existe una plantilla que coincide en días, minutos y objetivo, '
        'es la primera — en las 300 combinaciones', () async {
      var conExacta = 0;
      for (final nivel in ExperienceLevel.values) {
        for (final d in dias) {
          for (final m in minutos) {
            for (final g in RoutineGoal.values) {
              final hay =
                  catalogo.any((r) => r.level == nivel && exacta(r, d, m, g));
              if (!hay) continue;
              conExacta++;
              final grilla = await _grilla(
                catalogo,
                nivel: nivel,
                prefs: TemplatePreferences(
                  daysPerWeek: d,
                  minutesPerSession: m,
                  goal: g,
                ),
              );
              expect(exacta(grilla.first, d, m, g), isTrue,
                  reason: '${nivel.name} · $d días · $m min · ${g.name}: '
                      'salió ${grilla.first.id}');
            }
          }
        }
      }
      // Que el barrido no salga verde por no haber probado nada.
      expect(conExacta, greaterThan(20));
    });

    test('casos de la spec, con nombre y apellido', () async {
      Future<String> primera(
        ExperienceLevel nivel,
        int d,
        int m,
        RoutineGoal g,
      ) async =>
          (await _grilla(
            catalogo,
            nivel: nivel,
            prefs: TemplatePreferences(
              daysPerWeek: d,
              minutesPerSession: m,
              goal: g,
            ),
          ))
              .first
              .id;

      expect(
        await primera(ExperienceLevel.beginner, 2, 30, RoutineGoal.health),
        'full-body-express-2dias',
      );
      expect(
        await primera(
            ExperienceLevel.beginner, 3, 30, RoutineGoal.injuryPrevention),
        'prevencion-lesiones-principiante',
      );
      expect(
        await primera(
            ExperienceLevel.intermediate, 2, 45, RoutineGoal.injuryPrevention),
        'fuerza-corredores-intermedio',
      );
      expect(
        await primera(ExperienceLevel.intermediate, 4, 45, RoutineGoal.sport),
        'ondas-fuerza-5x10-intermedio',
      );
      expect(
        await primera(ExperienceLevel.advanced, 6, 75, RoutineGoal.aesthetics),
        'split-clasico-6dias-avanzado',
      );
    });
  });
  group('zonas', () {
    const piernas = TemplatePreferences(
      priorityMuscleGroups: ['glutes', 'quads'],
    );

    test('40 de las 50 tienen al menos un ejercicio de cuerpo completo', () {
      // El dato que hacía inútil al filtro: con la regla vieja, un solo
      // `fullbody` le daba 1 en zonas a la plantilla, pidiera lo que pidiera
      // el atleta.
      final conGlobal = catalogo.where(
        (r) => r.primaryMuscleGroups.contains(MuscleGroup.cuerpoCompleto),
      );
      expect(conGlobal, hasLength(40));
    });

    test('pedir piernas/glúteos no empata a todo el catálogo', () async {
      final grilla = await _grilla(catalogo, prefs: piernas);
      final primera = grilla.first.id;
      final ultima = grilla.last.id;
      // Con la regla vieja 47 de 50 daban 1 en zonas: el orden quedaba igual
      // al del JSON y la primera era `ppl-beginner`.
      expect(primera, isNot('ppl-beginner'));
      expect(primera, isNot(ultima));
    });

    test('las de glúteos y piernas van antes que las de tren superior',
        () async {
      bool trenSuperior(Routine r) {
        const arriba = {
          MuscleGroup.pecho,
          MuscleGroup.espalda,
          MuscleGroup.hombros,
          MuscleGroup.biceps,
          MuscleGroup.triceps,
        };
        final grupos = [
          for (final d in r.days)
            for (final s in d.slots) MuscleGroup.fromKey(s.muscleGroup),
        ].whereType<MuscleGroup>().toList();
        return grupos.where(arriba.contains).length >= grupos.length * 0.6;
      }

      const deGluteos = {
        ExperienceLevel.beginner: ['gluteos-piernas-principiante'],
        ExperienceLevel.intermediate: [
          'gluteos-foco-intermedio',
          'fuerza-corredores-intermedio',
        ],
      };
      for (final MapEntry(key: nivel, value: ids) in deGluteos.entries) {
        final grilla = await _grilla(catalogo, nivel: nivel, prefs: piernas);
        final orden = grilla.map((r) => r.id).toList();
        final superiores = [
          for (final r in grilla)
            if (trenSuperior(r)) r.id,
        ];
        expect(superiores, isNotEmpty, reason: nivel.name);
        for (final id in ids) {
          expect(orden.indexOf(id), lessThan(3),
              reason: '$id tiene que estar entre las 3 primeras: $orden');
          for (final sup in superiores) {
            expect(orden.indexOf(id), lessThan(orden.indexOf(sup)),
                reason: '$id antes que $sup (${nivel.name})');
          }
        }
      }
    });

    test('pedir pecho y espalda manda las de glúteos al fondo', () async {
      final grilla = await _grilla(
        catalogo,
        nivel: ExperienceLevel.beginner,
        prefs: const TemplatePreferences(
          priorityMuscleGroups: ['chest', 'back'],
        ),
      );
      final orden = grilla.map((r) => r.id).toList();
      expect(orden.indexOf('gluteos-piernas-principiante'),
          greaterThanOrEqualTo(orden.length - 3),
          reason: '$orden');
    });
  });
}
