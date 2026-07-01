import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../domain/media_type.dart';

/// Uploads chat media (photos and videos) to Firebase Storage under
/// `chatMedia/{chatId}/{uid}/{ts}.{ext}` and returns the HTTPS download URL.
///
/// **Abstract cross-platform contract**. See:
///   - [ChatMediaUploadServiceMobile] — uses `dart:io.File` + `putFile`
///     (native mobile / desktop).
///   - `ChatMediaUploadServiceWeb` — uses `putData(bytes)` because
///     `dart:io.File` does not compile in web builds (Fase W2 V2,
///     2026-07-01). The web impl reads the picked file via
///     `XFile.readAsBytes()`.
///
/// The provider [chatMediaUploadServiceProvider] picks the right impl at
/// runtime via `kIsWeb`, so callers depend on this abstract class and never
/// touch the concrete type.
///
/// The pure helpers (`contentTypeForExt`, `guardSize`, `buildPath`,
/// `extensionFor`) live on this base class so both impls share them —
/// avoids duplication between mobile and web.
abstract class ChatMediaUploadService {
  const ChatMediaUploadService();

  static const int _maxImageBytes = 15 * 1024 * 1024; // 15 MB
  static const int _maxVideoBytes = 100 * 1024 * 1024; // 100 MB

  // ─── Public upload API ──────────────────────────────────────────────────

  /// Uploads [localPath] to Storage and returns the download URL.
  ///
  /// [chatId] is the Firestore chat doc id.
  /// [mediaType] determines the contentType and size limit.
  /// [onProgress] receives a 0..1 fraction for progress bar rendering.
  ///
  /// On web, [localPath] is treated as a "handle" the impl already knows
  /// how to resolve to bytes (typically the `XFile.path` returned by
  /// `image_picker` web, which is a blob URL).
  ///
  /// Throws [ArgumentError] if the file exceeds the allowed size.
  /// Throws [StateError] if no user is authenticated.
  Future<String> upload(
    String localPath, {
    required String chatId,
    required MediaType mediaType,
    void Function(double fraction)? onProgress,
  });

  /// Deletes the Storage object identified by its download URL.
  /// Returns false if the URL is not a Firebase Storage URL or the object
  /// is already gone — both are benign (mirrors CustomExerciseVideoUploadService).
  Future<bool> deleteByDownloadUrl(String url);

  // ─── Testable pure helpers (shared between impls) ───────────────────────

  /// Maps a file extension (lowercased, no dot) to a MIME content type.
  /// Falls back to `application/octet-stream` for unknown extensions.
  String contentTypeForExt(String ext) {
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'heic' => 'image/heic',
      'webp' => 'image/webp',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'm4v' => 'video/x-m4v',
      _ => 'application/octet-stream',
    };
  }

  /// Extracts the lowercased extension from a file path (without the dot).
  /// Returns empty string if there is no extension.
  String extensionFor(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  /// Throws [ArgumentError] if [sizeBytes] exceeds the per-[mediaType] limit.
  /// Images: 15 MB max. Videos: 100 MB max.
  void guardSize({required int sizeBytes, required MediaType mediaType}) {
    final limit = switch (mediaType) {
      MediaType.image => _maxImageBytes,
      MediaType.video => _maxVideoBytes,
    };
    if (sizeBytes > limit) {
      throw ArgumentError.value(
        sizeBytes,
        'sizeBytes',
        'El archivo supera el tamaño máximo permitido para '
            '${mediaType.toJson()} (${limit ~/ (1024 * 1024)} MB).',
      );
    }
  }

  /// Builds the Storage path for a chat media file.
  /// Pattern: `chatMedia/{chatId}/{uid}/{timestamp}.{ext}`
  String buildPath({
    required String chatId,
    required String uid,
    required String ext,
    required String timestamp,
  }) {
    return 'chatMedia/$chatId/$uid/$timestamp.$ext';
  }

  /// Extracts the Storage object path from a Firebase download URL.
  /// Returns null if the URL is not recognized as a Firebase Storage URL.
  /// Shared between impls because [deleteByDownloadUrl] uses the same URL
  /// parsing regardless of platform.
  String? extractStoragePath(String url) {
    try {
      final uri = Uri.parse(url);
      // Firebase Storage download URLs have the path in the `o` query param
      // for the v0 API (https://firebasestorage.googleapis.com/v0/b/.../o/PATH?...)
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

/// Mobile/desktop implementation — reads the picked file as `dart:io.File`
/// and streams it to Storage via `putFile`.
///
/// This is the impl the app has been shipping on mobile since the SDD
/// `chat-media-messages` (PR #194); it stays byte-for-byte identical to the
/// old service (before the abstract refactor of 2026-07-01) so no regression
/// in the mobile app.
class ChatMediaUploadServiceMobile extends ChatMediaUploadService {
  ChatMediaUploadServiceMobile({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Constructor for unit tests — skips Firebase initialization so pure
  /// helper methods (contentTypeForExt, guardSize, buildPath, extensionFor)
  /// can be tested without platform channels.
  ChatMediaUploadServiceMobile.testable()
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
        'Use ChatMediaUploadServiceMobile() not .testable() for real uploads.');

    final user = _auth!.currentUser;
    if (user == null) {
      throw StateError('No hay usuario autenticado para subir el archivo.');
    }

    final file = File(localPath);
    final sizeBytes = await file.length();
    guardSize(sizeBytes: sizeBytes, mediaType: mediaType);

    final ext = extensionFor(localPath);
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final path =
        buildPath(chatId: chatId, uid: user.uid, ext: ext, timestamp: ts);
    final contentType = contentTypeForExt(ext);

    final ref = _storage!.ref().child(path);
    final task = ref.putFile(
      file,
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
        'Use ChatMediaUploadServiceMobile() not .testable() for real deletes.');

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
