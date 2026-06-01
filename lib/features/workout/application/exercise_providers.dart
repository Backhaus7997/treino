import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/exercise_repository.dart';
import '../domain/exercise.dart';
import 'custom_exercise_providers.dart'
    show customExerciseRepositoryProvider;

final exerciseRepositoryProvider = Provider<ExerciseRepository>(
  (ref) => ExerciseRepository(firestore: ref.watch(firestoreProvider)),
);

/// Eager-loads the full exercise catalogue (~25-30 docs). Auth-gated:
/// returns an empty list when unauthenticated, mirroring `userProfileProvider`
/// behaviour (but as FutureProvider, not StreamProvider).
///
/// Waits for auth state to settle before deciding: if [authStateChangesProvider]
/// emits null (unauthenticated), returns []. If it emits a User, loads the
/// catalogue. This avoids premature evaluation during the async loading phase.
final exercisesProvider = FutureProvider<List<Exercise>>((ref) async {
  // Await the first emission from the auth stream rather than reading
  // .valueOrNull synchronously. This ensures the FutureProvider's own
  // future only settles after auth is known — not during AsyncLoading.
  final user = await ref.watch(authStateChangesProvider.future);
  if (user == null) return const [];
  return ref.watch(exerciseRepositoryProvider).listAll();
});

/// O(1) in-memory lookup. Derives from [exercisesProvider] — never re-fetches
/// from Firestore. All family instances share one Firestore round-trip.
final exerciseByIdProvider = FutureProvider.family<Exercise?, String>(
  (ref, id) async {
    final exercises = await ref.watch(exercisesProvider.future);
    for (final e in exercises) {
      if (e.id == id) return e;
    }
    return null;
  },
);

/// Routine-slot-aware exercise lookup. Tries the public catalogue first; if
/// the id is unknown there AND an `ownerId` was provided (the routine's
/// `assignedBy`, i.e. the trainer who built the plan), falls back to that
/// trainer's `customExercises/{exerciseId}` subcollection so athletes can
/// open the detail screen for a trainer-defined exercise without
/// duplicating its content into the routine slot.
///
/// CustomExercise is projected into [Exercise] with `category: 'custom'` so
/// the existing detail screen renders it without branching. `techniqueInstructions`
/// stays null for now — trainers don't author per-instruction lists yet.
final slotExerciseProvider = FutureProvider.family<
    Exercise?, ({String exerciseId, String? ownerId})>(
  (ref, key) async {
    final fromCatalogue = await ref.watch(
      exerciseByIdProvider(key.exerciseId).future,
    );
    if (fromCatalogue != null) return fromCatalogue;

    final ownerId = key.ownerId;
    if (ownerId == null || ownerId.isEmpty) return null;

    final custom = await ref.read(customExerciseRepositoryProvider).getById(
          trainerId: ownerId,
          exerciseId: key.exerciseId,
        );
    if (custom == null) return null;

    return Exercise(
      id: custom.id,
      name: custom.name,
      muscleGroup: custom.muscleGroup,
      category: 'custom',
      videoUrl: custom.videoUrl,
      defaultRestSeconds: custom.defaultRestSeconds,
    );
  },
);
