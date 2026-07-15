import 'dart:async';

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
/// entrenador autenticado, uniendo DOS orígenes:
///   Q1 — las que el PF registró (`recordedBy == trainerUid`), y
///   Q2 — [athlete-self-measurements] las que el alumno se cargó a sí mismo
///        (`recordedBy == athleteId`), visibles al PF con vínculo activo +
///        consentimiento (ver la regla de lectura de `measurements`).
///
/// Se mantienen como DOS queries y se fusionan (no una `athleteId ==` a secas):
/// una query única también matchearía los docs de un PF ANTERIOR, que fallan la
/// regla para el PF nuevo → Firestore deniega la lista entera (design R4). Cada
/// query por separado es probable-como-legible.
///
/// Q2 es TOLERANTE A ERROR: un alumno sin consentimiento/vínculo hace que Q2
/// vuelva `permission-denied`; en ese caso se degrada a lista vacía para que el
/// PF siga viendo lo suyo (Q1) en vez de que el stream entero se caiga. Q1 NO
/// es tolerante: si el PF no puede leer lo suyo, es un error real que debe verse.
///
/// Ordena por [recordedAt] ascendente client-side. Lista vacía si no hay
/// entrenador autenticado.
final measurementsForAthleteProvider = StreamProvider.autoDispose
    .family<List<Measurement>, String>((ref, athleteId) {
  final trainerUid = ref.watch(currentUidProvider);
  if (trainerUid == null) return Stream.value(const []);

  final repo = ref.watch(measurementRepositoryProvider);
  return _mergeSorted(
    repo.watchForTrainerAthlete(trainerUid, athleteId), // Q1
    repo.watchSelfLoggedForAthlete(athleteId), // Q2 (error-tolerant)
  );
});

/// Une [q1] y [q2] emitiendo la concatenación ordenada de sus últimos valores
/// cada vez que cualquiera emite. [q2] es tolerante a error (→ lista vacía);
/// los errores de [q1] se propagan.
Stream<List<Measurement>> _mergeSorted(
  Stream<List<Measurement>> q1,
  Stream<List<Measurement>> q2,
) {
  final controller = StreamController<List<Measurement>>();
  var latest1 = const <Measurement>[];
  var latest2 = const <Measurement>[];
  var seen1 = false;
  var q1Failed = false;

  void emit() {
    // Un error de Q1 es TERMINAL: una vez propagado, no volvemos a emitir data
    // (si no, un `onDone` de Q1 tras el error, o una emisión de Q2, taparían el
    // error del PF con una lista sólo-self-logged). Y espera a que Q1 haya
    // emitido al menos una vez para no mostrar una lista que arranca sólo con
    // lo self-logged mientras Q1 todavía carga.
    if (q1Failed || !seen1) return;
    final merged = [...latest1, ...latest2]
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    controller.add(merged);
  }

  final sub1 = q1.listen(
    (v) {
      latest1 = v;
      seen1 = true;
      emit();
    },
    onError: (Object e, StackTrace st) {
      // Q1 error = error real del PF leyendo lo SUYO → propaga y queda terminal.
      q1Failed = true;
      controller.addError(e, st);
    },
    // Si Q1 cierra SIN emitir (p.ej. un stub `Stream.empty()`), destraba el
    // merge igual — un `snapshots()` real siempre emite, pero no dependemos de
    // eso para no colgar el provider en loading. NO destraba si Q1 ya falló.
    onDone: () {
      if (!seen1 && !q1Failed) {
        seen1 = true;
        emit();
      }
    },
  );
  final sub2 = q2.listen(
    (v) {
      latest2 = v;
      emit();
    },
    onError: (_, __) {
      // Q2 denegada (sin consentimiento/vínculo), o revocada a mitad de camino
      // → degradar a vacío para que el PF siga viendo lo suyo (Q1).
      latest2 = const [];
      emit();
    },
  );

  controller.onCancel = () async {
    await sub1.cancel();
    await sub2.cancel();
  };
  return controller.stream;
}

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
