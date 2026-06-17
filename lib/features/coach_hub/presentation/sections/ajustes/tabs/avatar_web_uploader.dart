import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Se lanza cuando la imagen elegida supera el máximo permitido (2 MB),
/// coincidiendo con el copy de la UI ("máximo 2MB").
class AvatarTooLargeException implements Exception {
  const AvatarTooLargeException(this.bytes);

  final int bytes;

  @override
  String toString() => 'AvatarTooLargeException($bytes bytes)';
}

/// Sube el avatar del PF en Flutter Web (Fase W3.1b).
///
/// El [AvatarUploadService] del mobile (`profile_setup`) usa `dart:io File` +
/// `putFile`, que NO corre en web. Acá usamos `putData` sobre los bytes que
/// devuelve el picker. Mismo bucket/path/reglas que el mobile:
/// `avatars/{uid}.jpg`, contentType `image/jpeg`.
///
/// TODO(tech-debt): unificar con AvatarUploadService usando `putData` en ambas
/// plataformas (vive en profile_setup, fuera del scope de la sección ajustes).
class AvatarWebUploader {
  AvatarWebUploader({
    ImagePicker? picker,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _picker = picker ?? ImagePicker(),
        _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Máximo de bytes aceptado (2 MB) — coincide con el copy de la UI.
  static const int maxBytes = 2 * 1024 * 1024;

  final ImagePicker _picker;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  /// Abre el picker, valida el tamaño, sube la imagen y devuelve la URL
  /// descargable. Devuelve `null` si el usuario cancela el picker.
  /// Throws [AvatarTooLargeException] si supera [maxBytes].
  /// Throws [StateError] si no hay usuario autenticado.
  Future<String?> pickAndUpload() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (file == null) return null;

    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No hay usuario autenticado para subir el avatar.');
    }

    final bytes = await file.readAsBytes();
    // `image_picker` en web ignora maxWidth/imageQuality, así que validamos los
    // bytes reales acá (la regla de Storage admite hasta 5MB, pero el producto
    // promete 2MB).
    if (bytes.lengthInBytes > maxBytes) {
      throw AvatarTooLargeException(bytes.lengthInBytes);
    }

    final ref = _storage.ref().child('avatars/${user.uid}.jpg');
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return task.ref.getDownloadURL();
  }

  /// Borra el objeto de Storage del avatar (best-effort). NO lanza si el objeto
  /// no existe (nunca se subió / otra extensión) — limpiar la referencia en
  /// Firestore es lo que importa para el usuario.
  Future<void> deleteStored() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _storage.ref().child('avatars/${user.uid}.jpg').delete();
    } catch (_) {
      // Best-effort: object-not-found u otros — no es un error para el usuario.
    }
  }
}

final avatarWebUploaderProvider = Provider<AvatarWebUploader>(
  (_) => AvatarWebUploader(),
);
