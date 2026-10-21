import 'nutrition_plan.dart';

/// Ids de comidas, grupos y opciones de un [NutritionPlan] que se edita.
///
/// Los editores identifican cada ítem por su `id` para actualizarlo o
/// borrarlo, y el editor mobile además lo usa como `Key` de su widget. Dos
/// ítems con el mismo id se editan juntos —tocás uno y cambian los dos— y dos
/// `Key` iguales en la misma lista tiran abajo el build.
///
/// El editor web genera ids con un contador que arranca en 0 cada vez que se
/// abre (`meal-1`, `meal-2`…): sobre un plan que ya tenía un `meal-1`
/// guardado, la próxima comida nueva sale con el mismo id. Por eso el plan que
/// llega de Firestore no se asume limpio: pasa por [withUniqueIds] antes de
/// editarse, y todo id nuevo sale de [nextFreeId], que mira lo que ya existe.
extension NutritionPlanIds on NutritionPlan {
  /// Todos los ids del plan, de los tres niveles.
  Set<String> get allIds => {
        for (final meal in meals) ...{
          meal.id,
          for (final group in meal.groups) ...{
            group.id,
            for (final option in group.options) option.id,
          },
        },
      };

  /// Copia del plan donde ningún id se repite. El primer ítem que usa un id
  /// lo conserva; los siguientes reciben uno nuevo. Un plan sin repetidos
  /// vuelve igual.
  NutritionPlan withUniqueIds() {
    final seen = <String>{};
    final taken = allIds;

    String claim(String id, String prefix) {
      if (seen.add(id)) return id;
      final fresh = nextFreeIdIn(taken, prefix);
      taken.add(fresh);
      seen.add(fresh);
      return fresh;
    }

    return copyWith(
      meals: [
        for (final meal in meals)
          meal.copyWith(
            id: claim(meal.id, 'meal'),
            groups: [
              for (final group in meal.groups)
                group.copyWith(
                  id: claim(group.id, 'group'),
                  options: [
                    for (final option in group.options)
                      option.copyWith(id: claim(option.id, 'opt')),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  /// Un id `'$prefix-N'` que no está usado en el plan.
  String nextFreeId(String prefix) => nextFreeIdIn(allIds, prefix);
}

/// Primer `'$prefix-N'` que no está en [taken].
String nextFreeIdIn(Set<String> taken, String prefix) {
  var n = 0;
  String candidate;
  do {
    n++;
    candidate = '$prefix-$n';
  } while (taken.contains(candidate));
  return candidate;
}
