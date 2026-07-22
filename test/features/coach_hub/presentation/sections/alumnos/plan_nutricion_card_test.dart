// Tests de PlanNutricionCard — selector ELEGIR UNA/TODAS de un FoodGroup.
//
// Remediación barrido final (accesibilidad de teclado sistémica): las pills
// del selector envolvían un TreinoTappable crudo (sin Focus ni
// Semantics(button)) en vez de TreinoInteractiveState — inalcanzables por
// teclado. `find.ancestor(..., matching: find.byType(TreinoTappable))` en
// `nutricion_tab_test.dart` sigue pasando: TreinoInteractiveState sigue
// envolviendo un TreinoTappable internamente.
//
// SCENARIO-PNC-01: tap en "TODAS" dispara onMealChanged con selectionMode
//   actualizado.
// SCENARIO-PNC-02: la pill "TODAS" es focusable, expone Semantics(button) y
//   Enter activa el mismo cambio que el tap.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/widgets/plan_nutricion_card.dart';

NutritionPlan _draft() => NutritionPlan(
      id: 'plan-1',
      trainerId: 't1',
      athleteId: 'a1',
      title: 'Plan',
      meals: [
        const Meal(
          id: 'm1',
          name: 'Desayuno',
          groups: [
            FoodGroup(
              id: 'g1',
              name: 'Hidratos',
              selectionMode: SelectionMode.chooseOne,
              options: [],
            ),
          ],
        ),
      ],
      updatedAt: DateTime(2026, 7, 1),
    );

Widget _wrap({required void Function(String, Meal) onMealChanged}) =>
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => SingleChildScrollView(
            child: PlanNutricionCard(
              draft: _draft(),
              palette: AppPalette.of(context),
              newIdFor: (prefix) => '${prefix}_new',
              onTitleChanged: (_) {},
              onMealChanged: onMealChanged,
              onRemoveMeal: (_) {},
              onAddMeal: () {},
            ),
          ),
        ),
      ),
    );

void main() {
  group('PlanNutricionCard — selector ELEGIR UNA/TODAS —', () {
    testWidgets('tap en "TODAS" dispara onMealChanged actualizado '
        '[SCENARIO-PNC-01]', (tester) async {
      String? changedMealId;
      Meal? changedMeal;

      await tester.pumpWidget(_wrap(onMealChanged: (id, meal) {
        changedMealId = id;
        changedMeal = meal;
      }));
      await tester.pump();

      await tester.tap(find.text('TODAS'));
      await tester.pump();

      expect(changedMealId, 'm1');
      expect(changedMeal!.groups.single.selectionMode, SelectionMode.all);
    });

    testWidgets(
        'pill "TODAS": focusable, Semantics(button) y Enter activa el '
        'cambio [SCENARIO-PNC-02]', (tester) async {
      final handle = tester.ensureSemantics();
      String? changedMealId;
      Meal? changedMeal;

      await tester.pumpWidget(_wrap(onMealChanged: (id, meal) {
        changedMealId = id;
        changedMeal = meal;
      }));
      await tester.pump();

      final semantics = tester.getSemantics(find.text('TODAS'));
      expect(semantics.flagsCollection.isButton, isTrue,
          reason: 'la pill "TODAS" debe exponer Semantics(button: true)');

      final focusNode = Focus.of(tester.element(find.text('TODAS')));
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(changedMealId, 'm1', reason: 'Enter debe activar onMealChanged');
      expect(changedMeal!.groups.single.selectionMode, SelectionMode.all);

      handle.dispose();
    });
  });
}
