import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/performance_test_repository.dart';
import '../domain/performance_test.dart';

final performanceTestRepositoryProvider = Provider<PerformanceTestRepository>(
  (ref) => PerformanceTestRepository(firestore: ref.watch(firestoreProvider)),
);

/// Live stream of all performance tests for [athleteId], regardless of who
/// recorded them.
///
/// - Queries by `athleteId` (single-field, no composite index) so the full
///   history is returned even across trainer reassignment or co-trainers.
/// - Sorts by [recordedAt] ascending client-side.
/// - Returns an empty list when no trainer is authenticated.
final performanceTestsForAthleteProvider = StreamProvider.autoDispose
    .family<List<PerformanceTest>, String>((ref, athleteId) {
  final trainerUid = ref.watch(currentUidProvider);
  if (trainerUid == null) return Stream.value(const []);

  return ref
      .watch(performanceTestRepositoryProvider)
      .watchForAthlete(athleteId)
      .map(
        (all) => all.toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt)),
      );
});
