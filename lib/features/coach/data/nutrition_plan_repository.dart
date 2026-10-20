import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_snapshots.dart';
import '../../../core/utils/firestore_write.dart';
import '../domain/nutrition_plan.dart';

/// Repository of PF-authored nutrition plans.
///
/// - Firestore doc at `nutrition_plans/{trainerId}_{athleteId}`. Single plan
///   per pair — every save overwrites the previous version.
/// - Only the PF writes; the PF and the athlete of the pair read (see
///   `firestore.rules`). The athlete's app reads it read-only.
/// - No composite index needed (queried by doc id).
class NutritionPlanRepository {
  NutritionPlanRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('nutrition_plans');

  String _docId(String trainerId, String athleteId) =>
      '${trainerId}_$athleteId';

  /// Watch reactivo del plan del par PF↔alumno.
  ///
  /// Emite `null` sólo cuando el SERVIDOR confirma que el doc no existe
  /// (#1581): con la caché fría la primera snapshot llega vacía y desde la
  /// caché, y eso es «todavía no sé». Emitirla como `null` arrancaba los
  /// editores de los presets con GUARDAR habilitado, y un guardado pisaba el
  /// plan real. Ver `snapshotsSinCacheVacia`. `distinct()` porque con
  /// `includeMetadataChanges` también llegan las snapshots que sólo cambian la
  /// metadata.
  ///
  /// Un doc que existe y no parsea emite [NutritionPlanIlegible], no `null`.
  Stream<NutritionPlan?> watch(String trainerId, String athleteId) {
    return _collection
        .doc(_docId(trainerId, athleteId))
        .snapshotsSinCacheVacia()
        .map(_fromDoc)
        .distinct();
  }

  /// One-shot fetch. Devuelve `null` si no existe; un doc que no parsea tira
  /// [NutritionPlanIlegible].
  Future<NutritionPlan?> get(String trainerId, String athleteId) async {
    final snap = await _collection.doc(_docId(trainerId, athleteId)).get();
    return _fromDoc(snap);
  }

  /// Upsert: crea el plan si no existe, o sobrescribe si ya está. Refresca
  /// `updatedAt` server-side. El caller es responsable de que
  /// `plan.trainerId` y `plan.athleteId` coincidan con el doc id.
  Future<void> save(NutritionPlan plan) async {
    final id = _docId(plan.trainerId, plan.athleteId);
    final withNow = plan.copyWith(id: id, updatedAt: DateTime.now());
    await _collection.doc(id).set(withNow.toJson()).boundedWrite;
  }

  Future<void> delete(String trainerId, String athleteId) async {
    await _collection.doc(_docId(trainerId, athleteId)).delete();
  }

  NutritionPlan? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (data == null) return null;
    try {
      return NutritionPlan.fromJson(data);
    } catch (e, st) {
      developer.log(
        'NutritionPlanRepository: failed to parse doc ${snap.id}',
        error: e,
        stackTrace: st,
      );
      // NO `null`: el doc existe. Ver [NutritionPlanIlegible].
      Error.throwWithStackTrace(NutritionPlanIlegible(snap.id, e), st);
    }
  }
}

/// El doc del plan existe pero no se pudo leer como [NutritionPlan] (#1581).
///
/// Es un error y no un `null` a propósito: `null` significa «el alumno no
/// tiene plan», y con eso los editores arrancan de los presets con GUARDAR
/// habilitado — un guardado ahí pisa el plan que existe y no se pudo leer.
/// Como error, cada pantalla cae en su estado de «no pudimos cargar».
class NutritionPlanIlegible implements Exception {
  const NutritionPlanIlegible(this.docId, this.cause);

  final String docId;
  final Object cause;

  @override
  String toString() => 'NutritionPlanIlegible($docId): $cause';
}
