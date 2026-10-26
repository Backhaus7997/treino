import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, FirebaseFirestore;

import '../../../core/utils/firestore_snapshots.dart';
import '../domain/trainer_public_profile.dart';
import '../domain/trainer_specialty.dart';

/// Repository for the `trainerPublicProfiles` collection.
///
/// Readable by any authenticated user; writable only by the owner via
/// [UserRepository] dual-write.
///
/// Query strategy:
///   - [listByGeohashPrefix]: legacy range query on `trainerGeohash` (singular,
///     DEPRECATED — kept until all clients migrate). New code should use
///     [listByGeohashes] instead.
///   - [listByGeohashes]: Firestore `array-contains-any` query on the
///     `trainerGeohashes` array. Devuelve PFs que tienen al menos una
///     ubicación con uno de los geohashes provistos. Reemplazo de
///     `listByGeohashPrefix` para el modelo multi-location (Fase 6 Etapa 0).
///   - [listVirtualOnly]: Firestore `where('trainerOffersOnline', true)`.
///     Usado por el chip "Solo virtual" del discovery.
///   - [listAll]: Firestore `orderBy displayNameLowercase ASC` with limit 50.
///     Optional [specialty] filter applied client-side.
///   - [getById]: single doc read, returns null if `!exists` (D12).
///
/// REQ-COACH-DISC-DATA-004..007.
class TrainerPublicProfileRepository {
  TrainerPublicProfileRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  /// Upper bound sentinel for geohash prefix range queries.
  static const _upperBoundSuffix = '￿';

  CollectionReference<Map<String, Object?>> get _col =>
      _firestore.collection('trainerPublicProfiles');

  /// Saca los perfiles con `hiddenFromDiscovery == true` (cuentas internas, de
  /// QA o de revisores de las tiendas). Es client-side a propósito: un
  /// `where('hiddenFromDiscovery', isEqualTo: false)` excluiría los docs que
  /// no tienen el campo (casi todos) y pediría un índice compuesto nuevo.
  /// Se aplica a TODO listado que ve el alumno; [getById] no lo usa.
  ///
  /// También saca al PF que pausó los alumnos nuevos (`acceptingAthletes`):
  /// mostrarlo en el mapa sería ofrecer a alguien que no puede tomar a nadie.
  /// Mismo motivo para filtrar en cliente, y [getById] tampoco lo aplica — el
  /// perfil sigue abierto por link para sus alumnos y para el que ya lo tenía.
  static bool _isVisible(TrainerPublicProfile t) =>
      !t.hiddenFromDiscovery && t.acceptingAthletes;

  /// Returns trainers whose `trainerGeohash` starts with [prefix5].
  ///
  /// Uses Firestore range query:
  ///   `>= prefix` AND `< prefix + '￿'`
  ///
  /// If [specialty] is provided, the result is filtered client-side
  /// (per D10 — no compound index needed).
  ///
  /// REQ-COACH-DISC-DATA-004, REQ-COACH-DISC-DATA-005.
  Future<List<TrainerPublicProfile>> listByGeohashPrefix(
    String prefix5, {
    TrainerSpecialty? specialty,
  }) async {
    final end = '$prefix5$_upperBoundSuffix';

    final snap = await _col
        .where('trainerGeohash', isGreaterThanOrEqualTo: prefix5)
        .where('trainerGeohash', isLessThan: end)
        .get();

    var results = snap.docs
        .map((d) => TrainerPublicProfile.fromJson(d.data()))
        .where(_isVisible)
        .toList();

    if (specialty != null) {
      results = results.where((t) => t.trainerSpecialty == specialty).toList();
    }

    return results;
  }

  /// Returns all trainers ordered by `displayNameLowercase` ASC, limit 50.
  ///
  /// If [specialty] is provided, the result is filtered client-side (D10).
  ///
  /// Ojo: los ocultos se descartan DESPUÉS del `limit(50)`, así que si hay
  /// ocultos entre los primeros 50 la lista puede traer menos de 50.
  ///
  /// REQ-COACH-DISC-DATA-006.
  Future<List<TrainerPublicProfile>> listAll({
    TrainerSpecialty? specialty,
  }) async {
    final snap = await _col.orderBy('displayNameLowercase').limit(50).get();

    var results = snap.docs
        .map((d) => TrainerPublicProfile.fromJson(d.data()))
        .where(_isVisible)
        .toList();

    if (specialty != null) {
      results = results.where((t) => t.trainerSpecialty == specialty).toList();
    }

    return results;
  }

  /// Returns the [TrainerPublicProfile] for [uid], or `null` if no doc exists.
  ///
  /// NO filtra `hiddenFromDiscovery`: abrir un perfil por uid (link, chat, las
  /// pantallas del propio PF, el flujo de los revisores) tiene que seguir
  /// andando para una cuenta oculta.
  ///
  /// REQ-COACH-DISC-DATA-007.
  Future<TrainerPublicProfile?> getById(String uid) async {
    final snap = await _col.doc(uid).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return TrainerPublicProfile.fromJson(data);
  }

  /// Igual que [getById] pero EN VIVO: emite cada vez que el documento cambia.
  ///
  /// Existe para quien mira el perfil público de un PF que él mismo edita (la
  /// vista previa del PF, #1498). Una lectura puntual se queda con lo que había
  /// al abrir —o con lo que el SDK tenía en caché— y no se entera del guardado:
  /// el PF cargaba un dato y la vista previa seguía mostrando el viejo hasta
  /// reiniciar la app. Un listener, en cambio, ve de inmediato su propia
  /// escritura local y después la confirmación del servidor.
  ///
  /// Emite `null` cuando el documento no existe, pero SÓLO si lo confirmó el
  /// servidor: con la caché fría la primera snapshot de un doc que no está
  /// llega vacía antes de que conteste el servidor, y mostrarla como un hecho
  /// pintaría «perfil no encontrado» en un PF que sí tiene perfil (ver
  /// [snapshotsSinCacheVacia]).
  ///
  /// NO filtra `hiddenFromDiscovery`, igual que [getById].
  Stream<TrainerPublicProfile?> watchById(String uid) =>
      _col.doc(uid).snapshotsSinCacheVacia().map((snap) {
        final data = snap.data();
        if (!snap.exists || data == null) return null;
        return TrainerPublicProfile.fromJson(data);
      })
          // `includeMetadataChanges` también emite los cambios que sólo tocan la
          // metadata (`hasPendingWrites`, `isFromCache`): con los mismos datos no
          // hay nada que repintar.
          .distinct();

  /// Multi-location query (Fase 6 Etapa 0).
  ///
  /// Devuelve PFs cuyo array `trainerGeohashes` contiene cualquiera de los
  /// [geohashes] provistos. Útil para buscar el geohash5 del atleta + los 8
  /// vecinos cardinales en una sola query, dedupeando client-side.
  ///
  /// Firestore tiene un límite duro de 30 valores para `array-contains-any`.
  /// Para el caso de uso actual (1-9 geohashes por consulta) estamos OK.
  ///
  /// Si [specialty] es provided, el filtro se aplica client-side.
  Future<List<TrainerPublicProfile>> listByGeohashes(
    List<String> geohashes, {
    TrainerSpecialty? specialty,
  }) async {
    if (geohashes.isEmpty) return const [];
    final snap =
        await _col.where('trainerGeohashes', arrayContainsAny: geohashes).get();
    final byUid = <String, TrainerPublicProfile>{};
    for (final d in snap.docs) {
      final profile = TrainerPublicProfile.fromJson(d.data());
      if (!_isVisible(profile)) continue;
      // Dedupe by uid — un PF con N ubicaciones cuyo geohashes solapan con
      // [geohashes] podría salir N veces; nos quedamos con la primera lectura
      // (todos los duplicates son el mismo doc).
      byUid.putIfAbsent(profile.uid, () => profile);
    }
    var results = byUid.values.toList();
    if (specialty != null) {
      results = results.where((t) => t.trainerSpecialty == specialty).toList();
    }
    return results;
  }

  /// Lista PFs que ofrecen clases virtuales (`trainerOffersOnline: true`),
  /// sin filtro de ubicación.
  ///
  /// Usado por el chip "Solo virtual" — útil para atletas que quieren un PF
  /// remoto independientemente de su ubicación física.
  Future<List<TrainerPublicProfile>> listVirtualOnly({
    TrainerSpecialty? specialty,
  }) async {
    final snap = await _col.where('trainerOffersOnline', isEqualTo: true).get();
    var results = snap.docs
        .map((d) => TrainerPublicProfile.fromJson(d.data()))
        .where(_isVisible)
        .toList();
    if (specialty != null) {
      results = results.where((t) => t.trainerSpecialty == specialty).toList();
    }
    return results;
  }
}
