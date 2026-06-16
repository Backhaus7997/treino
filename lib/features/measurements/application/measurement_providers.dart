import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/measurement_repository.dart';
import '../domain/measurement.dart';

final measurementRepositoryProvider = Provider<MeasurementRepository>(
  (ref) => MeasurementRepository(firestore: ref.watch(firestoreProvider)),
);

/// Live stream of all measurements for [athleteId], regardless of who recorded
/// them.
///
/// - Queries by `athleteId` (single-field, no composite index) so the full
///   history is returned even across trainer reassignment or co-trainers.
/// - Sorts by [recordedAt] ascending client-side.
/// - Returns an empty list when no trainer is authenticated.
final measurementsForAthleteProvider = StreamProvider.autoDispose
    .family<List<Measurement>, String>((ref, athleteId) {
  final trainerUid = ref.watch(currentUidProvider);
  if (trainerUid == null) return Stream.value(const []);

  return ref
      .watch(measurementRepositoryProvider)
      .watchForAthlete(athleteId)
      .map(
        (all) => all.toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt)),
      );
});
