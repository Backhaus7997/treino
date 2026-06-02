// ignore: unused_import — Timestamp is used by the generated measurement.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'measurement.freezed.dart';
part 'measurement.g.dart';

@freezed
class Measurement with _$Measurement {
  const factory Measurement({
    required String id,
    required String athleteId,

    /// Trainer uid who logged this measurement.
    required String recordedBy,
    @TimestampConverter() required DateTime recordedAt,

    // ─── Body composition ────────────────────────────────────────────────
    double? weightKg,
    double? fatPercentage,
    double? muscleMassKg,

    // ─── Trunk circumferences (cm) ───────────────────────────────────────
    double? shouldersCm,
    double? chestCm,
    double? waistCm,
    double? hipsCm,
    double? glutesCm,

    // ─── Upper body bilateral (cm) ───────────────────────────────────────
    double? bicepsLCm,
    double? bicepsRCm,
    double? bicepsFlexedLCm,
    double? bicepsFlexedRCm,
    double? forearmLCm,
    double? forearmRCm,

    // ─── Lower body bilateral (cm) ───────────────────────────────────────
    double? upperThighLCm,
    double? upperThighRCm,
    double? midThighLCm,
    double? midThighRCm,
    double? calfLCm,
    double? calfRCm,

    // ─── Meta ─────────────────────────────────────────────────────────────
    String? notes,
  }) = _Measurement;

  factory Measurement.fromJson(Map<String, Object?> json) =>
      _$MeasurementFromJson(json);
}
