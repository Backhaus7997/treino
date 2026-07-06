import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/nutrition_plan.dart';

/// Repository of PF-authored nutrition plans (Coach Hub web).
///
/// - Firestore doc at `nutrition_plans/{trainerId}_{athleteId}`. Single plan
///   per pair — every save overwrites the previous version.
/// - Trainer-only in rules (see `firestore.rules`).
/// - No composite index needed (queried by doc id).
class NutritionPlanRepository {
  NutritionPlanRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('nutrition_plans');

  String _docId(String trainerId, String athleteId) =>
      '${trainerId}_$athleteId';

  /// Watch reactivo del plan del par PF↔alumno. Emite `null` cuando el doc
  /// no existe todavía.
  Stream<NutritionPlan?> watch(String trainerId, String athleteId) {
    return _collection
        .doc(_docId(trainerId, athleteId))
        .snapshots()
        .map(_fromDoc);
  }

  /// One-shot fetch. Devuelve `null` si no existe.
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
    await _collection.doc(id).set(withNow.toJson());
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
      return null;
    }
  }
}
