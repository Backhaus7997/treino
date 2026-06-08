import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../profile/domain/experience_level.dart';
import '../data/routine_repository.dart';
import '../domain/routine.dart';

final routineRepositoryProvider = Provider<RoutineRepository>(
  (ref) => RoutineRepository(firestore: ref.watch(firestoreProvider)),
);

/// Eager-loads the system template catalogue (~6 docs). Auth-gated:
/// returns an empty list when unauthenticated, mirroring [exercisesProvider].
/// Uses [RoutineRepository.listSystemTemplates] (REQ-USR-015, ADR-USR-05) —
/// only `source == 'system'` routines; athlete-created routines are isolated
/// in [userCreatedRoutinesProvider].
final routinesProvider = FutureProvider<List<Routine>>((ref) async {
  final user = await ref.watch(authStateChangesProvider.future);
  if (user == null) return const [];
  return ref.watch(routineRepositoryProvider).listSystemTemplates();
});

/// Live stream of the trainer's own templates (assignedBy == trainerId,
/// source == trainer-template). Powers the template library section of
/// `TrainerWorkoutView`.
final trainerTemplatesStreamProvider =
    StreamProvider.autoDispose.family<List<Routine>, String>((ref, trainerId) {
  return ref.read(routineRepositoryProvider).watchTemplatesBy(trainerId);
});

/// Single-doc fetch. Hits Firestore directly via `getById` so it works for
/// BOTH public catalog plantillas AND private trainer-assigned plans
/// (which are not in [routinesProvider] because [listSystemTemplates] filters
/// by `source == 'system'` and `visibility == 'public'`).
final routineByIdProvider = FutureProvider.family<Routine?, String>(
  (ref, id) async {
    return ref.watch(routineRepositoryProvider).getById(id);
  },
);

/// Currently selected level filter for the Plantillas section.
/// `null` means "Todas" (no filter applied).
final routinesLevelFilterProvider =
    StateProvider<ExperienceLevel?>((ref) => null);

/// Derived view of [routinesProvider] filtered by [routinesLevelFilterProvider].
/// Returns an [AsyncValue] so the UI keeps a unified loading/error contract.
/// When the filter is `null`, the full list is returned unchanged.
///
/// [AsyncValue.whenData] preserves loading and error states automatically
/// — only the data branch runs the transform.
final filteredRoutinesProvider = Provider<AsyncValue<List<Routine>>>((ref) {
  final routines = ref.watch(routinesProvider);
  final filter = ref.watch(routinesLevelFilterProvider);
  return routines.whenData((list) {
    if (filter == null) return list;
    return list.where((r) => r.level == filter).toList();
  });
});
