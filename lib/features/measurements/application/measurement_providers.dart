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

/// Live stream de TODAS las mediciones de [athleteId], desde la óptica del
/// PROPIO atleta — sin importar quién las registró.
///
/// Contraparte de [measurementsForAthleteProvider], que es la óptica del
/// ENTRENADOR y sólo ve las que él mismo cargó (`recordedBy == trainerUid`).
/// Un atleta que llamara a aquél con su propio uid obtendría la query
/// `recordedBy == suUid`, que devuelve vacío para todo lo que le cargó su PF.
///
/// Query de un solo campo (`athleteId ==`), permitida por la regla de lectura
/// `recordedBy == uid || athleteId == uid` (firestore.rules). NO requiere
/// índice compuesto.
///
/// ⚠️ SÓLO válido cuando el caller ES el atleta ([athleteId] == uid
/// autenticado). Un entrenador que lo llame con el uid de su alumno recibe
/// PERMISSION_DENIED: la query no satisface la rama `recordedBy == uid` y
/// Firestore no puede probar la otra. Ver
/// [MeasurementRepository.watchForAthlete].
///
/// Ordena por [Measurement.recordedAt] ascendente client-side — el contrato que
/// espera [MeasurementProgressChart].
final ownMeasurementsProvider = StreamProvider.autoDispose
    .family<List<Measurement>, String>((ref, athleteId) {
  if (athleteId.isEmpty) return Stream.value(const []);

  return ref
      .watch(measurementRepositoryProvider)
      .watchForAthlete(athleteId)
      .map(
        (all) =>
            all.toList()..sort((a, b) => a.recordedAt.compareTo(b.recordedAt)),
      );
});
