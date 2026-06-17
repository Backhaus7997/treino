import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import 'equipment_type.dart';

part 'custom_exercise.freezed.dart';
part 'custom_exercise.g.dart';

EquipmentType? _equipmentFromJson(String? raw) => EquipmentType.fromJson(raw);
String? _equipmentToJson(EquipmentType? v) => v?.jsonValue;

/// A trainer's personal exercise — stored in their own subcollection at
/// `users/{trainerId}/customExercises/{exId}`. Same shape as the stock
/// [Exercise] catalogue but owner-scoped so each trainer builds their own
/// library (names they prefer, videos they trust, rest defaults that fit
/// their style).
///
/// `videoUrl` validation is the UI's job — the editor only saves URLs whose
/// YouTube id we successfully parsed and that the embed preview accepted.
/// The repo trusts whatever the client persists.
@freezed
class CustomExercise with _$CustomExercise {
  const factory CustomExercise({
    required String id,
    required String ownerId,
    required String name,
    @Default('') String muscleGroup,
    // Optional secondary muscle (canonical key). null = single-muscle exercise.
    String? secondaryMuscleGroup,
    @Default('') String description,
    String? videoUrl,
    int? defaultRestSeconds,
    // ignore: invalid_annotation_target
    @JsonKey(fromJson: _equipmentFromJson, toJson: _equipmentToJson)
    EquipmentType?
        equipment, // REQ-RER-015: nullable; stays null on existing docs (no backfill — ADR-RER-03)
    @TimestampConverter() required DateTime createdAt,
    @TimestampConverter() required DateTime updatedAt,
  }) = _CustomExercise;

  factory CustomExercise.fromJson(Map<String, Object?> json) =>
      _$CustomExerciseFromJson(json);
}
