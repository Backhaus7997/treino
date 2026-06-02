import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/performance_test_repository.dart';
import '../domain/performance_test.dart';

final performanceTestRepositoryProvider = Provider<PerformanceTestRepository>(
  (ref) => PerformanceTestRepository(firestore: ref.watch(firestoreProvider)),
);

/// Live stream of performance tests for [athleteId] recorded by the current trainer.
///
/// - Queries by `recordedBy` (single-field, no composite index).
/// - Filters to [athleteId] and sorts by [recordedAt] ascending client-side.
/// - Returns an empty list when no trainer is authenticated.
final performanceTestsForAthleteProvider = StreamProvider.autoDispose
    .family<List<PerformanceTest>, String>((ref, athleteId) {
  final trainerUid = ref.watch(currentUidProvider);
  if (trainerUid == null) return Stream.value(const []);

  return ref
      .watch(performanceTestRepositoryProvider)
      .watchRecordedBy(trainerUid)
      .map(
        (all) => all.where((t) => t.athleteId == athleteId).toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt)),
      );
});
