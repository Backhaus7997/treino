import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/domain/experience_level.dart';
import 'muscle_group.dart';
import 'routine_day.dart';
import 'routine_goal.dart';
import 'routine_source.dart';
import 'routine_status.dart';
import 'routine_visibility.dart';

part 'routine.freezed.dart';
part 'routine.g.dart';

@freezed
class Routine with _$Routine {
  /// Private constructor required for custom getters in freezed classes.
  const Routine._();

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
    // ── Catálogo pago (paywall del alumno suelto, spec §4.1.1) ───────────────
    // `true` en las plantillas del sistema que sólo puede usar un alumno con
    // derecho. Lo siembra `scripts/seed_templates.js` (Admin SDK, saltea las
    // reglas) desde `improved-templates.json`; el cliente sólo lo LEE.
    //
    // `includeToJson: false` por el mismo motivo que ratingAvg/ratingsCount, y
    // acá el motivo es más filoso: sin eso `toJson()` lo emitiría en TODA
    // rutina, incluidas las `user-created`, y el `hasOnly(userCreatedRoutineFields())`
    // de firestore.rules —que no conoce este campo— rechazaría el create y el
    // update de cualquier rutina de atleta. Es exactamente el modo de falla de
    // #563 que el propio archivo de reglas advierte en su COUPLING WARNING.
    // Manteniéndolo fuera del payload, las reglas no necesitan enterarse.
    //
    // Default `false`: una plantilla sin el campo es GRATIS. Ningún doc lo
    // tiene hoy, así que el default es lo que hace que esto no necesite
    // backfill y que un error de siembra falle del lado seguro (abre, no cobra).
    //
    // NO gobierna el tope de días/semanas: ese es el otro eje del paywall y
    // aplica a la rutina propia del alumno, no al catálogo (spec §4).
    // ignore: invalid_annotation_target
    @JsonKey(includeToJson: false) @Default(false) bool isPremium,
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

    // ── Para qué sirve esta rutina (#635 PR#1) ───────────────────────────────
    // Multi-valor a propósito: una Full Body sirve a *salud* y a *estética* a
    // la vez, y forzar un objetivo único mentiría. Lista vacía = sin declarar,
    // que el scoring de PLANTILLAS tiene que tratar como NEUTRO — no rankea
    // alto, pero tampoco desaparece. Toda plantilla publicada por la comunidad
    // antes de este cambio llega así, y son la mayoría del catálogo.
    //
    // Es el único de los dos campos de #635 que se GUARDA. El otro
    // ([primaryMuscleGroups]) se deriva — ver su dartdoc.
    //
    // Reparto en firestore.rules, mismo criterio asimétrico que `summary` y
    // por la misma razón (el modo de falla de #563):
    //   • paths 3 y 4 (PF): en `keys()` Y en `affectedKeys()`. El PF lo
    //     declara y lo edita desde el editor de plantillas.
    //   • path 2 (atleta): SÓLO en `keys()`. Puede seguir editando una rutina
    //     que lo tenga, pero no cambiarlo: el objetivo es una afirmación
    //     editorial de quien publica, no una preferencia de quien la usa.
    @RoutineGoalListConverter()
    @Default(<RoutineGoal>[])
    List<RoutineGoal> goals,
  }) = _Routine;

  /// Zonas que esta rutina prioriza, DERIVADAS de sus slots (#635 PR#1).
  ///
  /// No es un campo de Firestore, y esa es la decisión de diseño que más
  /// cambia el issue. `RoutineSlot.muscleGroup` ya viaja denormalizado en el
  /// documento —está ahí para dibujar la card—, así que esto es una cuenta
  /// pura sobre datos que ya llegaron. Guardarlo además significaría:
  ///
  ///   1. un backfill de las 7 plantillas stock,
  ///   2. una cuarta y quinta entrada en cada `hasOnly` de `firestore.rules`
  ///      —el modo de falla de #563, multiplicado—,
  ///   3. exponerlo en el editor del PF, y
  ///   4. sobre todo: **toda plantilla de la comunidad publicada antes de
  ///      este cambio nacería sin zonas** y se evaporaría del ranking el día
  ///      del deploy. Derivando, funcionan solas — sin migración y sin que
  ///      nadie las vuelva a tocar.
  ///
  /// Ordenadas por frecuencia descendente: la zona que más slots ocupa es la
  /// que la rutina más prioriza. Empate resuelto por el orden del enum, para
  /// que el resultado sea estable entre corridas.
  ///
  /// Pasa por [MuscleGroup.fromKey], no por comparación cruda: el catálogo
  /// sembrado guarda `fullbody` donde el enum dice `full_body`, y las rutinas
  /// viejas del editor de ejercicios propios guardan etiquetas en español.
  /// `fromKey` canonicaliza las tres formas; lo desconocido se descarta en
  /// vez de contaminar el conteo.
  List<MuscleGroup> get primaryMuscleGroups {
    final counts = <MuscleGroup, int>{};
    for (final day in days) {
      for (final slot in day.slots) {
        final group = MuscleGroup.fromKey(slot.muscleGroup);
        if (group == null) continue;
        counts[group] = (counts[group] ?? 0) + 1;
      }
    }
    final ordered = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.index.compareTo(b.index);
      });
    return List.unmodifiable(ordered);
  }

  /// Las claves canónicas de [primaryMuscleGroups], que es el vocabulario con
  /// el que `TemplatePreferences.priorityMuscleGroups` guarda las respuestas
  /// del atleta (#635 PR#2). Los dos lados hablan `MuscleGroup.wireKey`.
  List<String> get primaryMuscleGroupKeys =>
      primaryMuscleGroups.map((g) => g.key).toList(growable: false);

  factory Routine.fromJson(Map<String, Object?> json) =>
      _$RoutineFromJson(json);
}
