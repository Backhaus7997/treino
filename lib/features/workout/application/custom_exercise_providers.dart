import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/custom_exercise_repository.dart';
import '../data/custom_exercise_video_upload_service.dart';
import '../domain/custom_exercise.dart';

/// Singleton upload service for trainer-provided exercise tutorial videos.
final customExerciseVideoUploadServiceProvider =
    Provider<CustomExerciseVideoUploadService>(
  (ref) => CustomExerciseVideoUploadService(),
);

/// Singleton repository. Takes the upload service so `delete` can clean up
/// the Storage object that backs a custom exercise's video if there is one.
final customExerciseRepositoryProvider = Provider<CustomExerciseRepository>(
  (ref) => CustomExerciseRepository(
    firestore: ref.watch(firestoreProvider),
    videoUploadService: ref.watch(customExerciseVideoUploadServiceProvider),
  ),
);

/// Live stream of a trainer's personal exercise library, ordered by name asc.
final customExercisesForTrainerStreamProvider = StreamProvider.autoDispose
    .family<List<CustomExercise>, String>((ref, trainerId) {
  return ref.read(customExerciseRepositoryProvider).watchForTrainer(trainerId);
});
