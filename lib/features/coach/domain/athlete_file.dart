// ignore: unused_import — Timestamp is used by the generated athlete_file.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'athlete_file.freezed.dart';
part 'athlete_file.g.dart';

/// Categorías de archivo que soporta el tab Archivos del alumno detail.
/// Wire values are stable — mapper defensivo en `athleteFileKindFromWire`.
enum AthleteFileKind {
  @JsonValue('pdf')
  pdf,
  @JsonValue('image')
  image,
  @JsonValue('other')
  other,
}

/// Private per-athlete file uploaded by the trainer (PDF o imagen).
///
/// Stored in Firestore at `athlete_files/{id}` con `id = {trainerId}_{athleteId}_{timestamp}`.
/// El archivo binario vive en Firebase Storage en
/// `athleteFiles/{trainerId}_{athleteId}/{timestamp}.{ext}`.
///
/// Trainer-only en Firestore rules + Storage rules — el alumno NO ve estos
/// archivos en ningún surface. Es una carpeta privada del PF por alumno.
@freezed
class AthleteFile with _$AthleteFile {
  const factory AthleteFile({
    required String id,
    required String trainerId,
    required String athleteId,
    required String fileName,
    required AthleteFileKind kind,
    required String contentType,
    required int sizeBytes,
    required String storagePath,
    required String downloadUrl,
    @TimestampConverter() required DateTime uploadedAt,
  }) = _AthleteFile;

  factory AthleteFile.fromJson(Map<String, Object?> json) =>
      _$AthleteFileFromJson(json);
}
