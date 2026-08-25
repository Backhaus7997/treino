// Widget tests for TemplateGridCard — hover/press via TreinoInteractiveState.
// REQ-BIBW-09, SCENARIO-BIBW-09a, SCENARIO-BIBW-09b.
// WU-08 (Fase 7 Biblioteca): TreinoInteractiveState + tokens (radii/spacing/fonts).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/widgets/template_grid_card.dart';
import 'package:treino/features/coach_hub/presentation/widgets/treino_interactive_state.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_source.dart';

Routine _makeRoutine({int days = 3, int weeks = 8}) {
  return Routine(
    id: 'tpl-a',
    name: 'Fuerza Total',
    level: ExperienceLevel.intermediate,
    days: List.generate(
      days,
      (i) =>
          RoutineDay(dayNumber: i + 1, name: 'Día ${i + 1}', slots: const []),
    ),
    numWeeks: weeks,
    source: RoutineSource.trainerTemplate,
  );
}

final _routine = _makeRoutine();

Widget _wrap(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Scaffold(body: SizedBox(width: 240, height: 220, child: child)),
    );

void main() {
  group('TemplateGridCard —', () {
    testWidgets(
        'usa TreinoInteractiveState como resolver de interacción '
        '(sin GestureDetector crudo propio)', (tester) async {
      await tester.pumpWidget(_wrap(
        TemplateGridCard(routine: _routine, onTap: () {}),
      ));
      await tester.pump();

      expect(find.byType(TreinoInteractiveState), findsOneWidget);
      // MouseRegion viene del resolver — confirma soporte de hover real.
      expect(
        find.descendant(
          of: find.byType(TreinoInteractiveState),
          matching: find.byType(MouseRegion),
        ),
        findsWidgets,
      );
    });

    testWidgets('preserva nombre, cadencia y nivel', (tester) async {
      await tester.pumpWidget(_wrap(
        TemplateGridCard(routine: _routine, onTap: () {}),
      ));
      await tester.pump();

      expect(find.text('Fuerza Total'), findsOneWidget);
      expect(find.textContaining('3 días/sem'), findsOneWidget);
      expect(find.textContaining('8 semanas'), findsOneWidget);
      expect(find.textContaining('INTERMEDIO'), findsOneWidget);
    });

    testWidgets(
        'no muestra conteo de "alumnos" — honestidad de datos (REQ-BIBW-09)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TemplateGridCard(routine: _routine, onTap: () {}),
      ));
      await tester.pump();

      expect(find.textContaining('alumnos'), findsNothing);
      expect(find.textContaining('alumno'), findsNothing);
    });

    testWidgets('tap invoca onTap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(
        TemplateGridCard(routine: _routine, onTap: () => tapped++),
      ));
      await tester.pump();

      await tester.tap(find.byKey(const Key('template_grid_card_root')));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets(
        'hover → decoration del root cambia realmente (token real, no smoke)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TemplateGridCard(routine: _routine, onTap: () {}),
      ));
      await tester.pump();

      Color decorationColor() {
        final container = tester.widget<AnimatedContainer>(
          find.byKey(const Key('template_grid_card_root')),
        );
        return (container.decoration! as BoxDecoration).color!;
      }

      final normalColor = decorationColor();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        tester.getCenter(find.byKey(const Key('template_grid_card_root'))),
      );
      await tester.pump();

      final hoverColor = decorationColor();
      expect(hoverColor, isNot(equals(normalColor)),
          reason: 'el color de fondo debe cambiar realmente en hover');
    });

    testWidgets('smoke: mover el puntero sobre la card no crashea',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TemplateGridCard(routine: _routine, onTap: () {}),
      ));
      await tester.pump();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        tester.getCenter(find.byKey(const Key('template_grid_card_root'))),
      );
      await tester.pumpAndSettle();
      await gesture.moveTo(Offset.zero);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('smoke dark+light sin crash', (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await tester.pumpWidget(_wrap(
          TemplateGridCard(routine: _routine, onTap: () {}),
          theme: theme,
        ));
        await tester.pump();
        expect(find.text('Fuerza Total'), findsOneWidget);
      }
    });
  });
}
