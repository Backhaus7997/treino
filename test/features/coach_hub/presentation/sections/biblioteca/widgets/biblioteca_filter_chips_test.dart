// Widget tests for BibliotecaFilterChips — adapter typed↔String sobre
// TreinoFilterChips (kit — animación de selección/filtro, misión especial
// Fase 7).
// REQ-BIBW-06, SCENARIO-BIBW-06a, SCENARIO-BIBW-06b, SCENARIO-BIBW-06c,
// SCENARIO-BIBW-06d.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/providers/biblioteca_providers.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/widgets/biblioteca_filter_chips.dart';
import 'package:treino/features/coach_hub/presentation/widgets/filter_chips/filter_chips.dart';
import 'package:treino/features/workout/domain/equipment_type.dart';
import 'package:treino/features/workout/domain/muscle_group.dart';

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: BibliotecaFilterChips()),
      ),
    );

void main() {
  group('BibliotecaFilterChips — render', () {
    testWidgets(
      'renderiza chips de músculo y equipamiento incluyendo TODOS',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        expect(find.text('MÚSCULO'), findsOneWidget);
        expect(find.text('EQUIPAMIENTO'), findsOneWidget);
        // TODOS aparece una vez por dimensión (2 filas).
        expect(find.text('TODOS'), findsNWidgets(2));
        expect(find.text('PECHO'), findsOneWidget);
        expect(find.text('MANCUERNA'), findsOneWidget);
      },
    );

    testWidgets(
      'usa TreinoFilterChips del kit — sin GestureDetector bespoke',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(BibliotecaFilterChips),
            matching: find.byType(TreinoFilterChips),
          ),
          findsNWidgets(2),
        );
      },
    );
  });

  group('BibliotecaFilterChips — selección músculo', () {
    testWidgets(
      'tap en PECHO escribe {MuscleGroup.pecho} y deselecciona TODOS',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        await tester.tap(find.text('PECHO'));
        await tester.pump();

        expect(
          container.read(bibliotecaMuscleFilterProvider),
          {MuscleGroup.pecho},
        );
      },
    );

    testWidgets(
      'tap en TODOS con un músculo activo limpia el set',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            bibliotecaMuscleFilterProvider.overrideWith(
              (ref) => {MuscleGroup.pecho},
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        // TODOS aparece en ambas filas — tomamos el primero (MÚSCULO).
        await tester.tap(find.text('TODOS').first);
        await tester.pump();

        expect(container.read(bibliotecaMuscleFilterProvider), isEmpty);
      },
    );

    testWidgets(
      'tap en un chip ya activo lo remueve',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            bibliotecaMuscleFilterProvider.overrideWith(
              (ref) => {MuscleGroup.pecho, MuscleGroup.espalda},
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        await tester.tap(find.text('PECHO'));
        await tester.pump();

        expect(
          container.read(bibliotecaMuscleFilterProvider),
          {MuscleGroup.espalda},
        );
      },
    );
  });

  group('BibliotecaFilterChips — selección equipamiento', () {
    testWidgets(
      'tap en MANCUERNA escribe {EquipmentType.mancuerna} y deselecciona '
      'TODOS',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        await tester.tap(find.text('MANCUERNA'));
        await tester.pump();

        expect(
          container.read(bibliotecaEquipmentFilterProvider),
          {EquipmentType.mancuerna},
        );
      },
    );

    testWidgets(
      'tap en TODOS con un equipamiento activo limpia el set',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            bibliotecaEquipmentFilterProvider.overrideWith(
              (ref) => {EquipmentType.mancuerna},
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        // TODOS aparece en ambas filas — la segunda es EQUIPAMIENTO.
        await tester.tap(find.text('TODOS').last);
        await tester.pump();

        expect(container.read(bibliotecaEquipmentFilterProvider), isEmpty);
      },
    );
  });
}
