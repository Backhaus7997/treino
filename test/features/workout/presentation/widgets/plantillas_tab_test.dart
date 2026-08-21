import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/presentation/widgets/level_filter_pills.dart';
import 'package:treino/features/workout/presentation/widgets/plantillas_tab.dart';
import 'package:treino/features/workout/presentation/widgets/routine_card.dart';
import 'package:treino/l10n/app_l10n.dart';

// ─── Fixtures ─────────────────────────────────────────────────────────────────

Routine makeRoutine({
  String id = 'test-id',
  String name = 'Routine',
  ExperienceLevel level = ExperienceLevel.beginner,
}) =>
    Routine(
      id: id,
      name: name,
      split: 'Full Body',
      level: level,
      days: const [],
    );

TrainerLink makeLink({String trainerId = 'trainer-1'}) => TrainerLink(
      id: 'link-1',
      trainerId: trainerId,
      athleteId: 'athlete-1',
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
    );

/// Overrides that resolve the rest of the coach chain (profile opt-in +
/// shared [templates]) — pair with `_wrap(link: makeLink())`.
List<Override> coachOverrides(List<Routine> templates) => [
      userPublicProfileProvider('trainer-1').overrideWith(
        (ref) => Stream.value(
          const UserPublicProfile(
            uid: 'trainer-1',
            displayName: 'Coach Vic',
            displayNameLowercase: 'coach vic',
            sharedTemplatesWithAthletes: true,
          ),
        ),
      ),
      trainerTemplatesStreamProvider('trainer-1').overrideWith(
        (ref) => Stream.value(templates),
      ),
    ];

Widget _wrap(
  Widget w, {
  List<Override> overrides = const [],
  // Default: athlete without linked coach — the grid is catalog-only. The
  // link lives HERE (not in per-test override lists) so the provider is
  // never overridden twice in one scope.
  TrainerLink? link,
}) =>
    ProviderScope(
      overrides: [
        currentAthleteLinkProvider.overrideWith((ref) async => link),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: SizedBox(
            height: 800,
            child: w,
          ),
        ),
      ),
    );

void main() {
  group('PlantillasTab — estados', () {
    testWidgets('AsyncLoading → CircularProgressIndicator present, no card',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          overrides: [
            routinesProvider.overrideWith(
              (ref) => Completer<List<Routine>>().future,
            ),
          ],
        ),
      );
      // Single pump — stays in loading state
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(RoutineCard), findsNothing);
    });

    testWidgets('AsyncData([]) + filter null → "No hay rutinas todavía."',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          overrides: [
            routinesProvider.overrideWith((ref) async => []),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('No hay rutinas todavía.'), findsOneWidget);
    });

    testWidgets(
        'AsyncData([]) + filter beginner → "No hay rutinas para este nivel."',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentAthleteLinkProvider.overrideWith((ref) async => null),
          routinesProvider.overrideWith((ref) async => []),
        ],
      );
      addTearDown(container.dispose);
      container.read(routinesLevelFilterProvider.notifier).state =
          ExperienceLevel.beginner;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            home: const Scaffold(
              body: SizedBox(
                height: 800,
                child: PlantillasTab(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('No hay rutinas para este nivel.'),
        findsOneWidget,
      );
    });

    testWidgets('AsyncError → error message + Reintentar re-fetches catalog',
        (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          overrides: [
            routinesProvider.overrideWith((ref) async {
              callCount++;
              throw Exception('network');
            }),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('Hubo un error cargando las rutinas.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);

      final callsBefore = callCount;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(callCount, greaterThan(callsBefore));
    });

    testWidgets('LevelFilterPills widget is present', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          overrides: [
            routinesProvider.overrideWith((ref) async => []),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(LevelFilterPills), findsOneWidget);
    });
  });

  group('PlantillasTab — grid unificado', () {
    testWidgets('catálogo completo en filas de a dos — sin "Ver más" ni cap',
        (tester) async {
      final routines = List.generate(
        8,
        (i) => makeRoutine(id: 'r$i', name: 'Routine $i'),
      );

      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          overrides: [
            routinesProvider.overrideWith((ref) async => routines),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // La tab dedicada muestra TODO el catálogo — el colapso "Ver más" de la
      // vieja sección desapareció junto con ella.
      final cards = find.byType(RoutineCard, skipOffstage: false);
      expect(cards, findsNWidgets(8));
      expect(find.text('Ver más'), findsNothing);
      expect(find.byType(GridView), findsNothing);
    });

    testWidgets(
        'coach + catálogo: las del coach van PRIMERO con badge DE TU COACH; '
        'las del catálogo sin badge', (tester) async {
      final catalog = [
        makeRoutine(id: 'sys-1', name: 'Sistema 1'),
        makeRoutine(id: 'sys-2', name: 'Sistema 2'),
      ];
      final coach = [makeRoutine(id: 'coach-1', name: 'Del Coach')];

      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          overrides: [
            routinesProvider.overrideWith((ref) async => catalog),
            ...coachOverrides(coach),
          ],
          link: makeLink(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // La cadena del coach resuelve en etapas async encadenadas (link →
      // perfil → stream de templates): pumps extra para asentarla.
      await tester.pump();
      await tester.pump();

      final cards = find.byType(RoutineCard, skipOffstage: false);
      expect(cards, findsNWidgets(3));

      // Badge SOLO en la del coach — misma key/clave l10n que el chip de la
      // lista RUTINAS (slice 1).
      expect(
        find.byKey(const Key('routine_coach_chip_coach-1'),
            skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('DE TU COACH', skipOffstage: false), findsOneWidget);

      // Pinned primero: la card del coach aparece arriba de las del sistema.
      final coachDy = tester
          .getTopLeft(
            find.text('DEL COACH', skipOffstage: false),
          )
          .dy;
      final sys1Dy = tester
          .getTopLeft(
            find.text('SISTEMA 1', skipOffstage: false),
          )
          .dy;
      expect(coachDy, lessThanOrEqualTo(sys1Dy));
    });

    testWidgets('los filtros de nivel aplican al grid COMPLETO (coach incl.)',
        (tester) async {
      final catalog = [
        makeRoutine(
          id: 'sys-1',
          name: 'Sistema Beg',
        ),
        makeRoutine(
          id: 'sys-2',
          name: 'Sistema Adv',
          level: ExperienceLevel.advanced,
        ),
      ];
      final coach = [
        makeRoutine(id: 'coach-1', name: 'Coach Beg'),
      ];

      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          overrides: [
            routinesProvider.overrideWith((ref) async => catalog),
            ...coachOverrides(coach),
          ],
          link: makeLink(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Cadena del coach: etapas async encadenadas — pumps extra.
      await tester.pump();
      await tester.pump();
      expect(find.byType(RoutineCard, skipOffstage: false), findsNWidgets(3));

      // Filtrar por Avanzado — la del coach (beginner) también sale del grid.
      // Scoped to the filter pills on purpose: since #639 the card caption
      // leads with the routine's level, so a bare find.text('Avanzado')
      // matches the card too and the tap goes ambiguous.
      await tester.tap(
        find.descendant(
          of: find.byType(LevelFilterPills),
          matching: find.text('Avanzado'),
        ),
      );
      await tester.pump();
      expect(find.byType(RoutineCard, skipOffstage: false), findsNWidgets(1));
      expect(find.text('SISTEMA ADV', skipOffstage: false), findsOneWidget);
      expect(
        find.byKey(const Key('routine_coach_chip_coach-1'),
            skipOffstage: false),
        findsNothing,
      );

      // Volver a Todas — grid completo de nuevo.
      await tester.tap(find.text('Todas'));
      await tester.pump();
      expect(find.byType(RoutineCard, skipOffstage: false), findsNWidgets(3));
    });

    testWidgets(
        'lock #402: sin IntrinsicHeight y altura de card uniforme, badge '
        'incluido', (tester) async {
      // Nombres mixtos (1 y 2 líneas) + una card con badge del coach: todas
      // tienen que medir lo mismo igual.
      final catalog = [
        for (var i = 0; i < 5; i++)
          makeRoutine(
            id: 'r$i',
            name: i < 2
                ? 'Push $i'
                : 'Rutina de hipertrofia avanzada del tren superior $i',
          ),
      ];
      final coach = [makeRoutine(id: 'coach-1', name: 'Push Coach')];

      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          overrides: [
            routinesProvider.overrideWith((ref) async => catalog),
            ...coachOverrides(coach),
          ],
          link: makeLink(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Cadena del coach: etapas async encadenadas — pumps extra.
      await tester.pump();
      await tester.pump();

      final cards = find.byType(RoutineCard, skipOffstage: false);
      expect(cards, findsNWidgets(6));

      expect(
        find.descendant(
          of: find.byType(PlantillasTab),
          matching: find.byType(IntrinsicHeight, skipOffstage: false),
        ),
        findsNothing,
      );

      final firstHeight = tester.getSize(cards.at(0)).height;
      for (var i = 1; i < 6; i++) {
        expect(
          tester.getSize(cards.at(i)).height,
          moreOrLessEquals(firstHeight, epsilon: 0.01),
        );
      }

      // Scroll de ida y vuelta — sin overflow ni errores. `.first` porque el
      // grid interno también scrollea: el de afuera es el de PlantillasTab.
      final scroller = find
          .descendant(
            of: find.byType(PlantillasTab),
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      await tester.drag(scroller, const Offset(0, -600));
      await tester.pump();
      await tester.drag(scroller, const Offset(0, 600));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'error del catálogo NO tapa las plantillas del coach ya cargadas: '
        'grid del coach + mensaje de error conviven', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          overrides: [
            routinesProvider.overrideWith(
              (ref) async => throw Exception('network'),
            ),
            ...coachOverrides([makeRoutine(id: 'coach-1', name: 'Del Coach')]),
          ],
          link: makeLink(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Cadena del coach: etapas async encadenadas — pumps extra.
      await tester.pump();
      await tester.pump();

      // La independencia que tenían las secciones viejas: el error del
      // catálogo no borra lo que el coach ya resolvió.
      expect(find.byType(RoutineCard, skipOffstage: false), findsOneWidget);
      expect(
        find.byKey(
          const Key('routine_coach_chip_coach-1'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.text('Hubo un error cargando las rutinas.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets(
        'text-scale 3x: cards de plantillas usan una columna sin achicar texto',
        (tester) async {
      final catalog = [
        makeRoutine(id: 'sys-1', name: 'Sistema 1'),
        makeRoutine(id: 'sys-2', name: 'Sistema 2'),
      ];
      final coach = [makeRoutine(id: 'coach-1', name: 'Del Coach')];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAthleteLinkProvider.overrideWith((ref) async => makeLink()),
            routinesProvider.overrideWith((ref) async => catalog),
            ...coachOverrides(coach),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(3.0),
              ),
              child: child!,
            ),
            home: const Scaffold(
              body: SizedBox(
                height: 800,
                child: PlantillasTab(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      await tester.pump();

      final cards = find.byType(RoutineCard, skipOffstage: false);
      expect(cards, findsNWidgets(3));

      final firstLeft = tester.getTopLeft(cards.at(0)).dx;
      for (var i = 1; i < 3; i++) {
        expect(
          tester.getTopLeft(cards.at(i)).dx,
          moreOrLessEquals(firstLeft, epsilon: 0.01),
        );
        expect(
          tester.getTopLeft(cards.at(i)).dy,
          greaterThan(tester.getTopLeft(cards.at(i - 1)).dy),
        );
      }
      expect(find.byType(FittedBox), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('gating: link activo pero trainer sin opt-in → sin badge',
        (tester) async {
      final catalog = [makeRoutine(id: 'sys-1', name: 'Sistema 1')];

      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          overrides: [
            routinesProvider.overrideWith((ref) async => catalog),
            userPublicProfileProvider('trainer-1').overrideWith(
              (ref) => Stream.value(
                const UserPublicProfile(
                  uid: 'trainer-1',
                  displayName: 'Coach Vic',
                  displayNameLowercase: 'coach vic',
                  sharedTemplatesWithAthletes: false,
                ),
              ),
            ),
            trainerTemplatesStreamProvider('trainer-1').overrideWith(
              (ref) => Stream.value([makeRoutine(id: 'coach-1')]),
            ),
          ],
          link: makeLink(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(RoutineCard, skipOffstage: false), findsOneWidget);
      expect(find.text('DE TU COACH', skipOffstage: false), findsNothing);
    });
  });
}
