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
    // Seeded via scripts/seed_templates.js (Admin SDK, bypasses rules) for the
    // 7 system templates, and escribible por el PF desde el editor.
    //
    // Ya NO lleva `includeToJson: false`. Sacarlo es lo que habilita que el PF
    // lo escriba, y es también lo que obliga a que firestore.rules lo conozca:
    // `toJson()` ahora lo emite en TODA rutina, así que los tres `hasOnly` de
    // los paths de update tuvieron que aprenderlo. Si alguno se quedara sin él,
    // esa rama entera de edición falla con permission-denied — el modo de falla
    // de #563.
    //
    // El reparto NO es simétrico, y es deliberado:
    //   • paths 3 y 4 (PF): `summary` está en `keys()` Y en `affectedKeys()`.
    //     El PF lo escribe y lo edita.
    //   • path 2 (atleta): está SÓLO en `keys()`. El atleta puede seguir
    //     editando una rutina que lo tenga, pero no puede cambiarlo. Mismo
    //     criterio que ratingAvg/ratingsCount, que se listan defensivamente por
    //     esa misma razón.
    //
    // El tope de largo (280) vive en las reglas, no acá: un cliente parcheado
    // no lo respetaría. Los 7 sembrados miden entre 61 y 100 caracteres.
    String? summary,
  }) = _Routine;

  factory Routine.fromJson(Map<String, Object?> json) =>
      _$RoutineFromJson(json);
}
