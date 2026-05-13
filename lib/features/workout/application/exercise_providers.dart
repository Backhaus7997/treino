import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/exercise_repository.dart';
import '../domain/exercise.dart';

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
  return ref.read(exerciseRepositoryProvider).listAll();
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
