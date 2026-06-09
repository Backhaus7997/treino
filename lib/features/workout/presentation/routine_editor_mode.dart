/// Parametrization of [RoutineEditorScreen] via Dart 3 sealed class.
///
/// Three variants:
/// - [TrainerAssigning] — trainer creates a plan for a specific athlete.
/// - [TrainerTemplating] — trainer creates a reusable template, no athlete
///   assigned (sidecar to ADR-USR-01 — pre-existing TrainerWorkoutView
///   "NUEVA PLANTILLA" CTA must keep working).
/// - [SelfCreating] — athlete self-authors a personal routine.
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
