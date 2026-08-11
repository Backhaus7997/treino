import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Uploaded object: the download URL plus the object path behind it.
///
/// Both travel together because the Firestore doc stores both — the URL to
/// render and the path to delete. Keeping them paired at the type level is what
/// stops one from being persisted without the other (the rules reject that, and
/// deny `update` outright so they can never drift apart later).
class SessionFeedbackPhoto {
  const SessionFeedbackPhoto({required this.downloadUrl, required this.path});

  final String downloadUrl;
  final String path;
}

/// Uploads the optional photo attached to an exercise feedback entry (#628) to
/// `sessionFeedback/{uid}/{sessionId}/{feedbackId}.{ext}`.
///
/// Follows the same mobile-first pattern as [PostPhotoUploadService] — `dart:io`
/// + putFile, pure helpers testable without platform channels, and a client-side
/// size guard mirroring the bound in storage.rules.
///
/// Unlike post photos, this object is **health data**: it may show where it
/// hurts. The read rule in storage.rules is gated on `session_shares` rather
/// than "any signed-in user", and the path is uid-first so the account-deletion
/// cascade can wipe it with a single prefix.
class SessionFeedbackPhotoUploadService {
  SessionFeedbackPhotoUploadService({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Unit-test constructor — skips Firebase init so the pure helpers can be
  /// tested without platform channels.
  SessionFeedbackPhotoUploadService.testable()
      : _storage = null,
        _auth = null;

  final FirebaseStorage? _storage;
  final FirebaseAuth? _auth;

  static const int _maxImageBytes = 15 * 1024 * 1024; // 15 MB

  /// Uploads [localPath] as the photo for [feedbackId] in [sessionId].
  ///
  /// The feedback doc id is allocated before the upload so the Storage object
  /// references the real document from the first byte (same ordering as
  /// [PostPhotoUploadService]).
  ///
  /// Throws [StateError] when nobody is signed in, [ArgumentError] when the file
  /// is over 15 MB or is not a supported image.
  Future<SessionFeedbackPhoto> upload(
    String localPath, {
    required String sessionId,
    required String feedbackId,
  }) async {
    assert(_auth != null && _storage != null,
        'Use SessionFeedbackPhotoUploadService() not .testable() for uploads.');

    final user = _auth!.currentUser;
    if (user == null) {
      throw StateError('No hay usuario autenticado para subir la foto.');
    }

    final file = File(localPath);
    guardSize(sizeBytes: await file.length());

    final ext = extensionFor(localPath);
    final contentType = contentTypeForExt(ext);
    if (!contentType.startsWith('image/')) {
      // storage.rules would reject the write anyway; guarding here turns an
      // opaque permission-denied into an actionable error before spending the
      // upload.
      throw ArgumentError.value(
          localPath, 'localPath', 'El archivo no es una imagen soportada.');
    }

    final path = buildPath(
      uid: user.uid,
      sessionId: sessionId,
      feedbackId: feedbackId,
      ext: ext,
    );
    final task = await _storage!.ref().child(path).putFile(
          file,
          SettableMetadata(contentType: contentType),
        );
    return SessionFeedbackPhoto(
      downloadUrl: await task.ref.getDownloadURL(),
      path: path,
    );
  }

  /// Deletes the object at [path]. Best-effort: returns false when the object is
  /// already gone (benign — same contract as the other upload services).
  ///
  /// Called on two paths: cleanup when the Firestore write fails after the
  /// upload succeeded, and when the athlete deletes their own entry.
  Future<bool> deleteByPath(String path) async {
    assert(_storage != null,
        'Use SessionFeedbackPhotoUploadService() not .testable() for deletes.');
    try {
      await _storage!.ref(path).delete();
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return false;
      rethrow;
    }
  }

  // ─── Pure helpers (testable without Firebase) ───────────────────────────

  /// Maps a lowercased, dot-less extension to its image MIME type. Unknown
  /// extensions fall to `application/octet-stream`, which [upload] rejects.
  String contentTypeForExt(String ext) {
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'heic' => 'image/heic',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }

  /// Lowercased extension without the dot. `'jpg'` when absent — image_picker
  /// always emits JPEG in that case.
  String extensionFor(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return 'jpg';
    return path.substring(dot + 1).toLowerCase();
  }

  /// Throws [ArgumentError] when [sizeBytes] exceeds 15 MB.
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

  /// `sessionFeedback/{uid}/{sessionId}/{feedbackId}.{ext}` — mirrors the match
  /// in storage.rules.
  ///
  /// uid first is deliberate: the account-deletion cascade deletes by prefix,
  /// and `chatMedia/{chatId}/{uid}/…` already showed what happens when the uid
  /// is not the first segment (the cascade has to iterate every chat).
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
