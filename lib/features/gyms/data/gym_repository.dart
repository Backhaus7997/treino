import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show
        CollectionReference,
        DocumentSnapshot,
        FieldPath,
        FirebaseFirestore,
        SetOptions;

import '../domain/gym.dart';

/// Lecturas + create self-service de `gyms/{gymId}`.
///
/// El catálogo está poblado por `scripts/seed_gyms.js` (`source: seed`).
/// Los PFs pueden agregar gyms nuevos vía `createSelfService()` (PR#5 del
/// rediseño multi-location); esos quedan con `source: self-service` y
/// `createdBy` apuntando al uid del PF para auditoría.
///
/// Update/delete NO se exponen client-side. Si hace falta moderar (gyms
/// duplicados o spam), se hace via Console o un Cloud Function privilegiado.
class GymRepository {
  GymRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('gyms');

  /// Trae el catálogo completo. ~20 docs en MVP — suficiente para listAll
  /// sin paginación. Cuando crezca a >100 gyms, se va a paginar por
  /// ciudad/región.
  Future<List<Gym>> listAll() async {
    final snap = await _collection.get();
    return snap.docs.map(_fromDoc).whereType<Gym>().toList();
  }

  Future<Gym?> getById(String id) async {
    final snap = await _collection.doc(id).get();
    return _fromDoc(snap);
  }

  /// Crea o actualiza `gyms/{gym.id}` con merge:true.
  ///
  /// Usado por el read-through cache client-side de `ResolveGymPlaceService`
  /// (Plan B — gym-google-places): al resolver un `place_id` nuevo, el gym
  /// se upsertea acá antes de asignarlo a `users/{uid}.gymId`.
  Future<void> upsert(Gym gym) async {
    await _collection.doc(gym.id).set(gym.toJson(), SetOptions(merge: true));
  }

  /// Batch lookup. `whereIn` está capado a 30 valores en Firestore —
  /// chunkeamos defensivamente para casos donde un PF tenga muchos gyms.
  Future<List<Gym>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    const chunkSize = 30;
    final out = <Gym>[];
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(
        i,
        i + chunkSize > ids.length ? ids.length : i + chunkSize,
      );
      final snap =
          await _collection.where(FieldPath.documentId, whereIn: chunk).get();
      out.addAll(snap.docs.map(_fromDoc).whereType<Gym>());
    }
    return out;
  }

  Gym? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    try {
      // Wrapped in try/catch so a single malformed gym doc (bad lat/lng,
      // missing geohash, etc.) is skipped instead of aborting the whole
      // catalog read — matches the resilient intent of `whereType<Gym>()`.
      //
      // `brandId`/`brandName`/`branchName` are nullable in `Gym` — decoded
      // automatically by `Gym.fromJson` (no fallback needed here) for docs
      // seeded before the two-level brand→sucursal migration.
      return Gym.fromJson({...data, 'id': snap.id});
    } catch (e, st) {
      developer.log(
        'GymRepository: skipped unparseable gym ${snap.id}',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}
