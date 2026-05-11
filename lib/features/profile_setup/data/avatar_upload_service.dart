import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Sube el avatar local del atleta a Firebase Storage en el bucket de `treino-dev`,
/// path `avatars/{uid}.jpg`, y devuelve la URL HTTPS descargable.
///
/// Pre-flight Firebase Console (Etapa 6): el bucket de Storage tiene que estar
/// creado en `southamerica-east1` con reglas que permitan al usuario escribir
/// sólo en `avatars/{uid}.*`. Sin eso, las llamadas explotan en runtime.
class AvatarUploadService {
  AvatarUploadService({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  /// Sube [localPath] como avatar del usuario autenticado.
  /// Throws [StateError] si no hay usuario logueado.
  Future<String> upload(String localPath) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No hay usuario autenticado para subir el avatar.');
    }
    final ref = _storage.ref().child('avatars/${user.uid}.jpg');
    final task = await ref.putFile(
      File(localPath),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return task.ref.getDownloadURL();
  }
}
