// ignore: unused_import — Timestamp is used by the generated performance_test.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'performance_test.freezed.dart';
part 'performance_test.g.dart';

@freezed
class PerformanceTest with _$PerformanceTest {
  const factory PerformanceTest({
    required String id,
    required String athleteId,

    /// Trainer uid who logged this performance test.
    required String recordedBy,
    @TimestampConverter() required DateTime recordedAt,

    // ─── Saltos (cm) ─────────────────────────────────────────────────────────
    double? cmjCm,
    double? squatJumpCm,
    double? abalakovCm,
    double? broadJumpCm,

    // ─── Velocidad / sprints (segundos) ──────────────────────────────────────
    double? sprint10mS,
    double? sprint20mS,
    double? sprint30mS,
    double? sprint40mS,

    // ─── Fuerza máxima 1RM (kg) ──────────────────────────────────────────────
    double? squat1rmKg,
    double? benchPress1rmKg,
    double? deadlift1rmKg,
    double? overheadPress1rmKg,
    double? pullUp1rmKg,

    // ─── Resistencia / otros ─────────────────────────────────────────────────
    double? vo2maxMlKgMin,
    double? courseNavetteLevel,
    double? cooperMeters,
    double? sitAndReachCm,

    // ─── Meta ─────────────────────────────────────────────────────────────────
    String? notes,
  }) = _PerformanceTest;

  factory PerformanceTest.fromJson(Map<String, Object?> json) =>
      _$PerformanceTestFromJson(json);
}
