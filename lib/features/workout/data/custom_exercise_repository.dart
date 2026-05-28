import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/custom_exercise.dart';

/// Firestore-backed repository for a trainer's personal exercise library.
///
/// Documents live at `users/{trainerId}/customExercises/{exId}` so ownership
/// is encoded in the path (rules can simply check `request.auth.uid == uid`).
/// Auto-generated doc IDs; `ownerId` field also stored in the doc body for
/// convenience when reading via collectionGroup queries in the future.
class CustomExerciseRepository {
  CustomExerciseRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> _col(String trainerId) =>
      _firestore.collection('users').doc(trainerId).collection('customExercises');

  // ─── create ────────────────────────────────────────────────────────────────

  /// Creates a new custom exercise under the trainer's subcollection. Returns
  /// the persisted entity with id + timestamps populated.
  Future<CustomExercise> create({
    required String trainerId,
    required String name,
    String muscleGroup = '',
    String description = '',
    String? videoUrl,
    int? defaultRestSeconds,
  }) async {
    final now = DateTime.now().toUtc();
    final ref = _col(trainerId).doc();
    final exercise = CustomExercise(
      id: ref.id,
      ownerId: trainerId,
      name: name,
      muscleGroup: muscleGroup,
      description: description,
      videoUrl: videoUrl,
      defaultRestSeconds: defaultRestSeconds,
      createdAt: now,
      updatedAt: now,
    );
    await ref.set(exercise.toJson()..remove('id'));
    return exercise;
  }

  // ─── update ────────────────────────────────────────────────────────────────

  /// Persists field changes and bumps `updatedAt`.
  Future<void> update(CustomExercise exercise) async {
    final next = exercise.copyWith(updatedAt: DateTime.now().toUtc());
    await _col(exercise.ownerId)
        .doc(exercise.id)
        .update(next.toJson()..remove('id'));
  }

  // ─── delete ────────────────────────────────────────────────────────────────

  /// Hard-delete. Custom exercises don't need a soft-delete trail — they're
  /// trainer-private and removing them shouldn't break anything because the
  /// routine slots already denormalize the exercise name/group at assign time.
  Future<void> delete({required String trainerId, required String id}) async {
    await _col(trainerId).doc(id).delete();
  }

  // ─── watchForTrainer ───────────────────────────────────────────────────────

  /// Live stream of the trainer's custom exercises, ordered by name asc so
  /// the picker shows them alphabetically by default.
  Stream<List<CustomExercise>> watchForTrainer(String trainerId) {
    return _col(trainerId)
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => CustomExercise.fromJson({...d.data(), 'id': d.id}))
            .toList());
  }
}
