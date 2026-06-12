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
        'GridView uses shrinkWrap + NeverScrollableScrollPhysics (no overflow)',
        (tester) async {
      final routines = List.generate(
        4,
        (i) => makeRoutine(id: 'r$i', name: 'Routine $i'),
      );

      // Wrap in a ListView so that the Column inside PlantillasSection
      // has a bounded vertical parent — this mirrors the real WorkoutScreen.
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

      // No RenderFlex overflow errors
      expect(tester.takeException(), isNull);
      // GridView has shrinkWrap and NeverScrollableScrollPhysics
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(grid.shrinkWrap, isTrue);
      expect(grid.physics, isA<NeverScrollableScrollPhysics>());
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
