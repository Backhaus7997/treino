// ignore: unused_import — Timestamp is used by the generated follow_up_entry.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'follow_up_entry.freezed.dart';
part 'follow_up_entry.g.dart';

/// Categoría/tag de una entrada de seguimiento.
///
/// Wire values estables. `general` es el default cuando el PF no elige nada
/// explícito — sirve para anotaciones libres. El resto agrupa por tipo de
/// observación de coaching, útil para filtrar y para dar significado visual
/// (color/ícono).
enum FollowUpTag {
  @JsonValue('general')
  general,
  @JsonValue('entrenamiento')
  entrenamiento,
  @JsonValue('nutricion')
  nutricion,
  @JsonValue('molestia')
  molestia,
  @JsonValue('motivacion')
  motivacion,
}

/// Entrada del log de seguimiento del PF sobre un alumno.
///
/// Es un log cronológico DESC — múltiples entradas datadas del PF a lo
/// largo del vínculo. Diferencia con `AthleteNote` (hoja libre única):
/// aquí cada entrada tiene su propio timestamp + tag para agrupar/filtrar.
///
/// Stored in Firestore at `follow_up_entries/{id}` con
/// `id = {trainerId}_{athleteId}_{timestamp}`. Trainer-only en rules — el
/// alumno NO ve estas entradas en ningún surface. Es una herramienta
/// interna del PF para trackear cambios/decisiones/observaciones.
@freezed
class FollowUpEntry with _$FollowUpEntry {
  const factory FollowUpEntry({
    required String id,
    required String trainerId,
    required String athleteId,
    required String text,
    required FollowUpTag tag,
    @TimestampConverter() required DateTime recordedAt,
  }) = _FollowUpEntry;

  factory FollowUpEntry.fromJson(Map<String, Object?> json) =>
      _$FollowUpEntryFromJson(json);
}
