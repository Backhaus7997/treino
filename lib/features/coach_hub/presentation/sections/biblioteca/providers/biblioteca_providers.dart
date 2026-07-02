// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../workout/application/custom_exercise_providers.dart';
import '../../../../../workout/application/exercise_filter.dart';
import '../../../../../workout/application/exercise_providers.dart';
import '../../../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../../../../workout/domain/equipment_type.dart';
import '../../../../../workout/domain/exercise.dart';
import '../../../../../workout/domain/muscle_group.dart';

// ── Filter state providers (autoDispose → reset on section exit) ──────────────

/// Active text search query. Empty string = no filter.
final bibliotecaQueryProvider = StateProvider.autoDispose<String>(
  (ref) => '',
);

/// Active muscle group filter set. Empty = no filter (all muscles shown).
final bibliotecaMuscleFilterProvider =
    StateProvider.autoDispose<Set<MuscleGroup>>(
  (ref) => const {},
);

/// Active equipment type filter set. Empty = no filter (all equipment shown).
/// When non-empty, exercises with null equipment are excluded (ADR-RER-05).
final bibliotecaEquipmentFilterProvider =
    StateProvider.autoDispose<Set<EquipmentType>>(
  (ref) => const {},
);

// ── Merged + filtered provider ────────────────────────────────────────────────

/// Merged exercise list (catalog ∪ custom) with active filters applied.
///
/// Folding rule (ADR-BIBW-02):
/// - Catalog is the spine: if catalog is loading → AsyncLoading;
///   if catalog errors → AsyncError.
/// - Custom stream errors are swallowed via `valueOrNull ?? []` so a trainer
///   with broken custom permissions still browses the catalog.
/// - Custom entries are prepended (mirrors picker "Tus ejercicios" precedence).
/// - Custom exercises carry `category == 'custom'` (via [customToExercise]).
final bibliotecaExercisesProvider =
    Provider.autoDispose<AsyncValue<List<Exercise>>>((ref) {
  final catalogAsync = ref.watch(exercisesProvider);
  final uid = ref.watch(currentUidProvider) ?? '';
  final query = ref.watch(bibliotecaQueryProvider);
  final muscles = ref.watch(bibliotecaMuscleFilterProvider);
  final equipment = ref.watch(bibliotecaEquipmentFilterProvider);

  // Catalog is the spine — propagate its loading/error states.
  if (catalogAsync.isLoading) return const AsyncLoading();
  if (catalogAsync.hasError) {
    return AsyncError(catalogAsync.error!, catalogAsync.stackTrace!);
  }

  final catalog = catalogAsync.requireValue;

  // Custom stream: degrade to empty on loading or error so catalog is always
  // shown. trainerId from currentUidProvider.
  final customsAsync = uid.isEmpty
      ? const AsyncValue<List<Exercise>>.data(<Exercise>[])
      : ref.watch(
          customExercisesForTrainerStreamProvider(uid).select(
            (a) => AsyncValue.data(
              a.valueOrNull?.map(customToExercise).toList(growable: false) ??
                  <Exercise>[],
            ),
          ),
        );

  final customs = customsAsync.requireValue;

  // Merge: customs first, then catalog.
  final merged = [...customs, ...catalog];

  // Apply filters.
  final filtered = merged
      .where(
        (e) => exerciseMatchesFilters(
          e,
          query: query,
          muscles: muscles,
          equipment: equipment,
        ),
      )
      .toList(growable: false);

  return AsyncData(filtered);
});

// ── Unfiltered count (stable tab label) ──────────────────────────────────────

/// Total count of all exercises (catalog + custom) regardless of active
/// filters. Used for the tab label so it stays stable while the trainer
/// filters the grid.
final bibliotecaUnfilteredCountProvider =
    Provider.autoDispose<AsyncValue<int>>((ref) {
  final catalogAsync = ref.watch(exercisesProvider);
  final uid = ref.watch(currentUidProvider) ?? '';

  if (catalogAsync.isLoading) return const AsyncLoading();
  if (catalogAsync.hasError) {
    return AsyncError(catalogAsync.error!, catalogAsync.stackTrace!);
  }

  final catalog = catalogAsync.requireValue;

  final customsAsync = uid.isEmpty
      ? const AsyncValue<List<Exercise>>.data(<Exercise>[])
      : ref.watch(
          customExercisesForTrainerStreamProvider(uid).select(
            (a) => AsyncValue.data(
              a.valueOrNull?.map(customToExercise).toList() ?? <Exercise>[],
            ),
          ),
        );

  final customs = customsAsync.requireValue;
  return AsyncData(catalog.length + customs.length);
});
