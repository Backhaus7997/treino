import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/custom_exercise_repository.dart';
import '../domain/custom_exercise.dart';

/// Singleton repository.
final customExerciseRepositoryProvider = Provider<CustomExerciseRepository>(
  (ref) => CustomExerciseRepository(
    firestore: ref.watch(firestoreProvider),
  ),
);

/// Live stream of a trainer's personal exercise library, ordered by name asc.
final customExercisesForTrainerStreamProvider = StreamProvider.autoDispose
    .family<List<CustomExercise>, String>((ref, trainerId) {
  return ref.read(customExerciseRepositoryProvider).watchForTrainer(trainerId);
});
