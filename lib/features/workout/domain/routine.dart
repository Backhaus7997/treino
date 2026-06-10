import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/domain/experience_level.dart';
import 'routine_day.dart';
import 'routine_source.dart';
import 'routine_status.dart';
import 'routine_visibility.dart';

part 'routine.freezed.dart';
part 'routine.g.dart';

@freezed
class Routine with _$Routine {
  /// Fields `source`, `assignedBy`, `assignedTo` y `visibility` se agregaron
  /// en Fase 5 Etapa 1 (foundations). Defaults `system` + `public` mantienen
  /// retro-compat con las plantillas seedeadas en Fase 2 que no tienen estos
  /// fields en sus docs Firestore.
  ///
  /// `createdBy` y `status` se agregaron en Fase 6 Etapa 1.5
  /// (athlete-self-routines). `createdBy` es null para plantillas del sistema
  /// y planes asignados por PF. `status` default = `active` para retro-compat.
  const factory Routine({
    required String id,
    required String name,
    String?
        split, // 'PPL' | 'Full Body' | 'Upper/Lower' | ... (free-form); null for athlete-created routines (REQ-RER-014, ADR-RER-04)
    required ExperienceLevel level,
    required List<RoutineDay> days, // empty list valid (spec SCENARIO-052)
    int? estimatedMinutesPerDay,
    String? imageUrl, // null for seed PR 2 (ADR-3); future Storage URL
    @Default(RoutineSource.system) RoutineSource source,
    String? assignedBy, // trainerId — solo cuando source == trainerAssigned
    String? assignedTo, // athleteId — solo en planes privados asignados
    @Default(RoutineVisibility.public) RoutineVisibility visibility,
    String?
        createdBy, // uid del atleta que creó la rutina; null para system/trainer-assigned
    @Default(RoutineStatus.active)
    RoutineStatus status, // default active — retro-compat
    // ── Periodization (Model B) ──────────────────────────────────────────────
    // Number of authored weeks. @Default(1) keeps single-week routines intact
    // and retro-compatible with docs that lack this field.
    @Default(1) int numWeeks,
  }) = _Routine;

  factory Routine.fromJson(Map<String, Object?> json) =>
      _$RoutineFromJson(json);
}
