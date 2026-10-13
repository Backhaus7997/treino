// Cuadro de búsqueda de EXPLORAR (#1412): tipear filtra (con debounce),
// borrar restaura, sin resultados muestra el estado vacío, y compone con la
// pill de nivel.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/unified_templates_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/presentation/widgets/plantillas_tab.dart';
import 'package:treino/features/workout/presentation/widgets/routine_card.dart';
import 'package:treino/features/workout/presentation/widgets/templates_search_field.dart';
import 'package:treino/l10n/app_l10n.dart';

Routine _routine(
  String id,
  String name,
  String muscle, {
  ExperienceLevel level = ExperienceLevel.beginner,
}) =>
    Routine(
      id: id,
      name: name,
      level: level,
      days: [
        RoutineDay(
          dayNumber: 1,
          name: 'Día 1',
          slots: [
            RoutineSlot(
              exerciseId: 'e-$id',
              exerciseName: 'Ejercicio $id',
              muscleGroup: muscle,
              targetSets: 3,
              targetRepsMin: 8,
              targetRepsMax: 12,
              restSeconds: 60,
            ),
          ],
        ),
      ],
    );

final _catalogo = [
  _routine('a', 'Alfa Total', 'chest'),
  _routine('b', 'Beta Total', 'quads'),
  _routine('c', 'Gamma Total', 'glutes', level: ExperienceLevel.advanced),
];

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      currentAthleteLinkProvider.overrideWith((ref) => Stream.value(null)),
      routinesProvider.overrideWith((ref) async => _catalogo),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(
          body: SizedBox(height: 1200, child: PlantillasTab()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return container;
}

Finder _card(String name) =>
    find.descendant(of: find.byType(RoutineCard), matching: find.text(name));

void main() {
  testWidgets('muestra el cuadro de búsqueda y todas las plantillas',
      (tester) async {
    await _pump(tester);

    expect(find.byType(TemplatesSearchField), findsOneWidget);
    expect(find.text('Buscar por nombre, músculo o ejercicio'), findsOneWidget);
    expect(find.byType(RoutineCard), findsNWidgets(3));
  });

  testWidgets('tipear filtra después del debounce, por músculo (sinónimo)',
      (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'Pecho');
    // Antes del debounce no filtró todavía.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RoutineCard), findsNWidgets(3));

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(_card('ALFA TOTAL'), findsOneWidget);
    expect(_card('BETA TOTAL'), findsNothing);
    expect(_card('GAMMA TOTAL'), findsNothing);
  });

  testWidgets('borrar restaura la grilla completa', (tester) async {
    final container = await _pump(tester);

    await tester.enterText(find.byType(TextField), 'piernas');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(RoutineCard), findsNWidgets(2));

    await tester.tap(find.byTooltip('Borrar búsqueda'));
    await tester.pump();

    expect(container.read(templatesSearchQueryProvider), '');
    expect(find.byType(RoutineCard), findsNWidgets(3));
    expect(find.byTooltip('Borrar búsqueda'), findsNothing);
  });

  testWidgets('sin resultados muestra el estado vacío con la consulta',
      (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'zzzxqw');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.byType(RoutineCard), findsNothing);
    expect(
        find.text('No encontramos plantillas para «zzzxqw»'), findsOneWidget);
  });

  testWidgets('la búsqueda filtra dentro de la pill de nivel elegida',
      (tester) async {
    final container = await _pump(tester);
    container.read(routinesLevelFilterProvider.notifier).state =
        ExperienceLevel.advanced;
    await tester.pump();

    // "piernas" matchea Beta (quads) y Gamma (glutes); sólo Gamma es avanzada.
    await tester.enterText(find.byType(TextField), 'piernas');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(_card('GAMMA TOTAL'), findsOneWidget);
    expect(_card('BETA TOTAL'), findsNothing);
  });
}
