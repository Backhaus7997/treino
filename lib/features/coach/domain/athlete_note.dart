// ignore: unused_import — Timestamp is used by the generated athlete_note.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'athlete_note.freezed.dart';
part 'athlete_note.g.dart';

/// Private per-athlete coaching note written by the trainer.
/// Stored in `athlete_notes/{trainerId}_{athleteId}`. Trainer-only (rules).
@freezed
class AthleteNote with _$AthleteNote {
  const factory AthleteNote({
    required String trainerId,
    required String athleteId,
    required String note,
    @TimestampConverter() required DateTime updatedAt,
  }) = _AthleteNote;

  factory AthleteNote.fromJson(Map<String, Object?> json) =>
      _$AthleteNoteFromJson(json);
}
