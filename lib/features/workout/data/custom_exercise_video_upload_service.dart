import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../presentation/widgets/exercise_video_player.dart'
    show extractFirebaseStoragePath;

/// Uploads a trainer's tutorial video to Firebase Storage under
/// `customExerciseVideos/{uid}/{fileName}` and returns the HTTPS download
/// URL the editor stores in `CustomExercise.videoUrl`.
///
/// Companion deletion helper [deleteByDownloadUrl] is the inverse — given
/// the download URL we round-trip back to the object path so the file can
/// be cleaned up when a custom exercise is removed.
class CustomExerciseVideoUploadService {
  CustomExerciseVideoUploadService({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  /// Uploads [localPath] (a video file on disk) for the authenticated user
  /// and returns the public download URL. The path inside Storage is
  /// `customExerciseVideos/{uid}/{generatedId}.{ext}` — the id is generated
  /// upfront so the URL is stable before the CustomExercise doc is saved.
  ///
  /// [onProgress] receives a 0..1 fraction so the editor can render a
  /// progress bar.
  Future<String> upload(
    String localPath, {
    void Function(double fraction)? onProgress,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No hay usuario autenticado para subir el video.');
    }
    final ext = _extensionFor(localPath);
    final fileName =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}.$ext';
    final ref =
        _storage.ref().child('customExerciseVideos/${user.uid}/$fileName');
    final task = ref.putFile(
      File(localPath),
      SettableMetadata(contentType: _contentTypeFor(ext)),
    );
    if (onProgress != null) {
      task.snapshotEvents.listen((s) {
        if (s.totalBytes <= 0) return;
        onProgress(s.bytesTransferred / s.totalBytes);
      });
    }
    final snapshot = await task;
    return snapshot.ref.getDownloadURL();
  }

  /// Best-effort delete of the Storage object behind a download URL. Used
  /// by the repository when a custom exercise that owns an uploaded video
  /// is removed. Returns false if the URL isn't a Firebase Storage URL or
  /// the object is missing — both are benign.
  Future<bool> deleteByDownloadUrl(String url) async {
    final path = extractFirebaseStoragePath(url);
    if (path == null) return false;
    try {
      await _storage.ref(path).delete();
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return false;
      rethrow;
    }
  }

  String _extensionFor(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return 'mp4';
    final ext = path.substring(dot + 1).toLowerCase();
    // Allowlist matches the storage.rules contentType check.
    const allowed = {'mp4', 'mov', 'm4v'};
    return allowed.contains(ext) ? ext : 'mp4';
  }

  String _contentTypeFor(String ext) {
    switch (ext) {
      case 'mov':
        return 'video/quicktime';
      case 'm4v':
        return 'video/x-m4v';
      default:
        return 'video/mp4';
    }
  }
}
