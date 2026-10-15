import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/set_enums.dart';

import 'periodized_draft_fixtures.dart';

List<MatcherExercise> _catalog() => [
      for (final l in ['A', 'B', 'C', 'D', 'E'])
        MatcherExercise(id: 'ex-$l', name: 'Ejercicio $l', muscleGroup: 'legs'),
    ];

Color _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.color!;

AppPalette _palette(WidgetTester tester) =>
    AppPalette.of(tester.element(find.byType(CoachHubPlanPreviewScreen)));

Future<void> _selectAnaAndAssign(WidgetTester tester) async {
  await tester.tap(find.text('Ana'));
  await tester.pump();
  await tester.tap(find.text('ASIGNAR PLAN'));
  await tester.pumpAndSettle();
}

void main() {
  useTallSurface();

  setUpAll(() => registerFallbackValue(
        const Routine(
            id: '', name: '', level: ExperienceLevel.beginner, days: []),
      ));

  group('selector de semana', () {
    testWidgets('muestra SEMANA 1..N y cambia lo que dibujan las tarjetas',
        (tester) async {
      final draft = draftOf(
        [
          [1, 'Ejercicio A', 60, '3x8', '3x9', '3x10', '3x12'],
        ],
        catalog: _catalog(),
      );
      await pumpPreview(tester, draft, MockRoutineRepo());

      for (var w = 1; w <= 4; w++) {
        expect(find.text('SEMANA $w'), findsOneWidget);
      }
      expect(find.text('3 × 8'), findsOneWidget);
      expect(find.text('3 × 9'), findsNothing);

      await tester.tap(find.text('SEMANA 2'));
      await tester.pumpAndSettle();
      expect(find.text('3 × 9'), findsOneWidget);
      expect(find.text('3 × 8'), findsNothing);

      await tester.tap(find.text('SEMANA 4'));
      await tester.pumpAndSettle();
      expect(find.text('3 × 12'), findsOneWidget);

      // Tocar la semana elegida no la deselecciona: siempre hay una.
      await tester.tap(find.text('SEMANA 4'));
      await tester.pumpAndSettle();
      expect(find.text('3 × 12'), findsOneWidget);
    });
  });

  group('celda de semana vacía', () {
    testWidgets(
        'el ejercicio sale en rojo con "falta cargar reps" SÓLO esa semana '
        'y el aviso lista su celda', (tester) async {
      final draft = draftOf(
        [
          [1, 'Ejercicio A', 60, '3x8', null, '3x10', '3x12'],
        ],
        catalog: _catalog(),
      );
      await pumpPreview(tester, draft, MockRoutineRepo());
      final palette = _palette(tester);

      // Semana 1: completa, nombre normal.
      expect(find.text('falta cargar reps'), findsNothing);
      expect(_colorOf(tester, 'Ejercicio A'), palette.textPrimary);

      // Semana 2: la celda venía vacía.
      await tester.tap(find.text('SEMANA 2'));
      await tester.pumpAndSettle();
      expect(find.text('falta cargar reps'), findsOneWidget);
      expect(_colorOf(tester, 'Ejercicio A'), palette.danger);

      // El aviso del parser apunta a la celda exacta (SEMANA 2 = columna E,
      // primer renglón de datos = fila 2).
      expect(find.textContaining('Programa!E2'), findsOneWidget);

      // Y vuelve a la normalidad en la semana siguiente.
      await tester.tap(find.text('SEMANA 3'));
      await tester.pumpAndSettle();
      expect(find.text('falta cargar reps'), findsNothing);
      expect(_colorOf(tester, 'Ejercicio A'), palette.textPrimary);
    });
  });

  group('superseries y chips', () {
    testWidgets('los componentes de una superserie van en UN bloque',
        (tester) async {
      final draft = draftOf(
        [
          [1, 'Ejercicio A + Ejercicio B', 90, ...sameWeeks('3x4+2')],
          [2, 'Ejercicio C', 60, ...sameWeeks('3x8')],
        ],
        catalog: _catalog(),
      );
      await pumpPreview(tester, draft, MockRoutineRepo());

      expect(find.text('SUPERSERIE'), findsOneWidget);
      final block = find.byKey(const ValueKey('superset-1-2'));
      expect(block, findsOneWidget);
      expect(find.descendant(of: block, matching: find.text('Ejercicio A')),
          findsOneWidget);
      expect(find.descendant(of: block, matching: find.text('Ejercicio B')),
          findsOneWidget);
      // El ejercicio suelto queda afuera del bloque.
      expect(find.descendant(of: block, matching: find.text('Ejercicio C')),
          findsNothing);
      // El descanso es de la superserie entera: un solo chip.
      expect(find.text('Descanso 90 s'), findsOneWidget);
      expect(find.text('3 × 4'), findsOneWidget);
      expect(find.text('3 × 2'), findsOneWidget);
    });

    testWidgets('chips de calentamiento, al fallo, duración, distancia y nota',
        (tester) async {
      final draft = draftOf(
        [
          [null, 'Ejercicio A', null, ...sameWeeks('2x10')],
          [1, 'Ejercicio B', 60, ...sameWeeks('3xmax')],
          [2, 'Ejercicio C', 60, ...sameWeeks("8'")],
          [3, 'Ejercicio D', 60, ...sameWeeks('4x20m')],
          [4, 'Ejercicio E', 60, ...sameWeeks('3x10 c/pierna')],
        ],
        catalog: _catalog(),
      );
      await pumpPreview(tester, draft, MockRoutineRepo());

      expect(find.text('CALENTAMIENTO'), findsOneWidget);
      expect(find.text('AL FALLO'), findsOneWidget);
      expect(find.text('8 min'), findsOneWidget);
      expect(find.text('20 m'), findsOneWidget);
      expect(find.text('c/pierna'), findsOneWidget);
    });
  });

  group('qué bloquea la asignación', () {
    testWidgets('un componente sin match bloquea y no escribe', (tester) async {
      final repo = MockRoutineRepo();
      final draft = draftOf(
        [
          [1, 'Ejercicio A', 60, ...sameWeeks('3x8')],
          [2, 'Ejercicio Z', 60, ...sameWeeks('3x8')],
        ],
        catalog: _catalog(),
      );
      await pumpPreview(tester, draft, repo);

      expect(find.text('sin match'), findsOneWidget);
      expect(find.text('Asignar manualmente'), findsOneWidget);

      await _selectAnaAndAssign(tester);
      expect(
        find.text('Hay ejercicios sin match. Asignalos manualmente antes de '
            'continuar.'),
        findsOneWidget,
      );
      verifyNever(() => repo.createAssigned(any()));
    });

    testWidgets(
        'una sugerencia pendiente de UN componente de una superserie '
        'bloquea', (tester) async {
      final repo = MockRoutineRepo();
      final draft = draftOf(
        [
          [1, 'Ejercicio A + Ejercicio Q', 60, ...sameWeeks('3x8+10')],
        ],
        catalog: _catalog(),
        suggestions: {
          'Ejercicio Q': MatcherExercise(id: 'ex-q', name: 'Ejercicio Quasi'),
        },
      );
      await pumpPreview(tester, draft, repo);

      expect(find.text('sugerencia pendiente'), findsOneWidget);
      expect(find.text('Sugerencia: Ejercicio Quasi'), findsOneWidget);
      expect(find.text('Confirmar'), findsOneWidget);
      expect(find.text('Cambiar'), findsOneWidget);

      await _selectAnaAndAssign(tester);
      expect(
        find.text('Hay sugerencias pendientes. Confirmalas o cambialas antes '
            'de continuar.'),
        findsOneWidget,
      );
      verifyNever(() => repo.createAssigned(any()));

      // Confirmar la resuelve y desbloquea.
      when(() => repo.createAssigned(any())).thenAnswer((inv) async =>
          (inv.positionalArguments.first as Routine).copyWith(id: 'r-1'));
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ASIGNAR PLAN'));
      await tester.pumpAndSettle();
      verify(() => repo.createAssigned(any())).called(1);
    });

    testWidgets('las celdas de semana vacías son SÓLO un aviso: no bloquean',
        (tester) async {
      final repo = MockRoutineRepo();
      Routine? captured;
      when(() => repo.createAssigned(any())).thenAnswer((inv) async {
        captured = inv.positionalArguments.first as Routine;
        return captured!.copyWith(id: 'r-1');
      });
      final draft = draftOf(
        [
          [1, 'Ejercicio A', 60, '3x8', null, null, '3x12'],
        ],
        catalog: _catalog(),
      );
      await pumpPreview(tester, draft, repo);
      expect(draft.warnings, hasLength(2));

      await _selectAnaAndAssign(tester);

      verify(() => repo.createAssigned(any())).called(1);
      expect(find.text('DASHBOARD'), findsOneWidget);
      // El ejercicio va igual, sin reps, esas semanas.
      final slot = captured!.days.single.slots.single;
      expect(slot.weeklySets[1].single.reps, isNull);
      expect(slot.weeklySets[2].single.reps, isNull);
      expect(slot.weeklySets[1].single.type, SetType.normal);
      expect(slot.weeklySets[3], hasLength(3));
    });
  });
}
