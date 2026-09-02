// ignore_for_file: library_private_types_in_public_api
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/utils/kg_format.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../coach/presentation/widgets/exercise_picker_sheet.dart';
import '../../onboarding/domain/onboarding_surface.dart';
import '../../onboarding/presentation/custom_exercise_onboarding_gate.dart';
import '../../profile/application/user_providers.dart'
    show userProfileProvider, userRepositoryProvider;
import '../../profile/domain/experience_level.dart';
import '../application/custom_exercise_providers.dart'
    show customExercisesForTrainerStreamProvider;
import '../domain/custom_exercise.dart' show CustomExercise;
import '../application/exercise_filter.dart'
    show customToExercise, exerciseMatchesFilters;
import '../application/exercise_providers.dart' show exercisesProvider;
import '../application/routine_providers.dart' show routineRepositoryProvider;
import '../application/session_providers.dart' show currentUidProvider;
import '../application/user_routines_providers.dart'
    show userCreatedRoutinesProvider;
import '../domain/exercise.dart';
import '../domain/routine.dart';
import '../domain/routine_day.dart';
import '../domain/routine_goal.dart';
// `templatesGoalLabel` vive con el mini-onboarding (#635 PR#2) y se reusa acá
// a propósito: es el ÚNICO mapeo de `RoutineGoal` a copy. Dos vocabularios
// para el mismo enum es exactamente cómo se desincronizan las etiquetas.
import 'onboarding/templates_onboarding_steps.dart';
import '../domain/routine_slot.dart';
import '../domain/routine_source.dart';
import '../domain/routine_visibility.dart';
import '../domain/set_enums.dart';
import '../domain/set_limits.dart';
import '../domain/set_spec.dart';
import 'routine_editor_mode.dart';
import 'widgets/duration_text_field.dart';
import 'widgets/day_tab_bar.dart';
import 'widgets/editor_footer_bar.dart';
import 'widgets/empty_day_state.dart';
import 'widgets/exercise_actions_sheet.dart';
import 'widgets/keyboard_accessory_bar.dart';
import 'widgets/exercise_card.dart';
import 'widgets/prescription_chips.dart';
import 'widgets/quick_entry_panel.dart';
import 'widgets/quick_entry_parser.dart';
import 'widgets/routine_action_buttons.dart';
import 'widgets/set_cell_field.dart';
// `parseEditorWeight` se mudó junto al campo que parsea. Se re-exporta desde
// acá porque `routine_editor_kg_decimal_test.dart` lo importa por esta ruta
// desde antes de que la celda fuera un widget propio, y su contrato no cambió.
export 'widgets/set_cell_field.dart' show parseEditorWeight;
import 'widgets/set_type_chip.dart';
import 'widgets/superset_block.dart';

// ── Presence-aware delete / add scope enums ───────────────────────────────────

/// Choice from the "¿Eliminar ejercicio?" dialog.
enum _DeleteScope { thisWeek, allWeeks }

/// Choice from the "¿En qué semanas agregar?" dialog.
enum _AddScope { thisWeek, allWeeks }

// ── Testable helpers ──────────────────────────────────────────────────────────

/// Swaps element at [index] with its neighbour in direction [dir] (-1 up,
/// +1 down) **only** when both elements satisfy [sameGroup]. Returns true if a
/// swap happened, false otherwise (edge or mismatched group).
///
/// Extracted so unit tests can verify the core swap logic without touching the
/// Flutter widget tree.
@visibleForTesting
bool swapAdjacentInGroup<T>(
  List<T> items,
  int index,
  int dir,
  bool Function(T a, T b) sameGroup,
) {
  final neighbor = index + dir;
  if (neighbor < 0 || neighbor >= items.length) return false;
  if (!sameGroup(items[index], items[neighbor])) return false;
  final tmp = items[index];
  items[index] = items[neighbor];
  items[neighbor] = tmp;
  return true;
}

// ── Mutable local state ────────────────────────────────────────────────────────

/// Mutable per-set row in the editor — mirrors [SetSpec] fields.
class _EditableSet {
  SetType type;
  double? weightKg;
  int? reps;
  int? repsMin;
  int? repsMax;
  int? durationSeconds;

  _EditableSet({
    this.type = SetType.normal,
    this.weightKg,
    this.reps,
    this.repsMin,
    this.repsMax,
    this.durationSeconds,
  });

  /// Returns a copy with the same values — used when duplicating the last set.
  _EditableSet clone() => _EditableSet(
        type: SetType.normal, // new sets are always normal
        weightKg: weightKg,
        reps: reps,
        repsMin: repsMin,
        repsMax: repsMax,
        durationSeconds: durationSeconds,
      );

  /// True deep copy preserving [type] — "Duplicar semana" must replicate the
  /// previous week exactly, W/D/F sets included (REQ-PERIOD-014). [clone]
  /// intentionally resets the type for the "+ Agregar set" template flow.
  _EditableSet copy() => _EditableSet(
        type: type,
        weightKg: weightKg,
        reps: reps,
        repsMin: repsMin,
        repsMax: repsMax,
        durationSeconds: durationSeconds,
      );

  SetSpec toSetSpec() => SetSpec(
        type: type,
        weightKg: weightKg,
        reps: reps,
        repsMin: repsMin,
        repsMax: repsMax,
        durationSeconds: durationSeconds,
      );
}

class _EditableSlot {
  Exercise? exercise;
  // ── New per-set model ──────────────────────────────────────────────────────
  ExerciseMode exerciseMode = ExerciseMode.reps;
  RepMode repMode = RepMode.single;

  /// One inner list of sets per plan week — outer index is the 0-based week.
  /// Invariant: every slot keeps exactly `_numWeeks` inner lists (week
  /// add/remove operations resize all slots together). REQ-PERIOD-013/015.
  List<List<_EditableSet>> weeklySets = [
    [_EditableSet()],
  ];
  // Rest starts at 0 by default — the trainer/athlete sets it per exercise
  // (device feedback 2026-06-11). Was 60.
  int restSeconds = 0;
  int? supersetGroup;

  /// Si la card se ve desplegada. Vive en el MODELO y no en el `State` del
  /// editor a propósito.
  ///
  /// Mover un slot entre la lista externa y la de una superserie lo cambia de
  /// lugar en el árbol, y ahí Flutter destruye y recrea su `State`: cualquier
  /// bandera local vuelve a su valor inicial. Con la bandera atada a
  /// `hasSlotError`, eso significaba que **reacomodar ejercicios desplegaba
  /// solos a los que tenían campos sin completar** — reportado en device.
  ///
  /// Arranca en `true` porque un ejercicio recién agregado nace con sus sets
  /// vacíos y hay que poder llenarlos sin un tap extra. La hidratación de una
  /// rutina existente lo pone en `false`: ahí todo nace plegado, y los que
  /// tienen algo sin completar se marcan con el borde rojo de [ExerciseCard]
  /// en vez de abrirse.
  bool expandido = true;

  /// The active week's set list — same object as `weeklySets[w]`, so in-place
  /// mutations are visible to the single source of truth (ADR-PB-02).
  List<_EditableSet> setsForWeek(int w) => weeklySets[w];

  // ── Presence mask (REQ-WPRES-001, ADR-WPRES-01) ────────────────────────────
  /// 0-based weeks in which this slot is present. Empty = present in ALL weeks
  /// (backward-compatible default — legacy single-week docs have no mask).
  /// A `Set<int>` in-editor for cheap add/remove; converted to a sorted
  /// `List<int>` at [buildRoutineSlot]. Mirrors [RoutineSlot.activeWeeks].
  Set<int> activeWeeks = <int>{};

  /// Whether this slot is present in 0-based [week].
  /// Rule: `activeWeeks.isEmpty || activeWeeks.contains(week)`.
  bool isPresentInWeek(int w) => activeWeeks.isEmpty || activeWeeks.contains(w);

  /// Trainer-authored coaching note for this slot. Null means no note.
  /// Gated to trainer modes at the UI layer (REQ-EN-002); stored and
  /// hydrated unconditionally so notes survive athlete re-edits (REQ-EN-005).
  String? notes;

  // ── Legacy scalar fields — kept for backward compat on submit ──────────────
  // These are now derived from [weeklySets] in _submit(); callers outside
  // _submit() should not rely on them being up-to-date.
  int targetSets = 1;
  int targetRepsMin = 0;
  int targetRepsMax = 0;
  List<int> targetReps = [];
  int? durationSeconds;

  _EditableSlot();
}

class _EditableDay {
  int dayNumber;
  String name;
  List<_EditableSlot> slots = [];

  /// True while [name] is the auto-generated default ("Día N"). Drives the
  /// re-numbering in `_removeDay`: only auto-named days follow their position,
  /// custom names (hydrated from a saved routine) are preserved. Tracked as a
  /// flag instead of comparing [name] to a localized template — that compare
  /// silently broke whenever the active locale differed from the literal.
  bool isDefaultName;

  /// Collapsed/expanded state lives HERE (on the model that persists in the
  /// editor's _days list), not in the tile's State — the ListView recycles
  /// off-screen tiles, so a tile-local flag reset to `true` every time the
  /// day scrolled back into view (device bug 2026-06-11).
  bool expanded = true;

  _EditableDay({
    required this.dayNumber,
    required this.name,
    this.isDefaultName = false,
  });
}

// ── Helpers ────────────────────────────────────────────────────────────────────

/// Returns the display label for a set chip.
/// Normal sets show their working-set number (count of normal-type sets up to
/// and including this one). W / D / F show the letter.
String setChipLabel(List<_EditableSet> sets, int index) {
  final s = sets[index];
  if (s.type != SetType.normal) return kSetTypeLabel[s.type]!;
  // Count normal sets up to and including index.
  var n = 0;
  for (var i = 0; i <= index; i++) {
    if (sets[i].type == SetType.normal) n++;
  }
  return n.toString();
}

/// Maps a persisted [SetSpec] into its mutable editor row.
_EditableSet _editableSetFromSpec(SetSpec spec) => _EditableSet(
      type: spec.type,
      weightKg: spec.weightKg,
      reps: spec.reps,
      repsMin: spec.repsMin,
      repsMax: spec.repsMax,
      durationSeconds: spec.durationSeconds,
    );

/// Picks the rep mode that matches the hydrated set data: REP RANGE only when at
/// least one non-failure set actually carries a min/max pair; otherwise SINGLE.
///
/// Why not just use `slot.effectiveRepMode`: a legacy slot can carry a
/// slot-level range (targetRepsMin != targetRepsMax) while its per-set specs
/// only hold a single `reps` value. That mismatch forced REP RANGE on edit and
/// left the min/max fields empty (and flagged red) for an exercise the user
/// never configured as a range.
RepMode _repModeFromHydratedSets(List<List<_EditableSet>> weeklySets) {
  for (final week in weeklySets) {
    for (final s in week) {
      if (s.type == SetType.failure) continue;
      if (s.repsMin != null || s.repsMax != null) return RepMode.range;
    }
  }
  return RepMode.single;
}

/// Validates a single [_EditableSet] given the slot's modes.
bool isSetValid(_EditableSet s, ExerciseMode exerciseMode, RepMode repMode) {
  // A failure set ("al fallo") has no countable target by definition — the
  // athlete works until failure. Reps/duration are an optional reference,
  // never a requirement.
  // QA-WKT-003: no set — failure or countable — may carry a load over the
  // shared ceiling; it would still corrupt totalVolumeKg. Checked first so it
  // also gates "al fallo" sets, and catches specs seeded before the caps.
  if (s.weightKg != null && s.weightKg! > kMaxWeightKg) return false;
  if (s.type == SetType.failure) return true;
  if (exerciseMode == ExerciseMode.duration) {
    return s.durationSeconds != null && s.durationSeconds! > 0;
  }
  if (repMode == RepMode.range) {
    return s.repsMin != null &&
        s.repsMin! > 0 &&
        s.repsMax != null &&
        s.repsMax! >= s.repsMin! &&
        s.repsMax! <= kMaxReps;
  }
  return s.reps != null && s.reps! > 0 && s.reps! <= kMaxReps;
}

/// QA-WKT-004: a day must never list the same exerciseId twice. The session
/// player keys ALL progress (logs, gating, set-count overrides) by exerciseId,
/// so two slots sharing an id collapse into one pool of logs — the second slot
/// can't be logged and the day counts double. Pure so the editor validation
/// and its tests share one definition.
bool dayHasDuplicateExerciseId(Iterable<String> exerciseIds) {
  final seen = <String>{};
  for (final id in exerciseIds) {
    if (!seen.add(id)) return true;
  }
  return false;
}

/// Copies the prescription of [source] onto [target] for the 0-based [week].
///
/// "Prescription" = the measurement mode (`exerciseMode` + `repMode`) plus that
/// week's set list, deep-copied via [_EditableSet.copy] so W/D/F types survive
/// and the two slots never share set instances (same contract as
/// "Duplicar semana", REQ-PERIOD-014).
///
/// Deliberately NOT copied:
/// - `activeWeeks`: presence is orthogonal to prescription — a copy must never
///   add or remove an exercise from a week (ADR-WPRES).
/// - other weeks: mirrors "Duplicar semana", which acts on the visible week
///   only. Copying every week would silently overwrite a periodized plan.
/// - `restSeconds`, `notes`, `exercise`: identity/coaching data, not the set
///   grid the user is complaining about.
///
/// The mode IS copied on purpose: pasting duration sets into a slot that still
/// renders KG/REPS columns would show empty, invalid rows. Since the mode is a
/// slot-level field, this also re-modes the target's OTHER weeks — the same
/// blast radius the existing REPS/TIEMPO header picker already has, and it is
/// surfaced by the per-week validation dots rather than failing silently.
void copyPrescriptionInto(
  _EditableSlot source,
  _EditableSlot target,
  int week,
) {
  if (week < 0) return;
  if (week >= source.weeklySets.length || week >= target.weeklySets.length) {
    return;
  }
  target.exerciseMode = source.exerciseMode;
  target.repMode = source.repMode;
  target.weeklySets[week] =
      source.weeklySets[week].map((s) => s.copy()).toList();
}

/// Writes [weights] onto [sets] positionally, REPLACING each row's
/// [_EditableSet] instance instead of mutating it in place.
///
/// Why replace: set rows are keyed by set identity (`ObjectKey`) and seed their
/// [TextEditingController] once in `initState`. Mutating a set in place would
/// update the model while the visible field kept showing the old number — the
/// exact silent-corruption failure mode the issue warns about.
///
/// Only the weight moves: [_EditableSet.copy] carries the SetType, reps,
/// range and duration through untouched, so a bulk fill can never break the
/// slot's measurement mode. Extra [sets] beyond [weights] are left alone (an
/// undo whose snapshot predates an added row still restores what it knows).
void applyColumnWeights(List<_EditableSet> sets, List<double?> weights) {
  for (var i = 0; i < sets.length && i < weights.length; i++) {
    if (sets[i].weightKg == weights[i]) continue;
    sets[i] = sets[i].copy()..weightKg = weights[i];
  }
}

/// Plate-sized jumps offered by the KG steppers, smallest first. A gym user
/// thinks in discs, not digits (issue #640): 2.5 is a pair of 1.25 plates,
/// 5 is a pair of 2.5s.
const List<double> kKgStepsKg = [2.5, 5];

/// Returns [current] moved by [deltaKg], clamped into `[0, kMaxWeightKg]`.
///
/// A missing weight counts as 0, so `+2.5` on an empty field authors 2.5
/// instead of doing nothing.
///
/// Landing on zero returns null — an EMPTY field is the editor's "sin peso",
/// and a stepper must never author a `0 kg` prescription the athlete never
/// typed. Together with the clamp, this is what makes a negative load
/// unreachable by construction rather than by validation.
///
/// The result is rounded to two decimals: `17.3 + 2.5` is
/// `19.799999999999997` in binary floating point, and the KG field renders
/// the raw double. Two decimals is finer than any plate in any gym.
double? steppedWeightKg(double? current, double deltaKg) {
  final next = clampWeightKg((current ?? 0) + deltaKg);
  if (next <= 0) return null;
  return double.parse(next.toStringAsFixed(2));
}

/// Builds the [RoutineSlot] from an [_EditableSlot], populating both new
/// and legacy fields. Extracted top-level so the submit path and tests share
/// the same derivation logic.
RoutineSlot buildRoutineSlot(_EditableSlot s, int? effectiveGroup) {
  // Legacy fields and the `sets:` list stay derived from WEEK 0, so every
  // non-week-aware consumer keeps reading the first week's prescription
  // (REQ-PERIOD-017, ADR-PB-03).
  final week0 = s.weeklySets.first;
  final specList = week0.map((e) => e.toSetSpec()).toList();

  // ── Legacy field derivation ────────────────────────────────────────────────
  final targetSets = specList.isNotEmpty ? specList.length : 1;

  int legacyRepsMin = 0;
  int legacyRepsMax = 0;
  double? legacyWeightKg;
  List<int> legacyTargetReps = [];
  int? legacyDurationSeconds;

  if (s.exerciseMode == ExerciseMode.duration) {
    legacyDurationSeconds =
        week0.isNotEmpty ? week0.first.durationSeconds : null;
    legacyRepsMin = 0;
    legacyRepsMax = 0;
    legacyTargetReps = [];
  } else {
    // reps mode
    legacyWeightKg = week0.isNotEmpty ? week0.first.weightKg : null;
    if (s.repMode == RepMode.single) {
      final repValues = week0.map((e) => e.reps ?? 0).toList();
      legacyTargetReps = repValues;
      legacyRepsMin =
          repValues.isNotEmpty ? repValues.reduce((a, b) => a < b ? a : b) : 0;
      legacyRepsMax =
          repValues.isNotEmpty ? repValues.reduce((a, b) => a > b ? a : b) : 0;
    } else {
      // range
      legacyRepsMin = week0.isNotEmpty
          ? week0.map((e) => e.repsMin ?? 0).reduce((a, b) => a < b ? a : b)
          : 0;
      legacyRepsMax = week0.isNotEmpty
          ? week0.map((e) => e.repsMax ?? 0).reduce((a, b) => a > b ? a : b)
          : 0;
      legacyTargetReps = [];
    }
  }

  return RoutineSlot(
    exerciseId: s.exercise!.id,
    exerciseName: s.exercise!.name,
    muscleGroup: s.exercise!.muscleGroup,
    targetSets: targetSets,
    targetRepsMin: legacyRepsMin,
    targetRepsMax: legacyRepsMax,
    restSeconds: s.restSeconds,
    targetWeightKg: legacyWeightKg,
    supersetGroup: effectiveGroup,
    targetReps: legacyTargetReps,
    durationSeconds: legacyDurationSeconds,
    exerciseMode: s.exerciseMode,
    repMode: s.repMode,
    sets: specList,
    // Full per-week prescription. Single-week plans write one entry
    // ([[week0]]) so re-editing and effectiveSetsForWeek(0) stay branch-free
    // (ADR-PB-03); `sets:` above keeps old readers on week 0.
    weeklySets: s.weeklySets
        .map((wk) => wk.map((e) => e.toSetSpec()).toList())
        .toList(),
    // Presence mask: sorted for deterministic wire output (ADR-WPRES-07).
    // Empty set → empty list → present in all weeks (backward compat).
    activeWeeks: (s.activeWeeks.toList()..sort()),
    // Emit coaching note; normalize empty/whitespace to null (REQ-EN-003).
    notes: (s.notes?.trim().isNotEmpty ?? false) ? s.notes!.trim() : null,
  );
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// Full-screen plan builder parametrized by [RoutineEditorMode].
///
/// Lives as a **top-level route** (outside the ShellRoute) — has its own
/// Scaffold + AppBackground + SafeArea so it occupies the full screen without
/// the bottom navigation bar.
///
/// Modes (ADR-USR-01):
///   * [TrainerAssigning] — trainer creates a plan for a specific athlete.
///     Submits via [RoutineRepository.createAssigned].
///   * [SelfCreating] — athlete self-authors a personal routine.
///     - existingRoutineId == null → create via [RoutineRepository.createUserOwned].
///     - existingRoutineId != null → edit: hydrates from Firestore via
///       [RoutineRepository.getById], saves via [RoutineRepository.updateUserOwned].
///
/// REQ-COACH-PLANS-023..028 · REQ-USR-011 · REQ-USR-018 ·
/// SCENARIO-457..463, 616..619.
class RoutineEditorScreen extends ConsumerStatefulWidget {
  const RoutineEditorScreen({super.key, required this.mode});

  final RoutineEditorMode mode;

  @override
  ConsumerState<RoutineEditorScreen> createState() =>
      _RoutineEditorScreenState();
}

/// Extracts the doc id the editor must HYDRATE FROM.
/// Returns null for the create-from-blank modes.
///
/// [SelfCustomizing] is the one variant where this id is a SOURCE, not a
/// destination: the editor loads it and then saves a brand-new doc (#647).
/// Everything that keeps the copy from becoming the trainer's routine follows
/// from that split — see [_submit].
String? _existingIdFor(RoutineEditorMode mode) => switch (mode) {
      SelfCreating(:final existingRoutineId) => existingRoutineId,
      SelfCustomizing(:final sourceRoutineId) => sourceRoutineId,
      TrainerAssigning(:final existingPlanId) => existingPlanId,
      TrainerTemplating(:final existingTemplateId) => existingTemplateId,
    };

/// Which custom-exercise onboarding deck this editor should show.
///
/// Keyed off the MODE, not off `userProfileProvider.role`, because the mode is
/// what the copy is about: `SelfCreating` is someone building their own routine
/// and gets the "your library" wording even if they happen to be a trainer,
/// while both trainer modes are building something to assign. Reading the role
/// instead would show a trainer the assign-to-students deck on a routine they
/// are writing for themselves.
OnboardingSurface _onboardingSurfaceFor(RoutineEditorMode mode) =>
    switch (mode) {
      SelfCreating() ||
      SelfCustomizing() =>
        OnboardingSurface.customExerciseAthleteMobile,
      TrainerAssigning() ||
      TrainerTemplating() =>
        OnboardingSurface.customExerciseTrainerMobile,
    };

String _titleFor(RoutineEditorMode mode, AppL10n l10n) => switch (mode) {
      TrainerAssigning(existingPlanId: null) => l10n.coachEditorTitle,
      TrainerAssigning() => l10n.coachEditorEditTitle,
      // Antes reusaban el copy de asignar un plan: crear una PLANTILLA, que
      // no se asigna a nadie, decía "Crear plan". Es el único cambio de copy
      // que el rediseño autoriza (#871). No cambia a qué repositorio se
      // escribe ni cuándo.
      TrainerTemplating(existingTemplateId: null) =>
        l10n.coachTemplateEditorTitle,
      TrainerTemplating() => l10n.coachTemplateEditorEditTitle,
      SelfCreating(existingRoutineId: null) => l10n.workoutSelfEditorTitle,
      SelfCreating() => l10n.workoutSelfEditorEditTitle,
      SelfCustomizing() => l10n.workoutRoutineCustomizeTitle,
    };

String _submitLabelFor(RoutineEditorMode mode, AppL10n l10n) => switch (mode) {
      TrainerAssigning(existingPlanId: null) => l10n.coachEditorSubmit,
      TrainerAssigning() => l10n.coachEditorUpdateLabel,
      // El CTA decía "ASIGNAR PLAN" en una plantilla que no se asigna a nadie.
      TrainerTemplating() => l10n.coachTemplateEditorSubmit,
      SelfCreating(existingRoutineId: null) =>
        l10n.workoutSelfEditorSubmitLabel,
      SelfCreating() => l10n.workoutSelfEditorUpdateLabel,
      SelfCustomizing() => l10n.workoutRoutineCustomizeSubmitLabel,
    };

class _RoutineEditorScreenState extends ConsumerState<RoutineEditorScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _splitController = TextEditingController();

  /// Qué celda de set se está editando, o null. Lo publican las filas y lo
  /// consume la barra de accesorio del `bottomSheet` — entre una y otra hay
  /// cinco niveles de árbol (#867).
  final FocusedCellNotifier _celdaEnfocada = FocusedCellNotifier();

  /// Plain-language resumen of the routine (#648). Written only in the trainer
  /// modes: firestore.rules lists `summary` in the athlete UPDATE path's
  /// `keys()` but NOT in its `affectedKeys()`, so an athlete literally cannot
  /// change it. Showing them a field whose every save is a permission-denied
  /// is worse than not showing it.
  final TextEditingController _summaryController = TextEditingController();
  ExperienceLevel _level = ExperienceLevel.beginner;

  /// ScrollController for the main ListView so we can programmatically
  /// scroll to the first invalid slot when the user taps save.
  final ScrollController _listScrollController = ScrollController();

  /// One GlobalKey per day tile, re-synced whenever [_days] changes.
  /// Used by [Scrollable.ensureVisible] in [_submit] to bring the first
  /// invalid day into view.
  final Map<_EditableDay, GlobalKey> _dayKeys = {};
  // Seeded with an empty name + isDefaultName: true; the real localized label
  // ("Día 1") is filled in by [_relabelDefaultDays] from didChangeDependencies,
  // where a BuildContext (and thus AppL10n) is available.
  List<_EditableDay> _days = [
    _EditableDay(dayNumber: 1, name: '', isDefaultName: true),
  ];

  /// Día visible en las pestañas. Presentación pura: no viaja al modelo.
  ///
  /// Se acota en [_removeDay]: borrar el último día dejaría el índice
  /// apuntando fuera de la lista.
  int _selectedDayIndex = 0;

  /// Subtítulo del app bar: qué es esta rutina y para quién.
  ///
  /// Cubre los CUATRO modos. El handoff de diseño sólo listaba tres — se
  /// olvidaba de [SelfCustomizing] (#647), el alumno que arranca de una rutina
  /// existente y termina con una propia.
  ///
  /// Para [TrainerAssigning] el diseño pedía "Plan para <Nombre>", pero la
  /// pantalla sólo conoce el `athleteId`: resolver el nombre significaría leer
  /// otro provider, y este rediseño no toca la capa de datos. Queda "Plan
  /// asignado" más el split y el nivel, que sí están.
  String _subtituloDelPlan(AppL10n l10n) {
    final partes = <String>[
      switch (widget.mode) {
        SelfCreating() => _sharedOnProfile
            ? l10n.routineEditorSubtitleSelfShared
            : l10n.routineEditorSubtitleSelfPrivate,
        SelfCustomizing() => l10n.routineEditorSubtitleCustomizing,
        TrainerAssigning() => l10n.routineEditorSubtitleAssigned,
        TrainerTemplating() => l10n.routineEditorSubtitleTemplate,
      },
      if (_isTrainerMode && _splitController.text.trim().isNotEmpty)
        _splitController.text.trim(),
      // `displayNameEs` es lo que ya usa el dropdown de nivel. No está
      // localizado —deuda anterior a este PR— pero usar otra cosa acá
      // haría que el subtítulo y el selector digan distinto.
      if (_isTrainerMode) _level.displayNameEs,
      l10n.routineEditorSubtitleWeeks(_numWeeks),
    ];
    // El separador es visual, no gramatical: cada parte es una frase completa
    // por sí sola, así que unirlas no arma una oración en ningún idioma.
    return partes.join(' · ');
  }

  /// Referencia al `setState` de la hoja "DATOS DEL PLAN" mientras está
  /// abierta.
  ///
  /// La hoja modal vive en otro `Navigator`, así que el `setState` de esta
  /// pantalla no la repinta: cambiar el nivel desde la hoja actualizaba el
  /// estado pero la hoja seguía mostrando el valor viejo hasta cerrarla.
  StateSetter? _sheetSetState;

  /// Repinta también la hoja, si está abierta.
  ///
  /// Se sobrescribe `setState` en vez de llamar a un helper en cada call site
  /// porque los controles de la hoja disparan métodos de esta clase —
  /// `_addWeek`, `_removeLastWeek`, `_duplicateWeek`— que ya existían y llaman
  /// al `setState` común. Con un helper aparte había que acordarse de usarlo
  /// en cada uno, y el que se olvidara dejaba la hoja mostrando datos viejos:
  /// agregar semanas actualizaba `_numWeeks` pero la hoja seguía listando las
  /// de antes.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    // La hoja vive en otro Navigator: el setState de esta pantalla no la toca.
    _sheetSetState?.call(() {});
  }

  /// Los campos del plan: nombre, split, objetivos, compartir, nivel y
  /// semanas. Antes ocupaban el tercio superior del scroll; ahora viven en la
  /// hoja del engranaje, en el mismo orden.
  List<Widget> _camposDelPlan(AppL10n l10n, AppPalette palette) {
    // Se calculaban en build() cuando estos campos vivían en el scroll; ahora
    // los necesita la hoja, que se construye en su propio Navigator.
    final invalidWeeks = _invalidWeekFirstDay;
    final hiddenInvalidWeeks =
        invalidWeeks.keys.where((w) => w != _selectedWeek).toList()..sort();
    return [
      // ── Resumen en criollo — trainer modes only (#648) ──
      //
      // Sits right under SPLIT because SPLIT is the jargon it
      // exists to translate: the detail screen's badge opens
      // with "PPL · DÍA 1" and 2 of 5 usability participants
      // could not say what that meant. Asking for the plain
      // sentence next to the term that needs it is what makes
      // the field self-explanatory.
      //
      // Absent in SelfCreating: firestore.rules keeps `summary`
      // out of the athlete UPDATE path's affectedKeys(), so the
      // athlete cannot change it. A field whose every save is a
      // permission-denied is worse than no field.

      // ── Para qué sirve — SOLO modo plantilla (#635 PR#1b) ──
      //
      // Debajo del RESUMEN porque son la misma pregunta a dos
      // niveles: el resumen la contesta en prosa para el humano
      // que lee la card, los objetivos la contestan en enum para
      // el ranking que ordena la grilla.
      //
      // `_isTemplateMode` y no `_isTrainerMode`: en un plan
      // asignado el guardado sería permission-denied, porque
      // firestore.rules deja `goals` fuera del affectedKeys de
      // ese path. Ver el dartdoc del predicado.
      if (_isTemplateMode) ...[
        const SizedBox(height: AppSpacing.s12),
        _SectionLabel(
          label: l10n.routineEditorGoalsLabel,
          palette: palette,
        ),
        const SizedBox(height: AppSpacing.hairline),
        Text(
          l10n.routineEditorGoalsHelp,
          style: GoogleFonts.barlow(
            fontWeight: FontWeight.w400,
            fontSize: 12,
            height: 1.35,
            color: palette.textMuted,
          ),
        ),
        // Sin estado vacío explícito: la bajada ya dice
        // "opcional". Vacío es un estado válido —la plantilla
        // sigue en la grilla, sin señal para rankear— y una línea
        // extra sólo para decirlo empujaba DÍAS DEL PLAN fuera
        // del área construida del ListView.
        const SizedBox(height: AppSpacing.s8),
        Wrap(
          key: const Key('editor_goals_picker'),
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            for (final goal in RoutineGoal.values)
              _GoalChip(
                key: Key('editor_goal_${goal.wireKey}'),
                label: templatesGoalLabel(l10n, goal),
                selected: _goals.contains(goal),
                palette: palette,
                onTap: () {
                  _markDirty();
                  setState(() {
                    // Toggle: volver a tocar deselecciona. Sin
                    // esto no habría forma de corregir un tap
                    // equivocado salvo recargando el editor.
                    if (!_goals.remove(goal)) _goals.add(goal);
                  });
                },
              ),
          ],
        ),
      ],

      // ── Row: Share on public profile — SelfCreating only
      //
      // Toggle that flips the routine's `visibility`
      // between `private` (default) and `public`. When
      // public, the routine shows in the "RUTINAS
      // PÚBLICAS" tab of the athlete's public profile.
      if (!_isTrainerMode) ...[
        const SizedBox(height: 12),
        _ShareOnProfileTile(
          value: _sharedOnProfile,
          palette: palette,
          onChanged: (v) {
            _markDirty();
            setState(() => _sharedOnProfile = v);
          },
        ),
      ],

      // ── Row: Level — trainer modes only ─────────────────
      if (_isTrainerMode) ...[
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel(
                      label: l10n.routineEditorLevelSection, palette: palette),
                  const SizedBox(height: 4),
                  _LevelDropdown(
                    value: _level,
                    palette: palette,
                    onChanged: (v) {
                      if (v != null) {
                        _markDirty();
                        setState(() => _level = v);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 12),

      // ── Semanas del plan ────────────────────────────────
      // Week state machine — REQ-PERIOD-010..014. The chips
      // switch the week every slot editor renders (live-view).
      _SectionLabel(label: l10n.routineEditorWeeksSection, palette: palette),
      const SizedBox(height: 6),
      _WeekTabBar(
        numWeeks: _numWeeks,
        selectedWeek: _selectedWeek,
        maxWeeks: _kMaxWeeks,
        warningWeeks: hiddenInvalidWeeks.toSet(),
        palette: palette,
        onSelectWeek: (w) {
          // Drop focus BEFORE swapping the week's field tree:
          // on-device the iOS IME can restore its editing
          // session into the replacement TextField and bleed
          // the previous week's value into the new week
          // (not reproducible in widget tests — no real IME).
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() => _selectedWeek = w);
        },
        onAddWeek: _addWeek,
        onRemoveLastWeek: _removeLastWeek,
        onDuplicateWeek: () => _duplicateWeek(),
      ),
      if (hiddenInvalidWeeks.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          '${l10n.routineEditorIncompleteSetsLabel(hiddenInvalidWeeks.first + 1)} · Día '
          '${invalidWeeks[hiddenInvalidWeeks.first]}',
          key: const Key('invalid_week_hint'),
          style: GoogleFonts.barlow(
            fontSize: 11,
            color: palette.danger,
          ),
        ),
      ],
      const SizedBox(height: 12),
    ];
  }

  /// Abre la hoja "DATOS DEL PLAN".
  Future<void> _abrirDatosDelPlan() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          _sheetSetState = setSheetState;
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.78,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: AppSpacing.s12),
                  Container(
                    width: 40,
                    height: AppSpacing.hairline,
                    decoration: BoxDecoration(
                      color: palette.borderStrong,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s18,
                      AppSpacing.s14,
                      AppSpacing.s8,
                      0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.routineEditorPlanSheetTitle,
                            style: GoogleFonts.barlowCondensed(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const Key('plan_sheet_close'),
                          icon: Icon(TreinoIcon.close,
                              size: 18, color: palette.textMuted),
                          tooltip: l10n.commonClose,
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.s18,
                        AppSpacing.s8,
                        AppSpacing.s18,
                        AppSpacing.s20,
                      ),
                      children: _camposDelPlan(l10n, palette),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    _sheetSetState = null;
  }

  /// Estado que la pestaña de un día comunica con su punto de color.
  ///
  /// Distingue "vacío" de "inválido" a propósito: un día sin ejercicios es un
  /// estado intermedio legítimo mientras se arma la rutina (warning), y un día
  /// con sets sin completar bloquea el guardado (danger).
  DayTabStatus _dayStatus(_EditableDay day) {
    final visibles =
        day.slots.where((s) => s.isPresentInWeek(_selectedWeek)).toList();
    if (visibles.isEmpty) return DayTabStatus.empty;
    for (final slot in visibles) {
      final sets = slot.setsForWeek(_selectedWeek);
      if (sets.isEmpty ||
          !sets.every((s) => isSetValid(s, slot.exerciseMode, slot.repMode))) {
        return DayTabStatus.invalid;
      }
    }
    return DayTabStatus.ok;
  }

  /// 0-based week shown in the editor. Display is 1-based ("Sem 1").
  int _selectedWeek = 0;

  /// Plan length in weeks. Every slot's `weeklySets` holds exactly this many
  /// inner lists (REQ-PERIOD-013). Capped at 16 (REQ-PERIOD-011).
  int _numWeeks = 1;

  /// Whether this user-created routine is shared on the athlete's public
  /// profile ("RUTINAS PÚBLICAS" tab). Defaults to `false` (private) — the
  /// same default as before the toggle existed, so nothing changes for users
  /// who don't opt in. Only meaningful in [SelfCreating] mode; ignored by
  /// trainer flows.
  bool _sharedOnProfile = false;

  /// Objetivos declarados de la plantilla (#635 PR#1b).
  ///
  /// `Set` y no `List`: la selección es un conjunto sin orden ni repetidos, y
  /// que dos PF elijan lo mismo en distinto orden no puede producir documentos
  /// distintos. Se serializa en el orden del enum al guardar.
  ///
  /// Vacío es un estado VÁLIDO, no un formulario a medio llenar: sin objetivos
  /// la plantilla sigue apareciendo en la grilla, sólo que sin señal para
  /// rankear. Por eso no hay validación que lo exija.
  final Set<RoutineGoal> _goals = <RoutineGoal>{};

  bool _submitting = false;

  /// True while the existing routine is being fetched from Firestore.
  /// Relevant in any mode with an existing id (all three edit variants).
  bool _loading = false;

  /// Shown when the routine to edit no longer exists in Firestore.
  bool _loadNotFound = false;

  /// True once the user has touched anything (name/split text, level, or any
  /// day/slot/set mutation). Drives the unsaved-changes guard (PopScope +
  /// "¿Descartar cambios?" dialog) on both the AppBar back button and the
  /// iOS edge-swipe / system back gesture.
  bool _isDirty = false;

  /// Suppresses dirtiness while we hydrate the editor from Firestore — the
  /// hydration path mutates the name controller and `_days`, which would
  /// otherwise mark a freshly-loaded routine as dirty.
  bool _hydrating = false;

  @override
  void initState() {
    super.initState();
    // Typing in the name/split fields marks the editor dirty. Guarded by
    // `_hydrating` so loading an existing routine doesn't trip the flag.
    _nameController.addListener(_markDirty);
    _splitController.addListener(_markDirty);
    _summaryController.addListener(_markDirty);
    // Hydrate editor when editing an existing routine/plan/template.
    // Works for all three modes: SelfCreating, TrainerAssigning, TrainerTemplating.
    final existingId = _existingIdFor(widget.mode);
    if (existingId != null) {
      _loadExistingRoutine(existingId);
    } else {
      // Create mode only — `existingId == null` is exactly that for three of
      // the four variants, so quien entra por deep-link a una rutina que ya
      // existe nunca recibe el onboarding encima de su plan.
      //
      // `SelfCustomizing` es la excepción y hoy queda AFUERA: su id es un
      // SOURCE, no un destino (ver `_existingIdFor`), así que nunca es null y
      // esta rama no corre. O sea que el atleta que arranca de una plantilla
      // —que está armando su propia rutina igual que `SelfCreating`— no ve
      // este onboarding. Es un gap conocido, no un descuido: incluirlo pide
      // separar "hidrata de un id" de "edita algo existente", que es un
      // cambio de #647 y no de este PR. `_onboardingSurfaceFor` ya lo mapea
      // al deck de atleta para cuando eso pase.
      //
      // Post-frame, not here: `initState` has no `Localizations` ancestor
      // resolved yet and the navigator cannot present mid-frame. In create mode
      // `_loading` is false, so the editor is fully laid out by then.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        maybeShowCustomExerciseOnboarding(
          context: context,
          ref: ref,
          surface: _onboardingSurfaceFor(widget.mode),
        );
      });
    }
  }

  /// Los objetivos elegidos, en orden del enum.
  ///
  /// El orden importa aunque el conjunto no: sin normalizar, dos PF que
  /// eligen lo mismo tocando en distinto orden producirían arrays distintos
  /// en Firestore, y cualquier comparación de documentos —tests, diffs,
  /// deduplicación futura— los vería como diferentes sin serlo.
  List<RoutineGoal> get _goalsOrdered =>
      RoutineGoal.values.where(_goals.contains).toList(growable: false);

  /// Marks the editor as having unsaved changes. No-op while hydrating.
  ///
  /// Deliberately sets the flag WITHOUT its own setState: every caller either
  /// runs alongside a setState that mutates editor data (structural methods),
  /// is itself inside a setState body, or fires from a TextField whose
  /// onChanged already rebuilds. PopScope re-reads `canPop` on each pop
  /// attempt, so no extra rebuild is needed for the guard to be live.
  void _markDirty() {
    if (_hydrating) return;
    _isDirty = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Localize (and re-localize on locale change) every auto-named day. Custom
    // names hydrated from a saved routine are left untouched.
    _relabelDefaultDays();
  }

  /// Rewrites the [name] of every default-named day to the current locale's
  /// "Día N" label. No-op for days the user/trainer named explicitly.
  void _relabelDefaultDays() {
    final l10n = AppL10n.of(context);
    for (final day in _days) {
      if (day.isDefaultName) {
        day.name = l10n.routineEditorDayName(day.dayNumber);
      }
    }
  }

  /// Commits an inline edit of the day-name field. Empty/whitespace-only
  /// input restores the localized default "Día N" (decisión 2A 2026-06-29 —
  /// borrar todo el texto significa "no quiero nombre custom" sin tener que
  /// mostrar un error). Setting `isDefaultName` is what prevents future
  /// `_relabelDefaultDays()` passes from clobbering the user's custom text.
  void _onDayNameChanged(int dayIndex, String newName) {
    final trimmed = newName.trim();
    final day = _days[dayIndex];
    final l10n = AppL10n.of(context);
    setState(() {
      if (trimmed.isEmpty) {
        day.name = l10n.routineEditorDayName(day.dayNumber);
        day.isDefaultName = true;
      } else {
        day.name = trimmed;
        day.isDefaultName = trimmed == l10n.routineEditorDayName(day.dayNumber);
      }
    });
    _markDirty();
  }

  /// Pads/truncates [slot]'s weeklySets to exactly `_numWeeks` inner lists
  /// and guarantees the one-placeholder-set minimum per week — defensive
  /// against docs whose slots disagree with `numWeeks` (REQ-PERIOD-018).
  /// Also clamps the presence mask: any index outside [0 .. _numWeeks-1] is
  /// dropped so a hand-edited doc can't carry dangling indices (ADR-WPRES-06).
  void _normalizeSlotWeeks(_EditableSlot slot) {
    while (slot.weeklySets.length < _numWeeks) {
      slot.weeklySets.add([_EditableSet()]);
    }
    if (slot.weeklySets.length > _numWeeks) {
      slot.weeklySets.removeRange(_numWeeks, slot.weeklySets.length);
    }
    for (var w = 0; w < slot.weeklySets.length; w++) {
      if (slot.weeklySets[w].isEmpty) {
        slot.weeklySets[w] = [_EditableSet()];
      }
    }
    // Clamp presence mask to valid week range.
    slot.activeWeeks.removeWhere((w) => w < 0 || w >= _numWeeks);
  }

  /// Fetches the existing routine from Firestore and maps it into editor state.
  /// Mode-agnostic: the hydration mapping is the same for all three edit modes.
  Future<void> _loadExistingRoutine(String id) async {
    setState(() => _loading = true);
    try {
      final routine = await ref.read(routineRepositoryProvider).getById(id);
      if (!mounted) return;
      if (routine == null) {
        setState(() {
          _loading = false;
          _loadNotFound = true;
        });
        return;
      }
      // Map Routine → editor state — inverse of the create path in _submit().
      // Applies equally to SelfCreating / TrainerAssigning / TrainerTemplating.
      // Guard against the controller listeners marking a freshly-loaded
      // routine dirty while we assign their text below.
      _hydrating = true;
      final l10n = AppL10n.of(context);
      // A copy must not land in MIS RUTINAS wearing the template's exact name
      // — five identical "Push Pull Legs — Principiante" are unusable (#647).
      // The suffix is a STARTING POINT, not a lock: the name field is the
      // first thing on screen and the athlete can rewrite it before saving.
      _nameController.text = _isCustomizing
          ? l10n.workoutRoutineCopyName(routine.name)
          : routine.name;
      _level = routine.level;
      // Defensive clamp — a hand-edited doc can't exceed the editor cap nor
      // drop below one week (REQ-PERIOD-011/018).
      _numWeeks = routine.numWeeks.clamp(1, _kMaxWeeks);
      // Restore the athlete's routine-visibility toggle. Only meaningful in
      // SelfCreating mode; trainer flows ignore this state.
      //
      // NOT inherited when customizing: every copyable source is `public`
      // (that is what makes it readable in the first place), so hydrating the
      // toggle from it would publish a copy of the catalogue on the athlete's
      // public profile the moment they tap save — a share they never asked
      // for. A copy starts private, exactly like a from-scratch routine, and
      // the athlete opts in from the same toggle if they want to.
      _sharedOnProfile =
          !_isCustomizing && routine.visibility == RoutineVisibility.public;
      // split is shown in trainer modes — restore it so the field is populated.
      if (routine.split != null) {
        _splitController.text = routine.split!;
      }
      // Resumen (#648). Hydrated for every mode that EDITS the doc it loaded:
      // the field only RENDERS in trainer modes, but a routine that carries a
      // resumen must round-trip it whatever mode reopens it. An athlete
      // editing a plan is never asked about it and never writes it (the
      // athlete branches of _submit omit `summary` entirely), so hydrating
      // here costs nothing and losing it would be silent data destruction.
      //
      // Excepto al COPIAR (#647): ahí el destino es un doc NUEVO que no lleva
      // resumen. Los branches de atleta de _submit ya omiten `summary`, así
      // que hidratarlo sería inerte — pero dejaría el controller cargado con
      // prosa del PF que la copia no va a tener, y el día que el editor del
      // atleta gane un campo de resumen empezaría a copiarla en silencio. Que
      // el estado coincida con el resultado.
      // Los objetivos SÍ se hidratan al personalizar (#635 PR#1b): a
      // diferencia del resumen, describen el contenido que se está copiando,
      // no la autoría de quien lo escribió. Una copia de una plantilla de
      // fuerza sigue siendo de fuerza. Y el selector sólo se muestra en modo
      // plantilla, así que en `SelfCustomizing` esto queda inerte de todos
      // modos — se hidrata igual para no depender de esa coincidencia.
      _goals
        ..clear()
        ..addAll(routine.goals);
      if (!_isCustomizing && routine.summary != null) {
        _summaryController.text = routine.summary!;
      }
      _days = routine.days.map((day) {
        final editableDay = _EditableDay(
          dayNumber: day.dayNumber,
          name: day.name,
          // A persisted day whose name still matches the localized default
          // ('Día N') is treated as default-named, so deleting a day keeps
          // re-numbering the remaining default-named days. A custom name set
          // by the user no longer matches and is preserved as-is.
          isDefaultName: day.name == l10n.routineEditorDayName(day.dayNumber),
        );
        editableDay.slots = day.slots.map((slot) {
          final editableSlot = _EditableSlot()
            // Una rutina que se abre nace TODA plegada, incluidos los
            // ejercicios a los que les falta completar sets: ésos se marcan
            // con el borde rojo de la card. Abrir cinco cards de golpe al
            // entrar es la pantalla de scroll infinito que el rediseño vino a
            // sacar.
            ..expandido = false
            ..exercise = Exercise(
              id: slot.exerciseId,
              name: slot.exerciseName,
              muscleGroup: slot.muscleGroup,
              category:
                  'compound', // denormalized — category not stored in slot
            )
            ..exerciseMode = slot.effectiveExerciseMode
            ..restSeconds = slot.restSeconds
            ..supersetGroup = slot.supersetGroup
            // Hydrate presence mask from the domain slot (REQ-WPRES-001).
            // Legacy docs have empty activeWeeks → empty set → all weeks.
            ..activeWeeks = slot.activeWeeks.toSet()
            // Hydrate coaching note unconditionally — data retention is
            // mode-independent (REQ-EN-005, bug fix: notes were lost on re-edit).
            ..notes = slot.notes;

          // Periodized docs hydrate every week from weeklySets; legacy docs
          // hydrate week 0 from effectiveSets so the original prescription
          // survives intact (REQ-PERIOD-018/019, SCENARIO-PERIOD-018/019).
          if (slot.weeklySets.isNotEmpty) {
            editableSlot.weeklySets = slot.weeklySets
                .map((wk) => wk.map(_editableSetFromSpec).toList())
                .toList();
          } else {
            editableSlot.weeklySets = [
              slot.effectiveSets.map(_editableSetFromSpec).toList(),
            ];
          }
          // Derive rep mode from the actual hydrated sets, not the slot's legacy
          // targetRepsMin/Max — otherwise an exercise whose sets carry only a
          // single `reps` value gets forced into REP RANGE with empty min/max
          // fields on edit (the bug seen on "Press de banca").
          editableSlot.repMode =
              _repModeFromHydratedSets(editableSlot.weeklySets);
          _normalizeSlotWeeks(editableSlot);
          return editableSlot;
        }).toList();
        return editableDay;
      }).toList();
      if (_days.isEmpty) {
        _days = [
          _EditableDay(
            dayNumber: 1,
            name: l10n.routineEditorDayName(1),
            isDefaultName: true,
          ),
        ];
      }
      _hydrating = false;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      _hydrating = false;
      setState(() {
        _loading = false;
        _loadNotFound = true;
      });
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_markDirty);
    _splitController.removeListener(_markDirty);
    _summaryController.removeListener(_markDirty);
    _nameController.dispose();
    _splitController.dispose();
    _celdaEnfocada.dispose();
    _summaryController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  /// Returns or creates a stable [GlobalKey] for [day]. Keys survive rebuilds
  /// because they are keyed on the [_EditableDay] identity (same instance across
  /// setState calls), not on the day's position in the list.
  GlobalKey _keyForDay(_EditableDay day) =>
      _dayKeys.putIfAbsent(day, () => GlobalKey());

  /// Finds the first day + slot where the current week has an invalid set.
  /// Returns null when every slot is valid.
  ({_EditableDay day, String? exerciseName})? _firstInvalidSlot() {
    for (final day in _days) {
      for (final slot in day.slots) {
        if (!slot.isPresentInWeek(_selectedWeek)) continue;
        final weekSets = slot.setsForWeek(_selectedWeek);
        final allValid = weekSets.isNotEmpty &&
            weekSets
                .every((s) => isSetValid(s, slot.exerciseMode, slot.repMode));
        if (!allValid) {
          return (day: day, exerciseName: slot.exercise?.name);
        }
      }
    }
    return null;
  }

  /// TODOS los problemas que impiden guardar, en el orden en que un usuario
  /// llena el formulario: nombre → un ejercicio por día → sin repetidos → sets
  /// completos → semanas que no se ven.
  ///
  /// Hasta #868 sólo existía [_firstValidationError], porque la validación
  /// corría al tocar guardar y salía por un `SnackBar`: un mensaje efímero no
  /// tiene lugar para más de un problema. El pie sí, y decir "faltan dos
  /// cosas" en vez de descubrirlas de a una es la diferencia entre corregir en
  /// una pasada o en cuatro.
  ///
  /// Es PURO: lo llama `build` en cada frame de tipeo. Recorre los sets con
  /// aritmética, sin construir widgets ni tocar estado — un plan grande son
  /// ~240 sets, que es barato comparado con el árbol que ese mismo build arma.
  List<({String mensaje, _EditableDay? dia})> _problemas(AppL10n l10n) {
    final out = <({String mensaje, _EditableDay? dia})>[];

    if (_nameController.text.trim().isEmpty) {
      out.add((mensaje: l10n.routineEditorProblemMissingName, dia: null));
    }
    if (_isTrainerMode && _splitController.text.trim().isEmpty) {
      out.add((mensaje: l10n.routineEditorProblemMissingSplit, dia: null));
    }

    for (final day in _days) {
      final tieneEjercicio = day.slots.any((s) => s.exercise != null);
      if (day.slots.isEmpty || !tieneEjercicio) {
        out.add((
          mensaje: l10n.routineEditorProblemEmptyDay(day.dayNumber),
          dia: day,
        ));
        continue;
      }
      if (dayHasDuplicateExerciseId(
        day.slots.where((s) => s.exercise != null).map((s) => s.exercise!.id),
      )) {
        out.add((
          mensaje: l10n.routineEditorProblemDuplicate(day.dayNumber),
          dia: day,
        ));
      }
      // Sets incompletos de la semana EN CURSO. Los de otras semanas se
      // cuentan aparte: nombrar "día 2" cuando el problema está en una semana
      // que no se ve manda al usuario a mirar una tabla que está bien.
      var incompletos = 0;
      for (final slot in day.slots) {
        if (!slot.isPresentInWeek(_selectedWeek)) continue;
        final sets = slot.setsForWeek(_selectedWeek);
        if (sets.isEmpty) {
          incompletos++;
          continue;
        }
        incompletos += sets
            .where((s) => !isSetValid(s, slot.exerciseMode, slot.repMode))
            .length;
      }
      if (incompletos > 0) {
        out.add((
          mensaje: l10n.routineEditorProblemIncompleteSets(
              day.dayNumber, incompletos),
          dia: day,
        ));
      }
    }

    // Semanas que no están a la vista. Desde #866 el chip de semana vive
    // dentro de la hoja del engranaje, así que si no se dice acá el guardado
    // queda bloqueado sin ninguna explicación en pantalla.
    final rotas = _invalidWeekFirstDay;
    for (final semana in rotas.keys.where((w) => w != _selectedWeek).toList()
      ..sort()) {
      out.add((
        mensaje: l10n.routineEditorProblemOtherWeek(semana + 1, rotas[semana]!),
        dia: null,
      ));
    }
    return out;
  }

  /// El resumen del pie cuando no falta nada: `2 días · 41 sets · todo listo`.
  ///
  /// Cuenta los sets de la semana en curso y sólo de los slots presentes en
  /// ella (ADR-WPRES): un slot borrado "sólo de esta semana" sigue en el
  /// modelo y contarlo daría un número que no coincide con lo que se ve.
  String _resumenPie(AppL10n l10n) {
    var sets = 0;
    for (final day in _days) {
      for (final slot in day.slots) {
        if (!slot.isPresentInWeek(_selectedWeek)) continue;
        sets += slot.setsForWeek(_selectedWeek).length;
      }
    }
    return l10n.routineEditorFooterSummary(_days.length, sets);
  }

  /// Lleva al usuario al día [dia]: lo selecciona y lo trae a la vista.
  ///
  /// Con pestañas, "llevar al error" es SELECCIONAR el día, no expandirlo: si
  /// el día ofensor no es el visible, su contenido ni siquiera está en el
  /// árbol y el scroll no tiene a dónde ir.
  void _irAlDia(_EditableDay dia) {
    final indice = _days.indexOf(dia);
    if (indice < 0) return;
    if (indice != _selectedDayIndex) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _selectedDayIndex = indice);
    }
    // Esperar un frame a que el día nuevo se monte antes de scrollear.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _keyForDay(dia);
      if (key.currentContext == null) return;
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: AppMotion.slow,
        curve: AppMotion.emphasized,
        alignment: 0.1,
      );
    });
  }

  /// Resolves the FIRST unmet save requirement into a specific, actionable
  /// message — so the user learns WHAT is missing instead of seeing the
  /// generic "incomplete sets" feedback regardless of cause (finding 21).
  ///
  /// Priority mirrors the order a user fills the form: name → at least one
  /// exercise per day → complete reps/duration on every visible set. Returns
  /// the offending [day] (when one applies) so the caller can scroll it into
  /// view, and `null` when the form is fully valid.
  ({String message, _EditableDay? day})? _firstValidationError(AppL10n l10n) {
    // 1) Name.
    if (_nameController.text.trim().isEmpty) {
      return (message: l10n.routineEditorMissingName, day: null);
    }
    // 2) Every day needs at least one exercise.
    for (final day in _days) {
      final hasExercise = day.slots.any((s) => s.exercise != null);
      if (day.slots.isEmpty || !hasExercise) {
        return (
          message: l10n.routineEditorMissingExercise(day.dayNumber),
          day: day,
        );
      }
    }
    // 3) No duplicate exercise within a day (QA-WKT-004).
    for (final day in _days) {
      if (dayHasDuplicateExerciseId(
        day.slots.where((s) => s.exercise != null).map((s) => s.exercise!.id),
      )) {
        return (message: l10n.routineEditorDuplicateExercise, day: day);
      }
    }
    // 4) Incomplete sets. Prefer the named-exercise feedback when we can point
    // at a specific exercise; otherwise fall back to the generic reps hint.
    final invalid = _firstInvalidSlot();
    if (invalid != null) {
      final name = invalid.exerciseName;
      return (
        message: name != null
            ? l10n.routineEditorIncompleteSetsFeedback(name)
            : l10n.routineEditorMissingReps,
        day: invalid.day,
      );
    }
    // 5) El problema está en OTRA semana.
    //
    // `_firstInvalidSlot` mira sólo `_selectedWeek`, pero `_isValid` mira
    // todas: sin esta rama el guardado quedaba bloqueado y sin mensaje —el
    // botón parecía muerto—. Antes el chip de semana con warning estaba
    // siempre a la vista y alcanzaba como explicación; desde #866 vive dentro
    // de la hoja del engranaje, así que hay que decirlo en voz alta.
    final semanasRotas = _invalidWeekFirstDay;
    final otra = semanasRotas.keys.where((w) => w != _selectedWeek).toList()
      ..sort();
    if (otra.isNotEmpty) {
      final semana = otra.first;
      final dia = semanasRotas[semana]!;
      // Llevar al usuario al problema, no sólo nombrárselo.
      if (semana != _selectedWeek) {
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() => _selectedWeek = semana);
      }
      return (
        message: l10n.routineEditorInvalidWeekHint(semana + 1, dia),
        day: null,
      );
    }
    return null;
  }

  /// Whether the editor is in a trainer-creating mode (assigning or
  /// templating). Athlete (SelfCreating / SelfCustomizing) modes hide
  /// trainer-only fields.
  /// REQ-RER-012, REQ-RER-013, ADR-RER-04.
  bool get _isTrainerMode =>
      widget.mode is TrainerAssigning || widget.mode is TrainerTemplating;

  /// Sólo el editor de PLANTILLAS, no el de planes asignados (#635 PR#1b).
  ///
  /// Más angosto que [_isTrainerMode] a propósito. Un plan asignado es privado
  /// de un alumno y nunca entra a la grilla de PLANTILLAS, así que declarar su
  /// objetivo no ordena nada — y `firestore.rules` deja `goals` fuera del
  /// `affectedKeys()` de ese path. Mostrar el selector ahí daría un campo cuyo
  /// guardado siempre falla con permission-denied, que es peor que no tenerlo:
  /// el mismo criterio con el que `summary` se ausenta del editor del atleta.
  bool get _isTemplateMode => widget.mode is TrainerTemplating;

  /// Whether the editor is copying an existing routine into a new one (#647).
  /// Drives the three places where hydration must NOT be faithful: the name
  /// (gets a copy suffix), the share-on-profile toggle (never inherited) and
  /// the resumen (the copy does not carry the PF's).
  bool get _isCustomizing => widget.mode is SelfCustomizing;

  /// The resumen to persist, or `null` when the PF left it blank (#648).
  ///
  /// The field is OPTIONAL: an empty (or whitespace-only) box must save as
  /// `null`, not as `''`. `optStrMaxLen` accepts both, but an empty string
  /// would make `routine.summary != null` true on the detail screen and
  /// render an empty paragraph where the layout is supposed to collapse.
  String? get _summaryOrNull {
    final trimmed = _summaryController.text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Per-week validation across ALL weeks — maps each invalid week (0-based)
  /// to the first day number that fails on it. Empty when every week is
  /// valid. Drives both the save gate and the per-tab warning affordance
  /// (REQ-PERIOD-016, SCENARIO-PERIOD-020).
  ///
  /// Presence-aware: a slot absent in week [w] (non-empty mask not containing
  /// [w]) is skipped for that week's validation — it contributes no sets to
  /// that week and its placeholder sets must not block save.
  Map<int, int> get _invalidWeekFirstDay {
    final result = <int, int>{};
    for (final day in _days) {
      for (final slot in day.slots) {
        for (var w = 0; w < slot.weeklySets.length; w++) {
          if (result.containsKey(w)) continue;
          // Skip validation for weeks where this slot is absent.
          if (!slot.isPresentInWeek(w)) continue;
          final weekSets = slot.weeklySets[w];
          final weekValid = weekSets.isNotEmpty &&
              weekSets
                  .every((s) => isSetValid(s, slot.exerciseMode, slot.repMode));
          if (!weekValid) result[w] = day.dayNumber;
        }
      }
    }
    return result;
  }

  /// Returns true when [activeWeeks] is a valid presence mask for a plan
  /// with [numWeeks] weeks. A mask is valid when it is empty (all weeks) OR
  /// all its indices fall within [0 .. numWeeks-1] (at least one in-range
  /// week). An all-out-of-range non-empty mask would create a ghost slot that
  /// is invisible everywhere (ADR-WPRES-03, REQ-WPRES-014).
  static bool _isPresenceMaskValid(Set<int> activeWeeks, int numWeeks) {
    if (activeWeeks.isEmpty) return true;
    return activeWeeks.any((w) => w >= 0 && w < numWeeks);
  }

  bool get _isValid {
    if (_nameController.text.trim().isEmpty) return false;
    // Split is required only in trainer modes (athlete-created routines
    // submit split: null per ADR-RER-04).
    if (_isTrainerMode && _splitController.text.trim().isEmpty) return false;
    if (_days.isEmpty) return false;
    for (final day in _days) {
      if (day.slots.isEmpty) return false;
      // QA-WKT-004: no duplicate exerciseId within a day.
      if (dayHasDuplicateExerciseId(
        day.slots.where((s) => s.exercise != null).map((s) => s.exercise!.id),
      )) {
        return false;
      }
      for (final slot in day.slots) {
        if (slot.exercise == null) return false;
        // Zero-presence guard (ADR-WPRES-03, REQ-WPRES-014): a non-empty mask
        // that excludes every valid week would create an invisible ghost slot.
        if (!_isPresenceMaskValid(slot.activeWeeks, _numWeeks)) return false;
      }
    }
    // Every week of every slot must have at least one valid set
    // (REQ-PERIOD-016).
    return _invalidWeekFirstDay.isEmpty;
  }

  // ── Week operations — keep every slot at exactly `_numWeeks` inner lists ──

  /// Hard cap on plan length (REQ-PERIOD-011) — also bounds Firestore doc
  /// size since weeklySets duplicates per-week set data.
  static const int _kMaxWeeks = 16;

  /// Client-side cap of the resumen field (#648). MUST stay equal to the
  /// `optStrMaxLen(..., 280)` guard on the two trainer UPDATE paths of
  /// firestore.rules — the rule is the real enforcement (a patched client
  /// would ignore this one), and this is the affordance that keeps an honest
  /// PF from ever meeting it as a permission-denied.
  ///
  /// The 7 seeded system summaries measure 61–100 characters; 280 leaves room
  /// without inviting an essay into a card subtitle.
  ///
  /// The web editor (`routine_editor_web_screen.dart`) carries its own copy of
  /// this number, the same way `_kMaxWeeks` is duplicated there: the two
  /// editors share no presentation code. Both are mirrors of the rule.
  static const int _kSummaryMaxLength = 280;

  /// Appends an EMPTY week (one placeholder set per slot) and jumps to it.
  /// Empty by design — "Duplicar semana" is the explicit copy affordance
  /// (ADR-PB-04). SCENARIO-PERIOD-010/011.
  void _addWeek() {
    if (_numWeeks >= _kMaxWeeks) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _markDirty();
    setState(() {
      _numWeeks++;
      for (final day in _days) {
        for (final slot in day.slots) {
          slot.weeklySets.add([_EditableSet()]);
        }
      }
      _selectedWeek = _numWeeks - 1;
    });
  }

  /// Drops the last week and its data from every slot, clamping the selected
  /// week (REQ-PERIOD-012, SCENARIO-PERIOD-012/013).
  void _removeLastWeek() {
    if (_numWeeks <= 1) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _markDirty();
    setState(() {
      final removedIndex = _numWeeks - 1; // the index being removed
      _numWeeks--;
      for (final day in _days) {
        for (final slot in day.slots) {
          slot.weeklySets.removeLast();
          // Drop the removed week's index from the presence mask
          // (ADR-WPRES-05). If this empties a non-empty mask, the slot falls
          // back to all-weeks (empty = all) rather than becoming a ghost.
          slot.activeWeeks.remove(removedIndex);
        }
      }
      if (_selectedWeek > _numWeeks - 1) {
        _selectedWeek = _numWeeks - 1;
      }
    });
  }

  /// Shows a confirmation dialog and, if confirmed, replaces the selected
  /// week's sets with a deep copy of the previous week's, slot by slot
  /// (REQ-PERIOD-014, SCENARIO-PERIOD-015/016). Uses [_EditableSet.copy] so
  /// set types survive the duplication.
  /// Also copies presence: a slot present in `_selectedWeek - 1` becomes
  /// present in `_selectedWeek` too (ADR-WPRES-06, SCENARIO-WPRES-020).
  ///
  /// The [FocusManager.instance.unfocus()] is called BEFORE the dialog to
  /// dismiss the IME and avoid keyboard-related assertion errors on iOS.
  Future<void> _duplicateWeek() async {
    if (_selectedWeek == 0) return;
    // Dismiss IME before showing dialog — avoids on-device IME state leaks.
    FocusManager.instance.primaryFocus?.unfocus();

    final l10n = AppL10n.of(context);
    final sourceWeekDisplay =
        _selectedWeek; // 1-based (selectedWeek is 0-based)
    final targetWeekDisplay = _selectedWeek + 1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return AlertDialog(
          backgroundColor: palette.bgCard,
          title: Text(
            l10n.routineEditorDuplicateWeekTitle,
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            l10n.routineEditorDuplicateWeekBody(
                sourceWeekDisplay, targetWeekDisplay),
            style: TextStyle(color: palette.textMuted, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.routineEditorDialogCancel,
                  style: TextStyle(color: palette.textMuted)),
            ),
            TextButton(
              key: const Key('duplicate_week_confirm_button'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.routineEditorDialogConfirm,
                  style: TextStyle(color: palette.accent)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    if (!mounted) return;

    _markDirty();
    setState(() {
      final sourceWeek = _selectedWeek - 1;
      final targetWeek = _selectedWeek;
      for (final day in _days) {
        for (final slot in day.slots) {
          // Duplicate prescription (REQ-PERIOD-014).
          slot.weeklySets[targetWeek] =
              slot.weeklySets[sourceWeek].map((e) => e.copy()).toList();

          // Duplicate presence (ADR-WPRES-06, SCENARIO-WPRES-020):
          // Only act when the source mask is non-empty; an empty mask means
          // "present in all weeks" — target inherits this transitively, so no
          // materialization is needed.
          if (slot.activeWeeks.isNotEmpty) {
            if (slot.isPresentInWeek(sourceWeek)) {
              // Source present → add target week to the mask.
              slot.activeWeeks = Set<int>.from(slot.activeWeeks)
                ..add(targetWeek);
            } else {
              // Source absent → ensure target is also absent.
              slot.activeWeeks = Set<int>.from(slot.activeWeeks)
                ..remove(targetWeek);
            }
          }
        }
      }
    });
  }

  /// A week has at most 7 days, so a plan can't have more (device feedback
  /// 2026-06-11).
  static const int _kMaxDays = 7;

  void _addDay() {
    if (_days.length >= _kMaxDays) return;
    final l10n = AppL10n.of(context);
    _markDirty();
    setState(() {
      final n = _days.length + 1;
      _days = [
        ..._days,
        _EditableDay(
          dayNumber: n,
          name: l10n.routineEditorDayName(n),
          isDefaultName: true,
        ),
      ];
      // Agregar un día y quedarse mirando el anterior no tiene sentido.
      _selectedDayIndex = _days.length - 1;
    });
  }

  void _removeDay(int index) {
    final l10n = AppL10n.of(context);
    _markDirty();
    setState(() {
      // Acotar la pestaña activa ANTES de tocar la lista: borrar el último día
      // dejaría _selectedDayIndex apuntando a un índice que ya no existe.
      if (_selectedDayIndex >= _days.length - 1) {
        _selectedDayIndex = (_days.length - 2).clamp(0, _days.length - 1);
      } else if (index < _selectedDayIndex) {
        _selectedDayIndex--;
      }
      _days = [
        for (int i = 0; i < _days.length; i++)
          if (i != index) _days[i],
      ];
      // Re-number — keep the default "Día N" name in sync with the new
      // position (so deleting Día 1 makes Día 2 become Día 1); preserve any
      // custom name the user typed. Tracked via [isDefaultName] rather than a
      // string compare so it stays correct in any locale.
      for (int i = 0; i < _days.length; i++) {
        final newNumber = i + 1;
        if (_days[i].isDefaultName) {
          _days[i].name = l10n.routineEditorDayName(newNumber);
        }
        _days[i].dayNumber = newNumber;
      }
    });
  }

  void _removeSlot(int dayIndex, int slotIndex) {
    _markDirty();
    setState(() {
      _days[dayIndex].slots = [
        for (int i = 0; i < _days[dayIndex].slots.length; i++)
          if (i != slotIndex) _days[dayIndex].slots[i],
      ];
    });
  }

  /// Routes the delete action for a slot through presence-aware logic.
  ///
  /// - `_numWeeks == 1` → structural delete immediately (HARD INVARIANT, ADR-WPRES-02).
  /// - `_numWeeks > 1` → show dialog: "Solo esta semana" or "Todas las semanas".
  ///   "Solo esta semana": materializes mask and removes current week. If the
  ///   resulting mask is empty (last-present-week case), routes to structural
  ///   delete (ADR-WPRES-03, SCENARIO-WPRES-015).
  Future<void> _onDeleteSlot(
      BuildContext context, int dayIndex, int slotIndex) async {
    if (_numWeeks <= 1) {
      // Single-week path: structural delete, no dialog (REQ-WPRES-015).
      _removeSlot(dayIndex, slotIndex);
      return;
    }

    // Multi-week path: show the delete scope dialog (REQ-WPRES-010).
    final l10n = AppL10n.of(context);
    final choice = await showDialog<_DeleteScope>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return SimpleDialog(
          backgroundColor: palette.bgCard,
          title: Text(
            '¿Eliminar ejercicio?',
            style: TextStyle(color: palette.textPrimary),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: Text(
                l10n.routineEditorDeleteScopeTitle,
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(_DeleteScope.thisWeek),
              child: Text(l10n.routineEditorScopeOnlyThisWeek,
                  style: TextStyle(color: palette.accent)),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(_DeleteScope.allWeeks),
              child: Text(l10n.routineEditorScopeAllWeeks,
                  style: TextStyle(color: palette.danger)),
            ),
          ],
        );
      },
    );

    if (choice == null || !mounted) return;

    if (choice == _DeleteScope.allWeeks) {
      _removeSlot(dayIndex, slotIndex);
      return;
    }

    // "Solo esta semana" — materialize mask and remove _selectedWeek.
    final slot = _days[dayIndex].slots[slotIndex];
    final Set<int> newMask;
    if (slot.activeWeeks.isEmpty) {
      // Empty = all weeks → materialize to all weeks except current.
      newMask = {
        for (var w = 0; w < _numWeeks; w++)
          if (w != _selectedWeek) w,
      };
    } else {
      newMask = Set<int>.from(slot.activeWeeks)..remove(_selectedWeek);
    }

    // ADR-WPRES-03: if removing _selectedWeek empties the mask, route to
    // structural delete (zero-presence ghost is forbidden).
    if (newMask.isEmpty) {
      _removeSlot(dayIndex, slotIndex);
      return;
    }

    _markDirty();
    setState(() => slot.activeWeeks = newMask);
  }

  /// Shows a scope chooser for the "add exercise" action when
  /// `_numWeeks > 1 && _selectedWeek > 0` (ADR-WPRES-04).
  ///
  /// Returns [_AddScope.allWeeks] (empty mask) or [_AddScope.thisWeek]
  /// ({_selectedWeek}), or `null` if the user dismissed the dialog.
  Future<_AddScope?> _promptAddScope(BuildContext context) async {
    if (_numWeeks <= 1 || _selectedWeek == 0) {
      // Week 1 (index 0) or single-week plan: always add to all weeks.
      return _AddScope.allWeeks;
    }
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return showDialog<_AddScope>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: palette.bgCard,
        title: Text(
          l10n.routineEditorAddScopeTitle,
          style: TextStyle(color: palette.textPrimary),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Text(
              l10n.routineEditorAddScopeBody,
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_AddScope.thisWeek),
            child: Text(l10n.routineEditorAddOnlyThisWeek,
                style: TextStyle(color: palette.accent)),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_AddScope.allWeeks),
            child: Text(l10n.routineEditorAddAllWeeks,
                style: TextStyle(color: palette.textMuted)),
          ),
        ],
      ),
    );
  }

  /// Replaces a day's slot order after a block-level reorder in the tile.
  void _reorderSlots(int dayIndex, List<_EditableSlot> newOrder) {
    _markDirty();
    setState(() {
      _days[dayIndex].slots = newOrder;
    });
  }

  /// Replaces [slot]'s exercise with [newExercise], keeping all other fields
  /// (sets, rest, exerciseMode, repMode, supersetGroup) intact.
  void _replaceExercise(_EditableSlot slot, Exercise newExercise) {
    // QA-WKT-004: don't replace into an exercise already present elsewhere in
    // the same day — mirrors the dedup the three add-flows do. A duplicated
    // exerciseId makes the player collapse both slots into one pool of logs.
    final day = _days.firstWhere((d) => d.slots.contains(slot));
    final isDuplicate = day.slots
        .any((s) => !identical(s, slot) && s.exercise?.id == newExercise.id);
    if (isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppL10n.of(context).routineEditorDuplicateExercise),
        ),
      );
      return;
    }
    _markDirty();
    setState(() {
      slot.exercise = newExercise;
    });
  }

  /// Swaps the slot at [absIndex] with the adjacent slot in direction [dir]
  /// (-1 = up, +1 = down) within the same superset group. No-op at edges or
  /// when the neighbour belongs to a different group.
  void _moveSlotWithinGroup(int dayIndex, int absIndex, int dir) {
    final slots = _days[dayIndex].slots;
    final group = slots[absIndex].supersetGroup;
    if (group == null) return;
    final swapped = swapAdjacentInGroup<_EditableSlot>(
      slots,
      absIndex,
      dir,
      (a, b) => a.supersetGroup == b.supersetGroup,
    );
    if (swapped) {
      _markDirty();
      setState(() {});
    }
  }

  /// Opens the multi-select picker for [dayIndex] and appends N new slots.
  /// Passes [alreadySelectedIds] so the picker pre-marks exercises already in
  /// the day — the user avoids accidental re-adds. (ADR-RER-01)
  Future<void> _pickExercisesForDay(BuildContext context, int dayIndex) async {
    final existingIds = _days[dayIndex]
        .slots
        .where((s) => s.exercise != null)
        .map((s) => s.exercise!.id)
        .toSet();
    // Ver la nota de `_addSupersetForDay`: el picker pre-marca lo que el día
    // ya tiene, así el usuario no elige un repetido sin darse cuenta.
    final picked = await showExercisePicker(context,
        alreadySelectedIds: _resolublesPorElPicker(existingIds));
    if (picked == null || picked.isEmpty || !mounted) return;

    final nuevos = picked.where((e) => !existingIds.contains(e.id)).toList();
    if (nuevos.isEmpty) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        // ignore: use_build_context_synchronously
        SnackBar(content: Text(AppL10n.of(context).routineEditorAddNothingNew)),
      );
      return;
    }

    // Determine presence scope for the new slots (ADR-WPRES-04).
    // Prompt only when multi-week AND viewing week ≥ 2 (index ≥ 1).
    // ignore: use_build_context_synchronously
    final scope = await _promptAddScope(context);
    if (scope == null || !mounted) return;

    _markDirty();
    setState(() {
      for (final ex in nuevos) {
        final slot = _EditableSlot()
          ..exercise = ex
          ..restSeconds = 0
          ..weeklySets = List.generate(_numWeeks, (_) => [_EditableSet()])
          ..activeWeeks =
              scope == _AddScope.thisWeek ? {_selectedWeek} : <int>{};
        _days[dayIndex].slots = [..._days[dayIndex].slots, slot];
      }
    });
  }

  /// El catálogo que el usuario puede ver: el del sistema más sus ejercicios
  /// propios. Es el mismo que alimenta al picker.
  List<Exercise> get _catalogoVisible {
    final uid = ref.read(currentUidProvider) ?? '';
    final propios = uid.isEmpty
        ? const <CustomExercise>[]
        : (ref.read(customExercisesForTrainerStreamProvider(uid)).valueOrNull ??
            const <CustomExercise>[]);
    return [
      ...?ref.read(exercisesProvider).valueOrNull,
      ...propios.map(customToExercise),
    ];
  }

  /// De [ids], los que el picker puede efectivamente mostrar.
  ///
  /// Un slot puede referenciar un ejercicio que este usuario NO ve — el caso
  /// concreto es `SelfCustomizing` sobre una plantilla que usa un ejercicio
  /// propio del entrenador. Pasarle ese id al picker como "ya seleccionado" lo
  /// hace contar algo que no puede mostrar ni desmarcar: el botón diría
  /// "Agregar 3" con dos tildados en pantalla.
  Set<String> _resolublesPorElPicker(Set<String> ids) {
    final conocidos = _catalogoVisible.map((e) => e.id).toSet();
    return ids.where(conocidos.contains).toSet();
  }

  /// Busca en el catálogo lo que la entrada rápida entendió como nombre.
  ///
  /// Devuelve como mucho tres: más que eso deja de ser un atajo y empieza a
  /// competir con el picker, que sigue estando para eso. Se filtran los que ya
  /// están en el día — un ejercicio por día es invariante del dominio
  /// (QA-WKT-004), y ofrecerlo para que el tap no haga nada es peor que no
  /// ofrecerlo.
  List<QuickEntryResult> _buscarParaEntradaRapida(String query, int dayIndex) {
    final texto = query.trim();
    if (texto.isEmpty) return const [];
    final yaEstan = _days[dayIndex]
        .slots
        .where((s) => s.exercise != null)
        .map((s) => s.exercise!.id)
        .toSet();
    // Catálogo del sistema MÁS los ejercicios propios. Buscar "sentadilla" y
    // no encontrar la variante que uno mismo cargó es peor que no tener el
    // atajo: el picker sí los muestra, y dos búsquedas que difieren en la
    // misma pantalla confunden más de lo que ayudan.
    final uid = ref.read(currentUidProvider) ?? '';
    final propios = uid.isEmpty
        ? const <CustomExercise>[]
        : (ref.read(customExercisesForTrainerStreamProvider(uid)).valueOrNull ??
            const <CustomExercise>[]);
    final catalogo = <Exercise>[
      ...?ref.read(exercisesProvider).valueOrNull,
      ...propios.map(customToExercise),
    ];
    // El mismo matcher que usa el picker (ADR-BIBW-01), no un `contains`:
    // busca por tokens y tolera diacríticos, así que "press banca" encuentra
    // "Press de Banca" —el `de` del medio rompe un contains— y "biceps" llega
    // a "Bíceps".
    return catalogo
        .where((e) =>
            !yaEstan.contains(e.id) &&
            exerciseMatchesFilters(
              e,
              query: texto,
              muscles: const {},
              equipment: const {},
            ))
        .take(QuickEntryPanel.kMaxResultados)
        .map((e) => QuickEntryResult(
              id: e.id,
              name: e.name,
              muscleGroup: e.muscleGroup,
            ))
        .toList();
  }

  /// Agrega [exerciseId] al día [dayIndex] con la prescripción de [entry].
  ///
  /// El slot resultante es INDISTINGUIBLE de uno agregado por el picker: mismo
  /// `_EditableSlot`, mismo `restSeconds`, misma pregunta de alcance por
  /// semana (ADR-WPRES-04). Lo único que cambia es que llega con los sets ya
  /// cargados en vez de vacíos.
  Future<void> _agregarPorEntradaRapida(
    BuildContext context,
    int dayIndex,
    String exerciseId,
    QuickEntry entry,
  ) async {
    final uid = ref.read(currentUidProvider) ?? '';
    final propios = uid.isEmpty
        ? const <CustomExercise>[]
        : (ref.read(customExercisesForTrainerStreamProvider(uid)).valueOrNull ??
            const <CustomExercise>[]);
    final catalogo = <Exercise>[
      ...?ref.read(exercisesProvider).valueOrNull,
      ...propios.map(customToExercise),
    ];
    final ex = catalogo.where((e) => e.id == exerciseId).firstOrNull;
    if (ex == null) return;

    final scope = await _promptAddScope(context);
    if (scope == null || !mounted) return;

    _markDirty();
    setState(() {
      final slot = _EditableSlot()
        ..exercise = ex
        ..restSeconds = 0
        // `3x30s` prescribe TIEMPO, no repeticiones: el slot entra derecho en
        // modo duración en vez de obligar a cambiarlo después desde el header
        // de la columna.
        ..exerciseMode =
            entry.esDuracion ? ExerciseMode.duration : ExerciseMode.reps
        ..weeklySets = List.generate(
          _numWeeks,
          // Cada set lleva LO SUYO: `4x10,8,6,4` es una pirámide y
          // `4x10 55,45,35,25` una descarga. Una lista más corta que la
          // cantidad de sets repite su último valor, que es como lo lee
          // cualquiera al escribirlo.
          (_) => List.generate(
            entry.sets,
            (i) => _EditableSet()
              ..reps = entry.repsDeSet(i)
              ..weightKg = entry.pesoDeSet(i)
              ..durationSeconds = entry.duracionDeSet(i),
          ),
        )
        ..activeWeeks = scope == _AddScope.thisWeek ? {_selectedWeek} : <int>{};
      _days[dayIndex].slots = [..._days[dayIndex].slots, slot];
    });
  }

  /// Opens the multi-select picker for [dayIndex] and appends all picked
  /// exercises as a new superset block (shared non-null [supersetGroup]).
  /// Available in every editor mode (trainer + athlete SelfCreating).
  Future<void> _addSupersetForDay(BuildContext context, int dayIndex) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final existingIds = _days[dayIndex]
        .slots
        .where((s) => s.exercise != null)
        .map((s) => s.exercise!.id)
        .toSet();
    // `alreadySelectedIds` pre-marca en el picker lo que el día ya tiene
    // (ADR-RER-01). El parámetro existía y ninguna de las tres llamadas del
    // editor lo pasaba: el usuario elegía un ejercicio repetido sin saberlo,
    // el editor lo filtraba, y no pasaba nada.
    final picked = await showExercisePicker(context,
        alreadySelectedIds: _resolublesPorElPicker(existingIds));
    if (picked == null || picked.isEmpty || !mounted) return;

    final nuevos = picked.where((e) => !existingIds.contains(e.id)).toList();
    // Ninguno era nuevo: decirlo. Antes esto era un `return` mudo adentro del
    // setState y el botón parecía roto.
    if (nuevos.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.routineEditorAddNothingNew)),
      );
      return;
    }

    // Determine presence scope for the new slots (ADR-WPRES-04).
    // ignore: use_build_context_synchronously
    final scope = await _promptAddScope(context);
    if (scope == null || !mounted) return;

    // Un solo ejercicio nuevo no es una superserie. Entra igual —el usuario lo
    // quería— pero suelto, y se dice por qué: un bloque magenta con un
    // ejercicio adentro miente sobre lo que es.
    final esSuperserie = nuevos.length >= 2;
    if (!esSuperserie) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.routineEditorSupersetNeedsTwo)),
      );
    }

    setState(() {
      final day = _days[dayIndex];
      final newOnes = nuevos;
      _markDirty();
      final nextGroup =
          (day.slots.map((s) => s.supersetGroup ?? 0).fold(0, max)) + 1;
      final newSlots = newOnes
          .map((ex) => _EditableSlot()
            ..exercise = ex
            ..restSeconds = 0
            ..supersetGroup = esSuperserie ? nextGroup : null
            ..weeklySets = List.generate(_numWeeks, (_) => [_EditableSet()])
            ..activeWeeks =
                scope == _AddScope.thisWeek ? {_selectedWeek} : <int>{})
          .toList();
      day.slots = [...day.slots, ...newSlots];
    });
  }

  /// Une el slot [absIndex] con su vecino en la lista VISIBLE: el de arriba
  /// con `dir: -1`, el de abajo con `dir: 1`.
  ///
  /// Las dos direcciones hacen falta y no son la misma cosa desde el lugar del
  /// usuario: unir hacia abajo es cómo se suma un ejercicio a una superserie
  /// que YA existe más abajo, sin tener que reordenar nada primero.
  ///
  /// El vecino es el VISIBLE, no el del modelo: un slot borrado "sólo de esta
  /// semana" sigue en `day.slots` y no se renderiza (ADR-WPRES), así que unir
  /// por índice crudo agruparía con un ejercicio que el usuario no tiene
  /// delante.
  void _unirConVecino(int dayIndex, int absIndex, {required int dir}) {
    final day = _days[dayIndex];
    final visibles = [
      for (var i = 0; i < day.slots.length; i++)
        if (day.slots[i].isPresentInWeek(_selectedWeek)) i,
    ];
    final pos = visibles.indexOf(absIndex);
    final destino = pos + dir;
    if (pos < 0 || destino < 0 || destino >= visibles.length) return;

    final vecino = day.slots[visibles[destino]];
    final actual = day.slots[absIndex];

    _markDirty();
    setState(() {
      // Si el vecino ya está en un grupo, éste se suma a ESE en vez de
      // estrenar uno.
      final grupo = vecino.supersetGroup ??
          (day.slots.map((s) => s.supersetGroup ?? 0).fold(0, max)) + 1;
      vecino.supersetGroup = grupo;
      actual.supersetGroup = grupo;
      // Escribir el mismo id NO alcanza para unirlos: `_blocks()` agrupa
      // corridas CONSECUTIVAS de `day.slots`, y entre dos vecinos VISIBLES
      // puede haber slots ocultos —ausentes en la semana en curso, ADR-WPRES—
      // que los separan en la lista real. Sin compactar, el usuario ve dos
      // bloques después de pedir uno.
      day.slots = _conGruposContiguos(day.slots);
    });
  }

  /// Une el slot suelto [absIndex] a la superserie [groupId].
  ///
  /// A diferencia de [_unirConVecino], el destino viene del hit-test del drag:
  /// puede estar a más de un bloque de distancia y la adyacencia no expresa la
  /// intención del usuario. La compactación sigue siendo la misma para que un
  /// slot oculto en la semana actual no parta el grupo resultante.
  void _unirAGrupo(int dayIndex, int absIndex, int groupId) {
    final day = _days[dayIndex];
    if (absIndex < 0 || absIndex >= day.slots.length) return;
    final actual = day.slots[absIndex];
    if (actual.supersetGroup != null ||
        !day.slots.any((slot) => slot.supersetGroup == groupId)) {
      return;
    }

    _markDirty();
    setState(() {
      actual.supersetGroup = groupId;
      day.slots = _conGruposContiguos(day.slots);
    });
  }

  /// Devuelve [slots] reordenada para que cada superserie sea una corrida
  /// CONSECUTIVA, que es la única forma en que `_blocks()` la ve como un solo
  /// bloque.
  ///
  /// Preserva el orden relativo: cada grupo se ancla donde aparece su PRIMER
  /// miembro y los demás se traen ahí. Los slots sueltos no se mueven entre sí.
  ///
  /// Hace falta en las dos operaciones que tocan `supersetGroup`: al unir, por
  /// los slots ocultos que pueden separar a dos vecinos visibles; al separar,
  /// porque sacar a un miembro del MEDIO de un grupo de tres deja a los de los
  /// costados con el mismo id y ya no contiguos.
  static List<_EditableSlot> _conGruposContiguos(List<_EditableSlot> slots) {
    final out = <_EditableSlot>[];
    final yaPuestos = <_EditableSlot>{};
    for (final s in slots) {
      if (yaPuestos.contains(s)) continue;
      final grupo = s.supersetGroup;
      if (grupo == null) {
        out.add(s);
        yaPuestos.add(s);
        continue;
      }
      // Primer miembro del grupo: se trae a TODO el grupo acá, en su orden.
      for (final m in slots) {
        if (m.supersetGroup == grupo && !yaPuestos.contains(m)) {
          out.add(m);
          yaPuestos.add(m);
        }
      }
    }
    return out;
  }

  /// Saca el slot [absIndex] de su superserie.
  ///
  /// Si el grupo queda con UN solo miembro, ese también sale: un grupo de uno
  /// no es una superserie, y `buildRoutineSlot` lo descartaría igual al
  /// guardar.
  void _separarDeGrupo(int dayIndex, int absIndex) {
    final day = _days[dayIndex];
    final grupo = day.slots[absIndex].supersetGroup;
    if (grupo == null) return;

    _markDirty();
    setState(() {
      day.slots[absIndex].supersetGroup = null;
      final quedan = [
        for (final s in day.slots)
          if (s.supersetGroup == grupo) s,
      ];
      if (quedan.length == 1) quedan.first.supersetGroup = null;
      // Sacar a un miembro del MEDIO de un grupo de tres deja a los de los
      // costados con el mismo id y ya NO contiguos: `_blocks()` los parte en
      // dos bloques, y `supersetBlockIndices` del dominio hace lo mismo al
      // guardar. Compactar los vuelve a juntar, con el que salió detrás.
      day.slots = _conGruposContiguos(day.slots);
    });
  }

  /// Opens the picker and adds the picked exercise(s) into the existing
  /// superset [groupId] of [dayIndex], inserted right after that group's last
  /// slot so the superset stays a consecutive run.
  Future<void> _addExerciseToGroup(
      BuildContext context, int dayIndex, int groupId) async {
    final day = _days[dayIndex];
    final existingIds = day.slots
        .where((s) => s.exercise != null)
        .map((s) => s.exercise!.id)
        .toSet();
    // Ver la nota de `_addSupersetForDay`.
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showExercisePicker(context,
        alreadySelectedIds: _resolublesPorElPicker(existingIds));
    if (picked == null || picked.isEmpty || !mounted) return;

    final nuevos = picked.where((e) => !existingIds.contains(e.id)).toList();
    if (nuevos.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.routineEditorAddNothingNew)),
      );
      return;
    }

    // Determine presence scope for the new slots (ADR-WPRES-04).
    // ignore: use_build_context_synchronously
    final scope = await _promptAddScope(context);
    if (scope == null || !mounted) return;

    setState(() {
      final newOnes = nuevos;
      _markDirty();
      final newSlots = newOnes
          .map((ex) => _EditableSlot()
            ..exercise = ex
            ..restSeconds = 0
            ..supersetGroup = groupId
            ..weeklySets = List.generate(_numWeeks, (_) => [_EditableSet()])
            ..activeWeeks =
                scope == _AddScope.thisWeek ? {_selectedWeek} : <int>{})
          .toList();
      // Insert right after the group's last slot to keep it consecutive.
      var insertAt = day.slots.length;
      for (var i = day.slots.length - 1; i >= 0; i--) {
        if (day.slots[i].supersetGroup == groupId) {
          insertAt = i + 1;
          break;
        }
      }
      day.slots = [...day.slots]..insertAll(insertAt, newSlots);
    });
  }

  /// Builds [List<RoutineDay>] from the current editor state.
  /// Used by both the create and update paths to avoid duplication.
  List<RoutineDay> _buildDays() {
    return _days.map((d) {
      // Normalize: a "superset" of 1 slot is just a standalone.
      final groupCounts = <int, int>{};
      for (final s in d.slots) {
        if (s.supersetGroup != null) {
          groupCounts[s.supersetGroup!] =
              (groupCounts[s.supersetGroup!] ?? 0) + 1;
        }
      }
      return RoutineDay(
        dayNumber: d.dayNumber,
        name: d.name,
        slots: d.slots.map((s) {
          final effectiveGroup = (s.supersetGroup != null &&
                  (groupCounts[s.supersetGroup!] ?? 0) >= 2)
              ? s.supersetGroup
              : null;
          return buildRoutineSlot(s, effectiveGroup);
        }).toList(),
      );
    }).toList();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    // If invalid: show a SPECIFIC message for the first unmet requirement
    // (missing name / no exercise on Día N / incomplete sets) and scroll to the
    // offending day, instead of a generic hint that always blames the sets
    // (finding 21). The button is always tappable so this feedback can fire.
    if (!_isValid) {
      final l10n = AppL10n.of(context);
      final error = _firstValidationError(l10n);
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
        // Expand and scroll to the day the error points at (name errors carry
        // no day — nothing to scroll to).
        final day = error.day;
        if (day != null) {
          // Con pestañas, "llevar al usuario al error" es SELECCIONAR el día,
          // no expandirlo: si el día ofensor no es el visible, el scroll no
          // tenía a dónde llevarlo porque su contenido ni está en el árbol.
          final indice = _days.indexOf(day);
          if (indice >= 0 && indice != _selectedDayIndex) {
            FocusManager.instance.primaryFocus?.unfocus();
            setState(() => _selectedDayIndex = indice);
          }
          // Esperar un frame a que el día nuevo se monte antes de scrollear.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final key = _keyForDay(day);
            if (key.currentContext != null) {
              Scrollable.ensureVisible(
                key.currentContext!,
                duration: AppMotion.slow,
                curve: AppMotion.emphasized,
                alignment: 0.1,
              );
            }
          });
        }
      }
      return;
    }

    // A successful save persists the work, so the editor is no longer "dirty":
    // clear the flag up front so the post-save context.pop()/context.go() in the
    // branches below is NOT intercepted by the unsaved-changes PopScope guard
    // (the discard dialog would otherwise fire on a successful save). Restored
    // in the catch branch when the save fails and the user stays on screen.
    _isDirty = false;
    setState(() => _submitting = true);
    final uid = ref.read(currentUidProvider) ?? '';
    final days = _buildDays();
    // Capture l10n before async gap (context may be stale after await).
    final l10n = AppL10n.of(context);

    try {
      final repo = ref.read(routineRepositoryProvider);

      switch (widget.mode) {
        case TrainerAssigning(:final athleteId, existingPlanId: final planId?):
          // Edit existing trainer-assigned plan.
          final draft = Routine(
            id: planId,
            name: _nameController.text.trim(),
            split: _splitController.text.trim(),
            level: _level,
            days: days,
            source: RoutineSource.trainerAssigned,
            assignedBy: uid,
            assignedTo: athleteId,
            visibility: RoutineVisibility.private,
            numWeeks: _numWeeks,
            summary: _summaryOrNull,
          );
          await repo.updateAssigned(uid: uid, draft: draft);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.coachUpdatePlanSuccess)),
          );
          context.pop();

        case TrainerAssigning(:final athleteId, existingPlanId: null):
          // Create new trainer-assigned plan.
          final routine = Routine(
            id: '',
            name: _nameController.text.trim(),
            split: _splitController.text.trim(),
            level: _level,
            days: days,
            source: RoutineSource.trainerAssigned,
            assignedBy: uid,
            assignedTo: athleteId,
            visibility: RoutineVisibility.private,
            numWeeks: _numWeeks,
            summary: _summaryOrNull,
          );
          final created = await repo.createAssigned(routine);
          ref.read(analyticsServiceProvider).logPlanAssigned(
                routineId: created.id,
                assignedBy: uid,
                assignedTo: athleteId,
              );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.coachCreatePlanSuccess)),
          );
          context.pop();

        case TrainerTemplating(existingTemplateId: final templateId?):
          // Edit existing trainer template.
          final draft = Routine(
            id: templateId,
            name: _nameController.text.trim(),
            split: _splitController.text.trim(),
            level: _level,
            days: days,
            source: RoutineSource.trainerTemplate,
            assignedBy: uid,
            visibility: RoutineVisibility.private,
            numWeeks: _numWeeks,
            summary: _summaryOrNull,
            goals: _goalsOrdered,
          );
          await repo.updateTemplate(uid: uid, draft: draft);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.coachUpdatePlanSuccess)),
          );
          context.pop();

        case TrainerTemplating(existingTemplateId: null):
          // Create new trainer template — reusable plantilla, no
          // athlete assignment. Mirrors pre-PR2 isTemplate branch.
          final routine = Routine(
            id: '',
            name: _nameController.text.trim(),
            split: _splitController.text.trim(),
            level: _level,
            days: days,
            source: RoutineSource.trainerTemplate,
            assignedBy: uid,
            visibility: RoutineVisibility.private,
            numWeeks: _numWeeks,
            summary: _summaryOrNull,
            goals: _goalsOrdered,
          );
          await repo.createTemplate(routine);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.coachCreatePlanSuccess)),
          );
          context.pop();

        // Both athlete CREATE paths share one exit, and that is the whole
        // safety argument of #647: "usar como base" produces a routine
        // through the SAME literal a from-scratch one goes through. The
        // template's `assignedBy`, `assignedTo`, `summary`, `imageUrl`,
        // `estimatedMinutesPerDay`, `split` and rating aggregates cannot leak
        // into the write because the editor never held them — the only thing
        // hydration carried over is content (days, slots, sets, weeks) plus
        // the suffixed name. The copy is the athlete's routine by
        // construction, not by a field-stripping step someone can forget.
        case SelfCreating(existingRoutineId: null) || SelfCustomizing():
          // Client-side cap check (ADR-USR-02).
          final userRoutines =
              ref.read(userCreatedRoutinesProvider(uid)).valueOrNull ?? [];
          if (userRoutines.length >= 10) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.workoutSelfEditorCapReached)),
            );
            // No save happened — re-arm the unsaved-changes guard.
            _isDirty = true;
            setState(() => _submitting = false);
            return;
          }
          // ADR-RER-04: athlete-created routines submit split: null and a
          // fixed beginner level. The form hides those fields in
          // SelfCreating mode (T-RER-030).
          final draft = Routine(
            id: '',
            name: _nameController.text.trim(),
            split: null,
            level: ExperienceLevel.beginner,
            days: days,
            source: RoutineSource.userCreated,
            visibility: _sharedOnProfile
                ? RoutineVisibility.public
                : RoutineVisibility.private,
            numWeeks: _numWeeks,
          );
          final created = await repo.createUserOwned(uid: uid, draft: draft);
          // The mounted-guard must run BEFORE touching `ref` again: a back
          // gesture during the create (canPop is true — _isDirty was cleared
          // at the top of _submit) disposes this element and ref.read would
          // throw. Returning early skips activation; the lazy adoption in
          // unifiedRoutinesProvider heals it on next listing.
          if (!mounted) return;
          // Auto-activa (workout redesign slice 1): the freshly created
          // routine becomes the active one ONLY when the athlete has no
          // active routine yet — an existing marker is never stolen. When
          // the profile isn't loaded yet the write is skipped; lazy
          // adoption covers that case too.
          final profileAsync = ref.read(userProfileProvider);
          final profile = profileAsync.valueOrNull;
          final hasActive = profile?.activeRoutineId?.isNotEmpty ?? false;
          if (profileAsync.hasValue && profile != null && !hasActive) {
            try {
              await ref.read(userRepositoryProvider).update(uid, {
                'activeRoutineId': created.id,
              });
            } catch (_) {
              // Best-effort: activation must not fail an already-successful
              // create; lazy adoption retries while the marker stays null.
            }
          }
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.workoutSelfEditorSuccess)),
          );
          context.pop();

        case SelfCreating(existingRoutineId: final existingId?):
          // Full edit path (REQ-USR-018) — update content in Firestore.
          //
          // `summary` is deliberately absent from this draft AND from
          // updateUserOwned's payload (#648): the athlete UPDATE path lists
          // it in keys() but not in affectedKeys(). A resumen written by a PF
          // on a routine the athlete later edits therefore survives untouched
          // instead of bricking the edit with permission-denied.
          final draft = Routine(
            id: existingId,
            name: _nameController.text.trim(),
            split: null,
            level: ExperienceLevel.beginner,
            days: days,
            source: RoutineSource.userCreated,
            visibility: _sharedOnProfile
                ? RoutineVisibility.public
                : RoutineVisibility.private,
            numWeeks: _numWeeks,
          );
          await repo.updateUserOwned(uid: uid, draft: draft);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.workoutSelfEditorUpdateSuccess)),
          );
          context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      final errorText = switch (widget.mode) {
        TrainerAssigning() => l10n.coachCreatePlanError,
        TrainerTemplating() => l10n.coachCreatePlanError,
        SelfCreating() ||
        SelfCustomizing() =>
          e.toString().contains('permission-denied')
              ? l10n.workoutSelfEditorPermissionDenied
              : l10n.workoutSelfEditorError,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorText)),
      );
      // The save failed — the user stays on screen with unsaved changes, so
      // re-arm the guard cleared at the top of _submit.
      _isDirty = true;
      setState(() => _submitting = false);
    }
  }

  /// Pops the editor the same way the bare back button used to, used after the
  /// unsaved-changes guard has cleared (no dirty state, or the user confirmed
  /// discard). Mirrors the original AppBar back navigation.
  void _leaveEditor() {
    if (context.canPop()) {
      context.pop();
    } else {
      // Deep-link / state-restoration fallback: the athlete modes belong to
      // the Entrenar tab, the trainer ones to Coach.
      final athleteMode = widget.mode is SelfCreating || _isCustomizing;
      context.go(athleteMode ? '/workout' : '/coach');
    }
  }

  /// Handles the AppBar back button. When there are unsaved changes, asks for
  /// confirmation before leaving; otherwise pops immediately.
  Future<void> _handleBackButton() async {
    if (!_isDirty) {
      _leaveEditor();
      return;
    }
    final discard = await _confirmDiscard();
    if (discard && mounted) {
      _leaveEditor();
    }
  }

  /// Shows the "¿Descartar cambios?" confirmation dialog. Returns true when the
  /// user chose to discard, false when they cancelled or dismissed it. Styled
  /// after the abandon-session dialog in session_player_screen.dart.
  Future<bool> _confirmDiscard() async {
    final l10n = AppL10n.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return AlertDialog(
          backgroundColor: palette.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          title: Text(
            l10n.routineEditorDiscardTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: palette.textPrimary,
            ),
          ),
          content: Text(
            l10n.routineEditorDiscardBody,
            style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                l10n.commonCancel,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: palette.textPrimary,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.highlight,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                l10n.routineEditorDiscardConfirm,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: palette.bg,
                ),
              ),
            ),
          ],
        );
      },
    );
    return discard ?? false;
  }

  /// Scaffold + AppBackground + PopScope estables, compartidos por las 3
  /// ramas (loading/notfound/editor) — el TreinoStateSwitcher cross-fadea
  /// solo [body], no la pantalla completa. Antes cada rama devolvía su
  /// propio Scaffold+AppBackground bajo el switcher: cross-fadear dos
  /// fullscreens opacos deja la cobertura combinada <100% a mitad de
  /// transición y se traslucía el fondo del Navigator (flash oscuro sutil
  /// en loading→editor). Mismo patrón que session_detail_screen.dart:36.
  /// PopScope/GestureDetector-dismiss-keyboard son no-ops fuera de la rama
  /// editor (_isDirty es false en loading/notfound) — hoistearlos es seguro.
  Widget _shell({required Key bodyKey, required Widget body}) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (discard && mounted) {
          _leaveEditor();
        }
      },
      // El scope envuelve al Scaffold, no al body: la barra vive en el
      // `bottomSheet` y tiene que poder leer el mismo notifier que publican
      // las celdas de adentro del body.
      child: RoutineEditorFocusScope(
        notifier: _celdaEnfocada,
        child: ValueListenableBuilder<FocusedSetCell?>(
          valueListenable: _celdaEnfocada,
          builder: (context, celda, child) {
            // La barra es un ACCESORIO DEL TECLADO: sin teclado arriba no hay
            // nada a lo que acompañar, y como el `bottomSheet` se superpone al
            // body en vez de achicarlo, dibujarla igual taparía el pie de la
            // pantalla — el botón de guardar, entre otras cosas.
            //
            // El foco solo no alcanza como condición: `enterText` en un test
            // deja el campo enfocado sin abrir ningún teclado, y ahí la barra
            // se comía el CTA. En el device el foco y el teclado van juntos,
            // así que la diferencia no se nota; en el árbol de widgets sí.
            final hayTeclado = MediaQuery.viewInsetsOf(context).bottom > 0;
            return Scaffold(
              // Tapping anywhere outside a field dismisses the keyboard
              // (device UX 2026-06-11). translucent → child widgets still
              // receive their taps.
              body: child,
              bottomSheet: celda == null || !hayTeclado
                  ? null
                  : KeyboardAccessorySlot(cell: celda),
            );
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: AppBackground(
              child: TreinoStateSwitcher(
                childKey: bodyKey,
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    // Los dos catálogos se OBSERVAN acá aunque quien los use sea
    // `_catalogoVisible` con un `read`.
    //
    // Un `FutureProvider` que nadie mira nunca se resuelve: el `read` lo
    // inicializa y devuelve `AsyncLoading`. Y el de ejercicios propios es
    // `autoDispose`: sin nadie suscripto se descarta apenas se lee, así que
    // `valueOrNull` vuelve a dar null y los ejercicios que el usuario cargó no
    // aparecían nunca en la búsqueda rápida — aunque el picker sí los muestre.
    //
    // Son providers cacheados: mirarlos no cuesta un rebuild por frame.
    ref.watch(exercisesProvider);
    final uidCatalogo = ref.watch(currentUidProvider) ?? '';
    if (uidCatalogo.isNotEmpty) {
      ref.watch(customExercisesForTrainerStreamProvider(uidCatalogo));
    }

    // Loading state: hydrating from Firestore.
    if (_loading) {
      return _shell(
        bodyKey: const ValueKey('loading'),
        body: Center(
          child: CircularProgressIndicator(color: palette.accent),
        ),
      );
    }

    // Not-found state: routine was deleted before the user opened it.
    if (_loadNotFound) {
      return _shell(
        bodyKey: const ValueKey('notfound'),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(TreinoIcon.back, color: palette.textPrimary),
                      tooltip: l10n.commonBack,
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go('/workout'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    l10n.workoutSelfEditorNotFound,
                    style: TextStyle(color: palette.textMuted),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Normal editor state.
    {
      // Cross-week validation state for the tab bar (SCENARIO-PERIOD-020).
      // The SELECTED week never shows a badge: its invalid sets are already
      // visible on screen — and with numWeeks == 1 (week 0 always selected)
      // this keeps the single-week editor visually identical to before
      // (REQ-PERIOD-062).
      // Unsaved-changes guard: blocks the iOS edge-swipe / system back gesture
      // while the editor is dirty and routes it through the discard confirm.
      // canPop is recomputed every build, so it stays in sync with _isDirty
      // — handled centrally in _shell(), no need to repeat PopScope here.
      return _shell(
        bodyKey: const ValueKey('editor'),
        body: SafeArea(
          child: Column(
            children: [
              // ── Custom header ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(TreinoIcon.back, color: palette.textPrimary),
                      tooltip: l10n.commonBack,
                      onPressed: _handleBackButton,
                    ),
                    // El título es el NOMBRE de la rutina, no el del modo:
                    // el modo ya se sabe por cómo se llegó, el nombre no.
                    // Sin nombre todavía, cae al label del modo.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _nameController.text.trim().isEmpty
                                ? _titleFor(widget.mode, l10n)
                                : _nameController.text.trim().toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.barlowCondensed(
                              fontWeight: FontWeight.w700,
                              fontSize: 19,
                              letterSpacing: 0.5,
                              color: palette.textPrimary,
                            ),
                          ),
                          Text(
                            _subtituloDelPlan(l10n),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.barlow(
                              fontWeight: FontWeight.w500,
                              fontSize: 11.5,
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Engranaje: nombre, split, nivel, compartir y semanas se
                    // setean una vez y después estorbaban en cada scroll.
                    IconButton(
                      key: const Key('plan_sheet_button'),
                      icon: Icon(TreinoIcon.contentSettings,
                          size: 18, color: palette.textPrimary),
                      tooltip: l10n.routineEditorPlanSheetA11y,
                      onPressed: _abrirDatosDelPlan,
                      constraints:
                          const BoxConstraints(minWidth: 44, minHeight: 44),
                      style: IconButton.styleFrom(
                        backgroundColor: palette.surfaceSubtle,
                        shape: const CircleBorder(),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Body ─────────────────────────────────────────────────
              Expanded(
                child: ListView(
                  // Dragging the list dismisses the keyboard (device UX
                  // 2026-06-11).
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  controller: _listScrollController,
                  // `s18` y no 16: la escala de spacing de AGENTS.md es
                  // cerrada (8·12·14·18·20) y el 16 no está en ella. Su
                  // dartdoc describe s18 como el padding horizontal de
                  // pantallas, que es exactamente lo que este gutter es.
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s18,
                    AppSpacing.s8,
                    AppSpacing.s18,
                    AppSpacing.s8,
                  ),
                  children: [
                    // ── Nombre y split ──────────────────────────────────
                    // NO van a la hoja del engranaje, a diferencia de
                    // objetivos, nivel, compartir y semanas. El nombre es el
                    // único campo OBLIGATORIO y lo primero que hacés: detrás
                    // de un ícono, una rutina nueva se abre en blanco y sin
                    // ningún lugar visible donde escribirlo. El split viaja con
                    // él porque comparten fila y son la identidad del plan, no
                    // su configuración.
                    // ── Name + (Split when trainer mode) ───────────────
                    // T-RER-030: athlete (SelfCreating) form shows only
                    // Name + Days-of-plan. Trainer modes show all fields.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel(
                                label: l10n.coachEditorNameLabel,
                                palette: palette,
                              ),
                              const SizedBox(height: 4),
                              TextField(
                                key: const Key('editor_name_field'),
                                controller: _nameController,
                                style: GoogleFonts.barlow(
                                  color: palette.textPrimary,
                                  fontSize: 13,
                                ),
                                decoration: _inputDecoration(
                                  palette,
                                  hint: _isTrainerMode
                                      ? l10n.routineEditorNameHint
                                      : l10n.workoutSelfEditorNameHint,
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                        if (_isTrainerMode) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SectionLabel(
                                  label: l10n.coachEditorSplitLabel,
                                  palette: palette,
                                ),
                                const SizedBox(height: 4),
                                TextField(
                                  key: const Key('editor_split_field'),
                                  controller: _splitController,
                                  style: GoogleFonts.barlow(
                                    color: palette.textPrimary,
                                    fontSize: 13,
                                  ),
                                  decoration: _inputDecoration(
                                    palette,
                                    hint: l10n.routineEditorSplitHint,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),

                    // ── Resumen del plan ────────────────────────────────
                    // NO se mudó a la hoja del engranaje, a diferencia de
                    // nombre, split, nivel, compartir y semanas. Esos cinco son
                    // configuración que se setea una vez; el resumen es algo
                    // que el PF escribe PARA el alumno, más cerca del contenido
                    // que de los ajustes. El handoff tampoco lo listaba en
                    // "DATOS DEL PLAN".
                    if (_isTrainerMode) ...[
                      const SizedBox(height: 12),
                      _SectionLabel(
                        label: l10n.routineEditorSummaryLabel,
                        palette: palette,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.routineEditorSummaryHelp,
                        style: GoogleFonts.barlow(
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                          height: 1.35,
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('editor_summary_field'),
                        controller: _summaryController,
                        // 2–3 lines: the 7 seeded resúmenes measure 61–100
                        // characters. A taller box would invite the essay the
                        // 280-char cap exists to prevent.
                        minLines: 2,
                        maxLines: 3,
                        maxLength: _kSummaryMaxLength,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        textCapitalization: TextCapitalization.sentences,
                        style: GoogleFonts.barlow(
                          color: palette.textPrimary,
                          fontSize: 13,
                        ),
                        decoration: _inputDecoration(
                          palette,
                          hint: l10n.routineEditorSummaryHint,
                        ).copyWith(
                          // The counter STAYS (the coaching-note field hides
                          // its own with counterText: ''): here the cap is a
                          // real editorial constraint the PF writes against,
                          // not a defensive ceiling they should never reach.
                          counterStyle: GoogleFonts.barlow(
                            fontSize: 11,
                            color: palette.textMuted,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                    // ── Días del plan ─────────────────────────────────
                    // Pestañas en vez de la pila de acordeones: se renderiza
                    // UN día a la vez, así el scroll vertical es el de un día
                    // y no el de la rutina entera.
                    //
                    // El aire de arriba no es decorativo: las pestañas nacían
                    // pegadas al campo del nombre y las dos cosas se leían como
                    // un solo bloque, cuando una nombra el plan y la otra
                    // navega entre sus días. Revisión en device del 31/08.
                    const SizedBox(height: AppSpacing.s14),
                    DayTabBar(
                      labels: [for (final d in _days) d.name],
                      statuses: [for (final d in _days) _dayStatus(d)],
                      selectedIndex: _selectedDayIndex,
                      onSelect: (i) {
                        // Soltar el foco ANTES de cambiar el árbol de campos:
                        // el IME de iOS puede restaurar su sesión de edición
                        // dentro del TextField de reemplazo y filtrar el valor
                        // del día anterior. Mismo motivo que en onSelectWeek.
                        FocusManager.instance.primaryFocus?.unfocus();
                        setState(() => _selectedDayIndex = i);
                      },
                      onAddDay: _days.length < _kMaxDays ? _addDay : null,
                      addDayLabel: l10n.coachEditorAddDay,
                      statusLabel: (estado) => switch (estado) {
                        DayTabStatus.empty =>
                          l10n.routineEditorEmptyDayTitle.toLowerCase(),
                        DayTabStatus.invalid => l10n.routineEditorMissingReps,
                        DayTabStatus.ok => '',
                      },
                    ),
                    const SizedBox(height: AppSpacing.s12),

                    _DayExpansionTile(
                      key: _keyForDay(_days[_selectedDayIndex]),
                      day: _days[_selectedDayIndex],
                      week: _selectedWeek,
                      palette: palette,
                      onAddSlot: () =>
                          _pickExercisesForDay(context, _selectedDayIndex),
                      onRemoveSlot: (si) =>
                          _onDeleteSlot(context, _selectedDayIndex, si),
                      onReorderSlots: (newOrder) =>
                          _reorderSlots(_selectedDayIndex, newOrder),
                      onRemoveDay: _days.length > 1
                          ? () => _removeDay(_selectedDayIndex)
                          : null,
                      onSlotChanged: () {
                        _markDirty();
                        setState(() {});
                      },
                      onAddToGroup: (g) =>
                          _addExerciseToGroup(context, _selectedDayIndex, g),
                      onReplaceExercise: (slot, ex) =>
                          _replaceExercise(slot, ex),
                      onMoveSlotInGroup: (absIndex, dir) =>
                          _moveSlotWithinGroup(
                              _selectedDayIndex, absIndex, dir),
                      onNameChanged: (newName) =>
                          _onDayNameChanged(_selectedDayIndex, newName),
                      // Supersets available in every mode, including the
                      // athlete's SelfCreating editor.
                      allowSuperset: true,
                      onAddSuperset: () =>
                          _addSupersetForDay(context, _selectedDayIndex),
                      onQuickSearch: (q) =>
                          _buscarParaEntradaRapida(q, _selectedDayIndex),
                      onQuickAdd: (id, entry) => _agregarPorEntradaRapida(
                          context, _selectedDayIndex, id, entry),
                      onMergeSlotWithPrevious: (i) =>
                          _unirConVecino(_selectedDayIndex, i, dir: -1),
                      onMergeSlotWithNext: (i) =>
                          _unirConVecino(_selectedDayIndex, i, dir: 1),
                      onMergeSlotIntoGroup: (i, groupId) =>
                          _unirAGrupo(_selectedDayIndex, i, groupId),
                      onUngroupSlot: (i) =>
                          _separarDeGrupo(_selectedDayIndex, i),
                      slotIsValid: (slot) {
                        if (!slot.isPresentInWeek(_selectedWeek)) {
                          return true;
                        }
                        final weekSets = slot.setsForWeek(_selectedWeek);
                        return weekSets.isNotEmpty &&
                            weekSets.every((s) =>
                                isSetValid(s, slot.exerciseMode, slot.repMode));
                      },
                      isTrainerMode: _isTrainerMode,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                  ],
                ),
              ),

              // ── Pie fijo: qué falta + guardar ────────────────────────
              // Fuera del ListView, como estaba el CTA. Lo que se suma es la
              // línea de validación EN VIVO: hasta #868 el usuario cargaba
              // todo el plan y recién al tocar guardar se enteraba, por un
              // SnackBar que además tapaba la pantalla.
              Builder(builder: (context) {
                // Los dos primeros: la línea tiene dos renglones, y una lista
                // de siete problemas deja de leerse como una lista de tareas.
                final problemas = _problemas(l10n).take(2).toList();
                final visibles = problemas.map((p) => p.mensaje).toList();
                // El día sale de los problemas QUE SE VEN, no de la lista
                // entera: en modo entrenador los dos primeros son "falta el
                // nombre" y "falta el split", ninguno con día, y buscar más
                // abajo ponía un IR al lado de dos mensajes que no llevan a
                // ningún lado — y saltaba a un problema que el usuario no
                // tiene en pantalla.
                final primerDia =
                    problemas.map((p) => p.dia).whereType<_EditableDay>();
                return EditorFooterBar(
                  summary: _resumenPie(l10n),
                  problems: visibles,
                  submitLabel: _submitLabelFor(widget.mode, l10n),
                  submitting: _submitting,
                  onSubmit: () => _submit(),
                  onGoToProblem: primerDia.isEmpty
                      ? null
                      : () => _irAlDia(primerDia.first),
                );
              }),
            ],
          ),
        ),
      );
    }
  }

  InputDecoration _inputDecoration(AppPalette palette, {String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
      filled: true,
      fillColor: palette.bgCard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: palette.accent),
      ),
    );
  }
}

// ── Week tab bar ──────────────────────────────────────────────────────────────

/// Plan-level week navigation rendered above the DÍAS DEL PLAN section:
/// one chip per week ("Sem 1".."Sem N"), an "+ Semana" control disabled at
/// [maxWeeks], plus "Quitar última" (disabled at 1 week) and "Duplicar
/// semana" (disabled on week 0). REQ-PERIOD-010/011/012/014.
class _WeekTabBar extends StatelessWidget {
  const _WeekTabBar({
    required this.numWeeks,
    required this.selectedWeek,
    required this.maxWeeks,
    required this.warningWeeks,
    required this.palette,
    required this.onSelectWeek,
    required this.onAddWeek,
    required this.onRemoveLastWeek,
    required this.onDuplicateWeek,
  });

  final int numWeeks;
  final int selectedWeek;
  final int maxWeeks;

  /// 0-based weeks that render a danger dot on their chip — weeks failing
  /// validation other than the selected one (SCENARIO-PERIOD-020).
  final Set<int> warningWeeks;
  final AppPalette palette;
  final void Function(int week) onSelectWeek;
  final VoidCallback onAddWeek;
  final VoidCallback onRemoveLastWeek;
  final VoidCallback onDuplicateWeek;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final canAdd = numWeeks < maxWeeks;
    final canRemove = numWeeks > 1;
    final canDuplicate = selectedWeek > 0;

    TextStyle actionStyle(bool enabled) => GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: enabled ? palette.accent : palette.border,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Week chips + add control — scrolls horizontally once chips overflow.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var w = 0; w < numWeeks; w++) ...[
                _WeekChip(
                  key: Key('week_tab_$w'),
                  index: w,
                  selected: w == selectedWeek,
                  warning: warningWeeks.contains(w),
                  palette: palette,
                  onTap: () => onSelectWeek(w),
                ),
                const SizedBox(width: 6),
              ],
              TextButton.icon(
                key: const Key('add_week_button'),
                onPressed: canAdd ? onAddWeek : null,
                icon: Icon(
                  TreinoIcon.plus,
                  size: 14,
                  color: canAdd ? palette.accent : palette.border,
                ),
                label: Text(l10n.routineEditorWeekLabel,
                    style: actionStyle(canAdd)),
              ),
            ],
          ),
        ),
        // Week actions — always rendered, disabled when not applicable.
        Row(
          children: [
            TextButton.icon(
              key: const Key('remove_week_button'),
              onPressed: canRemove ? onRemoveLastWeek : null,
              icon: Icon(
                TreinoIcon.trash,
                size: 14,
                color: canRemove ? palette.textMuted : palette.border,
              ),
              label: Text(
                l10n.routineEditorRemoveLastWeek,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: canRemove ? palette.textMuted : palette.border,
                ),
              ),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              key: const Key('duplicate_week_button'),
              onPressed: canDuplicate ? onDuplicateWeek : null,
              icon: Icon(
                TreinoIcon.copy,
                size: 14,
                color: canDuplicate ? palette.accent : palette.border,
              ),
              label: Text(l10n.routineEditorDuplicateWeekTitle,
                  style: actionStyle(canDuplicate)),
            ),
          ],
        ),
      ],
    );
  }
}

/// One selectable week pill — accent-filled when [selected]; shows a danger
/// dot when [warning] (the week fails validation while not on screen).
/// Pill de objetivo del editor de plantillas (#635 PR#1b).
///
/// Calcado de [_WeekChip] a propósito: misma geometría, mismo relleno de
/// acento al seleccionar, mismo `Semantics(button/selected)`. Dos controles
/// de selección en la misma pantalla que se vieran distinto serían ruido.
///
/// El texto sobre acento sale de `TreinoButtonTokens.foreground`, no de
/// `palette.bg`: en tema claro esa convención da 1.57:1 y falla AA
/// (AGENTS.md §2).
class _GoalChip extends StatelessWidget {
  const _GoalChip({
    super.key,
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s14,
            vertical: AppSpacing.s8,
          ),
          decoration: BoxDecoration(
            color: selected ? palette.accent : palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.5,
              color: selected
                  ? TreinoButtonTokens.foreground(context)
                  : palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekChip extends StatelessWidget {
  const _WeekChip({
    super.key,
    required this.index,
    required this.selected,
    required this.warning,
    required this.palette,
    required this.onTap,
  });

  /// 0-based week — rendered 1-based ("Sem 1").
  final int index;
  final bool selected;
  final bool warning;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Semantics(
      // Announce the chip as a selectable tab so VoiceOver conveys the
      // selected state; the "Sem N" text child supplies the label.
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? palette.accent : palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.routineEditorWeekShort(index + 1),
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.5,
                  color: selected
                      ? TreinoButtonTokens.foreground(context)
                      : palette.textMuted,
                ),
              ),
              if (warning) ...[
                const SizedBox(width: 5),
                Semantics(
                  // The danger dot is purely visual; expose its meaning to
                  // screen readers so the week's validation state is announced.
                  label: l10n.commonWarning,
                  child: Container(
                    key: Key('week_tab_warning_$index'),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: palette.danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Day expansion tile ────────────────────────────────────────────────────────

class _DayExpansionTile extends StatefulWidget {
  const _DayExpansionTile({
    super.key,
    required this.day,
    required this.week,
    required this.palette,
    required this.onAddSlot,
    required this.onRemoveSlot,
    required this.onReorderSlots,
    required this.onRemoveDay,
    required this.onSlotChanged,
    required this.onAddToGroup,
    required this.onReplaceExercise,
    required this.onMoveSlotInGroup,
    required this.onMergeSlotIntoGroup,
    required this.onNameChanged,
    this.allowSuperset = false,
    this.onAddSuperset,
    this.slotIsValid,
    this.isTrainerMode = false,
    this.onQuickSearch,
    this.onQuickAdd,
    this.onMergeSlotWithPrevious,
    this.onMergeSlotWithNext,
    this.onUngroupSlot,
  });

  final _EditableDay day;

  /// 0-based week whose sets the slot editors render (ADR-PB-02 live-view).
  final int week;
  final AppPalette palette;
  final VoidCallback onAddSlot;
  final void Function(int slotIndex) onRemoveSlot;
  final void Function(List<_EditableSlot> newOrder) onReorderSlots;
  final VoidCallback? onRemoveDay;
  final VoidCallback onSlotChanged;
  final bool allowSuperset;
  final VoidCallback? onAddSuperset;
  final void Function(int groupId) onAddToGroup;
  final void Function(_EditableSlot slot, Exercise newExercise)
      onReplaceExercise;
  final void Function(int absIndex, int dir) onMoveSlotInGroup;

  /// Called when the user commits an edit to the day's name via the inline
  /// TextField. The parent updates `_EditableDay.name` + `isDefaultName` and
  /// marks the editor dirty. Empty input restores the localized "Día N"
  /// default (decisión 2A 2026-06-29).
  final void Function(String newName) onNameChanged;

  /// Returns true when [slot] has no incomplete sets for the currently viewed
  /// week. Used to drive red affordances in the slot and day-header cards.
  final bool Function(_EditableSlot slot)? slotIsValid;

  /// When true, slot editors show trainer-only fields (e.g. coaching note).
  /// Defaults to false (fail-closed) so caller must opt in explicitly.
  /// REQ-EN-002.
  final bool isTrainerMode;

  /// Busca en el catálogo lo que la entrada rápida entendió como nombre. Null
  /// esconde el atajo — el picker completo sigue estando igual.
  final List<QuickEntryResult> Function(String query)? onQuickSearch;

  /// Agrega el ejercicio elegido con la prescripción que se tipeó.
  final void Function(String exerciseId, QuickEntry entry)? onQuickAdd;

  /// Une el slot con el de arriba en una superserie, y lo saca de ella. Null
  /// esconde las dos acciones — el editor web del Coach Hub no las ofrece.
  final void Function(int absIndex)? onMergeSlotWithPrevious;
  final void Function(int absIndex)? onMergeSlotWithNext;
  final void Function(int absIndex, int groupId) onMergeSlotIntoGroup;
  final void Function(int absIndex)? onUngroupSlot;

  @override
  State<_DayExpansionTile> createState() => _DayExpansionTileState();
}

class _DayExpansionTileState extends State<_DayExpansionTile> {
  /// Fracción vertical CENTRAL que absorbe un ejercicio suelto al soltarlo.
  ///
  /// El 40% restante (20% por borde) conserva el reorder normal: rozar una
  /// superserie camino a otra posición no debe convertirse en una unión.
  static const double _kFraccionVerticalParaUnir = 0.6;

  final Map<_EditableSlot, GlobalKey> _supersetHitTestKeys = {};
  int? _draggedStandaloneAbsIndex;
  int? _highlightedSupersetGroup;

  /// Que este arrastre ya terminó en unión, y por lo tanto el `onReorder` que
  /// puede llegar después no tiene que mover nada. Se resetea en
  /// `onReorderStart` y no al consumirlo: cuando hay unión sin cambio de
  /// índice, `onReorder` nunca llega, y el flag quedaría trabado tragándose el
  /// reorder SIGUIENTE.
  bool _unionAplicada = false;

  /// Cuánto tiene que salirse el dedo del bloque para que soltar signifique
  /// SACAR al miembro del grupo, en dp.
  ///
  /// No es cero: en el borde exacto el dedo tiembla y el gesto quedaría a
  /// suerte. Es el mismo criterio que el 60% central de la unión — entrar y
  /// salir tienen que ser intenciones, no accidentes de un píxel.
  static const double _kMargenParaSacar = 16;

  /// Miembro de superserie en arrastre dentro de su grupo, o null.
  int? _draggedMemberAbsIndex;

  /// El grupo del que ese miembro saldría. Necesario para ubicar el bloque.
  int? _draggedMemberGroup;

  /// Que el dedo salió del bloque con margen suficiente: al soltar, se separa.
  bool _miembroFueraDelBloque = false;

  /// Gemelo de [_unionAplicada] para la separación. Misma razón: el `onReorder`
  /// del reorderable ANIDADO puede no llegar nunca.
  bool _separacionAplicada = false;

  /// Si el panel de entrada rápida está abierto. Presentación local pura: no
  /// sobrevive a cerrar el día ni viaja al modelo.
  bool _quickEntryOpen = false;
  final TextEditingController _quickEntryCtrl = TextEditingController();

  /// El foco del campo de entrada rápida. Vive acá porque elegir un resultado
  /// tiene que DEVOLVERLO con el cursor al final: el tap sobre la lista lo
  /// suelta, y sin recuperarlo el teclado se cierra justo cuando el usuario va
  /// a escribir la prescripción.
  final FocusNode _quickEntryFocus = FocusNode();

  /// El ejercicio ya elegido en la entrada rápida, o null mientras se busca.
  ///
  /// Elegir un candidato AUTOCOMPLETA el nombre y guarda esto; recién el botón
  /// AGREGAR suma el ejercicio. Hasta la revisión en device del 31/08 el tap
  /// agregaba en el acto, y como el nombre se escribe primero, el atajo se
  /// cerraba justo antes de poder decir `4x10 55`.
  QuickEntryResult? _quickEntryElegido;

  void _cerrarEntradaRapida() {
    _quickEntryOpen = false;
    _quickEntryElegido = null;
    _quickEntryCtrl.clear();
  }
  // Reads/writes widget.day.expanded so the collapse survives the ListView
  // recycling the tile off-screen.

  /// True while the inline TextField is replacing the Text label. Local to the
  /// tile — does NOT survive the tile being recycled off-screen by the
  /// ListView (acceptable: the only state that would be lost is "user mid-
  /// typing while scrolling away", which is not a real flow).
  bool _editingName = false;
  late final TextEditingController _nameController;
  late final FocusNode _nameFocus;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.day.name);
    _nameFocus = FocusNode();
    // Commit on blur: matches Hevy-style editors where tap-elsewhere persists
    // the edit (instead of discarding it like a modal Cancel).
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus && _editingName) {
        _commitName();
      }
    });
  }

  @override
  void didUpdateWidget(_DayExpansionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Parent re-numbered the day (e.g. another day was deleted) and pushed a
    // fresh default name. Sync the controller so the inline TextField reflects
    // the new label next time the user taps edit.
    if (!_editingName && widget.day.name != _nameController.text) {
      _nameController.text = widget.day.name;
    }
  }

  @override
  void dispose() {
    _quickEntryFocus.dispose();
    _quickEntryCtrl.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _startEditing() {
    _nameController.text = widget.day.name;
    setState(() => _editingName = true);
    // Schedule focus AFTER the TextField is in the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocus.requestFocus();
      _nameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _nameController.text.length,
      );
    });
  }

  void _commitName() {
    if (!_editingName) return;
    widget.onNameChanged(_nameController.text);
    setState(() => _editingName = false);
  }

  /// The nearest slot BEFORE [slotIndex] that can act as a copy source: it must
  /// already have an exercise and be present in the viewed week (a slot absent
  /// this week has no visible prescription to copy, ADR-WPRES). Returns null
  /// for the first exercise of the day.
  _EditableSlot? _copySourceFor(int slotIndex) {
    for (var i = slotIndex - 1; i >= 0; i--) {
      final candidate = widget.day.slots[i];
      if (candidate.exercise == null) continue;
      if (!candidate.isPresentInWeek(widget.week)) continue;
      return candidate;
    }
    return null;
  }

  /// Confirmation + copy for "Copiar sets del ejercicio anterior".
  /// Mirrors `_duplicateWeek`: unfocus → AlertDialog → mutate → onChanged so
  /// validation (and the red slot border) recalculates. Overwriting the target's
  /// sets is destructive, hence the same confirm step.
  Future<void> _copyPrescriptionFromPrevious(int slotIndex) async {
    final source = _copySourceFor(slotIndex);
    if (source == null) return;
    // Dismiss IME before showing the dialog — same reason as _duplicateWeek.
    FocusManager.instance.primaryFocus?.unfocus();

    final l10n = AppL10n.of(context);
    final sourceName = source.exercise!.name;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return AlertDialog(
          backgroundColor: palette.bgCard,
          title: Text(
            l10n.routineEditorCopyPrescriptionTitle,
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            l10n.routineEditorCopyPrescriptionBody(sourceName),
            style: TextStyle(color: palette.textMuted, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.routineEditorDialogCancel,
                  style: TextStyle(color: palette.textMuted)),
            ),
            TextButton(
              key: const Key('copy_prescription_confirm_button'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.routineEditorDialogConfirm,
                  style: TextStyle(color: palette.accent)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      copyPrescriptionInto(source, widget.day.slots[slotIndex], widget.week);
    });
    widget.onSlotChanged();
  }

  /// Returns the copy callback for the slot at [absIndex], or null when there
  /// is no eligible previous exercise — which renders the menu item disabled.
  VoidCallback? _copyPreviousCallback(int absIndex) =>
      _copySourceFor(absIndex) == null
          ? null
          : () => _copyPrescriptionFromPrevious(absIndex);

  /// Rect global del bloque de la superserie [group], o null si no está montado.
  Rect? _rectDelBloque(int group) {
    for (final entry in _supersetHitTestKeys.entries) {
      if (entry.key.supersetGroup != group) continue;
      final ro = entry.value.currentContext?.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize) continue;
      return ro.localToGlobal(Offset.zero) & ro.size;
    }
    return null;
  }

  void _actualizarDestinoDeUnion(PointerMoveEvent event) {
    // Rama de SALIDA: hay un miembro en arrastre dentro de su grupo.
    final memberGroup = _draggedMemberGroup;
    if (memberGroup != null) {
      final rect = _rectDelBloque(memberGroup);
      final fuera = rect == null || !rect.inflate(_kMargenParaSacar).contains(event.position);
      if (fuera != _miembroFueraDelBloque) {
        setState(() => _miembroFueraDelBloque = fuera);
      }
      return;
    }

    if (_draggedStandaloneAbsIndex == null) return;

    int? targetGroup;
    for (final entry in _supersetHitTestKeys.entries) {
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      final margen = rect.height * (1 - _kFraccionVerticalParaUnir) / 2;
      final zonaCentral = Rect.fromLTRB(
        rect.left,
        rect.top + margen,
        rect.right,
        rect.bottom - margen,
      );
      if (zonaCentral.contains(event.position)) {
        targetGroup = entry.key.supersetGroup;
        break;
      }
    }

    if (targetGroup == _highlightedSupersetGroup) return;
    setState(() => _highlightedSupersetGroup = targetGroup);
  }

  void _iniciarReorder(
    int visibleBlockIndex,
    List<List<({int index, _EditableSlot slot})>> blocks,
    List<int> visiblesIdx,
  ) {
    final block = blocks[visiblesIdx[visibleBlockIndex]];
    final standalone = block.length == 1 &&
        block.first.slot.supersetGroup == null &&
        block.first.slot.isPresentInWeek(widget.week);
    setState(() {
      _draggedStandaloneAbsIndex = standalone ? block.first.index : null;
      _highlightedSupersetGroup = null;
      _unionAplicada = false;
    });
  }

  /// Aplica la unión pendiente, si la hay, al levantar el dedo.
  ///
  /// La unión NO puede colgar de `onReorder`: Flutter sólo lo llama cuando el
  /// índice cambió — `SliverReorderableListState._dropCompleted` hace
  /// `if (fromIndex != toIndex) widget.onReorder(...)`. Y los dos umbrales no
  /// coinciden: el resaltado arranca al 20% del alto del bloque
  /// ([_kFraccionVerticalParaUnir]), mientras que el reorderable recién mueve
  /// el índice cuando el proxy cruza el punto medio del vecino. En la franja
  /// entre ambos, el bloque prometía absorber y no absorbía nada — medido en
  /// `routine_editor_drop_superserie_test.dart`.
  ///
  /// `onReorderEnd` se llama SIEMPRE (`_dragEnd`), así que es el único lugar
  /// donde la promesa se puede cumplir.
  void _terminarReorder(int _) {
    final absIndex = _draggedStandaloneAbsIndex;
    final targetGroup = _highlightedSupersetGroup;
    if (absIndex == null && targetGroup == null) return;

    setState(() {
      _draggedStandaloneAbsIndex = null;
      _highlightedSupersetGroup = null;
    });

    if (absIndex != null && targetGroup != null) {
      // El reorder que el usuario "pidió" con el gesto queda anulado: soltar
      // adentro es unir, no mover. `onReorder` puede llegar igual después de la
      // animación del proxy, y [_unionAplicada] es lo que le dice que ya no hay
      // nada que mover.
      _unionAplicada = true;
      widget.onMergeSlotIntoGroup(absIndex, targetGroup);
    }
  }

  void _cancelarReorder(PointerCancelEvent _) {
    if (_draggedStandaloneAbsIndex == null &&
        _highlightedSupersetGroup == null &&
        _draggedMemberGroup == null &&
        !_miembroFueraDelBloque) {
      return;
    }
    setState(() {
      _draggedStandaloneAbsIndex = null;
      _highlightedSupersetGroup = null;
      _draggedMemberAbsIndex = null;
      _draggedMemberGroup = null;
      _miembroFueraDelBloque = false;
    });
  }

  /// Arranca el arrastre de un MIEMBRO dentro de su superserie.
  void _iniciarArrastreDeMiembro(int absIndex, int group) {
    setState(() {
      _draggedMemberAbsIndex = absIndex;
      _draggedMemberGroup = group;
      _miembroFueraDelBloque = false;
      _separacionAplicada = false;
    });
  }

  /// Al soltar un miembro: si el dedo quedó fuera del bloque, lo SACA del grupo
  /// en vez de reordenarlo adentro.
  ///
  /// La simetría con la unión es deliberada. Sin esto, arrastrar servía para
  /// meter un ejercicio en una superserie y no para sacarlo: una puerta de
  /// entrada sin puerta de salida, y el único camino afuera era el ⋮, que no
  /// descubre nadie. Igual que la unión, se aplica en `onReorderEnd` porque
  /// `onReorder` no llega cuando el índice no cambió.
  void _terminarArrastreDeMiembro(int _) {
    final absIndex = _draggedMemberAbsIndex;
    final fuera = _miembroFueraDelBloque;
    if (absIndex == null) return;

    setState(() {
      _draggedMemberAbsIndex = null;
      _draggedMemberGroup = null;
      _miembroFueraDelBloque = false;
    });

    if (fuera) {
      _separacionAplicada = true;
      widget.onUngroupSlot?.call(absIndex);
    }
  }

  /// Walks the slot list and emits either a standalone [_SlotEditor] or a
  /// "SUPERSERIE" wrapper card for consecutive slots sharing a non-null group.
  /// Slots que se ven en la semana en curso. Un slot borrado "sólo de esta
  /// semana" sigue en el modelo pero no se renderiza (ADR-WPRES), así que un
  /// día puede tener slots y verse vacío.
  List<_EditableSlot> get _slotsVisibles => widget.day.slots
      .where((s) => s.isPresentInWeek(widget.week))
      .toList(growable: false);

  Widget _buildSlotRows(AppPalette palette) {
    final blocks = _blocks();
    // Qué bloques tienen ALGO que mostrar en la semana en curso. Los flags de
    // mover y de unir se calculan sobre ESTOS, no sobre el índice crudo: con
    // bloques ocultos delante, el primer bloque VISIBLE tenía `canMoveUp` en
    // true y ofrecía "Subir" y "Unir con el de arriba" para no hacer nada.
    final visiblesIdx = [
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i].any((r) => r.slot.isPresentInWeek(widget.week))) i,
    ];
    final rows = <Widget>[];
    for (var b = 0; b < blocks.length; b++) {
      final block = blocks[b];
      // Presence filter (REQ-WPRES render): a slot deleted "solo de esta
      // semana" must disappear from this week's view — and one added "solo
      // esta semana" must only appear here. Callbacks keep the ORIGINAL flat
      // indices carried by each record, so delete/move still target the
      // right slot in the unfiltered day list.
      final visible = [
        for (final r in block)
          if (r.slot.isPresentInWeek(widget.week)) r,
      ];
      if (visible.isEmpty) continue;
      final posVisible = visiblesIdx.indexOf(b);
      final canUp = posVisible > 0;
      final canDown = posVisible < visiblesIdx.length - 1;
      if (block.length == 1 && block.first.slot.supersetGroup == null) {
        // Standalone slot. ObjectKey keeps each row's State bound to its slot
        // so the int fields don't show stale values after the list shifts.
        final idx = visible.first.index;
        final slot = visible.first.slot;
        rows.add(Padding(
          key: ObjectKey(slot),
          padding: const EdgeInsets.only(bottom: AppSpacing.s8),
          child: _SlotEditor(
            slot: slot,
            week: widget.week,
            palette: palette,
            reorderIndex: posVisible,
            onRemove: () => widget.onRemoveSlot(idx),
            onChanged: widget.onSlotChanged,
            onReplaceExercise: (ex) => widget.onReplaceExercise(slot, ex),
            slotIndex: idx,
            canMoveUp: canUp,
            canMoveDown: canDown,
            onMoveUp: () => _moveBlock(b, -1),
            onMoveDown: () => _moveBlock(b, 1),
            onCopyPrevious: _copyPreviousCallback(idx),
            hasSlotError:
                widget.slotIsValid != null ? !widget.slotIsValid!(slot) : false,
            isTrainerMode: widget.isTrainerMode,
            onMergeWithPrevious: widget.onMergeSlotWithPrevious == null
                ? null
                : () => widget.onMergeSlotWithPrevious!(idx),
            onMergeWithNext: widget.onMergeSlotWithNext == null
                ? null
                : () => widget.onMergeSlotWithNext!(idx),
          ),
        ));
      } else {
        // Superset block — the whole block moves as one unit. Only the
        // members present in the viewed week are rendered.
        rows.add(Padding(
          key: ObjectKey(block.first.slot),
          padding: const EdgeInsets.only(bottom: AppSpacing.s8),
          child: _SupersetGroupCard(
            hitTestKey: _supersetHitTestKeys.putIfAbsent(
              block.first.slot,
              GlobalKey.new,
            ),
            groupSlots: visible,
            reorderIndex: posVisible,
            week: widget.week,
            palette: palette,
            onRemoveSlot: widget.onRemoveSlot,
            onChanged: widget.onSlotChanged,
            onAddExercise: () =>
                widget.onAddToGroup(block.first.slot.supersetGroup!),
            onReplaceExercise: widget.onReplaceExercise,
            onMoveSlotInGroup: widget.onMoveSlotInGroup,
            canMoveUp: canUp,
            canMoveDown: canDown,
            onMoveUp: () => _moveBlock(b, -1),
            onMoveDown: () => _moveBlock(b, 1),
            onCopyPreviousFor: _copyPreviousCallback,
            slotIsValid: widget.slotIsValid,
            isTrainerMode: widget.isTrainerMode,
            onUngroupSlot: widget.onUngroupSlot,
            resaltadoParaUnir:
                _highlightedSupersetGroup == block.first.slot.supersetGroup,
            onMemberDragStart: _iniciarArrastreDeMiembro,
            onMemberDragEnd: _terminarArrastreDeMiembro,
            separacionAplicada: () => _separacionAplicada,
          ),
        ));
      }
    }
    return Listener(
      onPointerMove: _actualizarDestinoDeUnion,
      onPointerCancel: _cancelarReorder,
      child: ReorderableListView(
        shrinkWrap: true,
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderStart: (index) => _iniciarReorder(index, blocks, visiblesIdx),
        onReorderEnd: _terminarReorder,
        onReorder: (oldIndex, newIndex) {
          // La unión ya la aplicó `_terminarReorder`. Soltar adentro es unir,
          // no mover: el reorder queda anulado.
          if (_unionAplicada) return;
          if (newIndex > oldIndex) newIndex--;
          if (oldIndex == newIndex) return;
          _moveBlock(
            visiblesIdx[oldIndex],
            visiblesIdx[newIndex] - visiblesIdx[oldIndex],
          );
        },
        children: rows,
      ),
    );
  }

  /// Groups the flat slot list into ordered blocks: a standalone slot is its
  /// own block; consecutive slots sharing a non-null supersetGroup form one.
  /// Each entry carries its ORIGINAL flat index — the render filters absent
  /// slots per week, so positions can no longer be derived from block order.
  List<List<({int index, _EditableSlot slot})>> _blocks() {
    final slots = widget.day.slots;
    final blocks = <List<({int index, _EditableSlot slot})>>[];
    var i = 0;
    while (i < slots.length) {
      final group = slots[i].supersetGroup;
      if (group != null) {
        final run = <({int index, _EditableSlot slot})>[];
        while (i < slots.length && slots[i].supersetGroup == group) {
          run.add((index: i, slot: slots[i]));
          i++;
        }
        blocks.add(run);
      } else {
        blocks.add([(index: i, slot: slots[i])]);
        i++;
      }
    }
    return blocks;
  }

  /// Moves block [blockIndex] by [dir] positions and flattens back to a slot
  /// list. The chevrons pass -1/+1; drag can cross several blocks at once.
  /// A whole superset moves as a single unit, so a reorder never splits it.
  void _moveBlock(int blockIndex, int dir) {
    // Operates on the UNFILTERED block list — flattening a presence-filtered
    // list would silently drop the slots absent in the viewed week.
    final blocks = _blocks();
    final target = blockIndex + dir;
    if (target < 0 || target >= blocks.length) return;
    final moved = blocks.removeAt(blockIndex);
    blocks.insert(target, moved);
    widget.onReorderSlots([
      for (final b in blocks) ...b.map((r) => r.slot),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final palette = widget.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: Column(
        children: [
          // La cabecera del día se fue (revisión en device del 31/08).
          //
          // Era el último resto del acordeón: un contenedor con borde que
          // repetía el nombre del día a 200 px de la pestaña que ya lo dice,
          // más el lápiz, el punto de error y el tacho. Entre el borde, sus
          // 12 px de padding vertical, el nombre duplicado y el divisor se
          // comía ~70 px de alto en la única pantalla donde el alto es el
          // recurso escaso — la de configurar sets.
          //
          // Renombrar y borrar el día se mudaron a la fila del botón RÁPIDO,
          // que ya ocupaba ese renglón. El punto de error no se mudó a ningún
          // lado: vive en la pestaña desde #865.
          // Fila de acciones del día: el atajo a la izquierda, y
          // renombrar/borrar a la derecha, donde antes había una
          // cabecera entera para lo mismo.
          if (_editingName)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('day_name_editing_field'),
                      controller: _nameController,
                      focusNode: _nameFocus,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _commitName(),
                      onTap: () {},
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: palette.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        hintText: l10n
                            .routineEditorDayName(widget.day.dayNumber),
                        hintStyle: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: Key(
                        'day_name_commit_button_${widget.day.dayNumber}'),
                    icon: Icon(TreinoIcon.check,
                        size: 18, color: palette.accentText),
                    tooltip: l10n.routineEditorEditDayNameA11y,
                    onPressed: _commitName,
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                if (widget.onQuickSearch != null &&
                    widget.onQuickAdd != null)
                  QuickEntryToggle(
                    active: _quickEntryOpen,
                    onTap: () => setState(() {
                      if (_quickEntryOpen) {
                        _cerrarEntradaRapida();
                      } else {
                        _quickEntryOpen = true;
                      }
                    }),
                  ),
                const Spacer(),
                IconButton(
                  key:
                      Key('day_name_edit_button_${widget.day.dayNumber}'),
                  icon: Icon(TreinoIcon.edit,
                      size: 16, color: palette.textMuted),
                  tooltip: l10n.routineEditorEditDayNameA11y,
                  onPressed: _startEditing,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  padding: EdgeInsets.zero,
                ),
                if (widget.onRemoveDay != null)
                  IconButton(
                    key: Key('day_remove_button_${widget.day.dayNumber}'),
                    icon: Icon(TreinoIcon.trash,
                        size: 18, color: palette.textMuted),
                    tooltip: l10n.routineEditorDeleteDayA11y,
                    onPressed: widget.onRemoveDay,
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          if (widget.onQuickSearch != null &&
              widget.onQuickAdd != null) ...[
            if (_quickEntryOpen) ...[
              const SizedBox(height: AppSpacing.s8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _quickEntryCtrl,
                builder: (context, value, _) {
                  final entry = parseQuickEntry(value.text);
                  // El elegido se suelta si el nombre dejó de estar en
                  // el texto: borrar el ejercicio para buscar otro tiene
                  // que devolver la lista sin cerrar el panel.
                  final elegido = _quickEntryElegido;
                  final sigueElegido = elegido != null &&
                      value.text
                          .toLowerCase()
                          .contains(elegido.name.toLowerCase());
                  if (elegido != null && !sigueElegido) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _quickEntryElegido = null);
                      }
                    });
                  }
                  return QuickEntryPanel(
                    controller: _quickEntryCtrl,
                    focusNode: _quickEntryFocus,
                    entry: entry,
                    selected: sigueElegido ? elegido : null,
                    results: sigueElegido
                        ? const []
                        : widget.onQuickSearch!(entry.query),
                    onSelect: (r) {
                      // Autocompletar, NO agregar: el usuario viene a
                      // escribir la prescripción después del nombre.
                      //
                      // Y se CONSERVA lo que ya escribió. El placeholder
                      // del campo enseña `banca 4x10 60`: quien lo sigue
                      // tipea todo junto y después toca el ejercicio, y
                      // reemplazar el texto entero por el nombre le
                      // borraba el `4x10 60` que acababa de escribir.
                      //
                      // Se quitan sólo las palabras que el parser
                      // entendió como BÚSQUEDA; el resto —los números—
                      // queda tal como se tipeó, sin normalizar.
                      // Se quita UNA ocurrencia por palabra del nombre,
                      // no todas: hay ejercicios del catálogo con
                      // números adentro —"Landmine 180"— y escribir
                      // `landmine 180 3x10 180` tiene el mismo token dos
                      // veces, una como nombre y otra como peso. Con un
                      // Set se borraban las dos y la prescripción perdía
                      // el kilaje.
                      final pendientes = entry.query
                          .toLowerCase()
                          .split(RegExp(r'\s+'))
                          .where((p) => p.isNotEmpty)
                          .toList();
                      final resto =
                          value.text.split(RegExp(r'\s+')).where((p) {
                        if (p.isEmpty) return false;
                        final i = pendientes.indexOf(p.toLowerCase());
                        if (i < 0) return true;
                        pendientes.removeAt(i);
                        return false;
                      }).join(' ');
                      final texto = resto.isEmpty
                          ? '${r.name} '
                          : '${r.name} $resto';
                      _quickEntryCtrl.value = TextEditingValue(
                        text: texto,
                        // Cursor AL FINAL, listo para seguir. Sin esto
                        // el usuario tenía que volver a tocar el campo y
                        // recolocar el cursor a mano.
                        selection:
                            TextSelection.collapsed(offset: texto.length),
                      );
                      setState(() => _quickEntryElegido = r);
                      // Y el foco de vuelta al campo: el tap sobre la
                      // lista lo soltó, y con él se fue el teclado.
                      _quickEntryFocus.requestFocus();
                    },
                    onConfirm: () {
                      final r = _quickEntryElegido;
                      if (r == null) return;
                      widget.onQuickAdd!(r.id, entry);
                      setState(_cerrarEntradaRapida);
                    },
                  );
                },
              ),
            ],
            const SizedBox(height: AppSpacing.s8),
          ],
          // Un día sin ejercicios era un acordeón que se abría
          // y no mostraba nada, sin decir si estaba bien así.
          if (_slotsVisibles.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s12),
              child: EmptyDayState(
                title: l10n.routineEditorEmptyDayTitle,
                body: l10n.routineEditorEmptyDayBody,
              ),
            )
          else
            _buildSlotRows(palette),
          // Acciones del día. Eran dos TextButton apilados a ancho
          // completo, cada uno con su padding heredado; ahora comparten
          // fila, alto y radio.
          DayActionButtons(
            exerciseLabel: l10n.routineEditorAddExercise,
            onAddExercise: widget.onAddSlot,
            supersetLabel:
                widget.allowSuperset ? l10n.coachEditorAddSuperset : null,
            onAddSuperset: widget.onAddSuperset,
          ),
          // Los atajos del ⋮ no los descubría nadie: el menú no se ve
          // hasta que se toca.
          if (_slotsVisibles.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              l10n.routineEditorSlotMenuHint,
              key: const Key('slot_menu_hint'),
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 11,
                color: palette.textFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Superset group card ───────────────────────────────────────────────────────

/// Wrapper card rendered around consecutive slots sharing the same
/// [supersetGroup]. Shows a "SUPERSERIE" header with a flame icon,
/// then stacks each slot's [_SlotEditor].
class _SupersetGroupCard extends StatelessWidget {
  const _SupersetGroupCard({
    required this.hitTestKey,
    required this.groupSlots,
    required this.week,
    required this.palette,
    required this.onRemoveSlot,
    required this.onChanged,
    required this.onAddExercise,
    required this.onReplaceExercise,
    required this.onMoveSlotInGroup,
    required this.reorderIndex,
    this.canMoveUp = false,
    this.canMoveDown = false,
    this.onMoveUp,
    this.onMoveDown,
    this.onCopyPreviousFor,
    this.slotIsValid,
    this.isTrainerMode = false,
    this.onUngroupSlot,
    this.resaltadoParaUnir = false,
    required this.onMemberDragStart,
    required this.onMemberDragEnd,
    required this.separacionAplicada,
  });

  final GlobalKey hitTestKey;
  final List<({int index, _EditableSlot slot})> groupSlots;

  /// 0-based week whose sets the member slot editors render.
  final int week;
  final AppPalette palette;
  final void Function(int slotIndex) onRemoveSlot;
  final VoidCallback onChanged;
  final VoidCallback onAddExercise;
  final void Function(_EditableSlot slot, Exercise newExercise)
      onReplaceExercise;
  final void Function(int absIndex, int dir) onMoveSlotInGroup;
  final int reorderIndex;

  /// Block-level reorder controls — the whole superset moves as one unit.
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// Resolves the "copy the previous exercise's sets" callback for the member
  /// at a given ORIGINAL flat index, or null when that member has no eligible
  /// source. The day tile owns the lookup — a superset card only sees its own
  /// block, and the source can live outside it.
  final VoidCallback? Function(int absIndex)? onCopyPreviousFor;

  /// Returns true when [slot] is valid for the current week.
  final bool Function(_EditableSlot slot)? slotIsValid;

  /// When true, slot editors show trainer-only fields (e.g. coaching note).
  final bool isTrainerMode;

  /// Saca un miembro del grupo.
  final void Function(int absIndex)? onUngroupSlot;

  /// Indica que el puntero está en la zona central de absorción del bloque.
  final bool resaltadoParaUnir;

  /// Avisan al día que arrancó/terminó el arrastre de un MIEMBRO, para que
  /// pueda decidir si al soltar hay que sacarlo del grupo. El hit-test contra
  /// el rect del bloque vive arriba, que es donde están las GlobalKeys.
  final void Function(int absIndex, int group) onMemberDragStart;
  final void Function(int mi) onMemberDragEnd;

  /// True cuando el drop ya se resolvió como separación: el reorder interno
  /// queda anulado.
  final bool Function() separacionAplicada;

  @override
  Widget build(BuildContext context) {
    return SupersetBlock(
      key: hitTestKey,
      count: groupSlots.length,
      resaltadoParaUnir: resaltadoParaUnir,
      reorderIndex: reorderIndex,
      trailing: (onMoveUp != null || onMoveDown != null)
          ? _MoveButtons(
              palette: palette,
              canMoveUp: canMoveUp,
              canMoveDown: canMoveDown,
              onMoveUp: onMoveUp,
              onMoveDown: onMoveDown,
            )
          : null,
      footer: TextButton.icon(
        onPressed: onAddExercise,
        icon: Icon(TreinoIcon.plus, size: 14, color: palette.accentText),
        label: Text(
          AppL10n.of(context).routineEditorAddExercise,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: palette.accentText,
          ),
        ),
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          alignment: Alignment.centerLeft,
        ),
      ),
      children: [
        ReorderableListView(
          shrinkWrap: true,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderStart: (mi) => onMemberDragStart(
            groupSlots[mi].index,
            groupSlots[mi].slot.supersetGroup!,
          ),
          onReorderEnd: onMemberDragEnd,
          onReorder: (oldIndex, newIndex) {
            // Si el miembro salió del bloque, ya lo separó `onReorderEnd`: no
            // hay nada que reordenar adentro de un grupo que este slot dejó.
            if (separacionAplicada()) return;
            if (newIndex > oldIndex) newIndex--;
            if (oldIndex == newIndex) return;
            final direction = newIndex > oldIndex ? 1 : -1;
            var absoluteIndex = groupSlots[oldIndex].index;
            final targetIndex = groupSlots[newIndex].index;
            while (absoluteIndex != targetIndex) {
              onMoveSlotInGroup(absoluteIndex, direction);
              absoluteIndex += direction;
            }
          },
          children: [
            for (var mi = 0; mi < groupSlots.length; mi++)
              Padding(
                key: ObjectKey(groupSlots[mi].slot),
                padding: EdgeInsets.only(
                  bottom: mi < groupSlots.length - 1 ? AppSpacing.s8 : 0,
                ),
                child: _SlotEditor(
                  slot: groupSlots[mi].slot,
                  week: week,
                  palette: palette,
                  reorderIndex: mi,
                  supersetPosition: mi,
                  // El índice ORIGINAL, que es lo que da la key del menú. Sin esto
                  // el ⋮ de un miembro de superserie no tenía key y no se podía
                  // alcanzar desde un test — ni referenciar desde ningún lado.
                  slotIndex: groupSlots[mi].index,
                  onRemove: () => onRemoveSlot(groupSlots[mi].index),
                  onChanged: onChanged,
                  onReplaceExercise: (ex) =>
                      onReplaceExercise(groupSlots[mi].slot, ex),
                  canMoveUp: mi > 0,
                  canMoveDown: mi < groupSlots.length - 1,
                  // Each record carries its ORIGINAL flat index — required now
                  // that absent-in-week members are filtered out of groupSlots.
                  onMoveUp: mi > 0
                      ? () => onMoveSlotInGroup(groupSlots[mi].index, -1)
                      : null,
                  onMoveDown: mi < groupSlots.length - 1
                      ? () => onMoveSlotInGroup(groupSlots[mi].index, 1)
                      : null,
                  onCopyPrevious: onCopyPreviousFor?.call(groupSlots[mi].index),
                  hasSlotError: slotIsValid != null
                      ? !slotIsValid!(groupSlots[mi].slot)
                      : false,
                  isTrainerMode: isTrainerMode,
                  onUngroup: onUngroupSlot == null
                      ? null
                      : () => onUngroupSlot!(groupSlots[mi].index),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Move (reorder) controls ───────────────────────────────────────────────────

/// Compact up/down chevrons used to reorder a block (a standalone slot or a
/// whole superset) within its day. Edge buttons render disabled.
class _MoveButtons extends StatelessWidget {
  const _MoveButtons({
    required this.palette,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final AppPalette palette;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    Widget btn(IconData icon, bool enabled, VoidCallback? cb, String label) =>
        IconButton(
          icon: Icon(
            icon,
            size: 18,
            color: enabled ? palette.textMuted : palette.border,
          ),
          tooltip: label,
          onPressed: enabled ? cb : null,
          visualDensity: VisualDensity.compact,
          // Keep the chevrons visually compact (18px icon) while expanding the
          // hit area to the 44x44 minimum touch target.
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 3),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(TreinoIcon.chevronUp, canMoveUp, onMoveUp,
            l10n.routineEditorSlotMenuMoveUp),
        btn(TreinoIcon.chevronDown, canMoveDown, onMoveDown,
            l10n.routineEditorSlotMenuMoveDown),
      ],
    );
  }
}

// ── Slot editor — Hevy-style set table ───────────────────────────────────────

class _SlotEditor extends StatefulWidget {
  const _SlotEditor({
    required this.slot,
    required this.week,
    required this.palette,
    required this.onRemove,
    required this.onChanged,
    required this.onReplaceExercise,
    this.slotIndex,
    this.canMoveUp = false,
    this.canMoveDown = false,
    this.onMoveUp,
    this.onMoveDown,
    this.onCopyPrevious,
    this.hasSlotError = false,
    this.isTrainerMode = false,
    this.supersetPosition,
    this.onMergeWithPrevious,
    this.onMergeWithNext,
    this.onUngroup,
    this.reorderIndex,
  });

  final _EditableSlot slot;

  /// 0-based week whose set list this editor renders and mutates.
  final int week;
  final AppPalette palette;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  /// Called when the user picks a replacement exercise via the tappable cell.
  final void Function(Exercise newExercise) onReplaceExercise;

  /// Flat index of this slot in its day — used to key the menu button so
  /// tests can find it via `Key('slot_menu_button_$slotIndex')`.
  final int? slotIndex;

  /// Posición en el reorderable exterior (suelto) o interior (superserie).
  final int? reorderIndex;

  /// Reorder controls. When both callbacks are null no move buttons render.
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// Copies the previous exercise's prescription into this slot. Null when this
  /// is the first exercise of the day (or the only one present this week) —
  /// the menu item then renders disabled, like the edge reorder items.
  final VoidCallback? onCopyPrevious;

  /// True when this slot has at least one incomplete set in the viewed week.
  /// Drives a subtle red left border so the user can find it when scrolling.
  final bool hasSlotError;

  /// When true, shows trainer-only fields (e.g. coaching note).
  /// Defaults to false (fail-closed). REQ-EN-002.
  final bool isTrainerMode;

  /// Posición 0-based dentro de la superserie que lo contiene, o null si el
  /// ejercicio es suelto. La card lo usa para el badge A1/A2 y para teñir el
  /// agarre.
  final int? supersetPosition;

  /// Une este ejercicio con el de arriba o con el de abajo, en una superserie.
  /// Null cuando no aplica — el editor web del Coach Hub no ofrece el gesto.
  ///
  /// Las dos direcciones no son la misma cosa desde el lugar del usuario: unir
  /// hacia abajo es cómo se suma un ejercicio a una superserie que YA existe
  /// más abajo, sin reordenar nada primero.
  final VoidCallback? onMergeWithPrevious;
  final VoidCallback? onMergeWithNext;

  /// Lo saca de su superserie.
  final VoidCallback? onUngroup;

  @override
  State<_SlotEditor> createState() => _SlotEditorState();
}

class _SlotEditorState extends State<_SlotEditor> {
  /// Si la tabla de series está desplegada. Presentación local pura: no toca
  /// el modelo ni sobrevive a la pantalla.
  ///
  /// Arranca colapsado, salvo que el slot tenga sets inválidos. Eso cubre solo
  /// el caso que importa y de paso el que parecía necesitar otra regla: un
  /// ejercicio recién agregado nace con sus sets vacíos, o sea inválido, así
  /// que se despliega solo. No hace falta rastrear "cuál fue el último".
  /// Delegado al modelo — ver el dartdoc de [_EditableSlot.expandido]. Acá
  /// vivía un `late bool _expanded = widget.hasSlotError` y ése era el bug:
  /// el `State` se recrea al mover un slot entre la lista externa y la de una
  /// superserie, y el inicializador volvía a correr desplegando la card.
  bool get _expanded => widget.slot.expandido;
  set _expanded(bool v) => widget.slot.expandido = v;

  // Antes había acá un `didUpdateWidget` que forzaba la apertura cuando
  // aparecía un error, con el argumento de que "un problema escondido no se
  // puede arreglar". Ya no hace falta y era la otra mitad del mismo problema:
  // el error ahora se ve con la card CERRADA, enmarcada en rojo, que es
  // justamente lo que deja al usuario elegir cuál abrir en vez de abrírselas
  // todas encima.

  /// Opens the exercise picker and, if a replacement is chosen, swaps the
  /// slot's exercise from the ⋮ "Cambiar ejercicio" action.
  /// Abre la hoja de acciones del ejercicio y ejecuta la elegida.
  ///
  /// Era un `PopupMenuButton`: un menú flotante de ítems de ~40 dp colgado de
  /// un ícono de 20. Las acciones y su lógica son las MISMAS —`_SlotAction` no
  /// cambia—; lo que cambia es dónde se muestran y de qué tamaño.
  ///
  /// El issue #871 pedía además "Duplicar ejercicio" y "Unir en superserie con
  /// el anterior", diciendo que las acciones ya existían. Ninguna de las dos
  /// cosas es cierta: no están en `_SlotAction`, y **duplicar un ejercicio
  /// dentro del mismo día viola QA-WKT-004** — el session player agrupa el
  /// progreso por `exerciseId`, así que dos slots con el mismo id colapsan sus
  /// logs en un solo pool. Unir en superserie es la pieza que #869 dejó afuera
  /// por ser cambio de comportamiento.
  Future<void> _abrirAcciones(BuildContext context, AppL10n l10n) async {
    final hayMovimiento = widget.onMoveUp != null || widget.onMoveDown != null;
    final elegida = await showExerciseActionsSheet(
      context,
      title: widget.slot.exercise?.name ?? l10n.routineEditorExerciseSheetTitle,
      actions: [
        ExerciseAction(
          id: _SlotAction.toggleExpanded,
          label: _expanded
              ? l10n.routineEditorSlotMenuCollapse
              : l10n.routineEditorSlotMenuExpand,
          icon: _expanded ? TreinoIcon.chevronUp : TreinoIcon.chevronDown,
        ),
        ExerciseAction(
          id: _SlotAction.replace,
          label: l10n.routineEditorSlotMenuReplace,
          icon: TreinoIcon.edit,
        ),
        ExerciseAction(
          id: _SlotAction.copyPrevious,
          label: l10n.routineEditorSlotMenuCopyPrevious,
          icon: TreinoIcon.copy,
          enabled: widget.onCopyPrevious != null,
        ),
        if (hayMovimiento) ...[
          ExerciseAction(
            id: _SlotAction.moveUp,
            label: l10n.routineEditorSlotMenuMoveUp,
            icon: TreinoIcon.chevronUp,
            enabled: widget.canMoveUp,
          ),
          ExerciseAction(
            id: _SlotAction.moveDown,
            label: l10n.routineEditorSlotMenuMoveDown,
            icon: TreinoIcon.chevronDown,
            enabled: widget.canMoveDown,
          ),
        ],
        // Unir / separar. El botón `+ Superserie` del día sigue haciendo lo
        // suyo —abrir el picker y agregar ejercicios NUEVOS agrupados—; esto
        // es el camino que faltaba, para ejercicios que ya están cargados.
        if (widget.supersetPosition == null) ...[
          ExerciseAction(
            id: _SlotAction.mergeWithPrevious,
            label: l10n.routineEditorSlotMenuMergeUp,
            icon: TreinoIcon.streak,
            // Deshabilitada en el primero: no hay con quién unirse hacia
            // arriba. `canMoveUp` ya sabe si hay un bloque antes.
            enabled: widget.onMergeWithPrevious != null && widget.canMoveUp,
          ),
          ExerciseAction(
            id: _SlotAction.mergeWithNext,
            label: l10n.routineEditorSlotMenuMergeDown,
            icon: TreinoIcon.streak,
            enabled: widget.onMergeWithNext != null && widget.canMoveDown,
          ),
        ] else
          ExerciseAction(
            id: _SlotAction.ungroup,
            label: l10n.routineEditorSlotMenuUngroup,
            icon: TreinoIcon.close,
            enabled: widget.onUngroup != null,
          ),
        ExerciseAction(
          id: _SlotAction.remove,
          label: l10n.routineEditorSlotMenuRemove,
          icon: TreinoIcon.trash,
          danger: true,
        ),
      ],
    );
    if (elegida == null || !mounted) return;
    switch (elegida as _SlotAction) {
      case _SlotAction.toggleExpanded:
        setState(() => _expanded = !_expanded);
      case _SlotAction.replace:
        await _replaceExercise();
      case _SlotAction.moveUp:
        widget.onMoveUp?.call();
      case _SlotAction.moveDown:
        widget.onMoveDown?.call();
      case _SlotAction.copyPrevious:
        widget.onCopyPrevious?.call();
      case _SlotAction.mergeWithPrevious:
        widget.onMergeWithPrevious?.call();
      case _SlotAction.mergeWithNext:
        widget.onMergeWithNext?.call();
      case _SlotAction.ungroup:
        widget.onUngroup?.call();
      case _SlotAction.remove:
        widget.onRemove();
    }
  }

  Future<void> _replaceExercise() async {
    final picked = await showExercisePicker(context);
    if (!mounted || picked == null || picked.isEmpty) return;
    widget.onReplaceExercise(picked.first);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final slot = widget.slot;
    final palette = widget.palette;
    // Active week's list — the same object as weeklySets[week], so in-place
    // mutations below stay visible to the single source of truth.
    final sets = slot.setsForWeek(widget.week);
    final invalidSetCount = sets
        .where((set) => !isSetValid(set, slot.exerciseMode, slot.repMode))
        .length;
    final hasMissingPrescription = invalidSetCount > 0;
    final summary = hasMissingPrescription
        ? l10n.routineEditorSetsMissingReps(invalidSetCount)
        : _prescriptionSummary(slot, sets, l10n);

    return ExerciseCard(
      title: slot.exercise?.name ?? l10n.coachExercisePicker,
      expanded: _expanded,
      hasError: hasMissingPrescription,
      supersetPosition: widget.supersetPosition,
      reorderIndex: widget.reorderIndex,
      dragHandleKey: widget.slotIndex == null
          ? null
          : Key('slot_drag_handle_${widget.slotIndex}'),
      // Una card con problemas TAMBIÉN se puede colapsar: el resumen colapsado
      // sigue diciendo cuántos sets están sin completar. Trabar la cabecera
      // para "proteger" al usuario sólo hace que el tap no responda y parezca
      // rota.
      onToggle: () => setState(() => _expanded = !_expanded),
      summary: PrescriptionChips(
        prescription: summary,
        rest: hasMissingPrescription ? null : _restSummary(slot.restSeconds),
        // El resumen DICE cuántos sets faltan, pero ya no lo pinta de rojo:
        // desde #868 las señales de error son tres —celda, punto de la
        // pestaña, pie— y ésta era la cuarta, a 40 px de la celda que ya lo
        // marca con más precisión.
      ),
      menu: Transform.translate(
        offset: const Offset(AppSpacing.s8, -AppSpacing.s8),
        child: IconButton(
          key: widget.slotIndex != null
              ? Key('slot_menu_button_${widget.slotIndex}')
              : null,
          icon: Icon(TreinoIcon.dotsThree, size: 20, color: palette.textMuted),
          tooltip: l10n.workoutRoutineOptionsA11y,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          padding: EdgeInsets.zero,
          onPressed: () => _abrirAcciones(context, l10n),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Rest duration row ─────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: DurationTextField(
                  label: l10n.routineEditorRestLabel,
                  valueSeconds: slot.restSeconds,
                  onChanged: (v) {
                    slot.restSeconds = v;
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Coaching note (trainer modes only) ────────────────────────────
          // Gated by isTrainerMode — absent from tree in SelfCreating mode.
          // REQ-EN-002, REQ-EN-004.
          if (widget.isTrainerMode) ...[
            TextFormField(
              key: const Key('slot_notes_field'),
              initialValue: slot.notes,
              maxLength: 200,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.routineEditorNotesLabel,
                hintText: l10n.routineEditorNotesHint,
                counterText: '',
                filled: true,
                fillColor: palette.bgCard,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s14,
                  vertical: AppSpacing.s12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: palette.accent),
                ),
              ),
              onChanged: (v) {
                slot.notes = v.isEmpty ? null : v;
                widget.onChanged();
              },
            ),
            const SizedBox(height: 12),
          ],

          // ── Set table ─────────────────────────────────────────────────────
          _SetTable(
            slot: slot,
            sets: sets,
            palette: palette,
            showSetErrors: widget.hasSlotError,
            onChanged: () {
              setState(() {}); // redraw chip labels after type change
              widget.onChanged();
            },
          ),

          // ── "+ Agregar set" button ─────────────────────────────────────────
          const SizedBox(height: 6),
          AddSetButton(
            key: const Key('add_set_button'),
            label: l10n.routineEditorAddSet,
            onPressed: () {
              setState(() {
                final template =
                    sets.isNotEmpty ? sets.last.clone() : _EditableSet();
                sets.add(template);
              });
              widget.onChanged();
            },
          ),
        ],
      ),
    );
  }

  String _prescriptionSummary(
    _EditableSlot slot,
    List<_EditableSet> sets,
    AppL10n l10n,
  ) {
    final measureValues = slot.exerciseMode == ExerciseMode.duration
        ? sets.map((set) => set.durationSeconds).toList()
        : sets.map((set) => set.reps).toList();
    final measure = _uniform(measureValues);
    final measureText = measure == null
        ? '—'
        : slot.exerciseMode == ExerciseMode.duration
            ? _restSummary(measure)
            : '$measure';

    final segments = <String>['${sets.length} × $measureText'];
    if (slot.exerciseMode != ExerciseMode.duration) {
      final weight = _uniform(sets.map((set) => set.weightKg).toList());
      if (weight != null) {
        segments.add(
          '${formatWeightKg(weight)} ${l10n.monthlyReportVolumeUnit}',
        );
      } else if (sets.any((set) => set.weightKg != null)) {
        segments.add('— ${l10n.monthlyReportVolumeUnit}');
      }
    }
    return segments.join(' · ');
  }

  T? _uniform<T>(List<T?> values) {
    if (values.isEmpty || values.first == null) return null;
    final first = values.first;
    return values.every((value) => value == first) ? first : null;
  }

  String _restSummary(int seconds) {
    final display = secondsToMmss(seconds);
    return display.startsWith('0') ? display.substring(1) : display;
  }
}

// ── Slot overflow menu (⋮) ────────────────────────────────────────────────────

/// Actions surfaced from a slot's ⋮ overflow menu.
enum _SlotAction {
  /// Desplegar o colapsar la tabla de series. La cabecera de la card ya es el
  /// toggle; acá está porque con la hoja abierta la cabecera queda tapada.
  toggleExpanded,
  replace,
  copyPrevious,
  moveUp,
  moveDown,

  /// Unir este ejercicio con el de arriba, en una superserie.
  ///
  /// Hasta acá NO existía forma de agrupar dos ejercicios YA cargados: el
  /// botón `+ Superserie` abre el picker y agrega ejercicios NUEVOS agrupados,
  /// así que el caso normal —cargás dos por separado y después decidís hacerlos
  /// juntos— obligaba a borrarlos y volver a agregarlos.
  mergeWithPrevious,

  /// Unir con el de abajo. Es cómo se suma un ejercicio a una superserie que
  /// ya existe más abajo, sin reordenar nada primero.
  mergeWithNext,

  /// Sacar este ejercicio de su superserie.
  ungroup,

  remove,
}

// ── Set table ─────────────────────────────────────────────────────────────────

/// Renders the column header and one row per set for a slot.
class _SetTable extends StatefulWidget {
  const _SetTable({
    required this.slot,
    required this.sets,
    required this.palette,
    required this.onChanged,
    this.showSetErrors = false,
  });

  final _EditableSlot slot;

  /// When true, individual set rows highlight their input fields with a red
  /// underline when [isSetValid] returns false for that set.
  final bool showSetErrors;

  /// The active week's set list (same object as `slot.weeklySets[w]`) — the
  /// table needs no week knowledge, it renders and mutates this list in place.
  final List<_EditableSet> sets;
  final AppPalette palette;
  final VoidCallback onChanged;

  @override
  State<_SetTable> createState() => _SetTableState();
}

class _SetTableState extends State<_SetTable> {
  /// Opens the measure-mode picker (Reps / Tiempo) anchored to the tapped
  /// header cell. Switches the whole exercise between rep-based and time-based
  /// sets. Rep ranges were removed from the UI — picking "Reps" normalises any
  /// legacy range slot back to single reps.
  Future<void> _pickMeasureMode(BuildContext context, Offset position) async {
    final l10n = AppL10n.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final relativeOffset = renderBox != null
        ? renderBox.localToGlobal(Offset.zero, ancestor: overlay)
        : position;

    final result = await showMenu<ExerciseMode>(
      context: context,
      position: RelativeRect.fromLTRB(
        relativeOffset.dx,
        relativeOffset.dy + (renderBox?.size.height ?? 24),
        relativeOffset.dx + 120,
        0,
      ),
      color: widget.palette.bgCard,
      items: [
        PopupMenuItem(
          value: ExerciseMode.reps,
          child: Text(
            l10n.routineEditorMeasureReps,
            style: GoogleFonts.barlow(
                color: widget.palette.textPrimary, fontSize: 13),
          ),
        ),
        PopupMenuItem(
          value: ExerciseMode.duration,
          child: Text(
            l10n.routineEditorMeasureTime,
            style: GoogleFonts.barlow(
                color: widget.palette.textPrimary, fontSize: 13),
          ),
        ),
      ],
    );
    if (result != null) {
      setState(() {
        widget.slot.exerciseMode = result;
        if (result == ExerciseMode.reps) {
          widget.slot.repMode = RepMode.single;
        }
      });
      widget.onChanged();
    }
  }

  /// Replica el KG de la fila [origen] en todos los sets del ejercicio —
  /// "cuatro sets al mismo peso" es el caso normal, no la excepción (#640).
  ///
  /// Hasta #867 la fuente era SIEMPRE la primera fila, porque el disparador
  /// vivía en el header de la columna y ahí no hay ninguna fila en particular.
  /// Ahora el disparador es "A TODAS" en la barra sobre el teclado, y la fuente
  /// es la celda que se está editando: replicar desde la primera fila cuando el
  /// usuario está mirando la tercera sería replicar un número que no tiene
  /// delante.
  ///
  /// Pisa lo que cada fila tenía, así que viene con DESHACER en vez de una
  /// confirmación: un atajo que cuesta un diálogo deja de ser un atajo, y el
  /// snapshot restaura los valores exactos.
  void _fillKgColumn(int origen) {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sets = widget.sets;
    // Se cierra el IME para que el SnackBar no quede atrás del teclado. La
    // barra de accesorio se va con él, que es el final correcto: la acción de
    // columna terminó y lo que hay que poder ver ahora es "Deshacer".
    FocusManager.instance.primaryFocus?.unfocus();

    final source =
        origen >= 0 && origen < sets.length ? sets[origen].weightKg : null;
    if (source == null) {
      // Nothing to replicate — say so instead of silently clearing the column.
      // El texto dice "este set" y no "el primer set": desde #867 la fuente es
      // la celda enfocada, y mandar al usuario a cargar la primera fila lo
      // dejaba corrigiendo un valor que no es el que se va a replicar.
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.routineEditorFillColumnEmpty)),
      );
      return;
    }

    final previous = sets.map((s) => s.weightKg).toList(growable: false);
    if (previous.every((w) => w == source)) return; // already uniform

    setState(() => _applyWeights(List<double?>.filled(sets.length, source)));
    widget.onChanged();

    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.routineEditorFillKgApplied),
        action: SnackBarAction(
          key: const Key('fill_kg_undo_action'),
          label: l10n.routineEditorFillKgUndo,
          onPressed: () {
            if (!mounted) return;
            setState(() => _applyWeights(previous));
            widget.onChanged();
          },
        ),
      ),
    );
  }

  void _applyWeights(List<double?> weights) =>
      applyColumnWeights(widget.sets, weights);

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final sets = widget.sets;
    final palette = widget.palette;
    final isDuration = slot.exerciseMode == ExerciseMode.duration;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Column headers ─────────────────────────────────────────────────
        _SetTableHeader(
          slot: slot,
          palette: palette,
          onPickMeasureMode: _pickMeasureMode,
          showRemoveColumn: sets.length > 1,
        ),
        const SizedBox(height: 4),
        // ── Set rows ───────────────────────────────────────────────────────
        for (var i = 0; i < sets.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _SetRow(
              key: ObjectKey(sets[i]),
              editableSet: sets[i],
              index: i,
              allSets: sets,
              palette: palette,
              exerciseMode: slot.exerciseMode,
              repMode: slot.repMode,
              isDuration: isDuration,
              isInvalid: widget.showSetErrors &&
                  !isSetValid(sets[i], slot.exerciseMode, slot.repMode),
              onTypeChanged: (type) {
                setState(() => sets[i].type = type);
                widget.onChanged();
              },
              onRemove: sets.length > 1
                  ? () {
                      setState(() => sets.removeAt(i));
                      widget.onChanged();
                    }
                  : null,
              onChanged: widget.onChanged,
              exerciseName: slot.exercise?.name,
              // Sin KG no hay columna que replicar, y con un solo set no hay
              // dónde: en los dos casos el botón no se dibuja.
              onFillColumn: !isDuration && sets.length > 1
                  ? (_) => _fillKgColumn(i)
                  : null,
            ),
          ),
      ],
    );
  }
}

// ── Set table header ──────────────────────────────────────────────────────────

class _SetTableHeader extends StatelessWidget {
  const _SetTableHeader({
    required this.slot,
    required this.palette,
    required this.onPickMeasureMode,
    required this.showRemoveColumn,
  });

  final _EditableSlot slot;
  final AppPalette palette;
  final Future<void> Function(BuildContext, Offset) onPickMeasureMode;

  /// Si las filas muestran botón de borrar. Ver el comentario en el hueco.
  final bool showRemoveColumn;

  @override
  Widget build(BuildContext context) {
    final isDuration = slot.exerciseMode == ExerciseMode.duration;

    TextStyle headerStyle() => GoogleFonts.barlowCondensed(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: palette.textFaint,
        );

    Widget cell(String label, {bool tappable = false}) {
      final text = Text(label, style: headerStyle());
      if (!tappable) {
        return Expanded(child: Center(child: text));
      }
      // Tappable: header opens the Reps / Tiempo picker.
      return Expanded(
        child: Builder(
          builder: (ctx) => GestureDetector(
            onTap: () => onPickMeasureMode(ctx, Offset.zero),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                text,
                const SizedBox(width: 3),
                Icon(TreinoIcon.chevronDown,
                    size: 11, color: palette.textMuted),
              ],
            ),
          ),
        ),
      );
    }

    // KG ya no lleva gesto propio: el bulk-fill de columna se mudó a "A TODAS"
    // en la barra sobre el teclado (#867). Acá era un tap sobre un label de
    // 10,5 px con un ícono de 11 — existía, y no lo encontraba nadie.
    return Row(
      children: [
        // SET column (fixed narrow width)
        SizedBox(
          // Acompaña el ancho del SetTypeChip de la fila.
          width: 44,
          child: Center(
            child: Text('SET', style: headerStyle()),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        if (isDuration) ...[
          cell('TIEMPO', tappable: true),
        ] else ...[
          cell('KG'),
          const SizedBox(width: AppSpacing.s8),
          if (slot.repMode == RepMode.range) ...[
            cell('MÍN', tappable: true),
            const SizedBox(width: AppSpacing.s8),
            cell('MÁX', tappable: true),
          ] else ...[
            cell('REPS', tappable: true),
          ],
        ],
        // Hueco que alinea los headers con el botón de borrar de cada fila.
        // Sólo cuando ese botón existe: con un set único no se puede borrar
        // —quedarías en cero— y reservar los 40 px igual empujaba chip, kg y
        // reps a la izquierda, con un vacío a la derecha que se lee como un
        // error de centrado.
        if (showRemoveColumn) const SizedBox(width: 40),
      ],
    );
  }
}

// ── Set row ───────────────────────────────────────────────────────────────────

/// Qué celda de una fila de set tiene el foco. Es lo que decide el paso del
/// stepper (2,5 en kilos, 1 en repeticiones) y qué columna replica "A TODAS".
enum _SetField { kg, reps, repsMin, repsMax }

class _SetRow extends StatefulWidget {
  const _SetRow({
    super.key,
    required this.editableSet,
    required this.index,
    required this.allSets,
    required this.palette,
    required this.exerciseMode,
    required this.repMode,
    required this.isDuration,
    required this.onTypeChanged,
    required this.onChanged,
    this.onRemove,
    this.isInvalid = false,
    this.exerciseName,
    this.onFillColumn,
  });

  final _EditableSet editableSet;
  final int index;
  final List<_EditableSet> allSets;
  final AppPalette palette;
  final ExerciseMode exerciseMode;
  final RepMode repMode;
  final bool isDuration;
  final void Function(SetType) onTypeChanged;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  /// When true, the reps/duration input fields show a red underline to
  /// indicate this set is incomplete and needs to be filled in.
  final bool isInvalid;

  /// Nombre del ejercicio, para la línea de contexto de la barra de accesorio.
  /// Con el teclado abierto la fila que se edita queda a pocos píxeles del
  /// borde y no siempre se ve cuál es.
  final String? exerciseName;

  /// Replica el valor de una celda de esta fila en toda su columna. Null
  /// cuando no hay dónde replicar (un ejercicio de un solo set).
  final void Function(_SetField campo)? onFillColumn;

  @override
  State<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<_SetRow> {
  late final TextEditingController _kgCtrl;
  late final TextEditingController _repsCtrl;
  late final TextEditingController _repsMinCtrl;
  late final TextEditingController _repsMaxCtrl;

  /// Un focus node por celda. Antes sólo lo tenía KG, porque los steppers
  /// vivían dentro de la fila y sólo servían para el peso; desde #867 la barra
  /// de accesorio la monta la pantalla y necesita saber CUÁL celda se está
  /// editando, no sólo si es el peso.
  final Map<_SetField, FocusNode> _focos = {};

  @override
  void initState() {
    super.initState();
    final s = widget.editableSet;
    _kgCtrl = TextEditingController(text: _formatWeight(s.weightKg));
    _repsCtrl =
        TextEditingController(text: s.reps != null ? s.reps.toString() : '');
    _repsMinCtrl = TextEditingController(
        text: s.repsMin != null ? s.repsMin.toString() : '');
    _repsMaxCtrl = TextEditingController(
        text: s.repsMax != null ? s.repsMax.toString() : '');
    for (final campo in _SetField.values) {
      _focos[campo] = FocusNode()..addListener(() => _onFocoCambiado(campo));
    }
  }

  /// Identidad de una celda para el notifier: la instancia del set más el
  /// campo. Sobrevive a un rebuild de la fila y distingue dos celdas del mismo
  /// set, que es lo que el notifier necesita para no borrar el foco nuevo con
  /// el blur del viejo.
  Object _idDe(_SetField campo) => (widget.editableSet, campo);

  /// El notifier del scope, cacheado. En `dispose()` ya no se puede resolver
  /// por `context`, y ahí es justamente donde hay que soltar el foco.
  FocusedCellNotifier? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = RoutineEditorFocusScope.maybeOf(context);
  }

  @override
  void didUpdateWidget(_SetRow old) {
    super.didUpdateWidget(old);
    if (old.isDuration != widget.isDuration || old.repMode != widget.repMode) {
      _soltarFocosAusentes();
    }
  }

  /// Qué celdas renderiza esta fila con la configuración actual del slot.
  Set<_SetField> get _camposVisibles {
    if (widget.isDuration) return const {};
    return widget.repMode == RepMode.range
        ? const {_SetField.kg, _SetField.repsMin, _SetField.repsMax}
        : const {_SetField.kg, _SetField.reps};
  }

  /// Suelta el foco de las celdas que dejaron de existir.
  ///
  /// La fila NO se reconstruye cuando el slot cambia de modo —es el mismo
  /// `ObjectKey(set)`—, sólo cambia qué campos muestra. El `FocusNode` de una
  /// columna que se fue sigue vivo y con el foco puesto, así que sin esto la
  /// barra de accesorio quedaba ofreciendo atajos de kilos sobre un ejercicio
  /// que ya se mide en tiempo.
  ///
  /// Va DIFERIDO al frame siguiente: `didUpdateWidget` corre dentro de la fase
  /// de build, y notificar el scope ahí marca como dirty a un ancestro que ya
  /// se construyó — el framework lo rechaza con "setState() called during
  /// build". El foco se suelta cuando el árbol terminó de armarse.
  void _soltarFocosAusentes() {
    final ausentes = _SetField.values
        .where((c) => !_camposVisibles.contains(c))
        .toList(growable: false);
    for (final campo in ausentes) {
      _focos[campo]?.unfocus();
    }
    final scope = _scope;
    if (scope == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final campo in ausentes) {
        scope.blur(_idDe(campo));
      }
    });
  }

  void _onFocoCambiado(_SetField campo) {
    if (!mounted) return;
    final notifier = _scope;
    if (notifier == null) return;
    if (_focos[campo]!.hasFocus) {
      notifier.focus(_celdaEnfocada(campo));
    } else {
      notifier.blur(_idDe(campo));
    }
  }

  @override
  void dispose() {
    // Soltar el foco ANTES de tirar los nodos. Disponer un FocusNode no
    // dispara su listener, así que sin esto una fila que desaparece con el
    // foco puesto —cambiar el ejercicio a modo duración borra la columna KG,
    // borrar un set borra la fila entera— dejaba la barra en pantalla
    // ofreciendo atajos sobre una celda que ya no existe.
    final scope = _scope;
    if (scope != null) {
      final ids = _SetField.values.map(_idDe).toList(growable: false);
      // Diferido por la misma razón que [_soltarFocosAusentes]: sacar una fila
      // del árbol es parte de un build, y ahí no se puede notificar.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final id in ids) {
          scope.blur(id);
        }
      });
    }
    _kgCtrl.dispose();
    _repsCtrl.dispose();
    _repsMinCtrl.dispose();
    _repsMaxCtrl.dispose();
    for (final foco in _focos.values) {
      foco.dispose();
    }
    super.dispose();
  }

  /// Seeds the KG controller without losing fractional loads: integers show
  /// without a decimal (60), fractional values keep theirs (17.5).
  static String _formatWeight(double? w) => formatEditorWeight(w);

  /// The weight this row currently shows. The controller text wins over the
  /// model: mid-edit they can disagree for a keystroke, and the stepper must
  /// operate on the number the user is looking at.
  double? get _currentKg =>
      parseEditorWeight(_kgCtrl.text) ?? widget.editableSet.weightKg;

  TextEditingController _controllerDe(_SetField campo) => switch (campo) {
        _SetField.kg => _kgCtrl,
        _SetField.reps => _repsCtrl,
        _SetField.repsMin => _repsMinCtrl,
        _SetField.repsMax => _repsMaxCtrl,
      };

  /// El valor que la celda muestra AHORA. El controller le gana al modelo: a
  /// mitad de una edición pueden diferir por un keystroke, y el stepper tiene
  /// que operar sobre el número que el usuario está mirando.
  int? _repsActuales(_SetField campo) {
    final delControl = int.tryParse(_controllerDe(campo).text);
    if (delControl != null) return delControl;
    final s = widget.editableSet;
    return switch (campo) {
      _SetField.reps => s.reps,
      _SetField.repsMin => s.repsMin,
      _SetField.repsMax => s.repsMax,
      _SetField.kg => null,
    };
  }

  /// Applies a plate-sized jump to this row's KG (issue #640, PR#3).
  ///
  /// The instance is mutated IN PLACE and the controller is written by hand —
  /// deliberately NOT the `sets[i] = sets[i].copy()` replacement that
  /// [applyColumnWeights] uses for the column bulk-fill. Rows are keyed by
  /// `ObjectKey(set)`, so swapping the instance mints a new key, a new State
  /// and a new [TextEditingController]: the field would be rebuilt from
  /// scratch and the focus — which is the very thing that put this bar on
  /// screen — would die under the user's finger. Mutating keeps the key
  /// stable; writing the controller is what stops the model and the visible
  /// field from drifting apart (the trap the bulk-fill had to dodge).
  void _stepKg(double deltaKg) {
    final next = steppedWeightKg(_currentKg, deltaKg);
    final text = formatEditorWeight(next);
    if (next == widget.editableSet.weightKg && text == _kgCtrl.text) {
      // Sin valor nuevo no hay nada que escribir, pero sí que republicar: es
      // el camino por el que el botón de menos se apaga al llegar al piso.
      _republicar(_SetField.kg);
      return;
    }

    widget.editableSet.weightKg = next;
    _kgCtrl.value = TextEditingValue(
      text: text,
      // Caret parked at the end so typing after a bump appends instead of
      // landing wherever the previous selection happened to be.
      selection: TextSelection.collapsed(offset: text.length),
    );
    // Re-runs the slot's inline validation — a set completed by a stepper must
    // stop being painted red (`_isValid` / `hasSlotError`).
    widget.onChanged();
    _republicar(_SetField.kg);
  }

  /// Mismo salto, sobre una celda de repeticiones. Vale la misma advertencia
  /// que [_stepKg]: se muta la instancia, nunca se la reemplaza.
  ///
  /// El piso es 1 y no 0: un set de cero repeticiones no es un set, y a
  /// diferencia del peso —donde vacío significa "sin peso"— acá vaciar el
  /// campo lo deja inválido. Restar desde 1 no hace nada en vez de autorear un
  /// set roto.
  void _stepReps(_SetField campo, double delta) {
    final actual = _repsActuales(campo) ?? 0;
    final next = (actual + delta.round()).clamp(0, kMaxReps);
    if (next == 0 || next == actual) {
      _republicar(campo);
      return;
    }

    final s = widget.editableSet;
    switch (campo) {
      case _SetField.reps:
        s.reps = next;
      case _SetField.repsMin:
        s.repsMin = next;
      case _SetField.repsMax:
        s.repsMax = next;
      case _SetField.kg:
        return;
    }
    final text = '$next';
    _controllerDe(campo).value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    widget.onChanged();
    _republicar(campo);
  }

  /// Vuelve a publicar la celda enfocada después de un paso.
  ///
  /// `canDecrease` se calcula sobre el valor actual: sin esto, restar hasta el
  /// piso dejaría el botón de menos encendido hasta que el usuario tocara otra
  /// celda.
  void _republicar(_SetField campo) {
    if (!mounted || !(_focos[campo]?.hasFocus ?? false)) return;
    _scope?.focus(_celdaEnfocada(campo));
  }

  /// Arma lo que la barra de accesorio necesita saber sobre [campo].
  FocusedSetCell _celdaEnfocada(_SetField campo) {
    final l10n = AppL10n.of(context);
    final esKg = campo == _SetField.kg;
    return FocusedSetCell(
      cellId: _idDe(campo),
      contextLabel: l10n.routineEditorAccessoryContext(
        widget.exerciseName ?? l10n.coachExercisePicker,
        widget.index + 1,
        esKg ? l10n.routineEditorFieldKg : l10n.routineEditorFieldReps,
      ),
      stepAmount: esKg ? kKgStepsKg.first : 1,
      stepLabel: esKg ? formatWeightKg(kKgStepsKg.first) : '1',
      canDecrease:
          esKg ? (_currentKg ?? 0) > 0 : (_repsActuales(campo) ?? 0) > 1,
      onStep: (delta) => esKg ? _stepKg(delta) : _stepReps(campo, delta),
      stepIncreaseLabel: esKg
          ? l10n
              .routineEditorKgStepIncreaseA11y(formatWeightKg(kKgStepsKg.first))
          : l10n.routineEditorRepsStepIncreaseA11y('1'),
      stepDecreaseLabel: esKg
          ? l10n
              .routineEditorKgStepDecreaseA11y(formatWeightKg(kKgStepsKg.first))
          : l10n.routineEditorRepsStepDecreaseA11y('1'),
      onFillColumn: esKg && widget.onFillColumn != null
          ? () => widget.onFillColumn!(campo)
          : null,
    );
  }

  Future<void> _pickSetType(BuildContext context) async {
    final l10n = AppL10n.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final offset = renderBox != null
        ? renderBox.localToGlobal(Offset.zero, ancestor: overlay)
        : Offset.zero;

    final result = await showMenu<SetType>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + (renderBox?.size.height ?? 28),
        offset.dx + 160,
        0,
      ),
      color: widget.palette.bgCard,
      items: [
        PopupMenuItem(
            value: SetType.normal,
            child: Text(l10n.routineEditorSetTypeNormal)),
        PopupMenuItem(
            value: SetType.warmup,
            child: Text(l10n.routineEditorSetTypeWarmup)),
        PopupMenuItem(
            value: SetType.drop, child: Text(l10n.routineEditorSetTypeDrop)),
        PopupMenuItem(
            value: SetType.failure,
            child: Text(l10n.routineEditorSetTypeFailure)),
      ],
    );
    if (result != null) widget.onTypeChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.editableSet;
    final palette = widget.palette;
    final l10n = AppL10n.of(context);
    final label = setChipLabel(widget.allSets, widget.index);

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Set chip ──────────────────────────────────────────────────────
        Builder(
          builder: (ctx) => SetTypeChip(
            label: label,
            type: s.type,
            palette: palette,
            // Announce the set position, its type (warmup/drop/failure) and
            // whether it is currently invalid — the bare "1"/"C" glyph carries
            // none of that meaning for VoiceOver.
            semanticsLabel:
                _chipSemanticsLabel(label, s.type, widget.isInvalid, l10n),
            onTap: () => _pickSetType(ctx),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        // ── Input cells ───────────────────────────────────────────────────
        if (widget.isDuration) ...[
          Expanded(
            // El alto de 48 lo pone DurationTextField, igual que SetCellField.
            child: DurationTextField(
              valueSeconds: s.durationSeconds ?? 0,
              hasError: widget.isInvalid,
              onChanged: (v) {
                s.durationSeconds = v > 0 ? v : null;
                widget.onChanged();
              },
            ),
          ),
        ] else ...[
          // KG field — always optional, no error highlight
          Expanded(
            child: SetCellField(
              controller: _kgCtrl,
              focusNode: _focos[_SetField.kg],
              palette: palette,
              hint: 'kg',
              decimal: true,
              onDecimalChanged: (v) {
                s.weightKg = v;
                widget.onChanged();
                // `canDecrease` se calcula sobre el valor: tipear el primer
                // número tiene que habilitar el botón de menos sin esperar a
                // que el foco se vaya y vuelva, y vaciar el campo tiene que
                // apagarlo en vez de dejar un no-op encendido.
                _republicar(_SetField.kg);
              },
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          if (widget.repMode == RepMode.range) ...[
            // REP MIN
            Expanded(
              child: SetCellField(
                controller: _repsMinCtrl,
                focusNode: _focos[_SetField.repsMin],
                palette: palette,
                hint: 'mín',
                hasError: widget.isInvalid,
                onChanged: (v) {
                  s.repsMin = v;
                  widget.onChanged();
                  _republicar(_SetField.repsMin);
                },
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            // REP MAX
            Expanded(
              child: SetCellField(
                controller: _repsMaxCtrl,
                focusNode: _focos[_SetField.repsMax],
                palette: palette,
                hint: 'máx',
                hasError: widget.isInvalid,
                onChanged: (v) {
                  s.repsMax = v;
                  widget.onChanged();
                  _republicar(_SetField.repsMax);
                },
              ),
            ),
          ] else ...[
            // REPS
            Expanded(
              child: SetCellField(
                controller: _repsCtrl,
                focusNode: _focos[_SetField.reps],
                palette: palette,
                hint: 'reps',
                hasError: widget.isInvalid,
                onChanged: (v) {
                  s.reps = v;
                  widget.onChanged();
                  _republicar(_SetField.reps);
                },
              ),
            ),
          ],
        ],
        // ── Delete button ─────────────────────────────────────────────────
        // Con un set único `onRemove` es null y la columna NO ocupa lugar:
        // reservar 40 px para un botón ausente descentra la fila entera.
        if (widget.onRemove != null)
          SizedBox(
            // 40, el ancho que ya tenía: los 30 del handoff achicaban el área
            // táctil de 1760 a 1440 px². El alto sí sube a 48.
            width: 40,
            child: IconButton(
              icon: Icon(TreinoIcon.close, size: 15, color: palette.textMuted),
              tooltip: l10n.commonClose,
              onPressed: widget.onRemove,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 48),
              padding: EdgeInsets.zero,
            ),
          ),
      ],
    );

    // La raíz es SIEMPRE la misma clase de widget, y desde #867 no hay nada
    // condicional colgando de ella. La advertencia que dejó #640 sigue en pie
    // para quien quiera volver a poner algo acá: alternar el root entre `Row`
    // y `Column` según el foco cambia el runtimeType, y `Widget.canUpdate` lo
    // compara — Flutter destruye y re-infla todo este subárbol, incluido el
    // `EditableText` de KG, cuyo `dispose()` cierra la conexión con el IME que
    // el cambio de foco acababa de abrir, y cuyo reemplazo no la reabre. El
    // teclado aparecía y desaparecía en el mismo frame. Los atajos se fueron a
    // la barra de accesorio, que la monta la pantalla, justamente para que
    // esta fila no tenga que cambiar de forma cuando gana el foco.
    return row;
  }

  /// Builds the VoiceOver label for the set-type chip: the set position, the
  /// localized type name, and the invalid/warning state when present.
  String _chipSemanticsLabel(
      String setLabel, SetType type, bool isInvalid, AppL10n l10n) {
    final typeName = switch (type) {
      SetType.warmup => l10n.routineEditorSetTypeWarmup,
      SetType.drop => l10n.routineEditorSetTypeDrop,
      SetType.failure => l10n.routineEditorSetTypeFailure,
      SetType.normal => l10n.routineEditorSetTypeNormal,
    };
    final parts = [setLabel, typeName];
    if (isInvalid) parts.add(l10n.commonWarning);
    return parts.join(', ');
  }
}

// ── KG stepper bar ────────────────────────────────────────────────────────────

/// Plate-sized shortcuts for the KG field of the row currently being edited
/// (issue #640, PR#3): a gym user thinks in discs, not digits.
///
/// **Where it lives** — an accessory bar under the row whose KG field holds
/// focus, not a pair of buttons parked beside every field. The set row is
/// already `chip · KG · REPS · borrar` inside a card on a phone; four more
/// controls per row would have forced the columns to shrink, and shrinking
/// the columns is a redesign, which the issue rules out. One bar, bound to
/// focus, keeps the table exactly as it is.
///
/// **Why decrements ship too** — an up-only stepper sends the user back to
/// the keyboard the moment they overshoot, which is the tedium the shortcut
/// exists to remove. Deloads and top-set back-offs move down, not up.
/// [steppedWeightKg] clamps at zero, so "abajo" bottoms out at an empty
/// field and never at a negative load.
// ── Level dropdown ────────────────────────────────────────────────────────────

class _LevelDropdown extends StatelessWidget {
  const _LevelDropdown({
    required this.value,
    required this.palette,
    required this.onChanged,
  });

  final ExperienceLevel value;
  final AppPalette palette;
  final void Function(ExperienceLevel?) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ExperienceLevel>(
          value: value,
          isExpanded: true,
          dropdownColor: palette.bgCard,
          style: GoogleFonts.barlow(color: palette.textPrimary, fontSize: 14),
          items: ExperienceLevel.values
              .map((l) => DropdownMenuItem(
                    value: l,
                    child: Text(
                      l.displayNameEs,
                      style: GoogleFonts.barlow(
                          color: palette.textPrimary, fontSize: 14),
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Weight (kg) field helpers ───────────────────────────────────────────────
// SetSpec.weightKg is a double, so the editor must author fractional loads
// (e.g. 17.5 kg). These keep the seed-formatter and the field parser in sync.

/// Formats a weight for display in the KG field: integers drop the decimal
/// (60), fractional values keep theirs (17.5). Null/absent → empty string.
/// Delegates to the app-wide rule so the editor can never drift from how the
/// rest of the app renders loads.
String formatEditorWeight(double? w) => formatWeightKg(w);

/// Parses KG field text into a nullable double, accepting comma as the decimal
/// separator (common on iOS numeric keypads). Empty/invalid → null.

// ── Test bridge ───────────────────────────────────────────────────────────────
// Exposes internal helpers for unit tests without making the private types
// themselves public. Only used via test imports; Flutter tree-shakes it in
// release builds since nothing in the widget tree references it.

/// Static bridge that lets test files exercise [setChipLabel], [isSetValid],
/// and [buildRoutineSlot] by constructing [_EditableSet]/[_EditableSlot]
/// instances internally and returning plain Dart values.
class RoutineEditorTestBridge {
  RoutineEditorTestBridge._();

  /// Corre `_conGruposContiguos` sobre una lista descrita por sus ids de
  /// grupo, y devuelve el resultado en la misma forma.
  ///
  /// `null` es un slot suelto. Existe como bridge porque los casos que
  /// importan —un slot OCULTO en la semana en curso separando a dos miembros—
  /// son caros de montar por UI y triviales de expresar acá.
  static List<int?> gruposContiguosBridge(List<int?> grupos) {
    final slots = [
      for (final g in grupos) _EditableSlot()..supersetGroup = g,
    ];
    return _RoutineEditorScreenState._conGruposContiguos(slots)
        .map((s) => s.supersetGroup)
        .toList();
  }

  /// Delegates to [isSetValid] after constructing a minimal [_EditableSet].
  static bool isSetValidBridge({
    required ExerciseMode exerciseMode,
    required RepMode repMode,
    SetType type = SetType.normal,
    double? weightKg,
    int? reps,
    int? repsMin,
    int? repsMax,
    int? durationSeconds,
  }) {
    final s = _EditableSet(
      type: type,
      weightKg: weightKg,
      reps: reps,
      repsMin: repsMin,
      repsMax: repsMax,
      durationSeconds: durationSeconds,
    );
    return isSetValid(s, exerciseMode, repMode);
  }

  /// Delegates to [buildRoutineSlot] after constructing a minimal
  /// [_EditableSlot] from the given parameters.
  static RoutineSlot buildSlotBridge({
    required ExerciseMode exerciseMode,
    required RepMode repMode,
    required List<
            ({
              SetType type,
              double? weightKg,
              int? reps,
              int? repsMin,
              int? repsMax,
              int? durationSeconds,
            })>
        sets,
    String? notes,
  }) {
    final slot = _EditableSlot()
      ..exercise = const Exercise(
        id: 'test-ex',
        name: 'Test Exercise',
        muscleGroup: 'chest',
        category: 'compound',
      )
      ..exerciseMode = exerciseMode
      ..repMode = repMode
      ..weeklySets = [
        sets
            .map((r) => _EditableSet(
                  type: r.type,
                  weightKg: r.weightKg,
                  reps: r.reps,
                  repsMin: r.repsMin,
                  repsMax: r.repsMax,
                  durationSeconds: r.durationSeconds,
                ))
            .toList(),
      ]
      ..notes = notes;
    return buildRoutineSlot(slot, null);
  }

  /// Exposes the [_isTrainerMode] logic for tests.
  /// Returns true when [mode] is [TrainerAssigning] or [TrainerTemplating].
  static bool isTrainerModeForTest(RoutineEditorMode mode) =>
      mode is TrainerAssigning || mode is TrainerTemplating;

  /// Delegates to [setChipLabel] after constructing a list of [_EditableSet]s
  /// with the specified types.
  static String chipLabelBridge({
    required List<SetType> sets,
    required int index,
  }) {
    final editableSets = sets.map((t) => _EditableSet(type: t)).toList();
    return setChipLabel(editableSets, index);
  }

  /// Like [buildSlotBridge] but with one set list PER WEEK — lets unit tests
  /// assert the multi-week `weeklySets` derivation and the week-0 legacy
  /// fields (REQ-PERIOD-017).
  static RoutineSlot buildSlotBridgeWeekly({
    required ExerciseMode exerciseMode,
    required RepMode repMode,
    required List<
            List<
                ({
                  SetType type,
                  double? weightKg,
                  int? reps,
                  int? repsMin,
                  int? repsMax,
                  int? durationSeconds,
                })>>
        weeklySets,
  }) {
    final slot = _EditableSlot()
      ..exercise = const Exercise(
        id: 'test-ex',
        name: 'Test Exercise',
        muscleGroup: 'chest',
        category: 'compound',
      )
      ..exerciseMode = exerciseMode
      ..repMode = repMode
      ..weeklySets = weeklySets
          .map((wk) => wk
              .map((r) => _EditableSet(
                    type: r.type,
                    weightKg: r.weightKg,
                    reps: r.reps,
                    repsMin: r.repsMin,
                    repsMax: r.repsMax,
                    durationSeconds: r.durationSeconds,
                  ))
              .toList())
          .toList();
    return buildRoutineSlot(slot, null);
  }

  /// Like [buildSlotBridgeWeekly] but also accepts a presence mask
  /// [activeWeeks] — lets unit tests assert that [buildRoutineSlot] emits the
  /// correct sorted [RoutineSlot.activeWeeks] (REQ-WPRES-013).
  static RoutineSlot buildSlotBridgeWithPresence({
    required ExerciseMode exerciseMode,
    required RepMode repMode,
    required List<
            List<
                ({
                  SetType type,
                  double? weightKg,
                  int? reps,
                  int? repsMin,
                  int? repsMax,
                  int? durationSeconds,
                })>>
        weeklySets,
    required Set<int> activeWeeks,
  }) {
    final slot = _EditableSlot()
      ..exercise = const Exercise(
        id: 'test-ex',
        name: 'Test Exercise',
        muscleGroup: 'chest',
        category: 'compound',
      )
      ..exerciseMode = exerciseMode
      ..repMode = repMode
      ..weeklySets = weeklySets
          .map((wk) => wk
              .map((r) => _EditableSet(
                    type: r.type,
                    weightKg: r.weightKg,
                    reps: r.reps,
                    repsMin: r.repsMin,
                    repsMax: r.repsMax,
                    durationSeconds: r.durationSeconds,
                  ))
              .toList())
          .toList()
      ..activeWeeks = activeWeeks;
    return buildRoutineSlot(slot, null);
  }

  /// Validates that [activeWeeks] is a valid presence mask for [numWeeks]
  /// weeks. Bridges [_RoutineEditorScreenState._isPresenceMaskValid] for unit
  /// tests (REQ-WPRES-014, SCENARIO-WPRES-022/023).
  static bool isPresenceMaskValidBridge({
    required int numWeeks,
    required Set<int> activeWeeks,
  }) =>
      _RoutineEditorScreenState._isPresenceMaskValid(activeWeeks, numWeeks);

  /// Simulates the [_duplicateWeek] presence-copy logic for a set of slots
  /// defined by [slots] records. Returns the resulting [activeWeeks] masks (as
  /// `Set<int>`) in slot order, after copying presence from [sourceWeek] to
  /// [targetWeek] in a [numWeeks]-week plan.
  ///
  /// Used by SCENARIO-WPRES-020/021 unit tests to assert the duplication
  /// logic without a full widget pump (REQ-WPRES-013, ADR-WPRES-06).
  static List<Set<int>> duplicateWeekPresence({
    required int numWeeks,
    required int sourceWeek,
    required int targetWeek,
    required List<
            ({
              Set<int> activeWeeks,
              List<
                  List<
                      ({
                        SetType type,
                        double? weightKg,
                        int? reps,
                        int? repsMin,
                        int? repsMax,
                        int? durationSeconds,
                      })>> weekSets,
            })>
        slots,
  }) {
    // Build mutable _EditableSlots.
    final editableSlots = slots.map((s) {
      final slot = _EditableSlot()
        ..exercise = const Exercise(
          id: 'test-ex',
          name: 'Test Exercise',
          muscleGroup: 'chest',
          category: 'compound',
        )
        ..activeWeeks = Set<int>.from(s.activeWeeks)
        ..weeklySets = s.weekSets
            .map((wk) => wk
                .map((r) => _EditableSet(
                      type: r.type,
                      weightKg: r.weightKg,
                      reps: r.reps,
                      repsMin: r.repsMin,
                      repsMax: r.repsMax,
                      durationSeconds: r.durationSeconds,
                    ))
                .toList())
            .toList();
      return slot;
    }).toList();

    // Simulate the _duplicateWeek presence logic (ADR-WPRES-06).
    for (final slot in editableSlots) {
      if (slot.activeWeeks.isNotEmpty) {
        if (slot.isPresentInWeek(sourceWeek)) {
          slot.activeWeeks = Set<int>.from(slot.activeWeeks)..add(targetWeek);
        } else {
          slot.activeWeeks = Set<int>.from(slot.activeWeeks)
            ..remove(targetWeek);
        }
      }
    }

    return editableSlots.map((s) => s.activeWeeks).toList();
  }

  /// Runs [copyPrescriptionInto] on a source/target pair built from the given
  /// per-week specs and returns the TARGET rendered through [buildRoutineSlot]
  /// — so tests can assert the copied week, the untouched weeks, the mode and
  /// the presence mask in one shot.
  ///
  /// [mutateSourceAfterCopy] overwrites every source set (reps/duration/weight)
  /// AFTER the copy and BEFORE rendering: a deep copy is unaffected, a shallow
  /// one would leak the mutation into the target.
  static RoutineSlot copyPrescriptionBridge({
    required ExerciseMode sourceMode,
    required RepMode sourceRepMode,
    required List<
            List<
                ({
                  SetType type,
                  double? weightKg,
                  int? reps,
                  int? repsMin,
                  int? repsMax,
                  int? durationSeconds,
                })>>
        sourceWeeklySets,
    required ExerciseMode targetMode,
    required RepMode targetRepMode,
    required List<
            List<
                ({
                  SetType type,
                  double? weightKg,
                  int? reps,
                  int? repsMin,
                  int? repsMax,
                  int? durationSeconds,
                })>>
        targetWeeklySets,
    required int week,
    Set<int> targetActiveWeeks = const <int>{},
    bool mutateSourceAfterCopy = false,
  }) {
    final source = _slotFromWeeklyRecords(
      exerciseMode: sourceMode,
      repMode: sourceRepMode,
      weeklySets: sourceWeeklySets,
    );
    final target = _slotFromWeeklyRecords(
      exerciseMode: targetMode,
      repMode: targetRepMode,
      weeklySets: targetWeeklySets,
    )..activeWeeks = Set<int>.from(targetActiveWeeks);

    copyPrescriptionInto(source, target, week);

    if (mutateSourceAfterCopy) {
      for (final wk in source.weeklySets) {
        for (final s in wk) {
          s.type = SetType.failure;
          s.weightKg = 999;
          s.reps = 999;
          s.repsMin = 999;
          s.repsMax = 999;
          s.durationSeconds = 999;
        }
      }
    }

    return buildRoutineSlot(target, null);
  }

  /// Runs [applyColumnWeights] over a single-week slot built from [sets] and
  /// returns it through [buildRoutineSlot] — lets unit tests assert that a KG
  /// bulk fill moves ONLY the weight (SetType, reps, range and duration all
  /// survive) without pumping the widget tree.
  static RoutineSlot fillColumnWeightsBridge({
    required ExerciseMode exerciseMode,
    required RepMode repMode,
    required List<
            ({
              SetType type,
              double? weightKg,
              int? reps,
              int? repsMin,
              int? repsMax,
              int? durationSeconds,
            })>
        sets,
    required List<double?> weights,
  }) {
    final slot = _slotFromWeeklyRecords(
      exerciseMode: exerciseMode,
      repMode: repMode,
      weeklySets: [sets],
    );
    applyColumnWeights(slot.weeklySets.first, weights);
    return buildRoutineSlot(slot, null);
  }

  /// Shared constructor for the weekly-records bridges above.
  static _EditableSlot _slotFromWeeklyRecords({
    required ExerciseMode exerciseMode,
    required RepMode repMode,
    required List<
            List<
                ({
                  SetType type,
                  double? weightKg,
                  int? reps,
                  int? repsMin,
                  int? repsMax,
                  int? durationSeconds,
                })>>
        weeklySets,
  }) =>
      _EditableSlot()
        ..exercise = const Exercise(
          id: 'test-ex',
          name: 'Test Exercise',
          muscleGroup: 'chest',
          category: 'compound',
        )
        ..exerciseMode = exerciseMode
        ..repMode = repMode
        ..weeklySets = weeklySets
            .map((wk) => wk
                .map((r) => _EditableSet(
                      type: r.type,
                      weightKg: r.weightKg,
                      reps: r.reps,
                      repsMin: r.repsMin,
                      repsMax: r.repsMax,
                      durationSeconds: r.durationSeconds,
                    ))
                .toList())
            .toList();
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.palette});

  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 1.2,
        color: palette.textMuted,
      ),
    );
  }
}

/// SelfCreating-only tile that toggles `Routine.visibility` between
/// `private` and `public`. When public, the routine surfaces in the
/// "RUTINAS PÚBLICAS" tab of the athlete's public profile screen.
///
/// Copy is intentionally descriptive ("Compartir en mi perfil") rather
/// than technical ("público/privado") — the term "privado" already means
/// "profile privacy" in this app after PR #273, and reusing it here for a
/// different concept was confusing users during smoke.
class _ShareOnProfileTile extends StatelessWidget {
  const _ShareOnProfileTile({
    required this.value,
    required this.palette,
    required this.onChanged,
  });

  final bool value;
  final AppPalette palette;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: value,
      label: 'Compartir rutina en mi perfil', // i18n: Fase W2
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.bgCard,
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Compartir en mi perfil', // i18n: Fase W2
                      style: GoogleFonts.barlow(
                        color: palette.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value
                          ? 'Cualquiera que vea tu perfil podrá encontrar esta rutina.' // i18n: Fase W2
                          : 'Nadie más va a ver esta rutina.', // i18n: Fase W2
                      style: GoogleFonts.barlow(
                        color: palette.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeThumbColor: palette.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
