import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/performance_test_repository.dart';
import '../domain/performance_test.dart';

final performanceTestRepositoryProvider = Provider<PerformanceTestRepository>(
  (ref) => PerformanceTestRepository(firestore: ref.watch(firestoreProvider)),
);

/// Live stream de los tests de performance del alumno [athleteId] visibles para
/// el entrenador autenticado: los que ÉL registró (`recordedBy`).
///
/// - Query por `recordedBy + athleteId` (dos igualdades, sin índice compuesto).
///   Es la única forma que las reglas de Firestore le permiten al entrenador:
///   un `where athleteId ==` a secas es denegado porque la regla exige
///   `recordedBy == uid || athleteId == uid` (ver
///   [PerformanceTestRepository.watchForTrainerAthlete]).
/// - Ordena por [recordedAt] ascendente client-side.
/// - Devuelve lista vacía si no hay entrenador autenticado.
final performanceTestsForAthleteProvider = StreamProvider.autoDispose
    .family<List<PerformanceTest>, String>((ref, athleteId) {
  final trainerUid = ref.watch(currentUidProvider);
  if (trainerUid == null) return Stream.value(const []);

  return ref
      .watch(performanceTestRepositoryProvider)
      .watchForTrainerAthlete(trainerUid, athleteId)
      .map(
        (all) =>
            all.toList()..sort((a, b) => a.recordedAt.compareTo(b.recordedAt)),
      );
});

/// Live stream de TODOS los tests de performance de [athleteId], desde la
/// óptica del PROPIO atleta — sin importar quién los registró.
///
/// Contraparte de [performanceTestsForAthleteProvider] (óptica del ENTRENADOR,
/// sólo ve los que él mismo cargó). Misma asimetría y mismas restricciones que
/// [ownMeasurementsProvider] — ver su doc para el detalle de las reglas.
///
/// ⚠️ SÓLO válido cuando el caller ES el atleta. Ver
/// [PerformanceTestRepository.watchForAthlete].
final ownPerformanceTestsProvider = StreamProvider.autoDispose
    .family<List<PerformanceTest>, String>((ref, athleteId) {
  if (athleteId.isEmpty) return Stream.value(const []);

  return ref
      .watch(performanceTestRepositoryProvider)
      .watchForAthlete(athleteId)
      .map(
        (all) =>
            all.toList()..sort((a, b) => a.recordedAt.compareTo(b.recordedAt)),
      );
});
