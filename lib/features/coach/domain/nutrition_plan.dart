// ignore: unused_import — Timestamp is used by the generated nutrition_plan.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'nutrition_plan.freezed.dart';
part 'nutrition_plan.g.dart';

/// How the athlete should read the options of a [FoodGroup].
///
/// - `chooseOne`: pick ONE of the options (e.g. "Hidratos" in breakfast:
///   choose either "5-6 discos de arroz" OR "4 tostadas de pan").
/// - `all`: the athlete's plate should contain ALL groups (e.g. "Almuerzos":
///   your plate must have hidratos + proteínas + vegetales).
///
/// Wire values estables.
enum SelectionMode {
  @JsonValue('chooseOne')
  chooseOne,
  @JsonValue('all')
  all,
}

/// A single food option inside a [FoodGroup].
///
/// - [name]: free-form label written by the PF (e.g. "5 a 6 discos de arroz",
///   "2 huevos", "Pan de papa (50 grs papa + 2 claras)").
/// - [quantity] + [unit]: optional. When present, rendered together (e.g.
///   "230-240" + "gramos peso cocido"). When absent, only [name] is shown.
/// - [notes]: optional aclaraciones (e.g. "Preferentemente marca Tregar").
@freezed
class FoodOption with _$FoodOption {
  const factory FoodOption({
    required String id,
    required String name,
    String? quantity,
    String? unit,
    String? notes,
  }) = _FoodOption;

  factory FoodOption.fromJson(Map<String, Object?> json) =>
      _$FoodOptionFromJson(json);
}

/// A group of food options inside a [Meal] (e.g. "Hidratos", "Proteínas",
/// "Vegetales", "Adicionales").
///
/// [selectionMode] tells how the athlete should read the options list:
/// pick one, or combine all of them into the plate.
@freezed
class FoodGroup with _$FoodGroup {
  const factory FoodGroup({
    required String id,
    required String name,
    required SelectionMode selectionMode,
    required List<FoodOption> options,
  }) = _FoodGroup;

  factory FoodGroup.fromJson(Map<String, Object?> json) =>
      _$FoodGroupFromJson(json);
}

/// A single meal in the plan (e.g. "Desayuno y merienda", "Almuerzo",
/// "Cena", "Comida pre-entrenamiento").
///
/// [time] is optional and free-form (e.g. "06:00" or "13:00-14:00").
@freezed
class Meal with _$Meal {
  const factory Meal({
    required String id,
    required String name,
    String? time,
    required List<FoodGroup> groups,
  }) = _Meal;

  factory Meal.fromJson(Map<String, Object?> json) => _$MealFromJson(json);
}

/// Nutrition plan document. Single plan per PF↔athlete pair — every save
/// overwrites the previous version. No history in the MVP.
///
/// Stored in Firestore at `nutrition_plans/{trainerId}_{athleteId}`.
/// Trainer-only in rules — the athlete does NOT see this in mobile yet;
/// exposing to the athlete is scoped for a future feature.
@freezed
class NutritionPlan with _$NutritionPlan {
  const factory NutritionPlan({
    required String id,
    required String trainerId,
    required String athleteId,
    required String title,
    required List<Meal> meals,
    @TimestampConverter() required DateTime updatedAt,
  }) = _NutritionPlan;

  factory NutritionPlan.fromJson(Map<String, Object?> json) =>
      _$NutritionPlanFromJson(json);
}

/// Sanitize helpers used by the UI at save time.
///
/// The Coach Hub web editor lets the PF add empty meals / groups / options as
/// scaffolding while thinking. When the PF hits «GUARDAR PLAN» we drop
/// anything with an empty name silently — no error, no blocking dialog — so
/// the persisted plan is always clean.
///
/// Rules (all use `.trim()`):
/// 1. Option with empty [FoodOption.name] → dropped.
/// 2. Group with empty [FoodGroup.name] → dropped (regardless of options).
///    A group with a valid name but zero options after step 1 → kept (the PF
///    may still be filling it in later). See `sanitizeForSave`.
/// 3. Meal with empty [Meal.name] → dropped (regardless of groups).
extension NutritionPlanSanitize on NutritionPlan {
  /// Returns a copy of the plan with empty-named meals, groups and options
  /// removed. The returned plan is safe to persist.
  NutritionPlan sanitizeForSave() {
    final cleanMeals = <Meal>[];
    for (final meal in meals) {
      if (meal.name.trim().isEmpty) continue;
      final cleanGroups = <FoodGroup>[];
      for (final group in meal.groups) {
        if (group.name.trim().isEmpty) continue;
        final cleanOptions = group.options
            .where((o) => o.name.trim().isNotEmpty)
            .toList(growable: false);
        cleanGroups.add(group.copyWith(options: cleanOptions));
      }
      cleanMeals.add(meal.copyWith(groups: cleanGroups));
    }
    return copyWith(meals: cleanMeals);
  }
}
