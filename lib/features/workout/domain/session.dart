// ignore: unused_import — Timestamp is used by the generated session.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import 'session_status.dart';

part 'session.freezed.dart';
part 'session.g.dart';

@freezed
class Session with _$Session {
  const factory Session({
    required String id,
    required String uid,
    required String routineId,
    required String routineName,
    @TimestampConverter() required DateTime startedAt,
    @TimestampConverter() DateTime? finishedAt,
    @Default(0.0) double totalVolumeKg,
    @Default(0) int durationMin,
    required SessionStatus status,
    @Default(1) int dayNumber,
    @Default(false) bool wasFullyCompleted,
    // Periodization (Model B): 0-based week of the plan this session belongs to.
    // @Default(0) keeps single-week sessions intact and retro-compatible.
    @Default(0) int weekNumber,
  }) = _Session;

  factory Session.fromJson(Map<String, Object?> json) =>
      _$SessionFromJson(json);
}
