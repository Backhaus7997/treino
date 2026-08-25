// ignore: unused_import — Timestamp lo usa el exercise_feedback.g.dart generado
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'exercise_feedback.freezed.dart';
part 'exercise_feedback.g.dart';

/// Qué clase de reporte es (#628).
///
/// `discomfort` NO es "un comentario más serio": es el que dispara el push al
/// PF y el que se marca distinto de su lado. Un comentario común no debería
/// vibrarle el teléfono al PF doce veces por sesión.
enum ExerciseFeedbackKind {
  @JsonValue('comment')
  comment,
  @JsonValue('discomfort')
  discomfort,
}

/// Lo que el alumno le dice a su PF, EN PALABRAS, durante la sesión y anclado
/// al ejercicio (#628).
///
/// Vive en `users/{uid}/sessions/{sessionId}/exerciseFeedback/{id}` — mismo
/// patrón que [SetLog], una subcolección de la sesión. Es deliberadamente un
/// modelo APARTE y no campos opcionales dentro de `SetLog`: ensuciar el modelo
/// numérico que consumen los agregadores de Insights y de progresión por
/// ejercicio, y encima no soportaría el feedback a nivel ejercicio (sin serie).
///
/// ⚠️ DATO DE SALUD. `kind: discomfort` describe dolor o lesión, y [photoUrl]
/// es una URL de descarga con token — una credencial al portador que NO pasa
/// por `storage.rules` (docs/security.md §3.1). Nunca denormalizar ninguno de
/// los dos a una colección con lectura más laxa que la del documento.
@freezed
class ExerciseFeedback with _$ExerciseFeedback {
  const ExerciseFeedback._();

  const factory ExerciseFeedback({
    /// Id del documento. Sale del PATH, no del cuerpo — misma trampa que
    /// documenta `SessionRepository._setLogFromDoc`.
    required String id,
    required String exerciseId,

    /// Denormalizado igual que en [SetLog]: el PF ve el reporte sin resolver
    /// el catálogo de ejercicios, y el nombre queda congelado al momento del
    /// reporte aunque el ejercicio se renombre después.
    required String exerciseName,

    /// Serie (1-based) sobre la que se reporta. `null` = comentario a nivel
    /// ejercicio, sin serie. Eso es exactamente lo que el chat no puede dar.
    int? setNumber,

    /// Si algún día el enum crece, un cliente viejo muestra el reporte con la
    /// marca de `comment` en vez de esconderlo. Es la dirección de falla
    /// menos mala: perder el badge es recuperable, perder el reporte no.
    // ignore: invalid_annotation_target
    @JsonKey(unknownEnumValue: ExerciseFeedbackKind.comment)
    required ExerciseFeedbackKind kind,
    String? text,

    /// URL HTTPS descargable de la foto, o null.
    String? photoUrl,

    /// Object path en Storage (`sessionFeedback/{uid}/{sessionId}/{id}.{ext}`).
    /// Se guarda para poder BORRAR el objeto: sin él, borrar el documento deja
    /// la foto en el bucket con su token vivo para siempre.
    String? photoPath,
    @TimestampConverter() required DateTime createdAt,
  }) = _ExerciseFeedback;

  factory ExerciseFeedback.fromJson(Map<String, Object?> json) =>
      _$ExerciseFeedbackFromJson(json);

  /// "Nada de reportes vacíos" (#628). Espejo client-side del predicado que
  /// `firestore.rules` aplica en create/update — el guard de acá convierte un
  /// `permission-denied` opaco en un error accionable antes de gastar el
  /// write, igual que hace `PostPhotoUploadService.guardSize`.
  bool get hasContent =>
      (text?.trim().isNotEmpty ?? false) ||
      (photoUrl?.trim().isNotEmpty ?? false);

  /// Un reporte de molestia, el único que notifica al PF.
  bool get isDiscomfort => kind == ExerciseFeedbackKind.discomfort;
}
