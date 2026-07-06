import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/nutrition_plan_repository.dart';
import '../domain/nutrition_plan.dart';

final nutritionPlanRepositoryProvider = Provider<NutritionPlanRepository>(
  (ref) => NutritionPlanRepository(firestore: ref.watch(firestoreProvider)),
);

typedef NutritionPlanKey = ({String trainerId, String athleteId});

/// Stream reactivo del plan de nutrición del par PF↔alumno. Emite `null`
/// cuando no existe todavía — la UI muestra el estado "sin plan" y arma
/// uno nuevo desde `defaultPresetMeals()`.
final nutritionPlanProvider = StreamProvider.autoDispose
    .family<NutritionPlan?, NutritionPlanKey>(
  (ref, key) => ref
      .watch(nutritionPlanRepositoryProvider)
      .watch(key.trainerId, key.athleteId),
);
