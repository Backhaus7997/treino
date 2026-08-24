import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/exercise_feedback_repository.dart';
import '../data/session_feedback_photo_upload_service.dart';
import '../domain/exercise_feedback.dart';
import 'exercise_feedback_providers.dart';

/// Orquesta el envío de un reporte por ejercicio (#628): aloca el id, sube la
/// foto si hay, y escribe el documento.
///
/// Está fuera del widget a propósito. El orden importa y el caso de falla
/// también: si la foto sube pero el write del documento revienta, el objeto
/// queda en el bucket **sin nadie que lo referencie** — dato de salud
/// huérfano, con su URL de descarga viva, que el cascade de borrado de cuenta
/// sí barre pero que nadie más va a mirar nunca. Por eso el rollback de la
/// foto es parte de esta clase y no una cortesía del que llame.
class ExerciseFeedbackSubmitter {
  ExerciseFeedbackSubmitter({
    required ExerciseFeedbackRepository repository,
    required SessionFeedbackPhotoUploadService photoUploader,
  })  : _repository = repository,
        _photoUploader = photoUploader;

  final ExerciseFeedbackRepository _repository;
  final SessionFeedbackPhotoUploadService _photoUploader;

  /// Sube (si hay foto) y persiste el reporte. Devuelve lo que quedó guardado.
  ///
  /// Throws [ArgumentError] si no hay ni texto ni foto — la misma regla que
  /// aplica `firestore.rules`, chequeada acá para no gastar un upload.
  Future<ExerciseFeedback> submit({
    required String uid,
    required String sessionId,
    required String exerciseId,
    required String exerciseName,
    required ExerciseFeedbackKind kind,
    int? setNumber,
    String? text,
    String? localPhotoPath,
    DateTime? now,
  }) async {
    final trimmed = text?.trim();
    final hasText = trimmed != null && trimmed.isNotEmpty;
    final hasPhoto = localPhotoPath != null && localPhotoPath.isNotEmpty;
    if (!hasText && !hasPhoto) {
      throw ArgumentError('Un reporte necesita al menos texto o foto.');
    }

    final id = _repository.newFeedbackId(uid, sessionId);

    String? photoUrl;
    String? photoPath;
    if (hasPhoto) {
      photoUrl = await _photoUploader.upload(
        localPhotoPath,
        sessionId: sessionId,
        feedbackId: id,
      );
      photoPath = _photoUploader.buildPath(
        uid: uid,
        sessionId: sessionId,
        feedbackId: id,
        ext: _photoUploader.extensionFor(localPhotoPath),
      );
    }

    final feedback = ExerciseFeedback(
      id: id,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      setNumber: setNumber,
      kind: kind,
      text: hasText ? trimmed : null,
      photoUrl: photoUrl,
      photoPath: photoPath,
      createdAt: now ?? DateTime.now(),
    );

    try {
      return await _repository.add(
        uid: uid,
        sessionId: sessionId,
        feedback: feedback,
      );
    } catch (_) {
      // Rollback best-effort: sin el documento, la foto no la referencia
      // nadie. Si el borrado también falla, que gane el error original — el
      // usuario tiene que enterarse de que su reporte NO se guardó.
      if (photoPath != null) {
        await _photoUploader.deleteByPath(photoPath).catchError((_) => false);
      }
      rethrow;
    }
  }
}

final exerciseFeedbackSubmitterProvider = Provider<ExerciseFeedbackSubmitter>(
  (ref) => ExerciseFeedbackSubmitter(
    repository: ref.watch(exerciseFeedbackRepositoryProvider),
    photoUploader: ref.watch(sessionFeedbackPhotoUploadServiceProvider),
  ),
);
