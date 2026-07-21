import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/presentation/widgets/level_filter_pills.dart';
import 'package:treino/features/workout/presentation/widgets/plantillas_section.dart';
import 'package:treino/features/workout/presentation/widgets/routine_card.dart';
import 'package:treino/features/workout/presentation/widgets/ver_mas_cell.dart';
import 'package:treino/l10n/app_l10n.dart';

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

Widget _wrap(
  Widget w, {
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: overrides,
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
  group('PlantillasSection', () {
    testWidgets('header text "PLANTILLAS" rendered in titleMedium style',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlantillasSection(),
          overrides: [
            routinesProvider.overrideWith((ref) async => []),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('PLANTILLAS'), findsOneWidget);
    });

    testWidgets('AsyncLoading → CircularProgressIndicator present, no card',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlantillasSection(),
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

    testWidgets('AsyncData([]) + filter null → "No hay plantillas todavía."',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlantillasSection(),
          overrides: [
            routinesProvider.overrideWith((ref) async => []),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('No hay plantillas todavía.'), findsOneWidget);
    });

    testWidgets(
        'AsyncData([]) + filter beginner → "No hay plantillas para este nivel."',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
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
            home: const Scaffold(
              body: SizedBox(
                height: 800,
                child: PlantillasSection(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('No hay plantillas para este nivel.'),
        findsOneWidget,
      );
    });

    testWidgets('AsyncError → error message + Reintentar button',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlantillasSection(),
          overrides: [
            routinesProvider.overrideWith(
              (ref) async => throw Exception('network'),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('Hubo un error cargando las plantillas.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('tapping Reintentar calls ref.invalidate(routinesProvider)',
        (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
        _wrap(
          const PlantillasSection(),
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

      final callsBefore = callCount;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // After invalidate, routinesProvider re-runs → callCount increases
      expect(callCount, greaterThan(callsBefore));
    });

    testWidgets('AsyncData([r1, r2]) → GridView with 2 RoutineCard instances',
        (tester) async {
      final routines = [
        makeRoutine(id: 'r1', name: 'Routine 1'),
        makeRoutine(id: 'r2', name: 'Routine 2'),
      ];

      // Wrap in SingleChildScrollView — grid now renders N cards + a
      // VerMasCell, so the section can exceed 800px and needs a scrollable
      // parent (mirrors WorkoutScreen's outer ListView).
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routinesProvider.overrideWith((ref) async => routines),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: SizedBox(
                height: 800,
                child: SingleChildScrollView(
                  child: PlantillasSection(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(RoutineCard), findsNWidgets(2));
    });

    testWidgets(
        'catálogo en filas tamaño-contenido (sin GridView anidado ni overflow)',
        (tester) async {
      final routines = List.generate(
        4,
        (i) => makeRoutine(id: 'r$i', name: 'Routine $i'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routinesProvider.overrideWith((ref) async => routines),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: SizedBox(
                height: 800,
                child: SingleChildScrollView(
                  child: PlantillasSection(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Sin RenderFlex overflow.
      expect(tester.takeException(), isNull);
      // El GridView anidado (reservaba alto fantasma que empujaba HISTORIAL)
      // fue reemplazado por filas de a dos tamaño-contenido.
      expect(find.byType(GridView), findsNothing);
      // 4 rutinas → 3 cards visibles (cap colapsado) + celda "Ver más".
      expect(find.byType(RoutineCard), findsNWidgets(3));
    });

    testWidgets(
        'expandida bajo el ListView real: sin IntrinsicHeight y altura de card '
        'uniforme (#402)', (tester) async {
      // Nombres mixtos: los primeros 3 caben en 1 línea, el resto fuerza 2.
      // La altura uniforme sólo se sostiene si la card reserva siempre las
      // dos líneas del título (sin eso, la fila de dos títulos cortos sale
      // más baja y este test falla).
      final routines = [
        for (var i = 0; i < 8; i++)
          makeRoutine(
            id: 'r$i',
            name: i < 3
                ? 'Push $i'
                : 'Rutina de hipertrofia avanzada del tren superior $i',
          ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routinesProvider.overrideWith((ref) async => routines),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              // Mismo host que _TuEntrenoPage (workout_screen.dart): la
              // sección vive como UN child del ListView lazy dueño del
              // scroll — el escenario real donde se manifestaba el jank.
              body: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [PlantillasSection()],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Colapsada: cap de 3 cards + celda Ver más.
      expect(find.byType(RoutineCard), findsNWidgets(3));
      expect(find.byType(VerMasCell), findsOneWidget);

      await tester.tap(find.byType(VerMasCell));
      await tester.pump();

      // Expandida: catálogo completo, sin celda Ver más.
      expect(find.byType(VerMasCell), findsNothing);
      final cards = find.byType(RoutineCard, skipOffstage: false);
      expect(cards, findsNWidgets(8));

      // Lock del fix #402: ninguna fila expandida pasa por IntrinsicHeight
      // (el doble pase de layout por fila era la causa del jank).
      expect(
        find.descendant(
          of: find.byType(PlantillasSection),
          matching: find.byType(IntrinsicHeight, skipOffstage: false),
        ),
        findsNothing,
      );

      // Altura determinística: con títulos de 1 y 2 líneas mezclados, todas
      // las cards miden lo mismo.
      final firstHeight = tester.getSize(cards.at(0)).height;
      for (var i = 1; i < 8; i++) {
        expect(
          tester.getSize(cards.at(i)).height,
          moreOrLessEquals(firstHeight, epsilon: 0.01),
        );
      }

      // Scroll de ida y vuelta sobre la lista expandida (re-entrada de filas
      // al viewport, el caso que jankeaba) — sin overflow ni errores.
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'colapsada: la celda Ver más iguala la altura de su card vecina',
        (tester) async {
      final routines = [
        for (var i = 0; i < 5; i++) makeRoutine(id: 'r$i', name: 'Push $i'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routinesProvider.overrideWith((ref) async => routines),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [PlantillasSection()],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // La celda Ver más comparte fila con la 3ra card y rellena su altura
      // (TableCellVerticalAlignment.fill) — el look del viejo Row(stretch).
      final cardHeight = tester.getSize(find.byType(RoutineCard).at(2)).height;
      final verMasHeight = tester.getSize(find.byType(VerMasCell)).height;
      expect(verMasHeight, moreOrLessEquals(cardHeight, epsilon: 0.01));
    });

    testWidgets('LevelFilterPills widget is present', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlantillasSection(),
          overrides: [
            routinesProvider.overrideWith((ref) async => []),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(LevelFilterPills), findsOneWidget);
    });
  });
}
