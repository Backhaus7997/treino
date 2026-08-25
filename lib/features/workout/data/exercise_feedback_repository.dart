import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore;

import '../domain/exercise_feedback.dart';

/// Acceso a `users/{uid}/sessions/{sessionId}/exerciseFeedback` (#628).
///
/// Repositorio APARTE de [SessionRepository] a propósito, por dos motivos:
///
///  1. `session_repository.dart` es el archivo caliente del entreno — lo toca
///     el player, el reloj y el historial. Sumarle una subcolección más lo
///     convierte en el cajón de sastre de todo lo que cuelga de una sesión.
///  2. Esto es dato de SALUD y tiene su propio contrato de reglas, su propia
///     foto en Storage y su propio paso de cascade. Que viva en su propio
///     archivo hace que quien lo lea vea ese contrato completo de una.
///
/// El PF lo lee con el MISMO repositorio, cross-user, gateado por
/// `session_shares` del lado de las reglas — no hay una variante "de coach".
class ExerciseFeedbackRepository {
  ExerciseFeedbackRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> _feedback(
    String uid,
    String sessionId,
  ) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .doc(sessionId)
          .collection('exerciseFeedback');

  /// Aloca un id client-side ANTES de subir la foto, para que el objeto de
  /// Storage (`sessionFeedback/{uid}/{sessionId}/{id}.{ext}`) referencie al
  /// documento real desde el primer byte. Mismo truco que `PostRepository`
  /// con `newPostId`.
  String newFeedbackId(String uid, String sessionId) =>
      _feedback(uid, sessionId).doc().id;

  /// Persiste un reporte. El id del documento sale de [feedback].
  ///
  /// Throws [ArgumentError] si el reporte no tiene ni texto ni foto — es la
  /// misma regla que `firestore.rules` aplica del lado del servidor, y
  /// chequearla acá convierte un `permission-denied` opaco en un error
  /// accionable.
  Future<ExerciseFeedback> add({
    required String uid,
    required String sessionId,
    required ExerciseFeedback feedback,
  }) async {
    if (!feedback.hasContent) {
      throw ArgumentError.value(
        feedback,
        'feedback',
        'Un reporte necesita al menos texto o foto.',
      );
    }
    await _feedback(uid, sessionId).doc(feedback.id).set(feedback.toJson());
    return feedback;
  }

  /// Borra un reporte. NO borra la foto de Storage: eso lo hace el llamador
  /// con `photoPath`, porque el repositorio no conoce Storage. Un borrado que
  /// deje el objeto huérfano deja dato de salud en el bucket con su token de
  /// descarga vivo (docs/security.md §3.1).
  Future<void> delete({
    required String uid,
    required String sessionId,
    required String feedbackId,
  }) async {
    await _feedback(uid, sessionId).doc(feedbackId).delete();
  }

  /// Los reportes de una sesión, del más viejo al más nuevo — el mismo orden
  /// en el que ocurrieron durante el entreno.
  Future<List<ExerciseFeedback>> list({
    required String uid,
    required String sessionId,
  }) async {
    if (uid.isEmpty || sessionId.isEmpty) return const <ExerciseFeedback>[];
    final snap = await _feedback(uid, sessionId).orderBy('createdAt').get();
    return snap.docs.map(_fromDoc).whereType<ExerciseFeedback>().toList();
  }

  /// Stream vivo de los reportes de una sesión.
  ///
  /// Existe por la misma razón que `watchSetLogs`: el player está abierto
  /// mientras el atleta reporta, y una lectura única dejaría la lista vieja.
  Stream<List<ExerciseFeedback>> watch({
    required String uid,
    required String sessionId,
  }) {
    if (uid.isEmpty || sessionId.isEmpty) {
      return Stream.value(const <ExerciseFeedback>[]);
    }
    return _feedback(uid, sessionId).orderBy('createdAt').snapshots().map(
        (s) => s.docs.map(_fromDoc).whereType<ExerciseFeedback>().toList());
  }

  ExerciseFeedback? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    try {
      // El id sale del path, no del cuerpo — misma razón que en
      // `SessionRepository._setLogFromDoc`: si alguna vez no coincidieran, un
      // delete por el id del cuerpo apuntaría a un documento que no existe.
      //
      // Y va envuelto por la misma razón: un reporte que no parsea no puede
      // llevarse puestos a los demás. Del lado del PF eso significaría que una
      // molestia reportada no se ve porque OTRA está mal formada.
      return ExerciseFeedback.fromJson({...data, 'id': snap.id});
    } catch (e, st) {
      developer.log(
        'ExerciseFeedbackRepository: reporte no parseable ${snap.id}',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}
