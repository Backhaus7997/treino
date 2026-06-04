// ignore: unused_import — Timestamp is used by the generated trainer_link.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import 'trainer_link_status.dart';

part 'trainer_link.freezed.dart';
part 'trainer_link.g.dart';

/// Vínculo PF ↔ atleta. Doc en `trainer_links/{id}` con id auto-generado.
/// Permite múltiples vínculos históricos entre el mismo par
/// (uno terminado + uno nuevo activo = 2 docs).
@freezed
class TrainerLink with _$TrainerLink {
  const factory TrainerLink({
    required String id,
    required String trainerId,
    required String athleteId,
    required TrainerLinkStatus status,
    @TimestampConverter() required DateTime requestedAt,
    @TimestampConverter() DateTime? acceptedAt,
    @TimestampConverter() DateTime? terminatedAt,
    String? terminationReason,
    @TimestampConverter() DateTime? pausedAt,
    // Privacy gate. When `true`, the athlete shares their history
    // (sessions, volume, streak) with their PF. Defaults to `false`
    // so legacy docs without the key decode safely; Etapa 6 will
    // consume this flag to gate PF reads on `sessions/{athleteId}/*`.
    // REQ-COACH-LINK-001 + REQ-COACH-LINK-002.
    @Default(false) bool sharedWithTrainer,
  }) = _TrainerLink;

  factory TrainerLink.fromJson(Map<String, Object?> json) =>
      _$TrainerLinkFromJson(json);
}
