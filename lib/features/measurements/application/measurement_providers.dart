import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/measurement_repository.dart';
import '../domain/measurement.dart';

final measurementRepositoryProvider = Provider<MeasurementRepository>(
  (ref) => MeasurementRepository(firestore: ref.watch(firestoreProvider)),
);

/// Live stream de las mediciones del alumno [athleteId] visibles para el
/// entrenador autenticado: las que ÉL registró (`recordedBy`).
///
/// - Query por `recordedBy + athleteId` (dos igualdades, sin índice compuesto).
///   Es la única forma que las reglas de Firestore le permiten al entrenador:
///   un `where athleteId ==` a secas es denegado porque la regla exige
///   `recordedBy == uid || athleteId == uid` (ver
///   [MeasurementRepository.watchForTrainerAthlete]).
/// - Ordena por [recordedAt] ascendente client-side.
/// - Devuelve lista vacía si no hay entrenador autenticado.
final measurementsForAthleteProvider = StreamProvider.autoDispose
    .family<List<Measurement>, String>((ref, athleteId) {
  final trainerUid = ref.watch(currentUidProvider);
  if (trainerUid == null) return Stream.value(const []);

  return ref
      .watch(measurementRepositoryProvider)
      .watchForTrainerAthlete(trainerUid, athleteId)
      .map(
        (all) =>
            all.toList()..sort((a, b) => a.recordedAt.compareTo(b.recordedAt)),
      );
});
