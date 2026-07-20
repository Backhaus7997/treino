import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../coach/application/nutrition_plan_providers.dart';
import '../../../../coach/application/trainer_link_providers.dart';
import '../../../../coach/domain/nutrition_plan.dart';
import '../../../../coach/domain/trainer_link.dart';
import '../../../../coach/domain/trainer_link_status.dart';
import '../../../../workout/application/session_providers.dart'
    show currentUidProvider;

/// Filtro del overview cross-alumno de Nutrición (ADR-F6-01) — chips
/// Todos/Con plan/Sin plan.
enum NutricionFiltro { todos, conPlan, sinPlan }

/// Una fila del overview: el [TrainerLink] activo con el alumno más el
/// estado de su [NutritionPlan] (`null` si todavía no tiene uno armado, o
/// mientras el stream sigue en [planLoading]).
typedef NutricionEntry = ({
  TrainerLink link,
  NutritionPlan? plan,
  bool planLoading,
});

/// Predicado puro — determina si [entry] pertenece a [filtro]:
/// - Todos: siempre `true`.
/// - Con plan: `entry.plan != null`.
/// - Sin plan: `entry.plan == null`.
///
/// Mientras `entry.planLoading` es `true`, `entry.plan` todavía es `null`
/// (el stream no resolvió su primer valor) — por diseño esto excluye la
/// entry de "Con plan" (todavía no hay evidencia de que exista un plan) SIN
/// contarla como "Sin plan" tampoco, ya que ese conteo definitivo recién es
/// correcto una vez que el stream resuelve. En la práctica el chip
/// "Sin plan" puede subcontar en un frame transitorio de loading; se
/// resuelve solo en el próximo rebuild cuando el stream emite.
bool matchesNutricionFiltro(NutricionEntry entry, NutricionFiltro filtro) =>
    switch (filtro) {
      NutricionFiltro.todos => true,
      NutricionFiltro.conPlan => !entry.planLoading && entry.plan != null,
      NutricionFiltro.sinPlan => !entry.planLoading && entry.plan == null,
    };

/// Overview cross-alumno de Nutrición: combina los vínculos `active` del PF
/// actual ([trainerLinksStreamProvider]) con el plan de cada alumno
/// ([nutritionPlanProvider]).
final nutricionEntriesProvider =
    Provider.autoDispose<AsyncValue<List<NutricionEntry>>>((ref) {
  return ref.watch(trainerLinksStreamProvider).whenData((links) {
    final trainerId = ref.watch(currentUidProvider) ?? '';
    final active =
        links.where((l) => l.status == TrainerLinkStatus.active).toList();

    NutricionEntry entryFor(TrainerLink l) {
      final planAsync = ref.watch(
        nutritionPlanProvider(
          (trainerId: trainerId, athleteId: l.athleteId),
        ),
      );
      return (
        link: l,
        plan: planAsync.valueOrNull,
        planLoading: planAsync.isLoading,
      );
    }

    return [for (final l in active) entryFor(l)];
  });
});

/// Chip seleccionado del overview. Default: Todos.
final nutricionFiltroProvider =
    StateProvider.autoDispose<NutricionFiltro>((_) => NutricionFiltro.todos);

/// Conteo por chip — badges de [TreinoFilterChips] en la screen real
/// (WU-04+).
Map<NutricionFiltro, int> nutricionFiltroCounts(List<NutricionEntry> entries) {
  return {
    for (final filtro in NutricionFiltro.values)
      filtro: entries.where((e) => matchesNutricionFiltro(e, filtro)).length,
  };
}
