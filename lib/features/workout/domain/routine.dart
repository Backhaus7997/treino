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
    // ── Community rating aggregates (Fase W3 — template publishing) ──────────
    // Written EXCLUSIVELY by the `templateRatingAggregate` Cloud Function.
    // `includeToJson: false` keeps them out of every client write payload;
    // firestore.rules additionally rejects them on create and never lists
    // them in any update affectedKeys allowlist.
    // ignore: invalid_annotation_target
    @JsonKey(includeToJson: false) double? ratingAvg,
    // ignore: invalid_annotation_target
    @JsonKey(includeToJson: false) int? ratingsCount,
    // ── Plain-language summary (#648) ────────────────────────────────────────
    // One sentence explaining what the routine IS, in words someone who has
    // never set foot in a gym can parse. The catalogue leads with jargon —
    // "Bro Split", "PPL", "Upper/Lower" — and 2 of 5 usability participants
    // could not tell what those meant; the term is not hidden, it is explained.
    //
    // Seeded via scripts/seed_templates.js (Admin SDK, bypasses rules).
    // `includeToJson: false` for the same reason as the rating aggregates
    // above, and it is what keeps this field OUT of firestore.rules: the
    // client never puts it in a write payload, so no `hasOnly` list has to
    // learn about it and no athlete/trainer routine update can break on it
    // (the #563 failure mode). Routine writes use `update()`, never `set()`,
    // so an excluded field survives untouched.
    //
    // Trainer-authored summaries would need the editor AND the rules
    // allowlists — deliberately a separate slice.
    // ignore: invalid_annotation_target
    @JsonKey(includeToJson: false) String? summary,
  }) = _Routine;

  factory Routine.fromJson(Map<String, Object?> json) =>
      _$RoutineFromJson(json);
}
