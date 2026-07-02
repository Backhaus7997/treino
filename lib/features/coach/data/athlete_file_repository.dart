import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../domain/athlete_file.dart';

/// Error thrown when the picked file exceeds [AthleteFileRepository.maxBytes].
class AthleteFileTooLargeException implements Exception {
  const AthleteFileTooLargeException(this.bytes);
  final int bytes;
  @override
  String toString() => 'AthleteFileTooLargeException($bytes bytes)';
}

/// Repository de archivos privados del PF sobre un alumno.
///
/// - Firestore: colección `athlete_files/{id}` con metadatos.
/// - Storage: `athleteFiles/{trainerId}_{athleteId}/{timestamp}.{ext}` con
///   el binario.
/// - Rules gate: trainer-only en ambos lados (ver `firestore.rules` y
///   `storage.rules`).
class AthleteFileRepository {
  AthleteFileRepository({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
  })  : _firestore = firestore,
        _storage = storage;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  /// Max 10 MB por archivo. Storage rule también aplica este cap.
  static const int maxBytes = 10 * 1024 * 1024;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('athlete_files');

  String _docId(String trainerId, String athleteId, String timestamp) =>
      '${trainerId}_${athleteId}_$timestamp';

  String _storagePath(String trainerId, String athleteId, String timestamp,
      String ext) {
    final safeExt = ext.isEmpty ? 'bin' : ext.toLowerCase();
    return 'athleteFiles/${trainerId}_$athleteId/$timestamp.$safeExt';
  }

  /// Sube [bytes] al Storage y crea el doc de metadata en Firestore.
  /// Devuelve el [AthleteFile] persistido.
  ///
  /// Throws [AthleteFileTooLargeException] si `bytes.length > maxBytes`.
  Future<AthleteFile> upload({
    required String trainerId,
    required String athleteId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    if (bytes.length > maxBytes) {
      throw AthleteFileTooLargeException(bytes.length);
    }

    final now = DateTime.now();
    final timestamp = now.microsecondsSinceEpoch.toString();
    final ext = _extensionFor(fileName, contentType);
    final path = _storagePath(trainerId, athleteId, timestamp, ext);
    final ref = _storage.ref().child(path);

    // Upload bytes with the declared contentType so Storage rules pass and
    // the browser gets the right handler on download.
    final task = ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    final snapshot = await task;
    final downloadUrl = await snapshot.ref.getDownloadURL();

    final kind = kindFor(contentType);
    final id = _docId(trainerId, athleteId, timestamp);
    final file = AthleteFile(
      id: id,
      trainerId: trainerId,
      athleteId: athleteId,
      fileName: fileName,
      kind: kind,
      contentType: contentType,
      sizeBytes: bytes.length,
      storagePath: path,
      downloadUrl: downloadUrl,
      uploadedAt: now,
    );
    await _collection.doc(id).set(file.toJson());
    return file;
  }

  /// Watch reactivo de la lista de archivos del par PF↔alumno, ordenados
  /// más nuevos arriba.
  Stream<List<AthleteFile>> watch(String trainerId, String athleteId) {
    return _collection
        .where('trainerId', isEqualTo: trainerId)
        .where('athleteId', isEqualTo: athleteId)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map(_fromDoc)
            .whereType<AthleteFile>()
            .toList(growable: false));
  }

  /// Borra el archivo del Storage y luego el doc de Firestore. Si Storage
  /// falla con `object-not-found` (archivo huérfano), igual borramos el doc.
  Future<void> delete(AthleteFile file) async {
    try {
      await _storage.ref(file.storagePath).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
      developer.log(
        'AthleteFileRepository: storage object missing for ${file.id} — '
        'proceeding to delete the Firestore doc anyway.',
      );
    }
    await _collection.doc(file.id).delete();
  }

  AthleteFile? _fromDoc(QueryDocumentSnapshot<Map<String, Object?>> snap) {
    try {
      return AthleteFile.fromJson(snap.data());
    } catch (e, st) {
      developer.log(
        'AthleteFileRepository: skipped unparseable doc ${snap.id}',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Pure helper — derives [AthleteFileKind] from a contentType so both the
  /// service and the widget layer can categorize consistently (icon, filter).
  static AthleteFileKind kindFor(String contentType) {
    if (contentType == 'application/pdf') return AthleteFileKind.pdf;
    if (contentType.startsWith('image/')) return AthleteFileKind.image;
    return AthleteFileKind.other;
  }

  /// Pure helper — extension del filename original o inferida del contentType
  /// como fallback. Usado para armar el path de Storage.
  static String _extensionFor(String fileName, String contentType) {
    final dot = fileName.lastIndexOf('.');
    if (dot > 0 && dot < fileName.length - 1) {
      return fileName.substring(dot + 1).toLowerCase();
    }
    switch (contentType) {
      case 'application/pdf':
        return 'pdf';
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      default:
        return 'bin';
    }
  }
}
