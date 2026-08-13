import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Uploads a trainer's tutorial video from Flutter Web.
///
/// The mobile [CustomExerciseVideoUploadService] uses `dart:io File` + `putFile`
/// which don't run on web (same situation the avatar uploader documents). Here
/// we pick the file with `file_picker` (bytes come back inline on web) and push
/// them with `putData`. Same Storage path / contentType allowlist as mobile —
/// `customExerciseVideos/{uid}/{id}.{ext}` — so storage.rules already cover it
/// and the athlete plays it back through the same [ExerciseVideoPlayer].
class CustomExerciseVideoWebUploader {
  CustomExerciseVideoWebUploader({FirebaseStorage? storage, FirebaseAuth? auth})
      : _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  /// Matches the storage.rules contentType check.
  static const _allowed = {'mp4', 'mov', 'm4v'};

  /// Opens the OS file picker (video only), uploads the chosen file and returns
  /// its HTTPS download URL. Returns `null` when the trainer cancels the picker.
  /// [onProgress] receives a 0..1 fraction for the progress bar.
  Future<String?> pickAndUpload({
    void Function(double fraction)? onProgress,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      throw StateError('No pudimos leer el archivo de video.');
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No hay usuario autenticado para subir el video.');
    }

    final rawExt = (file.extension ?? '').toLowerCase();
    final ext = _allowed.contains(rawExt) ? rawExt : 'mp4';
    final fileName =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}.$ext';
    final ref =
        _storage.ref().child('customExerciseVideos/${user.uid}/$fileName');
    final task = ref.putData(
      bytes,
      SettableMetadata(contentType: _contentTypeFor(ext)),
    );
    if (onProgress != null) {
      task.snapshotEvents.listen((s) {
        if (s.totalBytes > 0) onProgress(s.bytesTransferred / s.totalBytes);
      });
    }
    final snapshot = await task;
    return snapshot.ref.getDownloadURL();
  }

  String _contentTypeFor(String ext) => switch (ext) {
        'mov' => 'video/quicktime',
        'm4v' => 'video/x-m4v',
        _ => 'video/mp4',
      };
}

final customExerciseVideoWebUploaderProvider =
    Provider<CustomExerciseVideoWebUploader>(
  (_) => CustomExerciseVideoWebUploader(),
);
