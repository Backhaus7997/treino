import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sube la foto opcional de un reporte por ejercicio (#628) a
/// `sessionFeedback/{uid}/{sessionId}/{feedbackId}.{ext}` y devuelve la URL
/// HTTPS descargable.
///
/// Espeja a [PostPhotoUploadService] —mismos helpers puros, mismo cap de
/// 15 MB, espejo del bound en `storage.rules`— con UNA diferencia que no es
/// cosmética y conviene tener presente al tocar cualquiera de los dos:
///
/// La foto de un post la puede bajar cualquier autenticado (`allow get: if
/// request.auth != null`). Esta NO: es dato de salud, y su bloque de Storage
/// la gatea con el grant de dos partes de `session_shares`. Pero el gate que
/// de verdad la custodia no es ese — la URL que devuelve [upload] lleva
/// `?alt=media&token=` y es una credencial al portador que no evalúa
/// `storage.rules` (docs/security.md §3.1). Quien custodia la foto es el
/// documento de Firestore donde se guarda la URL. Regla práctica: esta URL
/// sólo se persiste en `exerciseFeedback`, nunca en otro lado.
class SessionFeedbackPhotoUploadService {
  SessionFeedbackPhotoUploadService({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Constructor para unit tests — saltea la init de Firebase para que los
  /// helpers puros se testeen sin platform channels.
  SessionFeedbackPhotoUploadService.testable()
      : _storage = null,
        _auth = null;

  final FirebaseStorage? _storage;
  final FirebaseAuth? _auth;

  static const int _maxImageBytes = 15 * 1024 * 1024; // 15 MB

  /// Sube [localPath] como foto del reporte [feedbackId] dentro de
  /// [sessionId], para el usuario autenticado.
  ///
  /// Throws [StateError] si no hay usuario logueado.
  /// Throws [ArgumentError] si el archivo supera 15 MB o no es una imagen.
  Future<String> upload(
    String localPath, {
    required String sessionId,
    required String feedbackId,
  }) async {
    assert(_auth != null && _storage != null,
        'Usá SessionFeedbackPhotoUploadService() y no .testable() para subir.');

    final user = _auth!.currentUser;
    if (user == null) {
      throw StateError('No hay usuario autenticado para subir la foto.');
    }

    final file = File(localPath);
    guardSize(sizeBytes: await file.length());

    final ext = extensionFor(localPath);
    final contentType = contentTypeForExt(ext);
    if (!contentType.startsWith('image/')) {
      // storage.rules rechazaría el write igual (contentType image/.*) — el
      // guard client-side convierte ese permission-denied opaco en un error
      // accionable antes de gastar el upload.
      throw ArgumentError.value(
          localPath, 'localPath', 'El archivo no es una imagen soportada.');
    }

    final ref = _storage!.ref().child(buildPath(
          uid: user.uid,
          sessionId: sessionId,
          feedbackId: feedbackId,
          ext: ext,
        ));
    final task = await ref.putFile(
      file,
      SettableMetadata(contentType: contentType),
    );
    return task.ref.getDownloadURL();
  }

  /// Borra el objeto por su object path (el `photoPath` del reporte).
  ///
  /// Se borra por PATH y no por URL a propósito: el path es lo que persiste el
  /// modelo justamente para esto, y no depende de que la URL siga siendo
  /// parseable. Devuelve false si el objeto ya no existe (benigno: el borrado
  /// es idempotente y puede reintentarse).
  Future<bool> deleteByPath(String path) async {
    assert(_storage != null,
        'Usá SessionFeedbackPhotoUploadService() y no .testable() para borrar.');
    if (path.isEmpty) return false;
    try {
      await _storage!.ref(path).delete();
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return false;
      rethrow;
    }
  }

  // ─── Helpers puros (testeables sin Firebase) ────────────────────────────

  /// Mapea una extensión (lowercased, sin punto) a su MIME type de imagen.
  /// Extensiones desconocidas caen a `application/octet-stream`, que
  /// [upload] rechaza.
  String contentTypeForExt(String ext) {
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'heic' => 'image/heic',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }

  /// Extensión lowercased de un path, sin el punto. `'jpg'` como fallback si
  /// no hay extensión — image_picker siempre emite JPEG en ese caso.
  String extensionFor(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return 'jpg';
    return path.substring(dot + 1).toLowerCase();
  }

  /// Throws [ArgumentError] si [sizeBytes] supera los 15 MB.
  void guardSize({required int sizeBytes}) {
    if (sizeBytes > _maxImageBytes) {
      throw ArgumentError.value(
        sizeBytes,
        'sizeBytes',
        'La foto supera el tamaño máximo permitido '
            '(${_maxImageBytes ~/ (1024 * 1024)} MB).',
      );
    }
  }

  /// Path de Storage de la foto de un reporte:
  /// `sessionFeedback/{uid}/{sessionId}/{feedbackId}.{ext}` — espejo EXACTO
  /// del match en `storage.rules`. Los tres segmentos importan: la regla pide
  /// exactamente tres wildcards, así que un path con más o menos niveles cae
  /// en el catch-all y se deniega.
  String buildPath({
    required String uid,
    required String sessionId,
    required String feedbackId,
    required String ext,
  }) {
    return 'sessionFeedback/$uid/$sessionId/$feedbackId.$ext';
  }
}

final sessionFeedbackPhotoUploadServiceProvider =
    Provider<SessionFeedbackPhotoUploadService>(
  (_) => SessionFeedbackPhotoUploadService(),
);
