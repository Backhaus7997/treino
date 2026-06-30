import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../coach_hub/data/exercise_matcher.dart' show normalize;
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/exercise_repository.dart';
import '../domain/exercise.dart';
import 'custom_exercise_providers.dart' show customExerciseRepositoryProvider;

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
  // Watch the auth AsyncValue directly (not `.future`) so this provider
  // RE-RUNS on every auth emission. With `.future` it settled on the FIRST
  // emission — which in release builds is usually `null` (emitted before
  // Firebase Auth restores the persisted session), leaving the catalogue
  // stuck empty even after the session is restored. Debug builds hid the bug
  // because their slower startup let auth restore before this ran.
  final authState = ref.watch(authStateChangesProvider);
  // While auth is still resolving its first value, keep this future pending
  // (don't flash an empty catalogue). Re-runs when auth later emits the User.
  if (authState.isLoading) {
    await ref.watch(authStateChangesProvider.future);
  }
  final user = ref.watch(authStateChangesProvider).valueOrNull;
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

/// Routine-slot-aware exercise lookup. Three-tier fallback:
///
///   1. Strict ID match in the public catalogue ([exerciseByIdProvider]).
///   2. **Name fallback**: if [exerciseName] was provided and the strict
///      lookup missed, scan the public catalogue for a normalized match
///      against [Exercise.name] or [Exercise.aliases]. Saves slots whose
///      stored `exerciseId` drifted from the catalogue — known causes:
///      seed scripts written with Spanish-slug IDs (`press-banca`) while
///      the catalogue uses English-kebab (`bench-press`), and
///      `dedup_exercise_generics.js` deleting generic docs (`bench-press`)
///      in favour of equipment-qualified variants (`bench-press-barbell`)
///      without updating in-flight routines.
///   3. If `ownerId` is non-null and the catalogue lookup fully missed,
///      try the trainer's `customExercises/{exerciseId}` subcollection
///      (so athletes can open trainer-defined exercises without
///      duplicating content into the slot).
///
/// CustomExercise is projected into [Exercise] with `category: 'custom'` so
/// the existing detail screen renders it without branching.
/// `techniqueInstructions` stays null — trainers don't author per-instruction
/// lists yet.
final slotExerciseProvider = FutureProvider.family<Exercise?,
    ({String exerciseId, String? ownerId, String? exerciseName})>(
  (ref, key) async {
    // Tier 1: strict ID.
    final fromCatalogue = await ref.watch(
      exerciseByIdProvider(key.exerciseId).future,
    );
    if (fromCatalogue != null) return fromCatalogue;

    // Tier 2: name / alias fallback (only if a name was supplied by the slot).
    final name = key.exerciseName;
    if (name != null && name.trim().isNotEmpty) {
      final all = await ref.watch(exercisesProvider.future);
      final target = normalize(name);
      if (target.isNotEmpty) {
        for (final ex in all) {
          if (normalize(ex.name) == target) return ex;
          for (final a in ex.aliases) {
            if (normalize(a) == target) return ex;
          }
        }
      }
    }

    // Tier 3: trainer custom exercises (id-keyed subcollection).
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
      secondaryMuscleGroup: custom.secondaryMuscleGroup,
      category: 'custom',
      videoUrl: custom.videoUrl,
      defaultRestSeconds: custom.defaultRestSeconds,
      equipment: custom.equipment,
    );
  },
);
