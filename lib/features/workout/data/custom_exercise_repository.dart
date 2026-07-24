import 'package:cloud_firestore/cloud_firestore.dart';

import '../application/exercise_filter.dart' show foldSearch;
import '../domain/custom_exercise.dart';
import '../domain/equipment_type.dart';
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

  CollectionReference<Map<String, Object?>> _col(String trainerId) => _firestore
      .collection('users')
      .doc(trainerId)
      .collection('customExercises');

  // ─── nameLowercase — #553 ──────────────────────────────────────────────────
  // Callers MUST NOT pass nameLowercase — it is always derived here, mirroring
  // how UserRepository derives `n`/`displayNameLowercase` (REQ-UPP-002 /
  // ADR-UPP-11). Normalized with the SAME foldSearch the exercise search uses
  // (#209), so ordering and searching agree on what "Pantorrilla" and
  // "pantorrílla" are. Kept out of the CustomExercise model on purpose: it is
  // a storage-level sort key, not a domain attribute — exactly like `n` on
  // users/{uid}.

  /// Doc payload for [exercise]: the model JSON without the path-encoded `id`,
  /// plus the derived `nameLowercase` sort key.
  Map<String, Object?> _docPayload(CustomExercise exercise) => exercise.toJson()
    ..remove('id')
    ..['nameLowercase'] = foldSearch(exercise.name);

  // ─── create ────────────────────────────────────────────────────────────────

  /// Creates a new custom exercise under the trainer's subcollection. Returns
  /// the persisted entity with id + timestamps populated.
  Future<CustomExercise> create({
    required String trainerId,
    required String name,
    String muscleGroup = '',
    String? secondaryMuscleGroup,
    String description = '',
    String? videoUrl,
    int? defaultRestSeconds,
    EquipmentType? equipment,
  }) async {
    final now = DateTime.now().toUtc();
    final ref = _col(trainerId).doc();
    final exercise = CustomExercise(
      id: ref.id,
      ownerId: trainerId,
      name: name,
      muscleGroup: muscleGroup,
      secondaryMuscleGroup: secondaryMuscleGroup,
      description: description,
      videoUrl: videoUrl,
      defaultRestSeconds: defaultRestSeconds,
      equipment: equipment,
      createdAt: now,
      updatedAt: now,
    );
    await ref.set(_docPayload(exercise));
    return exercise;
  }

  // ─── update ────────────────────────────────────────────────────────────────

  /// Persists field changes and bumps `updatedAt`. `nameLowercase` rides
  /// along on every update, so a rename keeps the sort key in lockstep (and
  /// any pre-#553 doc self-heals on its first edit).
  Future<void> update(CustomExercise exercise) async {
    final next = exercise.copyWith(updatedAt: DateTime.now().toUtc());
    await _col(exercise.ownerId).doc(exercise.id).update(_docPayload(next));
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

  /// Live stream of the trainer's custom exercises, alphabetized ignoring
  /// case and Spanish diacritics (#553) — "Pantorrilla en prensa" sorts
  /// between "dorsiflexion" and "…", not before "abdominales".
  ///
  /// The old `orderBy('name')` sorted by UTF-8 byte order, where `A`–`Z`
  /// (65–90) precede `a`–`z` (97–122), so any capitalized name jumped to the
  /// top. Sorting happens in Dart over [foldSearch] of the live name rather
  /// than `orderBy('nameLowercase')` because a server-side orderBy EXCLUDES
  /// every doc missing the field — pre-#553 docs would vanish from the picker
  /// until `backfill_custom_exercise_name_lowercase.js` runs. The stream
  /// already reads the whole (small, per-trainer) collection, so the local
  /// sort costs nothing, is byte-identical with the search normalization, and
  /// works the same before and after the backfill.
  Stream<List<CustomExercise>> watchForTrainer(String trainerId) {
    return _col(trainerId).snapshots().map((snap) {
      final list = snap.docs
          .map((d) => CustomExercise.fromJson({...d.data(), 'id': d.id}))
          .toList();
      list.sort((a, b) {
        final byFolded = foldSearch(a.name).compareTo(foldSearch(b.name));
        if (byFolded != 0) return byFolded;
        final byName = a.name.compareTo(b.name);
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
      return list;
    });
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
