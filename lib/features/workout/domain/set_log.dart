// ignore: unused_import — Timestamp is used by the generated set_log.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'set_log.freezed.dart';
part 'set_log.g.dart';

@freezed
class SetLog with _$SetLog {
  const factory SetLog({
    required String id,
    required String exerciseId,
    required String exerciseName,
    required int setNumber,
    required int reps,
    required double weightKg,
    int? rpe,
    @TimestampConverter() required DateTime completedAt,
  }) = _SetLog;

  factory SetLog.fromJson(Map<String, Object?> json) => _$SetLogFromJson(json);
}
