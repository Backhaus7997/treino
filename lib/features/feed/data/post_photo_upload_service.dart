import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sube la foto opcional de un post del feed a Firebase Storage bajo
/// `postPhotos/{uid}/{postId}.{ext}` y devuelve la URL HTTPS descargable.
///
/// El `postId` se aloca client-side ANTES de subir (PostRepository.newPostId)
/// así el objeto de Storage referencia al doc real desde el primer byte.
///
/// Mismo patrón mobile-first que [AvatarUploadService] (`dart:io` + putFile);
/// los helpers puros (contentTypeForExt / extensionFor / guardSize /
/// extractStoragePath) espejan los de [ChatMediaUploadService] pero acotados
/// a imágenes — 15 MB max, espejo del bound server-side en storage.rules.
class PostPhotoUploadService {
  PostPhotoUploadService({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Constructor para unit tests — saltea la init de Firebase para que los
  /// helpers puros se testeen sin platform channels.
  PostPhotoUploadService.testable()
      : _storage = null,
        _auth = null;

  final FirebaseStorage? _storage;
  final FirebaseAuth? _auth;

  static const int _maxImageBytes = 15 * 1024 * 1024; // 15 MB

  /// Sube [localPath] como foto del post [postId] del usuario autenticado.
  ///
  /// Throws [StateError] si no hay usuario logueado.
  /// Throws [ArgumentError] si el archivo supera 15 MB o no es una imagen.
  Future<String> upload(String localPath, {required String postId}) async {
    assert(_auth != null && _storage != null,
        'Use PostPhotoUploadService() not .testable() for real uploads.');

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
          postId: postId,
          ext: ext,
        ));
    final task = await ref.putFile(
      file,
      SettableMetadata(contentType: contentType),
    );
    return task.ref.getDownloadURL();
  }

  /// Borra el objeto de Storage identificado por su download URL. Best-effort
  /// para cleanup cuando el create del post falla después de subir la foto —
  /// devuelve false si la URL no es de Firebase Storage o el objeto ya no
  /// existe (ambos benignos, mismo contrato que ChatMediaUploadService).
  Future<bool> deleteByDownloadUrl(String url) async {
    assert(_storage != null,
        'Use PostPhotoUploadService() not .testable() for real deletes.');

    final path = extractStoragePath(url);
    if (path == null) return false;
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
  /// no hay extensión — image_picker/image_cropper siempre emiten JPEG en
  /// ese caso.
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

  /// Path de Storage de la foto de un post:
  /// `postPhotos/{uid}/{postId}.{ext}` — espejo del match en storage.rules.
  String buildPath({
    required String uid,
    required String postId,
    required String ext,
  }) {
    return 'postPhotos/$uid/$postId.$ext';
  }

  /// Extrae el object path de una download URL de Firebase Storage.
  /// Null si la URL no es reconocida. Mismo parsing que
  /// ChatMediaUploadService.extractStoragePath.
  String? extractStoragePath(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.host.contains('firebasestorage.googleapis.com')) return null;
      final encoded = uri.pathSegments.lastWhere(
        (s) => s.isNotEmpty,
        orElse: () => '',
      );
      if (encoded.isEmpty) return null;
      return Uri.decodeComponent(encoded);
    } catch (_) {
      return null;
    }
  }
}

final postPhotoUploadServiceProvider = Provider<PostPhotoUploadService>(
  (_) => PostPhotoUploadService(),
);
