import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';
import 'package:treino/features/coach/domain/nutrition_plan_ids.dart';

NutritionPlan _plan(List<Meal> meals) => NutritionPlan(
      id: 't1_a1',
      trainerId: 't1',
      athleteId: 'a1',
      title: '',
      meals: meals,
      updatedAt: DateTime.utc(2026, 10, 16),
    );

void main() {
  group('nextFreeId', () {
    // El caso del editor web: el contador arranca en 0 en cada sesión, así
    // que sobre un plan con `meal-1` guardado la próxima comida salía con el
    // mismo id.
    test('saltea los ids que el plan ya usa', () {
      final plan = _plan(const [
        Meal(id: 'meal-1', name: 'Desayuno', groups: []),
        Meal(id: 'meal-2', name: 'Almuerzo', groups: []),
      ]);

      expect(plan.nextFreeId('meal'), 'meal-3');
    });

    test('mira los tres niveles, no sólo el del prefijo', () {
      final plan = _plan(const [
        Meal(
          id: 'opt-1',
          name: 'Desayuno',
          groups: [
            FoodGroup(
              id: 'g',
              name: 'Hidratos',
              selectionMode: SelectionMode.chooseOne,
              options: [FoodOption(id: 'opt-2', name: 'Avena')],
            ),
          ],
        ),
      ]);

      expect(plan.nextFreeId('opt'), 'opt-3');
    });
  });

  group('withUniqueIds', () {
    test('un plan sin repetidos vuelve igual', () {
      final plan = _plan(const [
        Meal(
          id: 'preset-breakfast',
          name: 'Desayuno',
          groups: [
            FoodGroup(
              id: 'preset-breakfast-carbs',
              name: 'Hidratos',
              selectionMode: SelectionMode.chooseOne,
              options: [FoodOption(id: 'opt-1', name: 'Avena')],
            ),
          ],
        ),
      ]);

      expect(plan.withUniqueIds(), plan);
    });

    test('el primero conserva el id; los repetidos reciben uno libre', () {
      final plan = _plan(const [
        Meal(id: 'meal-1', name: 'Desayuno', groups: []),
        Meal(id: 'meal-2', name: 'Almuerzo', groups: []),
        Meal(id: 'meal-1', name: 'Cena', groups: []),
      ]);

      final fixed = plan.withUniqueIds();

      expect(fixed.meals.map((m) => m.id), ['meal-1', 'meal-2', 'meal-3']);
      // El contenido no se toca: sólo los ids.
      expect(fixed.meals.map((m) => m.name), ['Desayuno', 'Almuerzo', 'Cena']);
    });

    test('ningún id queda repetido entre niveles', () {
      final plan = _plan(const [
        Meal(
          id: 'x',
          name: 'Desayuno',
          groups: [
            FoodGroup(
              id: 'x',
              name: 'Hidratos',
              selectionMode: SelectionMode.chooseOne,
              options: [
                FoodOption(id: 'x', name: 'Avena'),
                FoodOption(id: 'x', name: 'Tostadas'),
              ],
            ),
          ],
        ),
      ]);

      final fixed = plan.withUniqueIds();
      final ids = [
        for (final m in fixed.meals) ...[
          m.id,
          for (final g in m.groups) ...[
            g.id,
            for (final o in g.options) o.id,
          ],
        ],
      ];

      expect(ids.toSet().length, ids.length, reason: 'ids: $ids');
      expect(fixed.meals.single.id, 'x');
    });
  });
}
