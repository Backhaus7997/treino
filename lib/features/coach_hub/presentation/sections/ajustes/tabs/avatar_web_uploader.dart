import 'dart:typed_data';

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
  ///
  /// Mantenido para los tests pre-existentes; los call sites nuevos usan
  /// [pickFile] + [uploadCroppedPath] para poder intercalar el cropper.
  Future<String?> pickAndUpload() async {
    final file = await pickFile();
    if (file == null) return null;
    return uploadXFile(file);
  }

  /// Abre solo el picker y devuelve el [XFile] (o `null` si cancela). El
  /// caller decide si pasarlo por un cropper antes de [uploadXFile]/
  /// [uploadCroppedPath].
  Future<XFile?> pickFile() {
    return _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
  }

  /// Sube el path local (típicamente el devuelto por el cropper) y devuelve
  /// la URL descargable. Misma validación de tamaño que [pickAndUpload].
  Future<String> uploadCroppedPath(String path) async {
    final bytes = await XFile(path).readAsBytes();
    return _uploadBytes(bytes);
  }

  /// Sube los bytes de un [XFile] tal cual (sin pasar por crop).
  Future<String> uploadXFile(XFile file) async {
    final bytes = await file.readAsBytes();
    return _uploadBytes(bytes);
  }

  Future<String> _uploadBytes(List<int> rawBytes) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No hay usuario autenticado para subir el avatar.');
    }

    // `image_picker` en web ignora maxWidth/imageQuality, así que validamos los
    // bytes reales acá (la regla de Storage admite hasta 5MB, pero el producto
    // promete 2MB).
    if (rawBytes.length > maxBytes) {
      throw AvatarTooLargeException(rawBytes.length);
    }

    final ref = _storage.ref().child('avatars/${user.uid}.jpg');
    final task = await ref.putData(
      Uint8List.fromList(rawBytes),
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
