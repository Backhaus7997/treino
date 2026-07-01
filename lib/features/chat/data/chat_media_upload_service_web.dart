import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../domain/media_type.dart';
import 'chat_media_upload_service.dart';

/// Web implementation of [ChatMediaUploadService].
///
/// The mobile impl uses `dart:io.File` + `putFile`, which do not compile in
/// Flutter Web. On web, `image_picker` returns an [XFile] whose `path` is a
/// blob URL and whose bytes are read via `readAsBytes()`; those bytes are
/// then uploaded via `putData()` (Firebase Storage's web-compatible API).
///
/// The path passed to [upload] must resolve to a picker-returned [XFile] —
/// the caller wraps it via `XFile(pickerXFile.path).readAsBytes()` inside
/// this class. We accept the plain path in the abstract contract so mobile
/// call sites (which pass `file.path` directly) don't need to know they're
/// on a different platform; the web impl handles the platform-specific
/// resolution here.
///
/// Fase W2 V2 chat web, 2026-07-01. See spec `chat-media-messages`.
class ChatMediaUploadServiceWeb extends ChatMediaUploadService {
  ChatMediaUploadServiceWeb({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Constructor for unit tests — skips Firebase initialization so pure
  /// helper methods can be tested without platform channels.
  ChatMediaUploadServiceWeb.testable()
      : _storage = null,
        _auth = null;

  final FirebaseStorage? _storage;
  final FirebaseAuth? _auth;

  @override
  Future<String> upload(
    String localPath, {
    required String chatId,
    required MediaType mediaType,
    void Function(double fraction)? onProgress,
  }) async {
    assert(_auth != null && _storage != null,
        'Use ChatMediaUploadServiceWeb() not .testable() for real uploads.');

    final user = _auth!.currentUser;
    if (user == null) {
      throw StateError('No hay usuario autenticado para subir el archivo.');
    }

    // On web, the picker gives us an XFile whose `path` is a blob URL. We
    // reconstruct the XFile handle from that path and read the bytes — this
    // is the same API used by cross_file on native platforms, so it's
    // cross-platform-safe if this service is ever called from mobile too.
    final xfile = XFile(localPath);
    final bytes = await xfile.readAsBytes();
    guardSize(sizeBytes: bytes.length, mediaType: mediaType);

    final ext = extensionFor(localPath);
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final path =
        buildPath(chatId: chatId, uid: user.uid, ext: ext, timestamp: ts);
    final contentType = contentTypeForExt(ext);

    final ref = _storage!.ref().child(path);
    final task = ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
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

  @override
  Future<bool> deleteByDownloadUrl(String url) async {
    assert(_storage != null,
        'Use ChatMediaUploadServiceWeb() not .testable() for real deletes.');

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
}
