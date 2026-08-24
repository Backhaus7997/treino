/// Parametrization of [RoutineEditorScreen] via Dart 3 sealed class.
///
/// Four variants:
/// - [TrainerAssigning] — trainer creates a plan for a specific athlete.
/// - [TrainerTemplating] — trainer creates a reusable template, no athlete
///   assigned (sidecar to ADR-USR-01 — pre-existing TrainerWorkoutView
///   "NUEVA PLANTILLA" CTA must keep working).
/// - [SelfCreating] — athlete self-authors a personal routine.
/// - [SelfCustomizing] — athlete starts from an existing template and ends up
///   with a routine of their own (#647).
///
/// See ADR-USR-01 (engram topic sdd/athlete-self-routines/design) for the
/// full rationale: sealed class gives variant-scoped fields and exhaustive
/// switch matching, preventing future regression when new modes are added.
sealed class RoutineEditorMode {
  const RoutineEditorMode();
}

/// Trainer-assigning mode: the trainer builds a plan for [athleteId].
///
/// - [existingPlanId] == null → create a new plan via
///   [RoutineRepository.createAssigned].
/// - [existingPlanId] != null → edit an existing plan: hydrates editor state
///   from Firestore via [RoutineRepository.getById], then saves updated
///   content via [RoutineRepository.updateAssigned].
final class TrainerAssigning extends RoutineEditorMode {
  const TrainerAssigning({required this.athleteId, this.existingPlanId});

  final String athleteId;
  final String? existingPlanId;
}

/// Trainer-templating mode: the trainer builds a reusable template, no
/// athlete assignment yet.
///
/// - [existingTemplateId] == null → create a new template via
///   [RoutineRepository.createTemplate].
/// - [existingTemplateId] != null → edit an existing template: hydrates
///   editor state from Firestore via [RoutineRepository.getById], then saves
///   updated content via [RoutineRepository.updateTemplate].
///
/// Sidecar to PR2 scope — the pre-PR2 editor distinguished templates from
/// assignments via `athleteId == null`. Making `mode` required forced this
/// case to become its own variant so the trainer's "NUEVA PLANTILLA" CTA
/// keeps working.
final class TrainerTemplating extends RoutineEditorMode {
  const TrainerTemplating({this.existingTemplateId});

  final String? existingTemplateId;
}

/// Self-creating mode: an authenticated athlete builds their own routine.
///
/// - [existingRoutineId] == null → create a new routine via
///   [RoutineRepository.createUserOwned].
/// - [existingRoutineId] != null → edit an existing routine: hydrates editor
///   state from Firestore via [RoutineRepository.getById], then saves updated
///   content (name, days) via [RoutineRepository.updateUserOwned].
final class SelfCreating extends RoutineEditorMode {
  const SelfCreating({this.existingRoutineId});

  final String? existingRoutineId;
}

/// Self-customizing mode (#647): the athlete starts from an EXISTING routine
/// and ends up with a NEW routine of their own.
///
/// It is the missing middle between the two extremes the usability study
/// found: use a template verbatim, or face a blank [SelfCreating] screen.
///
/// Reads [sourceRoutineId], writes a brand-new doc — the only variant where
/// the id the editor hydrates from is NOT the id it saves to. The source is
/// never mutated, and no link back to it is stored: the copy is independent
/// on purpose, so nothing has to be decided about what happens when the
/// trainer edits or unpublishes the original.
///
/// Submits via [RoutineRepository.createUserOwned], exactly like
/// `SelfCreating(existingRoutineId: null)` — same cap check, same
/// `source: user-created` + `createdBy: <uid>` stamping. That shared exit is
/// what guarantees the copy is the ATHLETE's routine and not the trainer's:
/// the editor only ever hydrates content (days, slots, sets, weeks), so the
/// source's `assignedBy`/`assignedTo`/`summary`/`imageUrl`/`ratingAvg` cannot
/// reach the write — they are never held in editor state to begin with.
final class SelfCustomizing extends RoutineEditorMode {
  const SelfCustomizing({required this.sourceRoutineId});

  /// Routine to copy FROM. Must be readable by the athlete: a system template
  /// or a trainer template published to the community. Trainer-ASSIGNED plans
  /// are deliberately not copyable — that would turn a prescription into a
  /// suggestion (see #647); if the athlete wants changes, they ask their PF.
  final String sourceRoutineId;
}
