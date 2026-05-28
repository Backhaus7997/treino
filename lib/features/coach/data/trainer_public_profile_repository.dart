import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, FirebaseFirestore;

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

    var results =
        snap.docs.map((d) => TrainerPublicProfile.fromJson(d.data())).toList();

    if (specialty != null) {
      results = results.where((t) => t.trainerSpecialty == specialty).toList();
    }

    return results;
  }

  /// Returns all trainers ordered by `displayNameLowercase` ASC, limit 50.
  ///
  /// If [specialty] is provided, the result is filtered client-side (D10).
  ///
  /// REQ-COACH-DISC-DATA-006.
  Future<List<TrainerPublicProfile>> listAll({
    TrainerSpecialty? specialty,
  }) async {
    final snap = await _col.orderBy('displayNameLowercase').limit(50).get();

    var results =
        snap.docs.map((d) => TrainerPublicProfile.fromJson(d.data())).toList();

    if (specialty != null) {
      results = results.where((t) => t.trainerSpecialty == specialty).toList();
    }

    return results;
  }

  /// Returns the [TrainerPublicProfile] for [uid], or `null` if no doc exists.
  ///
  /// REQ-COACH-DISC-DATA-007.
  Future<TrainerPublicProfile?> getById(String uid) async {
    final snap = await _col.doc(uid).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return TrainerPublicProfile.fromJson(data);
  }

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
    var results =
        snap.docs.map((d) => TrainerPublicProfile.fromJson(d.data())).toList();
    if (specialty != null) {
      results = results.where((t) => t.trainerSpecialty == specialty).toList();
    }
    return results;
  }
}
