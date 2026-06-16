// ignore_for_file: library_private_types_in_public_api
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../coach/presentation/widgets/exercise_picker_sheet.dart';
import '../../profile/domain/experience_level.dart';
import '../application/routine_providers.dart' show routineRepositoryProvider;
import '../application/session_providers.dart' show currentUidProvider;
import '../application/user_routines_providers.dart'
    show userCreatedRoutinesProvider;
import '../domain/exercise.dart';
import '../domain/routine.dart';
import '../domain/routine_day.dart';
import '../domain/routine_slot.dart';
import '../domain/routine_source.dart';
import '../domain/routine_visibility.dart';
import '../domain/set_enums.dart';
import '../domain/set_spec.dart';
import 'routine_editor_mode.dart';
import 'widgets/duration_text_field.dart';

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
  if (s.type == SetType.failure) return true;
  if (exerciseMode == ExerciseMode.duration) {
    return s.durationSeconds != null && s.durationSeconds! > 0;
  }
  if (repMode == RepMode.range) {
    return s.repsMin != null &&
        s.repsMin! > 0 &&
        s.repsMax != null &&
        s.repsMax! >= s.repsMin!;
  }
  return s.reps != null && s.reps! > 0;
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

/// Extracts the existing doc id from any mode that supports editing.
/// Returns null for create modes.
String? _existingIdFor(RoutineEditorMode mode) => switch (mode) {
      SelfCreating(:final existingRoutineId) => existingRoutineId,
      TrainerAssigning(:final existingPlanId) => existingPlanId,
      TrainerTemplating(:final existingTemplateId) => existingTemplateId,
    };

String _titleFor(RoutineEditorMode mode, AppL10n l10n) => switch (mode) {
      TrainerAssigning(existingPlanId: null) => l10n.coachEditorTitle,
      TrainerAssigning() => l10n.coachEditorEditTitle,
      TrainerTemplating(existingTemplateId: null) => l10n.coachEditorTitle,
      TrainerTemplating() => l10n.coachEditorEditTitle,
      SelfCreating(existingRoutineId: null) => l10n.workoutSelfEditorTitle,
      SelfCreating() => l10n.workoutSelfEditorEditTitle,
    };

String _submitLabelFor(RoutineEditorMode mode, AppL10n l10n) => switch (mode) {
      TrainerAssigning(existingPlanId: null) => l10n.coachEditorSubmit,
      TrainerAssigning() => l10n.coachEditorUpdateLabel,
      TrainerTemplating(existingTemplateId: null) => l10n.coachEditorSubmit,
      TrainerTemplating() => l10n.coachEditorUpdateLabel,
      SelfCreating(existingRoutineId: null) =>
        l10n.workoutSelfEditorSubmitLabel,
      SelfCreating() => l10n.workoutSelfEditorUpdateLabel,
    };

class _RoutineEditorScreenState extends ConsumerState<RoutineEditorScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _splitController = TextEditingController();
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

  /// 0-based week shown in the editor. Display is 1-based ("Sem 1").
  int _selectedWeek = 0;

  /// Plan length in weeks. Every slot's `weeklySets` holds exactly this many
  /// inner lists (REQ-PERIOD-013). Capped at 16 (REQ-PERIOD-011).
  int _numWeeks = 1;

  bool _submitting = false;

  /// True while the existing routine is being fetched from Firestore.
  /// Relevant in any mode with an existing id (all three edit variants).
  bool _loading = false;

  /// Shown when the routine to edit no longer exists in Firestore.
  bool _loadNotFound = false;

  @override
  void initState() {
    super.initState();
    // Hydrate editor when editing an existing routine/plan/template.
    // Works for all three modes: SelfCreating, TrainerAssigning, TrainerTemplating.
    final existingId = _existingIdFor(widget.mode);
    if (existingId != null) {
      _loadExistingRoutine(existingId);
    }
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
      _nameController.text = routine.name;
      _level = routine.level;
      // Defensive clamp — a hand-edited doc can't exceed the editor cap nor
      // drop below one week (REQ-PERIOD-011/018).
      _numWeeks = routine.numWeeks.clamp(1, _kMaxWeeks);
      // split is shown in trainer modes — restore it so the field is populated.
      if (routine.split != null) {
        _splitController.text = routine.split!;
      }
      final l10n = AppL10n.of(context);
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
            ..activeWeeks = slot.activeWeeks.toSet();

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
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadNotFound = true;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _splitController.dispose();
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
            weekSets.every((s) => isSetValid(s, slot.exerciseMode, slot.repMode));
        if (!allValid) {
          return (day: day, exerciseName: slot.exercise?.name);
        }
      }
    }
    return null;
  }

  /// Whether the editor is in a trainer-creating mode (assigning or
  /// templating). Athlete (SelfCreating) mode hides trainer-only fields.
  /// REQ-RER-012, REQ-RER-013, ADR-RER-04.
  bool get _isTrainerMode =>
      widget.mode is TrainerAssigning || widget.mode is TrainerTemplating;

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

  /// Appends an EMPTY week (one placeholder set per slot) and jumps to it.
  /// Empty by design — "Duplicar semana" is the explicit copy affordance
  /// (ADR-PB-04). SCENARIO-PERIOD-010/011.
  void _addWeek() {
    if (_numWeeks >= _kMaxWeeks) return;
    FocusManager.instance.primaryFocus?.unfocus();
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
    });
  }

  void _removeDay(int index) {
    final l10n = AppL10n.of(context);
    setState(() {
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
                '¿Eliminar solo de esta semana o de todas?',
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(_DeleteScope.thisWeek),
              child: Text('Solo esta semana',
                  style: TextStyle(color: palette.accent)),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(_DeleteScope.allWeeks),
              child: Text('Todas las semanas',
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
    return showDialog<_AddScope>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: palette.bgCard,
        title: Text(
          '¿En qué semanas agregar?',
          style: TextStyle(color: palette.textPrimary),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Text(
              '¿Agregar el ejercicio solo en esta semana o en todas?',
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_AddScope.thisWeek),
            child: Text('Agregar solo en esta semana',
                style: TextStyle(color: palette.accent)),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_AddScope.allWeeks),
            child: Text('Agregar en todas las semanas',
                style: TextStyle(color: palette.textMuted)),
          ),
        ],
      ),
    );
  }

  /// Replaces a day's slot order after a block-level reorder in the tile.
  void _reorderSlots(int dayIndex, List<_EditableSlot> newOrder) {
    setState(() {
      _days[dayIndex].slots = newOrder;
    });
  }

  /// Replaces [slot]'s exercise with [newExercise], keeping all other fields
  /// (sets, rest, exerciseMode, repMode, supersetGroup) intact.
  void _replaceExercise(_EditableSlot slot, Exercise newExercise) {
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
    if (swapped) setState(() {});
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
    final picked = await showExercisePicker(context);
    if (picked == null || picked.isEmpty || !mounted) return;

    // Determine presence scope for the new slots (ADR-WPRES-04).
    // Prompt only when multi-week AND viewing week ≥ 2 (index ≥ 1).
    // ignore: use_build_context_synchronously
    final scope = await _promptAddScope(context);
    if (scope == null || !mounted) return;

    setState(() {
      // Only add exercises not already in this day (one instance per day) —
      // avoids the duplicate-on-reopen issue.
      for (final ex in picked.where((e) => !existingIds.contains(e.id))) {
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

  /// Opens the multi-select picker for [dayIndex] and appends all picked
  /// exercises as a new superset block (shared non-null [supersetGroup]).
  /// Available in every editor mode (trainer + athlete SelfCreating).
  Future<void> _addSupersetForDay(BuildContext context, int dayIndex) async {
    final existingIds = _days[dayIndex]
        .slots
        .where((s) => s.exercise != null)
        .map((s) => s.exercise!.id)
        .toSet();
    final picked = await showExercisePicker(context);
    if (picked == null || picked.isEmpty || !mounted) return;

    // Determine presence scope for the new slots (ADR-WPRES-04).
    // ignore: use_build_context_synchronously
    final scope = await _promptAddScope(context);
    if (scope == null || !mounted) return;

    setState(() {
      final day = _days[dayIndex];
      // Skip exercises already in this day (one instance per day).
      final newOnes = picked.where((e) => !existingIds.contains(e.id)).toList();
      if (newOnes.isEmpty) return;
      final nextGroup =
          (day.slots.map((s) => s.supersetGroup ?? 0).fold(0, max)) + 1;
      final newSlots = newOnes
          .map((ex) => _EditableSlot()
            ..exercise = ex
            ..restSeconds = 0
            ..supersetGroup = nextGroup
            ..weeklySets = List.generate(_numWeeks, (_) => [_EditableSet()])
            ..activeWeeks =
                scope == _AddScope.thisWeek ? {_selectedWeek} : <int>{})
          .toList();
      day.slots = [...day.slots, ...newSlots];
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
    final picked = await showExercisePicker(context);
    if (picked == null || picked.isEmpty || !mounted) return;

    // Determine presence scope for the new slots (ADR-WPRES-04).
    // ignore: use_build_context_synchronously
    final scope = await _promptAddScope(context);
    if (scope == null || !mounted) return;

    setState(() {
      final newOnes = picked.where((e) => !existingIds.contains(e.id)).toList();
      if (newOnes.isEmpty) return;
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

    // If invalid: show feedback and scroll to first offending slot instead of
    // silently blocking save (UX fix: button is now always tappable).
    if (!_isValid) {
      final l10n = AppL10n.of(context);
      final first = _firstInvalidSlot();
      final message = first?.exerciseName != null
          ? l10n.routineEditorIncompleteSetsFeedback(first!.exerciseName!)
          : l10n.routineEditorIncompleteSetsFeedback('…');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      // Expand the first invalid day and scroll to it.
      if (first != null) {
        // Ensure the day is expanded so the user can see the invalid sets.
        if (!first.day.expanded) {
          setState(() => first.day.expanded = true);
        }
        // Wait one frame for the expansion to apply before scrolling.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final key = _keyForDay(first.day);
          if (key.currentContext != null) {
            Scrollable.ensureVisible(
              key.currentContext!,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
              alignment: 0.1,
            );
          }
        });
      }
      return;
    }

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
          );
          await repo.createTemplate(routine);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.coachCreatePlanSuccess)),
          );
          context.pop();

        case SelfCreating(existingRoutineId: null):
          // Client-side cap check (ADR-USR-02).
          final userRoutines =
              ref.read(userCreatedRoutinesProvider(uid)).valueOrNull ?? [];
          if (userRoutines.length >= 10) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(l10n.workoutSelfEditorCapReached)),
            );
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
            visibility: RoutineVisibility.private,
            numWeeks: _numWeeks,
          );
          await repo.createUserOwned(uid: uid, draft: draft);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.workoutSelfEditorSuccess)),
          );
          context.pop();

        case SelfCreating(existingRoutineId: final existingId?):
          // Full edit path (REQ-USR-018) — update content in Firestore.
          final draft = Routine(
            id: existingId,
            name: _nameController.text.trim(),
            split: null,
            level: ExperienceLevel.beginner,
            days: days,
            source: RoutineSource.userCreated,
            visibility: RoutineVisibility.private,
            numWeeks: _numWeeks,
          );
          await repo.updateUserOwned(uid: uid, draft: draft);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(l10n.workoutSelfEditorUpdateSuccess)),
          );
          context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      final errorText = switch (widget.mode) {
        TrainerAssigning() => l10n.coachCreatePlanError,
        TrainerTemplating() => l10n.coachCreatePlanError,
        SelfCreating() => e.toString().contains('permission-denied')
            ? l10n.workoutSelfEditorPermissionDenied
            : l10n.workoutSelfEditorError,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorText)),
      );
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    // Loading state: hydrating from Firestore.
    if (_loading) {
      return Scaffold(
        body: AppBackground(
          child: Center(
            child: CircularProgressIndicator(color: palette.accent),
          ),
        ),
      );
    }

    // Not-found state: routine was deleted before the user opened it.
    if (_loadNotFound) {
      return Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(TreinoIcon.back, color: palette.textPrimary),
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
      final invalidWeeks = _invalidWeekFirstDay;
      final hiddenInvalidWeeks =
          invalidWeeks.keys.where((w) => w != _selectedWeek).toList()..sort();
      return Scaffold(
        // Tapping anywhere outside a field dismisses the keyboard (device UX
        // 2026-06-11). translucent → child widgets still receive their taps.
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: AppBackground(
            child: SafeArea(
              child: Column(
                children: [
                  // ── Custom header ────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon:
                              Icon(TreinoIcon.back, color: palette.textPrimary),
                          onPressed: () => context.canPop()
                              ? context.pop()
                              : context.go(widget.mode is SelfCreating
                                  ? '/workout'
                                  : '/coach'),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _titleFor(widget.mode, l10n),
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: palette.textPrimary,
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
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      children: [
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
                                          ? 'Ej: Fuerza PPL'
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
                                        hint: 'PPL / Full Body',
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),

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
                                        label: l10n.routineEditorLevelLabel,
                                        palette: palette),
                                    const SizedBox(height: 4),
                                    _LevelDropdown(
                                      value: _level,
                                      palette: palette,
                                      onChanged: (v) {
                                        if (v != null) {
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
                        _SectionLabel(
                            label: l10n.routineEditorWeeksLabel,
                            palette: palette),
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
                            l10n.routineEditorInvalidWeekHint(
                              hiddenInvalidWeeks.first + 1,
                              invalidWeeks[hiddenInvalidWeeks.first]!,
                            ),
                            key: const Key('invalid_week_hint'),
                            style: GoogleFonts.barlow(
                              fontSize: 11,
                              color: palette.danger,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),

                        // ── Días del plan ───────────────────────────────────
                        _SectionLabel(
                            label: l10n.routineEditorDaysLabel,
                            palette: palette),
                        const SizedBox(height: 6),

                        for (int di = 0; di < _days.length; di++) ...[
                          _DayExpansionTile(
                            key: _keyForDay(_days[di]),
                            day: _days[di],
                            week: _selectedWeek,
                            palette: palette,
                            onAddSlot: () => _pickExercisesForDay(context, di),
                            onRemoveSlot: (si) =>
                                _onDeleteSlot(context, di, si),
                            onReorderSlots: (newOrder) =>
                                _reorderSlots(di, newOrder),
                            onRemoveDay:
                                _days.length > 1 ? () => _removeDay(di) : null,
                            onSlotChanged: () => setState(() {}),
                            onAddToGroup: (g) =>
                                _addExerciseToGroup(context, di, g),
                            onReplaceExercise: (slot, ex) =>
                                _replaceExercise(slot, ex),
                            onMoveSlotInGroup: (absIndex, dir) =>
                                _moveSlotWithinGroup(di, absIndex, dir),
                            // Supersets available in every mode, including the
                            // athlete's SelfCreating editor.
                            allowSuperset: true,
                            onAddSuperset: () =>
                                _addSupersetForDay(context, di),
                            slotIsValid: (slot) {
                              if (!slot.isPresentInWeek(_selectedWeek)) {
                                return true;
                              }
                              final weekSets = slot.setsForWeek(_selectedWeek);
                              return weekSets.isNotEmpty &&
                                  weekSets.every((s) => isSetValid(
                                      s, slot.exerciseMode, slot.repMode));
                            },
                          ),
                          const SizedBox(height: 6),
                        ],

                        // Add day button — disabled at the 7-day cap.
                        TextButton.icon(
                          onPressed: _days.length < _kMaxDays ? _addDay : null,
                          icon: Icon(TreinoIcon.plus,
                              size: 14,
                              color: _days.length < _kMaxDays
                                  ? palette.accent
                                  : palette.textMuted),
                          label: Text(
                            l10n.coachEditorAddDay,
                            style: GoogleFonts.barlowCondensed(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: _days.length < _kMaxDays
                                  ? palette.accent
                                  : palette.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),

                  // ── Submit button — pinned outside ListView ───────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            !_submitting ? () => _submit() : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: palette.accent,
                          foregroundColor: palette.bg,
                          disabledBackgroundColor: palette.accent.withAlpha(80),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999),
                          ),
                        ),
                        child: _submitting
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: palette.bg,
                                ),
                              )
                            : Text(
                                _submitLabelFor(widget.mode, l10n),
                                style: GoogleFonts.barlowCondensed(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: 0.8,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                label: Text(l10n.routineEditorAddWeek,
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
              label: Text(l10n.routineEditorDuplicateWeek,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? palette.accent : palette.bgCard,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: selected ? palette.accent : palette.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppL10n.of(context).routineEditorWeekShort(index + 1),
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.5,
                color: selected ? palette.bg : palette.textMuted,
              ),
            ),
            if (warning) ...[
              const SizedBox(width: 5),
              Container(
                key: Key('week_tab_warning_$index'),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: palette.danger,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
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
    this.allowSuperset = false,
    this.onAddSuperset,
    this.slotIsValid,
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

  /// Returns true when [slot] has no incomplete sets for the currently viewed
  /// week. Used to drive red affordances in the slot and day-header cards.
  final bool Function(_EditableSlot slot)? slotIsValid;

  @override
  State<_DayExpansionTile> createState() => _DayExpansionTileState();
}

class _DayExpansionTileState extends State<_DayExpansionTile> {
  // Reads/writes widget.day.expanded so the collapse survives the ListView
  // recycling the tile off-screen.
  bool get _expanded => widget.day.expanded;
  set _expanded(bool v) => widget.day.expanded = v;

  /// Walks the slot list and emits either a standalone [_SlotEditor] or a
  /// "SUPERSERIE" wrapper card for consecutive slots sharing a non-null group.
  List<Widget> _buildSlotRows(AppPalette palette) {
    final blocks = _blocks();
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
      final canUp = b > 0;
      final canDown = b < blocks.length - 1;
      if (block.length == 1 && block.first.slot.supersetGroup == null) {
        // Standalone slot. ObjectKey keeps each row's State bound to its slot
        // so the int fields don't show stale values after the list shifts.
        final idx = visible.first.index;
        final slot = visible.first.slot;
        rows.add(_SlotEditor(
          key: ObjectKey(slot),
          slot: slot,
          week: widget.week,
          palette: palette,
          onRemove: () => widget.onRemoveSlot(idx),
          onChanged: widget.onSlotChanged,
          onReplaceExercise: (ex) => widget.onReplaceExercise(slot, ex),
          slotIndex: idx,
          canMoveUp: canUp,
          canMoveDown: canDown,
          onMoveUp: () => _moveBlock(b, -1),
          onMoveDown: () => _moveBlock(b, 1),
          hasSlotError: widget.slotIsValid != null
              ? !widget.slotIsValid!(slot)
              : false,
        ));
      } else {
        // Superset block — the whole block moves as one unit. Only the
        // members present in the viewed week are rendered.
        rows.add(_SupersetGroupCard(
          groupSlots: visible,
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
          slotIsValid: widget.slotIsValid,
        ));
      }
      rows.add(const SizedBox(height: 8));
    }
    return rows;
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

  /// Swaps block [blockIndex] with its neighbour in [dir] (-1 up / +1 down) and
  /// flattens back to a slot list. No-op at the edges. A whole superset moves
  /// as a single unit, so a reorder never splits a block.
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
    // Day-level error: at least one visible slot has incomplete sets.
    final hasDayError = widget.slotIsValid != null &&
        widget.day.slots.any((slot) =>
            slot.isPresentInWeek(widget.week) &&
            !widget.slotIsValid!(slot));
    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasDayError
              ? palette.danger.withAlpha(180)
              : palette.border,
          width: hasDayError ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        children: [
          // Header row
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? TreinoIcon.chevronDown
                        : TreinoIcon.chevronRight,
                    size: 16,
                    color: hasDayError ? palette.danger : palette.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.day.name,
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  if (hasDayError) ...[
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: palette.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  if (widget.onRemoveDay != null)
                    IconButton(
                      icon: Icon(TreinoIcon.trash,
                          size: 18, color: palette.textMuted),
                      onPressed: widget.onRemoveDay,
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
          ),

          // Body
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Column(
                children: [
                  ..._buildSlotRows(palette),
                  // Add slot button
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: widget.onAddSlot,
                      icon: Icon(TreinoIcon.plus,
                          size: 14, color: palette.accent),
                      label: Text(
                        l10n.routineEditorAddExercise,
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: palette.accent,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ),
                  // "+ Superserie" button — trainer mode only
                  if (widget.allowSuperset)
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        key: const Key('add_superset_button'),
                        onPressed: widget.onAddSuperset,
                        icon: Icon(TreinoIcon.streak,
                            size: 14, color: palette.highlight),
                        label: Text(
                          l10n.coachEditorAddSuperset,
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: palette.highlight,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ),
                ],
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
    required this.groupSlots,
    required this.week,
    required this.palette,
    required this.onRemoveSlot,
    required this.onChanged,
    required this.onAddExercise,
    required this.onReplaceExercise,
    required this.onMoveSlotInGroup,
    this.canMoveUp = false,
    this.canMoveDown = false,
    this.onMoveUp,
    this.onMoveDown,
    this.slotIsValid,
  });

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

  /// Block-level reorder controls — the whole superset moves as one unit.
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// Returns true when [slot] is valid for the current week.
  final bool Function(_EditableSlot slot)? slotIsValid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: palette.highlight.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.highlight.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(TreinoIcon.streak, size: 15, color: palette.highlight),
              const SizedBox(width: 6),
              Text(
                'SUPERSERIE',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 1.2,
                  color: palette.highlight,
                ),
              ),
              if (onMoveUp != null || onMoveDown != null) ...[
                const Spacer(),
                _MoveButtons(
                  palette: palette,
                  canMoveUp: canMoveUp,
                  canMoveDown: canMoveDown,
                  onMoveUp: onMoveUp,
                  onMoveDown: onMoveDown,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // Slot editors stacked
          for (var mi = 0; mi < groupSlots.length; mi++) ...[
            _SlotEditor(
              key: ObjectKey(groupSlots[mi].slot),
              slot: groupSlots[mi].slot,
              week: week,
              palette: palette,
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
              hasSlotError: slotIsValid != null
                  ? !slotIsValid!(groupSlots[mi].slot)
                  : false,
            ),
            if (mi < groupSlots.length - 1) const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          // Add another exercise into THIS superset block.
          TextButton.icon(
            onPressed: onAddExercise,
            icon: Icon(TreinoIcon.plus, size: 14, color: palette.highlight),
            label: Text(
              AppL10n.of(context).routineEditorAddExercise,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: palette.highlight,
              ),
            ),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              alignment: Alignment.centerLeft,
            ),
          ),
        ],
      ),
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
    Widget btn(IconData icon, bool enabled, VoidCallback? cb) => IconButton(
          icon: Icon(
            icon,
            size: 18,
            color: enabled ? palette.textMuted : palette.border,
          ),
          onPressed: enabled ? cb : null,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.symmetric(horizontal: 3),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(TreinoIcon.chevronUp, canMoveUp, onMoveUp),
        btn(TreinoIcon.chevronDown, canMoveDown, onMoveDown),
      ],
    );
  }
}

// ── Slot editor — Hevy-style set table ───────────────────────────────────────

class _SlotEditor extends StatefulWidget {
  const _SlotEditor({
    super.key,
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
    this.hasSlotError = false,
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

  /// Reorder controls. When both callbacks are null no move buttons render.
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// True when this slot has at least one incomplete set in the viewed week.
  /// Drives a subtle red left border so the user can find it when scrolling.
  final bool hasSlotError;

  @override
  State<_SlotEditor> createState() => _SlotEditorState();
}

class _SlotEditorState extends State<_SlotEditor> {
  /// Opens the exercise picker and, if a replacement is chosen, swaps the
  /// slot's exercise. Shared by the name tap and the ⋮ "Cambiar ejercicio".
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
    // One light surface per card — no outer border, just a fill + generous
    // padding. Inner fields are NOT individually boxed.
    // A red left accent stripe appears when the slot has incomplete sets so
    // the user can locate the problem at a glance while scrolling.
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: widget.hasSlotError
            ? Border(
                left: BorderSide(
                  color: palette.danger.withAlpha(180),
                  width: 3,
                ),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row: full-width exercise name + ⋮ overflow menu ────────
          // The name owns its own row (wraps up to 2 lines) so long names like
          // "Press de banca con barra" are fully readable — the actions live in
          // the ⋮ menu instead of competing for width (Hevy-style).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  onTap: _replaceExercise,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      slot.exercise?.name ?? l10n.coachExercisePicker,
                      style: GoogleFonts.barlow(
                        fontSize: 19,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: slot.exercise != null
                            ? palette.textPrimary
                            : palette.textMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<_SlotAction>(
                key: widget.slotIndex != null
                    ? Key('slot_menu_button_${widget.slotIndex}')
                    : null,
                icon: Icon(TreinoIcon.dotsThree,
                    size: 20, color: palette.textMuted),
                color: palette.bgCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                onSelected: (action) {
                  switch (action) {
                    case _SlotAction.replace:
                      _replaceExercise();
                    case _SlotAction.moveUp:
                      widget.onMoveUp?.call();
                    case _SlotAction.moveDown:
                      widget.onMoveDown?.call();
                    case _SlotAction.remove:
                      widget.onRemove();
                  }
                },
                itemBuilder: (context) {
                  final showMove =
                      widget.onMoveUp != null || widget.onMoveDown != null;
                  return [
                    _slotMenuItem(
                      _SlotAction.replace,
                      TreinoIcon.edit,
                      l10n.routineEditorSlotMenuReplace,
                      palette,
                    ),
                    if (showMove)
                      _slotMenuItem(
                        _SlotAction.moveUp,
                        TreinoIcon.chevronUp,
                        l10n.routineEditorSlotMenuMoveUp,
                        palette,
                        enabled: widget.canMoveUp,
                      ),
                    if (showMove)
                      _slotMenuItem(
                        _SlotAction.moveDown,
                        TreinoIcon.chevronDown,
                        l10n.routineEditorSlotMenuMoveDown,
                        palette,
                        enabled: widget.canMoveDown,
                      ),
                    _slotMenuItem(
                      _SlotAction.remove,
                      TreinoIcon.trash,
                      l10n.routineEditorSlotMenuRemove,
                      palette,
                      danger: true,
                    ),
                  ];
                },
              ),
            ],
          ),
          const SizedBox(height: 10),

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
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              key: const Key('add_set_button'),
              onPressed: () {
                setState(() {
                  final template =
                      sets.isNotEmpty ? sets.last.clone() : _EditableSet();
                  sets.add(template);
                });
                widget.onChanged();
              },
              icon: Icon(TreinoIcon.plus, size: 14, color: palette.accent),
              label: Text(
                l10n.routineEditorAddSet,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: palette.accent,
                ),
              ),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slot overflow menu (⋮) ────────────────────────────────────────────────────

/// Actions surfaced from a slot's ⋮ overflow menu.
enum _SlotAction { replace, moveUp, moveDown, remove }

/// Builds one styled item for the slot ⋮ menu, matching treino's dark palette.
/// [enabled] dims the row (used for edge reorder); [danger] tints it red.
PopupMenuItem<_SlotAction> _slotMenuItem(
  _SlotAction value,
  IconData icon,
  String label,
  AppPalette palette, {
  bool enabled = true,
  bool danger = false,
}) {
  final color = !enabled
      ? palette.border
      : danger
          ? palette.danger
          : palette.textPrimary;
  return PopupMenuItem<_SlotAction>(
    value: value,
    enabled: enabled,
    height: 44,
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            label,
            style: GoogleFonts.barlow(fontSize: 14, color: color),
          ),
        ),
      ],
    ),
  );
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
  });

  final _EditableSlot slot;
  final AppPalette palette;
  final Future<void> Function(BuildContext, Offset) onPickMeasureMode;

  @override
  Widget build(BuildContext context) {
    final isDuration = slot.exerciseMode == ExerciseMode.duration;

    TextStyle headerStyle() => GoogleFonts.barlowCondensed(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: palette.textMuted,
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

    return Row(
      children: [
        // SET column (fixed narrow width)
        SizedBox(
          width: 44,
          child: Center(
            child: Text('SET', style: headerStyle()),
          ),
        ),
        const SizedBox(width: 6),
        if (isDuration) ...[
          cell('TIEMPO', tappable: true),
        ] else ...[
          cell('KG'),
          const SizedBox(width: 6),
          if (slot.repMode == RepMode.range) ...[
            cell('MÍN', tappable: true),
            const SizedBox(width: 6),
            cell('MÁX', tappable: true),
          ] else ...[
            cell('REPS', tappable: true),
          ],
        ],
        // Delete icon placeholder (same width as delete button)
        const SizedBox(width: 40),
      ],
    );
  }
}

// ── Set row ───────────────────────────────────────────────────────────────────

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

  @override
  State<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<_SetRow> {
  late final TextEditingController _kgCtrl;
  late final TextEditingController _repsCtrl;
  late final TextEditingController _repsMinCtrl;
  late final TextEditingController _repsMaxCtrl;

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
  }

  @override
  void dispose() {
    _kgCtrl.dispose();
    _repsCtrl.dispose();
    _repsMinCtrl.dispose();
    _repsMaxCtrl.dispose();
    super.dispose();
  }

  /// Seeds the KG controller without losing fractional loads: integers show
  /// without a decimal (60), fractional values keep theirs (17.5).
  static String _formatWeight(double? w) => formatEditorWeight(w);

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
    final label = setChipLabel(widget.allSets, widget.index);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Set chip — 44×44 tap target ───────────────────────────────────
        Builder(
          builder: (ctx) => GestureDetector(
            onTap: () => _pickSetType(ctx),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _chipColor(s.type, palette),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                style: GoogleFonts.barlowCondensed(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _chipTextColor(s.type, palette),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // ── Input cells ───────────────────────────────────────────────────
        if (widget.isDuration) ...[
          Expanded(
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
            child: _NumberField(
              controller: _kgCtrl,
              palette: palette,
              hint: 'kg',
              decimal: true,
              onDecimalChanged: (v) {
                s.weightKg = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          if (widget.repMode == RepMode.range) ...[
            // REP MIN
            Expanded(
              child: _NumberField(
                controller: _repsMinCtrl,
                palette: palette,
                hint: 'mín',
                hasError: widget.isInvalid,
                onChanged: (v) {
                  s.repsMin = v;
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 8),
            // REP MAX
            Expanded(
              child: _NumberField(
                controller: _repsMaxCtrl,
                palette: palette,
                hint: 'máx',
                hasError: widget.isInvalid,
                onChanged: (v) {
                  s.repsMax = v;
                  widget.onChanged();
                },
              ),
            ),
          ] else ...[
            // REPS
            Expanded(
              child: _NumberField(
                controller: _repsCtrl,
                palette: palette,
                hint: 'reps',
                hasError: widget.isInvalid,
                onChanged: (v) {
                  s.reps = v;
                  widget.onChanged();
                },
              ),
            ),
          ],
        ],
        // ── Delete button — 40px wide tap target ──────────────────────────
        SizedBox(
          width: 40,
          child: widget.onRemove != null
              ? IconButton(
                  icon: Icon(TreinoIcon.close,
                      size: 16, color: palette.textMuted),
                  onPressed: widget.onRemove,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 44),
                  padding: EdgeInsets.zero,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Color _chipColor(SetType type, AppPalette palette) {
    return switch (type) {
      SetType.warmup => palette.accent.withAlpha(30),
      SetType.drop => palette.highlight.withAlpha(30),
      SetType.failure => Colors.red.withAlpha(30),
      SetType.normal => palette.bgCard,
    };
  }

  Color _chipTextColor(SetType type, AppPalette palette) {
    return switch (type) {
      SetType.warmup => palette.accent,
      SetType.drop => palette.highlight,
      SetType.failure => Colors.red,
      SetType.normal => palette.textMuted,
    };
  }
}

// ── Number input field ────────────────────────────────────────────────────────

/// Compact numeric text field without a label (used inside set rows).
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.palette,
    this.onChanged,
    this.onDecimalChanged,
    this.decimal = false,
    this.hint,
    this.hasError = false,
  }) : assert(
          decimal ? onDecimalChanged != null : onChanged != null,
          'decimal fields need onDecimalChanged; integer fields need onChanged',
        );

  final TextEditingController controller;
  final AppPalette palette;
  final String? hint;

  /// Integer callback used when [decimal] is false (reps, etc.).
  final void Function(int?)? onChanged;

  /// Double callback used when [decimal] is true (weight in kg).
  final void Function(double?)? onDecimalChanged;

  /// When true the field accepts fractional values (e.g. 17.5 kg).
  final bool decimal;

  /// When true the field underline turns danger-red to signal the value
  /// is missing or invalid.
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final errorBorder = UnderlineInputBorder(
      borderSide: BorderSide(color: palette.danger, width: 1.5),
    );
    return TextField(
      controller: controller,
      keyboardType: decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      style: GoogleFonts.barlow(fontSize: 16, color: palette.textPrimary),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: GoogleFonts.barlow(
          fontSize: 13,
          color: hasError ? palette.danger.withAlpha(180) : palette.textMuted,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        filled: false,
        border: hasError
            ? errorBorder
            : UnderlineInputBorder(
                borderSide: BorderSide(color: palette.border),
              ),
        enabledBorder: hasError
            ? errorBorder
            : UnderlineInputBorder(
                borderSide: BorderSide(color: palette.border),
              ),
        focusedBorder: hasError
            ? UnderlineInputBorder(
                borderSide: BorderSide(color: palette.danger, width: 2),
              )
            : UnderlineInputBorder(
                borderSide: BorderSide(color: palette.accent, width: 2),
              ),
      ),
      onChanged: (v) {
        if (decimal) {
          onDecimalChanged!(parseEditorWeight(v));
        } else {
          onChanged!(int.tryParse(v));
        }
      },
    );
  }
}

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
String formatEditorWeight(double? w) {
  if (w == null) return '';
  return w == w.truncateToDouble() ? w.toInt().toString() : w.toString();
}

/// Parses KG field text into a nullable double, accepting comma as the decimal
/// separator (common on iOS numeric keypads). Empty/invalid → null.
double? parseEditorWeight(String v) => double.tryParse(v.replaceAll(',', '.'));

// ── Test bridge ───────────────────────────────────────────────────────────────
// Exposes internal helpers for unit tests without making the private types
// themselves public. Only used via test imports; Flutter tree-shakes it in
// release builds since nothing in the widget tree references it.

/// Static bridge that lets test files exercise [setChipLabel], [isSetValid],
/// and [buildRoutineSlot] by constructing [_EditableSet]/[_EditableSlot]
/// instances internally and returning plain Dart values.
class RoutineEditorTestBridge {
  RoutineEditorTestBridge._();

  /// Delegates to [isSetValid] after constructing a minimal [_EditableSet].
  static bool isSetValidBridge({
    required ExerciseMode exerciseMode,
    required RepMode repMode,
    SetType type = SetType.normal,
    int? reps,
    int? repsMin,
    int? repsMax,
    int? durationSeconds,
  }) {
    final s = _EditableSet(
      type: type,
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
      ];
    return buildRoutineSlot(slot, null);
  }

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
