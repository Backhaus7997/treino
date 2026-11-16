// ignore_for_file: invalid_annotation_target — @JsonKey sobre un parámetro de la
// factory freezed (falso positivo del analyzer; mismo criterio que post.dart).

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

    /// Segundos que duró una serie por TIEMPO (una plancha). `null` en las
    /// series por reps/peso y en las guardadas antes de que existiera el
    /// campo (#1701): ahí la métrica era `reps: 0, weightKg: 0` y no había
    /// dónde guardar el tiempo.
    ///
    /// `includeIfNull: false` para que una serie por reps no escriba la clave
    /// y su documento quede idéntico al de antes. `rpe` conserva su
    /// serialización (`rpe: null`) a propósito: cambiarla es otra decisión.
    @JsonKey(includeIfNull: false) int? durationSeconds,

    /// Metros de una serie por DISTANCIA (un trineo, un farmer carry). `null`
    /// en las series por reps/peso y en las anteriores al campo (#1701). Mismo
    /// criterio de serialización que [durationSeconds].
    @JsonKey(includeIfNull: false) double? distanceMeters,
  }) = _SetLog;

  factory SetLog.fromJson(Map<String, Object?> json) => _$SetLogFromJson(json);
}
