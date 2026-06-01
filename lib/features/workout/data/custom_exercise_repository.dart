import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/custom_exercise.dart';
import 'custom_exercise_video_upload_service.dart';

/// Firestore-backed repository for a trainer's personal exercise library.
///
/// Documents live at `users/{trainerId}/customExercises/{exId}` so ownership
/// is encoded in the path (rules can simply check `request.auth.uid == uid`).
/// Auto-generated doc IDs; `ownerId` field also stored in the doc body for
/// convenience when reading via collectionGroup queries in the future.
class CustomExerciseRepository {
  CustomExerciseRepository({
    required FirebaseFirestore firestore,
    required CustomExerciseVideoUploadService videoUploadService,
  })  : _firestore = firestore,
        _videoUploadService = videoUploadService;

  final FirebaseFirestore _firestore;
  final CustomExerciseVideoUploadService _videoUploadService;

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
  ///
  /// If the exercise has a Firebase Storage-backed video, the underlying
  /// object is cleaned up best-effort before the doc is removed. Failures
  /// on the Storage side don't block the Firestore delete — orphan files
  /// are tolerable here, broken UI is not.
  Future<void> delete({required String trainerId, required String id}) async {
    final docRef = _col(trainerId).doc(id);
    try {
      final snap = await docRef.get();
      final url = (snap.data()?['videoUrl'] as String?)?.trim();
      if (url != null && url.isNotEmpty) {
        try {
          await _videoUploadService.deleteByDownloadUrl(url);
        } catch (_) {
          // Best-effort — proceed with the doc delete.
        }
      }
    } catch (_) {
      // Read failures still let the delete attempt go through.
    }
    await docRef.delete();
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

  // ─── getById ───────────────────────────────────────────────────────────────

  /// Single-doc fetch for a routine slot whose exercise lives in this
  /// trainer's personal library. Returns null if the doc is missing — the
  /// detail screen handles that as a "no encontrado" state instead of
  /// crashing. Reads are gated by firestore.rules: any authenticated user
  /// can read any trainer's customExercises so athletes can open the
  /// detail screen for a custom exercise referenced from a routine.
  Future<CustomExercise?> getById({
    required String trainerId,
    required String exerciseId,
  }) async {
    final snap = await _col(trainerId).doc(exerciseId).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return CustomExercise.fromJson({...data, 'id': snap.id});
  }
}
