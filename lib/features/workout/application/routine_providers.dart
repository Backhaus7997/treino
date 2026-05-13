import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../profile/domain/experience_level.dart';
import '../data/routine_repository.dart';
import '../domain/routine.dart';

final routineRepositoryProvider = Provider<RoutineRepository>(
  (ref) => RoutineRepository(firestore: ref.watch(firestoreProvider)),
);

/// Eager-loads the full routine catalogue (~6 docs). Auth-gated:
/// returns an empty list when unauthenticated, mirroring [exercisesProvider].
final routinesProvider = FutureProvider<List<Routine>>((ref) async {
  final user = await ref.watch(authStateChangesProvider.future);
  if (user == null) return const [];
  return ref.watch(routineRepositoryProvider).listAll();
});

/// O(1) in-memory lookup. Derives from [routinesProvider] — never re-fetches
/// from Firestore. All family instances share one Firestore round-trip.
final routineByIdProvider = FutureProvider.family<Routine?, String>(
  (ref, id) async {
    final routines = await ref.watch(routinesProvider.future);
    for (final r in routines) {
      if (r.id == id) return r;
    }
    return null;
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
