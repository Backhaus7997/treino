import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../coach/presentation/coach_strings.dart';
import '../../coach/presentation/widgets/exercise_picker_sheet.dart';
import '../../profile/domain/experience_level.dart';
import '../application/routine_providers.dart' show routineRepositoryProvider;
import '../application/session_providers.dart' show currentUidProvider;
import '../application/user_routines_providers.dart'
    show userCreatedRoutinesProvider;
import '../domain/exercise.dart';
import '../domain/reps_format.dart';
import '../domain/routine.dart';
import '../domain/routine_day.dart';
import '../domain/routine_slot.dart';
import '../domain/routine_source.dart';
import '../domain/routine_visibility.dart';
import 'routine_editor_mode.dart';
import 'widgets/duration_text_field.dart';
import 'workout_strings.dart';

// ── Mutable local state classes ───────────────────────────────────────────────

class _EditableSlot {
  Exercise? exercise;
  int targetSets = 3;
  int targetRepsMin = 8;
  int targetRepsMax = 12;
  int restSeconds = 60;
  int? supersetGroup;
  List<int> targetReps = [];
  int? durationSeconds;

  _EditableSlot();
}

class _EditableDay {
  int dayNumber;
  String name;
  List<_EditableSlot> slots = [];

  _EditableDay({required this.dayNumber, required this.name});
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// Full-screen plan builder parametrized by [RoutineEditorMode].
///
/// Lives inside the ShellRoute — NO own Scaffold (bottom bar provided by
/// shell). Uses local StatefulWidget state for the mutable form.
///
/// Modes (ADR-USR-01):
///   * [TrainerAssigning] — trainer creates a plan for a specific athlete.
///     Submits via [RoutineRepository.createAssigned].
///   * [SelfCreating] — athlete self-authors a personal routine.
///     Submits via [RoutineRepository.createUserOwned].
///     With a non-null existingRoutineId → stub toast (full edit deferred).
///
/// REQ-COACH-PLANS-023..028 · REQ-USR-011 · SCENARIO-457..463, 616..619.
class RoutineEditorScreen extends StatefulWidget {
  const RoutineEditorScreen({super.key, required this.mode});

  final RoutineEditorMode mode;

  @override
  State<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

String _titleFor(RoutineEditorMode mode) => switch (mode) {
      TrainerAssigning() => CoachStrings.editorTitle,
      TrainerTemplating() => CoachStrings.editorTitle,
      SelfCreating() => WorkoutStrings.selfEditorTitle,
    };

String _submitLabelFor(RoutineEditorMode mode) => switch (mode) {
      TrainerAssigning() => CoachStrings.editorSubmit,
      TrainerTemplating() => CoachStrings.editorSubmit,
      SelfCreating() => WorkoutStrings.selfEditorSubmitLabel,
    };

class _RoutineEditorScreenState extends State<RoutineEditorScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _splitController = TextEditingController();
  ExperienceLevel _level = ExperienceLevel.beginner;
  List<_EditableDay> _days = [_EditableDay(dayNumber: 1, name: 'Día 1')];
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _splitController.dispose();
    super.dispose();
  }

  /// Whether the editor is in a trainer-creating mode (assigning or
  /// templating). Athlete (SelfCreating) mode hides trainer-only fields.
  /// REQ-RER-012, REQ-RER-013, ADR-RER-04.
  bool get _isTrainerMode =>
      widget.mode is TrainerAssigning || widget.mode is TrainerTemplating;

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
        if (slot.targetSets < 1) return false;
        // A slot is valid when it has reps OR a duration > 0.
        final hasReps =
            slot.targetReps.isNotEmpty && slot.targetReps.every((r) => r > 0);
        final hasDuration =
            slot.durationSeconds != null && slot.durationSeconds! > 0;
        if (!hasReps && !hasDuration) return false;
      }
    }
    return true;
  }

  void _addDay() {
    setState(() {
      final n = _days.length + 1;
      _days = [..._days, _EditableDay(dayNumber: n, name: 'Día $n')];
    });
  }

  void _removeDay(int index) {
    setState(() {
      _days = [
        for (int i = 0; i < _days.length; i++)
          if (i != index) _days[i],
      ];
      // Re-number
      for (int i = 0; i < _days.length; i++) {
        _days[i].dayNumber = i + 1;
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

  /// Replaces a day's slot order after a block-level reorder in the tile.
  void _reorderSlots(int dayIndex, List<_EditableSlot> newOrder) {
    setState(() {
      _days[dayIndex].slots = newOrder;
    });
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
    setState(() {
      // Only add exercises not already in this day (one instance per day) —
      // avoids the duplicate-on-reopen issue.
      for (final ex in picked.where((e) => !existingIds.contains(e.id))) {
        final slot = _EditableSlot()
          ..exercise = ex
          ..restSeconds = ex.defaultRestSeconds ?? 60;
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
            ..restSeconds = ex.defaultRestSeconds ?? 60
            ..supersetGroup = nextGroup)
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
    setState(() {
      final newOnes = picked.where((e) => !existingIds.contains(e.id)).toList();
      if (newOnes.isEmpty) return;
      final newSlots = newOnes
          .map((ex) => _EditableSlot()
            ..exercise = ex
            ..restSeconds = ex.defaultRestSeconds ?? 60
            ..supersetGroup = groupId)
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

  Future<void> _submit(WidgetRef ref) async {
    if (!_isValid || _submitting) return;

    // SelfCreating with existingRoutineId → stub toast; no network call.
    if (widget.mode case SelfCreating(existingRoutineId: final id?)
        when id.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(WorkoutStrings.editStubToast)),
      );
      return;
    }

    setState(() => _submitting = true);
    final uid = ref.read(currentUidProvider) ?? '';

    final days = _days.map((d) {
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
          return RoutineSlot(
            exerciseId: s.exercise!.id,
            exerciseName: s.exercise!.name,
            muscleGroup: s.exercise!.muscleGroup,
            targetSets: s.targetSets,
            // Legacy fields kept populated so older readers don't break.
            targetRepsMin: s.targetReps.isNotEmpty ? s.targetReps.first : 0,
            targetRepsMax: s.targetReps.isNotEmpty ? s.targetReps.last : 0,
            restSeconds: s.restSeconds,
            supersetGroup: effectiveGroup,
            targetReps: s.targetReps,
            durationSeconds: s.durationSeconds,
          );
        }).toList(),
      );
    }).toList();

    try {
      final repo = ref.read(routineRepositoryProvider);

      switch (widget.mode) {
        case TrainerAssigning(:final athleteId):
          // Preserve existing trainer-assigned flow — unchanged behaviour.
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
          );
          final created = await repo.createAssigned(routine);
          ref.read(analyticsServiceProvider).logPlanAssigned(
                routineId: created.id,
                assignedBy: uid,
                assignedTo: athleteId,
              );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(CoachStrings.createPlanSuccess)),
          );
          context.pop();

        case TrainerTemplating():
          // Pre-existing trainer template flow — reusable plantilla, no
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
          );
          await repo.createTemplate(routine);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(CoachStrings.createPlanSuccess)),
          );
          context.pop();

        case SelfCreating(existingRoutineId: null):
          // Client-side cap check (ADR-USR-02).
          final userRoutines =
              ref.read(userCreatedRoutinesProvider(uid)).valueOrNull ?? [];
          if (userRoutines.length >= 10) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(WorkoutStrings.selfEditorCapReached)),
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
          );
          await repo.createUserOwned(uid: uid, draft: draft);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(WorkoutStrings.selfEditorSuccess)),
          );
          context.pop();

        case SelfCreating(existingRoutineId: _):
          // Non-null existingRoutineId handled above via early return.
          // This branch is unreachable in practice but exhausts the switch.
          break;
      }
    } catch (e) {
      if (!mounted) return;
      final errorText = switch (widget.mode) {
        TrainerAssigning() => CoachStrings.createPlanError,
        TrainerTemplating() => CoachStrings.createPlanError,
        SelfCreating() => e.toString().contains('permission-denied')
            ? WorkoutStrings.selfEditorPermissionDenied
            : WorkoutStrings.selfEditorError,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorText)),
      );
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final palette = AppPalette.of(context);

        return Column(
          children: [
            // ── Custom header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(TreinoIcon.back, color: palette.textPrimary),
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/coach'),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _titleFor(widget.mode),
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ───────────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                children: [
                  // ── Name + (Split when trainer mode) ─────────────────────
                  // T-RER-030: athlete (SelfCreating) form shows only Name +
                  // Days-of-plan. Trainer modes show all fields.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionLabel(
                              label: CoachStrings.editorNameLabel,
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
                                    : WorkoutStrings.selfEditorNameHint,
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
                                label: CoachStrings.editorSplitLabel,
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

                  // ── Row: Days/week + Level — trainer modes only ──────────
                  if (_isTrainerMode) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel(label: 'NIVEL', palette: palette),
                              const SizedBox(height: 4),
                              _LevelDropdown(
                                value: _level,
                                palette: palette,
                                onChanged: (v) {
                                  if (v != null) setState(() => _level = v);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),

                  // ── Días del plan ─────────────────────────────────────────
                  _SectionLabel(label: 'DÍAS DEL PLAN', palette: palette),
                  const SizedBox(height: 6),

                  for (int di = 0; di < _days.length; di++) ...[
                    _DayExpansionTile(
                      day: _days[di],
                      palette: palette,
                      onAddSlot: () => _pickExercisesForDay(context, di),
                      onRemoveSlot: (si) => _removeSlot(di, si),
                      onReorderSlots: (newOrder) => _reorderSlots(di, newOrder),
                      onRemoveDay:
                          _days.length > 1 ? () => _removeDay(di) : null,
                      onSlotChanged: () => setState(() {}),
                      onAddToGroup: (g) => _addExerciseToGroup(context, di, g),
                      // Supersets available in every mode, including the
                      // athlete's SelfCreating editor (same builder as trainers).
                      allowSuperset: true,
                      onAddSuperset: () => _addSupersetForDay(context, di),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // Add day button
                  TextButton.icon(
                    onPressed: _addDay,
                    icon:
                        Icon(TreinoIcon.plus, size: 14, color: palette.accent),
                    label: Text(
                      CoachStrings.editorAddDay,
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: palette.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),

            // ── Submit button — pinned outside ListView ────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      (_isValid && !_submitting) ? () => _submit(ref) : null,
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
                          _submitLabelFor(widget.mode),
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
        );
      },
    );
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

// ── Day expansion tile ────────────────────────────────────────────────────────

class _DayExpansionTile extends StatefulWidget {
  const _DayExpansionTile({
    required this.day,
    required this.palette,
    required this.onAddSlot,
    required this.onRemoveSlot,
    required this.onReorderSlots,
    required this.onRemoveDay,
    required this.onSlotChanged,
    required this.onAddToGroup,
    this.allowSuperset = false,
    this.onAddSuperset,
  });

  final _EditableDay day;
  final AppPalette palette;
  final VoidCallback onAddSlot;
  final void Function(int slotIndex) onRemoveSlot;
  final void Function(List<_EditableSlot> newOrder) onReorderSlots;
  final VoidCallback? onRemoveDay;
  final VoidCallback onSlotChanged;
  final bool allowSuperset;
  final VoidCallback? onAddSuperset;
  final void Function(int groupId) onAddToGroup;

  @override
  State<_DayExpansionTile> createState() => _DayExpansionTileState();
}

class _DayExpansionTileState extends State<_DayExpansionTile> {
  bool _expanded = true;

  /// Walks the slot list and emits either a standalone [_SlotEditor] or a
  /// "SUPERSERIE" wrapper card for consecutive slots sharing a non-null group.
  List<Widget> _buildSlotRows(AppPalette palette) {
    final blocks = _blocks();
    final rows = <Widget>[];
    // Running absolute index into the flat slot list — onRemove still expects
    // the slot's flat position, not the block index.
    var flatStart = 0;
    for (var b = 0; b < blocks.length; b++) {
      final block = blocks[b];
      final canUp = b > 0;
      final canDown = b < blocks.length - 1;
      if (block.length == 1 && block.first.supersetGroup == null) {
        // Standalone slot. ObjectKey keeps each row's State bound to its slot
        // so the int fields don't show stale values after the list shifts.
        final idx = flatStart;
        final slot = block.first;
        rows.add(_SlotEditor(
          key: ObjectKey(slot),
          slot: slot,
          palette: palette,
          onRemove: () => widget.onRemoveSlot(idx),
          onChanged: widget.onSlotChanged,
          canMoveUp: canUp,
          canMoveDown: canDown,
          onMoveUp: () => _moveBlock(b, -1),
          onMoveDown: () => _moveBlock(b, 1),
        ));
      } else {
        // Superset block — the whole block moves as one unit.
        final groupSlots = <({int index, _EditableSlot slot})>[
          for (var k = 0; k < block.length; k++)
            (index: flatStart + k, slot: block[k]),
        ];
        rows.add(_SupersetGroupCard(
          groupSlots: groupSlots,
          palette: palette,
          onRemoveSlot: widget.onRemoveSlot,
          onChanged: widget.onSlotChanged,
          onAddExercise: () => widget.onAddToGroup(block.first.supersetGroup!),
          canMoveUp: canUp,
          canMoveDown: canDown,
          onMoveUp: () => _moveBlock(b, -1),
          onMoveDown: () => _moveBlock(b, 1),
        ));
      }
      rows.add(const SizedBox(height: 8));
      flatStart += block.length;
    }
    return rows;
  }

  /// Groups the flat slot list into ordered blocks: a standalone slot is its
  /// own block; consecutive slots sharing a non-null supersetGroup form one.
  List<List<_EditableSlot>> _blocks() {
    final slots = widget.day.slots;
    final blocks = <List<_EditableSlot>>[];
    var i = 0;
    while (i < slots.length) {
      final group = slots[i].supersetGroup;
      if (group != null) {
        final run = <_EditableSlot>[];
        while (i < slots.length && slots[i].supersetGroup == group) {
          run.add(slots[i]);
          i++;
        }
        blocks.add(run);
      } else {
        blocks.add([slots[i]]);
        i++;
      }
    }
    return blocks;
  }

  /// Swaps block [blockIndex] with its neighbour in [dir] (-1 up / +1 down) and
  /// flattens back to a slot list. No-op at the edges. A whole superset moves
  /// as a single unit, so a reorder never splits a block.
  void _moveBlock(int blockIndex, int dir) {
    final blocks = _blocks();
    final target = blockIndex + dir;
    if (target < 0 || target >= blocks.length) return;
    final moved = blocks.removeAt(blockIndex);
    blocks.insert(target, moved);
    widget.onReorderSlots([for (final b in blocks) ...b]);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
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
                    color: palette.textMuted,
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
                        CoachStrings.editorAddSlot,
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: palette.accent,
                        ),
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
                          CoachStrings.editorAddSuperset,
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: palette.highlight,
                          ),
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
    required this.palette,
    required this.onRemoveSlot,
    required this.onChanged,
    required this.onAddExercise,
    this.canMoveUp = false,
    this.canMoveDown = false,
    this.onMoveUp,
    this.onMoveDown,
  });

  final List<({int index, _EditableSlot slot})> groupSlots;
  final AppPalette palette;
  final void Function(int slotIndex) onRemoveSlot;
  final VoidCallback onChanged;
  final VoidCallback onAddExercise;

  /// Block-level reorder controls — the whole superset moves as one unit.
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: palette.highlight.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.highlight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(TreinoIcon.streak, size: 14, color: palette.highlight),
              const SizedBox(width: 6),
              Text(
                'SUPERSERIE',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
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
          const SizedBox(height: 8),
          // Slot editors stacked
          for (final entry in groupSlots) ...[
            _SlotEditor(
              key: ObjectKey(entry.slot),
              slot: entry.slot,
              palette: palette,
              onRemove: () => onRemoveSlot(entry.index),
              onChanged: onChanged,
            ),
            if (entry != groupSlots.last) const SizedBox(height: 6),
          ],
          const SizedBox(height: 4),
          // Add another exercise into THIS superset block.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAddExercise,
              icon: Icon(TreinoIcon.plus, size: 14, color: palette.highlight),
              label: Text(
                'Agregar ejercicio',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: palette.highlight,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
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

// ── Slot editor row ───────────────────────────────────────────────────────────

class _SlotEditor extends StatefulWidget {
  const _SlotEditor({
    super.key,
    required this.slot,
    required this.palette,
    required this.onRemove,
    required this.onChanged,
    this.canMoveUp = false,
    this.canMoveDown = false,
    this.onMoveUp,
    this.onMoveDown,
  });

  final _EditableSlot slot;
  final AppPalette palette;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  /// Reorder controls. When both callbacks are null (e.g. a slot nested inside a
  /// superset card, which moves as part of its block) no move buttons render.
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  State<_SlotEditor> createState() => _SlotEditorState();
}

class _SlotEditorState extends State<_SlotEditor> {
  late final TextEditingController _repsCtrl;

  @override
  void initState() {
    super.initState();
    _repsCtrl = TextEditingController(
      text: formatReps(widget.slot.targetReps),
    );
  }

  @override
  void dispose() {
    _repsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final palette = widget.palette;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  // Exercise cell is read-only after PR2 redesign — slots are
                  // created pre-filled via multi-select picker. To change
                  // exercise, remove the slot and add again. ADR-RER-01.
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.bgCard,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    slot.exercise?.name ?? CoachStrings.exercisePicker,
                    style: GoogleFonts.barlow(
                      fontSize: 13,
                      color: slot.exercise != null
                          ? palette.textPrimary
                          : palette.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (widget.onMoveUp != null || widget.onMoveDown != null)
                _MoveButtons(
                  palette: palette,
                  canMoveUp: widget.canMoveUp,
                  canMoveDown: widget.canMoveDown,
                  onMoveUp: widget.onMoveUp,
                  onMoveDown: widget.onMoveDown,
                ),
              const SizedBox(width: 6),
              IconButton(
                icon:
                    Icon(TreinoIcon.trash, size: 16, color: palette.textMuted),
                onPressed: widget.onRemove,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── [Series] [Reps] [Min] [Descanso] ──────────────────────────────
          Row(
            children: [
              _SmallIntField(
                label: 'Series',
                value: slot.targetSets,
                palette: palette,
                onChanged: (v) {
                  slot.targetSets = v;
                  widget.onChanged();
                },
              ),
              const SizedBox(width: 6),
              // Reps — free-text: "10" or "6-8-10"
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reps',
                      style: GoogleFonts.barlow(
                          fontSize: 10, color: palette.textMuted),
                    ),
                    const SizedBox(height: 2),
                    TextField(
                      controller: _repsCtrl,
                      keyboardType: TextInputType.text,
                      style: GoogleFonts.barlow(
                          fontSize: 13, color: palette.textPrimary),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '10 o 6-8-10',
                        hintStyle: GoogleFonts.barlow(
                            fontSize: 11, color: palette.textMuted),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        filled: true,
                        fillColor: palette.bgCard,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: palette.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: palette.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: palette.accent),
                        ),
                      ),
                      onChanged: (v) {
                        slot.targetReps = parseReps(v);
                        widget.onChanged();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              DurationTextField(
                label: 'Min',
                valueSeconds: slot.durationSeconds ?? 0,
                onChanged: (v) {
                  slot.durationSeconds = v > 0 ? v : null;
                  widget.onChanged();
                },
              ),
              const SizedBox(width: 6),
              DurationTextField(
                label: 'Descanso',
                valueSeconds: slot.restSeconds,
                onChanged: (v) {
                  slot.restSeconds = v;
                  widget.onChanged();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallIntField extends StatefulWidget {
  const _SmallIntField({
    required this.label,
    required this.value,
    required this.palette,
    required this.onChanged,
  });

  final String label;
  final int value;
  final AppPalette palette;
  final void Function(int) onChanged;

  @override
  State<_SmallIntField> createState() => _SmallIntFieldState();
}

class _SmallIntFieldState extends State<_SmallIntField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toString());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: GoogleFonts.barlow(fontSize: 10, color: palette.textMuted),
          ),
          const SizedBox(height: 2),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            style: GoogleFonts.barlow(fontSize: 13, color: palette.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              filled: true,
              fillColor: palette.bgCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: palette.accent),
              ),
            ),
            onChanged: (v) {
              final parsed = int.tryParse(v);
              if (parsed != null) widget.onChanged(parsed);
            },
          ),
        ],
      ),
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
