import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/measurement_repository.dart';
import '../domain/measurement.dart';

final measurementRepositoryProvider = Provider<MeasurementRepository>(
  (ref) => MeasurementRepository(firestore: ref.watch(firestoreProvider)),
);

/// Live stream of measurements for [athleteId] recorded by the current trainer.
///
/// - Queries by `recordedBy` (single-field, no composite index).
/// - Filters to [athleteId] and sorts by [recordedAt] ascending client-side.
/// - Returns an empty list when no trainer is authenticated.
final measurementsForAthleteProvider = StreamProvider.autoDispose
    .family<List<Measurement>, String>((ref, athleteId) {
  final trainerUid = ref.watch(currentUidProvider);
  if (trainerUid == null) return Stream.value(const []);

  return ref
      .watch(measurementRepositoryProvider)
      .watchRecordedBy(trainerUid)
      .map(
        (all) => all.where((m) => m.athleteId == athleteId).toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt)),
      );
});
