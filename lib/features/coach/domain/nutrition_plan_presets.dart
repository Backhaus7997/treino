import 'nutrition_plan.dart';

/// Default meals used to bootstrap a new [NutritionPlan] when the PF opens
/// the Nutrition tab for an athlete that has no plan saved yet.
///
/// Structure is empty on purpose — the PF fills every group with real
/// options. We just prime the meals + typical groups + selection modes so
/// the first-use experience isn't a blank canvas.
///
/// Ids are stable strings (not timestamps) because these are re-generated
/// every time from scratch; if they were UUIDs a hot-reload during
/// development would look like a rebuild.
List<Meal> defaultPresetMeals() {
  return [
    const Meal(
      id: 'preset-breakfast',
      name: 'Desayuno',
      time: '',
      groups: [
        FoodGroup(
          id: 'preset-breakfast-carbs',
          name: 'Hidratos de carbono',
          selectionMode: SelectionMode.chooseOne,
          options: [],
        ),
        FoodGroup(
          id: 'preset-breakfast-protein',
          name: 'Proteínas',
          selectionMode: SelectionMode.chooseOne,
          options: [],
        ),
        FoodGroup(
          id: 'preset-breakfast-extras',
          name: 'Adicionales',
          selectionMode: SelectionMode.chooseOne,
          options: [],
        ),
      ],
    ),
    const Meal(
      id: 'preset-midmorning',
      name: 'Media mañana',
      time: '',
      groups: [
        FoodGroup(
          id: 'preset-midmorning-snack',
          name: 'Colación',
          selectionMode: SelectionMode.chooseOne,
          options: [],
        ),
      ],
    ),
    const Meal(
      id: 'preset-lunch',
      name: 'Almuerzo',
      time: '',
      groups: [
        FoodGroup(
          id: 'preset-lunch-carbs',
          name: 'Hidratos',
          selectionMode: SelectionMode.chooseOne,
          options: [],
        ),
        FoodGroup(
          id: 'preset-lunch-protein',
          name: 'Proteínas',
          selectionMode: SelectionMode.chooseOne,
          options: [],
        ),
        FoodGroup(
          id: 'preset-lunch-veggies',
          name: 'Vegetales',
          selectionMode: SelectionMode.all,
          options: [],
        ),
      ],
    ),
    const Meal(
      id: 'preset-afternoon',
      name: 'Merienda',
      time: '',
      groups: [
        FoodGroup(
          id: 'preset-afternoon-carbs',
          name: 'Hidratos de carbono',
          selectionMode: SelectionMode.chooseOne,
          options: [],
        ),
        FoodGroup(
          id: 'preset-afternoon-protein',
          name: 'Proteínas',
          selectionMode: SelectionMode.chooseOne,
          options: [],
        ),
      ],
    ),
    const Meal(
      id: 'preset-snack',
      name: 'Colación',
      time: '',
      groups: [
        FoodGroup(
          id: 'preset-snack-opt',
          name: 'Opciones',
          selectionMode: SelectionMode.chooseOne,
          options: [],
        ),
      ],
    ),
    const Meal(
      id: 'preset-dinner',
      name: 'Cena',
      time: '',
      groups: [
        FoodGroup(
          id: 'preset-dinner-carbs',
          name: 'Hidratos',
          selectionMode: SelectionMode.chooseOne,
          options: [],
        ),
        FoodGroup(
          id: 'preset-dinner-protein',
          name: 'Proteínas',
          selectionMode: SelectionMode.chooseOne,
          options: [],
        ),
        FoodGroup(
          id: 'preset-dinner-veggies',
          name: 'Vegetales',
          selectionMode: SelectionMode.all,
          options: [],
        ),
      ],
    ),
  ];
}
