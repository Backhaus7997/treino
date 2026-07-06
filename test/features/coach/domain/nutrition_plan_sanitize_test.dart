// Unit tests for `NutritionPlanSanitize.sanitizeForSave()`.
//
// Regla del feature: al guardar el plan, filtramos silenciosamente comidas,
// grupos y opciones con nombre vacío. Esto es el criterio "Opción B —
// filtrado silencioso al guardar" acordado en el brief.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';

NutritionPlan _plan(List<Meal> meals) => NutritionPlan(
      id: 't_a',
      trainerId: 't',
      athleteId: 'a',
      title: 'X',
      meals: meals,
      updatedAt: DateTime(2026, 7, 6),
    );

void main() {
  group('NutritionPlanSanitize.sanitizeForSave', () {
    test('drops meals whose name is empty or blank', () {
      final plan = _plan([
        const Meal(id: 'm1', name: '  ', groups: []),
        const Meal(id: 'm2', name: 'Desayuno', groups: []),
      ]);
      final clean = plan.sanitizeForSave();
      expect(clean.meals.map((m) => m.id), ['m2']);
    });

    test('drops groups whose name is empty inside a valid meal', () {
      final plan = _plan([
        const Meal(id: 'm1', name: 'Desayuno', groups: [
          FoodGroup(
            id: 'g1',
            name: '',
            selectionMode: SelectionMode.chooseOne,
            options: [],
          ),
          FoodGroup(
            id: 'g2',
            name: 'Hidratos',
            selectionMode: SelectionMode.chooseOne,
            options: [],
          ),
        ]),
      ]);
      final clean = plan.sanitizeForSave();
      expect(clean.meals.single.groups.map((g) => g.id), ['g2']);
    });

    test('drops options whose name is empty inside a valid group', () {
      final plan = _plan([
        const Meal(id: 'm1', name: 'Desayuno', groups: [
          FoodGroup(
            id: 'g1',
            name: 'Hidratos',
            selectionMode: SelectionMode.chooseOne,
            options: [
              FoodOption(id: 'o1', name: ''),
              FoodOption(id: 'o2', name: '5 discos de arroz'),
              FoodOption(id: 'o3', name: '   '),
            ],
          ),
        ]),
      ]);
      final clean = plan.sanitizeForSave();
      expect(
        clean.meals.single.groups.single.options.map((o) => o.id),
        ['o2'],
      );
    });

    test('keeps a named group even if all its options were dropped', () {
      // El PF puede tener un grupo válido con nombre pero vacío de opciones
      // — es válido persistirlo, la sección la va a completar más adelante.
      final plan = _plan([
        const Meal(id: 'm1', name: 'Desayuno', groups: [
          FoodGroup(
            id: 'g1',
            name: 'Hidratos',
            selectionMode: SelectionMode.chooseOne,
            options: [FoodOption(id: 'o1', name: '')],
          ),
        ]),
      ]);
      final clean = plan.sanitizeForSave();
      expect(clean.meals.single.groups.length, 1);
      expect(clean.meals.single.groups.single.options, isEmpty);
    });

    test('an all-empty plan is reduced to zero meals (caller must check)',
        () {
      final plan = _plan([
        const Meal(id: 'm1', name: '', groups: []),
        const Meal(id: 'm2', name: '   ', groups: []),
      ]);
      final clean = plan.sanitizeForSave();
      expect(clean.meals, isEmpty);
    });

    test('preserves title, trainerId, athleteId, id and updatedAt', () {
      final plan = _plan([
        const Meal(id: 'm1', name: 'Desayuno', groups: []),
      ]);
      final clean = plan.sanitizeForSave();
      expect(clean.id, plan.id);
      expect(clean.trainerId, plan.trainerId);
      expect(clean.athleteId, plan.athleteId);
      expect(clean.title, plan.title);
      expect(clean.updatedAt, plan.updatedAt);
    });
  });
}
