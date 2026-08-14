// Widget tests for ExerciseGridCard — hover/press via TreinoInteractiveState.
// REQ-BIBW-04, SCENARIO-BIBW-04a, SCENARIO-BIBW-03a.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/widgets/exercise_grid_card.dart';
import 'package:treino/features/coach_hub/presentation/widgets/treino_interactive_state.dart';
import 'package:treino/features/workout/domain/equipment_type.dart';
import 'package:treino/features/workout/domain/exercise.dart';

const _bench = Exercise(
  id: 'bench-press',
  name: 'Press de Banca',
  muscleGroup: 'chest',
  category: 'compound',
  equipment: EquipmentType.barra,
  defaultRestSeconds: 90,
);

const _customEx = Exercise(
  id: 'custom-squat',
  name: 'Sentadilla Personalizada',
  muscleGroup: 'quads',
  category: 'custom',
);

Widget _wrap(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Scaffold(body: SizedBox(width: 220, height: 260, child: child)),
    );

void main() {
  group('ExerciseGridCard —', () {
    testWidgets(
        'usa TreinoInteractiveState como resolver de interacción '
        '(sin GestureDetector crudo propio)', (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseGridCard(exercise: _bench, onTap: () {}),
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

    testWidgets('CUSTOM badge presente en ejercicio custom [SCENARIO-BIBW-03a]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseGridCard(exercise: _customEx, onTap: () {}),
      ));
      await tester.pump();

      expect(find.text('CUSTOM'), findsOneWidget);
    });

    testWidgets('sin CUSTOM badge en ejercicio de catálogo', (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseGridCard(exercise: _bench, onTap: () {}),
      ));
      await tester.pump();

      expect(find.text('CUSTOM'), findsNothing);
    });

    testWidgets('tap invoca onTap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(
        ExerciseGridCard(exercise: _bench, onTap: () => tapped++),
      ));
      await tester.pump();

      await tester.tap(find.byKey(const Key('exercise_grid_card_root')));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets(
        'hover → decoration del root cambia realmente (token real, no smoke)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseGridCard(exercise: _bench, onTap: () {}),
      ));
      await tester.pump();

      Color decorationColor() {
        final container = tester.widget<AnimatedContainer>(
          find.byKey(const Key('exercise_grid_card_root')),
        );
        return (container.decoration! as BoxDecoration).color!;
      }

      final normalColor = decorationColor();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        tester.getCenter(find.byKey(const Key('exercise_grid_card_root'))),
      );
      await tester.pump();

      final hoverColor = decorationColor();
      expect(hoverColor, isNot(equals(normalColor)),
          reason: 'el color de fondo debe cambiar realmente en hover');
    });

    testWidgets('smoke: mover el puntero sobre la card no crashea',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ExerciseGridCard(exercise: _bench, onTap: () {}),
      ));
      await tester.pump();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        tester.getCenter(find.byKey(const Key('exercise_grid_card_root'))),
      );
      await tester.pumpAndSettle();
      await gesture.moveTo(Offset.zero);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('smoke dark+light sin crash', (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await tester.pumpWidget(_wrap(
          ExerciseGridCard(exercise: _bench, onTap: () {}),
          theme: theme,
        ));
        await tester.pump();
        expect(find.text('Press de Banca'), findsOneWidget);
      }
    });
  });
}
