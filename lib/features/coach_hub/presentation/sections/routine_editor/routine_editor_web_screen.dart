// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../profile/application/user_public_profile_providers.dart';
import '../../../../profile/domain/experience_level.dart';
import '../../../../workout/application/assigned_routine_providers.dart';
import '../../../../workout/application/routine_providers.dart'
    show routineRepositoryProvider;
import '../../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../../../workout/domain/exercise.dart';
import '../../../../workout/domain/routine.dart';
import '../../../../workout/domain/routine_day.dart';
import '../../../../workout/domain/routine_slot.dart';
import '../../../../workout/domain/routine_source.dart';
import '../../../../workout/domain/routine_visibility.dart';
import '../../../../workout/domain/set_enums.dart';
import '../../../../workout/domain/set_spec.dart';
import '../../widgets/exercise_picker_dialog.dart';

/// Editor de rutinas web — crea o edita la rutina de UN alumno (mirrors
/// mobile's `RoutineEditorScreen(TrainerAssigning)`). Soporta, por ejercicio:
/// reps fijas o rango (mín–máx), duración (por tiempo), peso, descanso, notas
/// para el alumno, supersets, N semanas con prescripción propia por semana
/// (`weeklySets`, Fase 4b, selector "Sem 1..N") y máscara de presencia por
/// semana (`activeWeeks`, Fase 4c, chips "Semanas:").
///
/// **Fidelidad total del modelo, NO paridad total de features**: el form
/// modela el 100% del esquema de [RoutineSlot], así que hidrata y reescribe
/// cualquier rutina sin perder un solo campo. Pero todavía NO sabe CREAR
/// algunas cosas que mobile sí: series tipadas (warm-up/drop/al-fallo — las
/// respeta y las round-trippea, pero no hay UI para asignarlas), plantillas
/// reusables y ejercicios custom nuevos. Fidelidad ≠ paridad.
///
/// **Modo edición** (`routineId != null`): carga la rutina y la abre en el
/// form. `updateAssigned` pisa el array `days` entero en cada guardado, pero
/// como el form modela el 100% del esquema, ninguna rutina asignada —sea cual
/// sea su origen (mobile o web)— pierde información al re-guardarse.
class RoutineEditorWebScreen extends ConsumerStatefulWidget {
  const RoutineEditorWebScreen({
    super.key,
    required this.athleteId,
    this.routineId,
  });

  final String athleteId;

  /// When non-null, the editor loads this existing routine and saves via
  /// `updateAssigned` instead of `createAssigned`.
  final String? routineId;

  @override
  ConsumerState<RoutineEditorWebScreen> createState() =>
      _RoutineEditorWebScreenState();
}

// ── Mutable editor state (web MVP) ────────────────────────────────────────────

class _EditorSet {
  /// Warm-up / normal / drop / failure. The web editor has no UI to CHANGE
  /// this yet, but it must round-trip: plans authored in the mobile app carry
  /// typed sets, and silently rewriting them to [SetType.normal] on save would
  /// destroy the trainer's prescription without asking.
  SetType type = SetType.normal;
  double? weightKg;
  int? reps; // used when repMode == single
  int? repsMin; // used when repMode == range
  int? repsMax; // used when repMode == range
  int? durationSeconds; // used when exerciseMode == duration

  /// Deep copy — used when padding a slot's `weeklySets` to a new week count
  /// ([_RoutineEditorWebScreenState._normalizeSlotWeeks]). Preserves [type],
  /// like mobile's `_EditableSet.copy()`: replicating a week must replicate
  /// its warm-ups and failure sets too.
  _EditorSet copy() => _EditorSet()
    ..type = type
    ..weightKg = weightKg
    ..reps = reps
    ..repsMin = repsMin
    ..repsMax = repsMax
    ..durationSeconds = durationSeconds;
}

/// Maps a persisted [SetSpec] into its mutable editor row.
_EditorSet _editorSetFromSpec(SetSpec spec) => _EditorSet()
  ..type = spec.type
  ..reps = spec.reps
  ..repsMin = spec.repsMin
  ..repsMax = spec.repsMax
  ..durationSeconds = spec.durationSeconds
  ..weightKg = spec.weightKg;

class _EditorSlot {
  Exercise? exercise;
  int restSeconds = 0;
  ExerciseMode exerciseMode = ExerciseMode.reps;
  RepMode repMode = RepMode.single;
  String notes = '';
  // True when this exercise is supersetted with the NEXT one in the day. A run
  // of linked slots becomes one superset group (id derived at build time).
  bool linkedToNext = false;

  /// One inner list of sets per plan week — outer index is the 0-based week.
  /// Invariant: every slot keeps exactly `_numWeeks` inner lists; week-count
  /// changes normalize all slots together via `_normalizeSlotWeeks`.
  /// Mirrors mobile's `_EditableSlot.weeklySets` (Fase 4b).
  List<List<_EditorSet>> weeklySets = [
    [_EditorSet()],
  ];

  /// 0-based weeks in which this slot is present. Empty = present in ALL
  /// weeks (back-compat default — legacy/single-week docs have no mask).
  /// Mirrors mobile's `_EditableSlot.activeWeeks` (Fase 4c).
  Set<int> activeWeeks = <int>{};

  /// Whether this slot is present in 0-based [w].
  /// Rule: `activeWeeks.isEmpty || activeWeeks.contains(w)`.
  bool isPresentInWeek(int w) => activeWeeks.isEmpty || activeWeeks.contains(w);
}

class _EditorDay {
  _EditorDay({required this.dayNumber, required this.name});
  int dayNumber;
  String name;
  List<_EditorSlot> slots = [];
}

const _kMaxDays = 7; // mirrors mobile's _kMaxDays
const _kMaxWeeks = 16; // mirrors mobile's _kMaxWeeks

class _RoutineEditorWebScreenState
    extends ConsumerState<RoutineEditorWebScreen> {
  final _nameCtrl = TextEditingController();
  final _splitCtrl = TextEditingController();
  ExperienceLevel _level = ExperienceLevel.beginner;
  int _numWeeks = 1;

  /// 0-based week shown in the editor — drives which inner list of each
  /// slot's `weeklySets` the day/slot cards render and edit (Fase 4b).
  /// Display is 1-based ("Sem 1"). Always kept in `[0, _numWeeks - 1]`.
  int _selectedWeek = 0;
  final List<_EditorDay> _days = [
    _EditorDay(dayNumber: 1, name: 'Día 1')
  ]; // i18n
  bool _submitting = false;
  bool _isDirty = false;
  String? _errorMessage;

  // ── Edit mode ─────────────────────────────────────────────────────────────
  bool get _isEditing => widget.routineId != null;

  /// The routine being edited (its identity fields are preserved on save).
  Routine? _loadedRoutine;

  /// True while the existing routine is being fetched (edit mode only).
  bool _loading = false;

  /// Non-null when the form can't be shown: routine not found, or it failed
  /// to load.
  String? _fatalMessage;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final routine =
          await ref.read(routineRepositoryProvider).getById(widget.routineId!);
      if (!mounted) return;
      if (routine == null) {
        setState(() {
          _loading = false;
          _fatalMessage = 'No encontramos la rutina.'; // i18n
        });
        return;
      }
      setState(() {
        _loadedRoutine = routine;
        _populate(routine);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fatalMessage = 'No pudimos cargar la rutina. Probá de nuevo.'; // i18n
      });
    }
  }

  /// Fills the form from an existing (web-editable) routine.
  void _populate(Routine routine) {
    _nameCtrl.text = routine.name;
    _splitCtrl.text = routine.split ?? '';
    _level = routine.level;
    _numWeeks = routine.numWeeks.clamp(1, _kMaxWeeks);
    _days
      ..clear()
      ..addAll(routine.days.map(_editorDayFrom));
    if (_days.isEmpty) {
      _days.add(_EditorDay(dayNumber: 1, name: 'Día 1')); // i18n
    }
  }

  _EditorDay _editorDayFrom(RoutineDay day) {
    final editorSlots = day.slots.map(_editorSlotFrom).toList();
    // Reconstruct linkedToNext: slot i is supersetted with i+1 when they share
    // a non-null supersetGroup (supersets are consecutive runs by construction).
    for (var i = 0; i < day.slots.length - 1; i++) {
      final g = day.slots[i].supersetGroup;
      editorSlots[i].linkedToNext =
          g != null && g == day.slots[i + 1].supersetGroup;
    }
    return _EditorDay(dayNumber: day.dayNumber, name: day.name)
      ..slots = editorSlots;
  }

  _EditorSlot _editorSlotFrom(RoutineSlot slot) {
    // Periodized docs hydrate every week from weeklySets; legacy/single-week
    // docs hydrate week 0 from effectiveSets (mirrors mobile's hydration in
    // _loadExistingRoutine, REQ-PERIOD-018/019).
    final weeklySets = slot.weeklySets.isNotEmpty
        ? slot.weeklySets
            .map((wk) => wk.map(_editorSetFromSpec).toList())
            .toList()
        : [slot.effectiveSets.map(_editorSetFromSpec).toList()];

    // Derive the mode from WEEK 0's set data — robust against stale
    // exerciseMode/repMode fields (mirrors mobile's _repModeFromHydratedSets),
    // applied to week 0 only since mode is per-slot, not per-week.
    final week0 = weeklySets.first;
    final isDuration = week0.any((s) => (s.durationSeconds ?? 0) > 0);
    final isRange =
        !isDuration && week0.any((s) => s.repsMin != null || s.repsMax != null);

    final editorSlot = _EditorSlot()
      // Synthesize a minimal Exercise from the slot's denormalized fields —
      // _buildSlot only reads id/name/muscleGroup, so category is a filler.
      ..exercise = Exercise(
        id: slot.exerciseId,
        name: slot.exerciseName,
        muscleGroup: slot.muscleGroup,
        category: '',
      )
      ..restSeconds = slot.restSeconds
      ..exerciseMode = isDuration ? ExerciseMode.duration : ExerciseMode.reps
      ..repMode = isRange ? RepMode.range : RepMode.single
      ..notes = slot.notes ?? ''
      ..weeklySets = weeklySets
      // Hydrate presence mask from the domain slot (Fase 4c). Legacy docs
      // have empty activeWeeks → empty set → all weeks.
      ..activeWeeks = slot.activeWeeks.toSet();
    // Pad/truncate to _numWeeks (already set by _populate before this runs)
    // and guard against an authored-empty week 0 (deload) leaving a blank
    // editor slot with 0 sets.
    _normalizeSlotWeeks(editorSlot);
    return editorSlot;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _splitCtrl.dispose();
    super.dispose();
  }

  // Deliberately no setState here (mirrors mobile's own _markDirty): callers
  // already rebuild via their own setState or a TextField's onChanged.
  void _markDirty() => _isDirty = true;

  // ── Week operations (periodización, Fase 4b) ────────────────────────────

  /// Pads/truncates [slot]'s `weeklySets` to exactly `_numWeeks` inner lists.
  /// Padding appends a DEEP COPY of the last week's sets (via
  /// [_EditorSet.copy]) so a newly-added week starts from the trainer's most
  /// recent prescription instead of a blank set. Never leaves a slot with 0
  /// weeks or a week with 0 sets. Also clamps the presence mask (Fase 4c) to
  /// the valid week range, mirroring mobile's own normalize.
  void _normalizeSlotWeeks(_EditorSlot slot) {
    if (slot.weeklySets.isEmpty) {
      slot.weeklySets.add([_EditorSet()]);
    }
    while (slot.weeklySets.length < _numWeeks) {
      slot.weeklySets.add(slot.weeklySets.last.map((e) => e.copy()).toList());
    }
    if (slot.weeklySets.length > _numWeeks) {
      slot.weeklySets.removeRange(_numWeeks, slot.weeklySets.length);
    }
    for (var w = 0; w < slot.weeklySets.length; w++) {
      if (slot.weeklySets[w].isEmpty) {
        slot.weeklySets[w] = [_EditorSet()];
      }
    }
    slot.activeWeeks.removeWhere((w) => w < 0 || w >= _numWeeks);
  }

  /// Replaces the selected week's prescription with a deep copy of the
  /// PREVIOUS week's, slot by slot — mirrors mobile's `_duplicateWeek`
  /// (REQ-PERIOD-014). `_EditorSet.copy()` keeps set types, so warm-ups and
  /// failure sets survive the duplication.
  ///
  /// Presence travels with it (ADR-WPRES-06): a slot present in the source
  /// week becomes present in the target too, and one absent from the source
  /// is dropped from the target.
  ///
  /// DELIBERATE DEVIATION from mobile, in exactly one case: when the target is
  /// a slot's ONLY week, mobile removes it from the mask and leaves the mask
  /// EMPTY — which in this model reads as "present in EVERY week", so an
  /// exercise scheduled once silently spreads across the whole plan (verified
  /// against mobile's own `duplicateWeekPresence` test bridge). Since the
  /// source week doesn't have that exercise, after the copy NO week does, and
  /// a slot scheduled nowhere is a ghost — so it's dropped instead.
  Future<void> _duplicateWeek() async {
    if (_selectedWeek == 0) return;
    final sourceWeek = _selectedWeek - 1;
    final targetWeek = _selectedWeek;

    final confirmed = await _confirmDuplicateWeek(sourceWeek, targetWeek);
    if (confirmed != true || !mounted) return;

    _markDirty();
    setState(() {
      for (final day in _days) {
        for (final slot in day.slots) {
          slot.weeklySets[targetWeek] =
              slot.weeklySets[sourceWeek].map((e) => e.copy()).toList();
        }
        // Back-to-front: dropping a slot keeps the lower indices valid.
        for (var i = day.slots.length - 1; i >= 0; i--) {
          if (!_copyPresenceToTarget(day.slots[i], sourceWeek, targetWeek)) {
            _dropSlotKeepingGroups(day.slots, i);
          }
        }
      }
    });
  }

  /// Confirms the overwrite. This replaces everything already loaded in the
  /// target week, so it asks first — and names both weeks, since "duplicar"
  /// alone doesn't say which direction it goes.
  Future<bool?> _confirmDuplicateWeek(int sourceWeek, int targetWeek) {
    final palette = AppPalette.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        title: Text(
          '¿Copiar la Semana ${sourceWeek + 1} acá?', // i18n
          style: GoogleFonts.barlow(
              color: palette.textPrimary, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Se reemplaza todo lo que tengas cargado en la Semana '
          '${targetWeek + 1}.', // i18n
          style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            // Keyed: the form footer has its own "Cancelar" too.
            key: const Key('duplicate_week_cancel_button'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar', // i18n
                style: GoogleFonts.barlow(color: palette.textMuted)),
          ),
          TextButton(
            key: const Key('duplicate_week_confirm_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Copiar', // i18n
                style: GoogleFonts.barlow(
                    color: palette.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  /// Copies [slot]'s presence from [sourceWeek] onto [targetWeek]. Returns
  /// false when the slot ends up scheduled in NO week and must be dropped.
  bool _copyPresenceToTarget(_EditorSlot slot, int sourceWeek, int targetWeek) {
    // An empty mask already means "every week" — the target inherits it.
    if (slot.activeWeeks.isEmpty) return true;
    if (slot.isPresentInWeek(sourceWeek)) {
      final mask = Set<int>.from(slot.activeWeeks)..add(targetWeek);
      // Canonicalize a now-full mask back to empty, like
      // [_toggleSlotWeekPresence] does — one wire shape for "all weeks".
      slot.activeWeeks = mask.length == _numWeeks ? <int>{} : mask;
      return true;
    }
    final mask = Set<int>.from(slot.activeWeeks)..remove(targetWeek);
    if (mask.isEmpty) return false; // scheduled nowhere → see _duplicateWeek
    slot.activeWeeks = mask;
    return true;
  }

  /// Removes `slots[index]`, keeping superset grouping intact: the previous
  /// slot inherits the dropped one's [_EditorSlot.linkedToNext]. Without this,
  /// a group that ENDED at the dropped slot would silently swallow whatever
  /// came after it, since `linkedToNext` links by POSITION, not by partner id.
  void _dropSlotKeepingGroups(List<_EditorSlot> slots, int index) {
    if (index > 0) {
      slots[index - 1].linkedToNext = slots[index].linkedToNext;
    }
    slots.removeAt(index);
  }

  void _setNumWeeks(int value) {
    final clamped = value.clamp(1, _kMaxWeeks);
    if (clamped == _numWeeks) return;
    _markDirty();
    setState(() {
      _numWeeks = clamped;
      for (final day in _days) {
        for (final slot in day.slots) {
          _normalizeSlotWeeks(slot);
        }
      }
      if (_selectedWeek > _numWeeks - 1) _selectedWeek = _numWeeks - 1;
      if (_selectedWeek < 0) _selectedWeek = 0;
    });
  }

  // ── Day operations ───────────────────────────────────────────────────────

  void _addDay() {
    if (_days.length >= _kMaxDays) return;
    _markDirty();
    setState(() {
      final n = _days.length + 1;
      _days.add(_EditorDay(dayNumber: n, name: 'Día $n')); // i18n
    });
  }

  void _removeDay(int index) {
    if (_days.length <= 1) return;
    _markDirty();
    setState(() {
      _days.removeAt(index);
      // Re-number remaining days so gaps don't appear in the UI.
      for (var i = 0; i < _days.length; i++) {
        _days[i].dayNumber = i + 1;
      }
    });
  }

  void _onDayNameChanged(int index, String value) {
    _markDirty();
    setState(() => _days[index].name = value);
  }

  // ── Slot operations ──────────────────────────────────────────────────────

  Future<void> _addExercisesToDay(int dayIndex) async {
    final day = _days[dayIndex];
    final alreadyIds = day.slots
        .where((s) => s.exercise != null)
        .map((s) => s.exercise!.id)
        .toSet();
    final picked =
        await showExercisePickerDialog(context, alreadySelectedIds: alreadyIds);
    if (picked == null || picked.isEmpty || !mounted) return;
    _markDirty();
    setState(() {
      for (final exercise in picked) {
        if (day.slots.any((s) => s.exercise?.id == exercise.id)) continue;
        day.slots.add(_EditorSlot()
          ..exercise = exercise
          ..weeklySets = List.generate(_numWeeks, (_) => [_EditorSet()]));
      }
    });
  }

  void _removeSlot(int dayIndex, int slotIndex) {
    _markDirty();
    setState(() => _days[dayIndex].slots.removeAt(slotIndex));
  }

  /// Groups [slots] into blocks: a superset run, or a lone standalone slot.
  /// `linkedToNext` links by POSITION, so a block is a maximal run of slots
  /// joined by it.
  List<List<_EditorSlot>> _blocksOf(List<_EditorSlot> slots) {
    final blocks = <List<_EditorSlot>>[];
    var current = <_EditorSlot>[];
    for (var i = 0; i < slots.length; i++) {
      current.add(slots[i]);
      if (!slots[i].linkedToNext || i == slots.length - 1) {
        blocks.add(current);
        current = <_EditorSlot>[];
      }
    }
    return blocks;
  }

  /// Flattens [blocks] back into [slots] and re-derives `linkedToNext` from
  /// the block structure: every member links to the next except the last.
  ///
  /// The flags are POSITIONAL, so they must be rewritten after a reorder
  /// rather than travel with the slots — carrying them is what let a plain
  /// swap re-wire which exercises were grouped.
  void _writeBlocks(List<_EditorSlot> slots, List<List<_EditorSlot>> blocks) {
    for (final block in blocks) {
      for (var i = 0; i < block.length; i++) {
        block[i].linkedToNext = i < block.length - 1;
      }
    }
    slots
      ..clear()
      ..addAll([for (final block in blocks) ...block]);
  }

  /// Moves the slot at [slotIndex] one step in [dir] (-1 up / +1 down),
  /// keeping superset grouping intact — mirrors mobile, which splits this
  /// across `_moveSlotWithinGroup` and `_moveBlock`:
  ///
  /// - Neighbour in the SAME superset → swap the two members; the group is
  ///   untouched.
  /// - At the block's edge → move the WHOLE block past the neighbouring one,
  ///   so a reorder can never split a superset or drag an outsider into it.
  ///
  /// The old code swapped raw positions, which silently re-grouped: moving a
  /// member out of a superset left the previous slot linked to whatever
  /// landed next to it.
  void _moveSlot(int dayIndex, int slotIndex, int dir) {
    final slots = _days[dayIndex].slots;
    if (slotIndex < 0 || slotIndex >= slots.length) return;
    final slot = slots[slotIndex];
    final blocks = _blocksOf(slots);

    final blockIndex = blocks.indexWhere((b) => b.contains(slot));
    final block = blocks[blockIndex];
    final from = block.indexOf(slot);
    final within = from + dir;

    if (within >= 0 && within < block.length) {
      // Reorder inside the superset.
      block[from] = block[within];
      block[within] = slot;
    } else {
      // Edge of the block → the whole block hops its neighbour.
      final target = blockIndex + dir;
      if (target < 0 || target >= blocks.length) return;
      blocks.insert(target, blocks.removeAt(blockIndex));
    }

    _markDirty();
    setState(() => _writeBlocks(slots, blocks));
  }

  // Links / unlinks this exercise with the next one into a superset.
  void _toggleSlotLink(int dayIndex, int slotIndex) {
    _markDirty();
    setState(() {
      final slot = _days[dayIndex].slots[slotIndex];
      slot.linkedToNext = !slot.linkedToNext;
    });
  }

  /// Toggles [week]'s presence for one slot (Fase 4c, "Semanas:" chips).
  ///
  /// An EMPTY mask means "present in all weeks" — so removing a week from an
  /// all-present slot first MATERIALIZES the mask to every week index, then
  /// removes the toggled one. Conversely, once a mask ends up covering EVERY
  /// week again it collapses back to EMPTY (the canonical "all weeks" form) —
  /// this keeps `[0, 1]` on a 2-week plan indistinguishable from "no mask" on
  /// save, matching mobile's own round-trip. A removal that would empty the
  /// mask is refused outright: a slot must stay present in at least one week
  /// (`_firstValidationError`'s mask check is only a backstop for this).
  void _toggleSlotWeekPresence(int dayIndex, int slotIndex, int week) {
    final slot = _days[dayIndex].slots[slotIndex];
    final mask = slot.activeWeeks.isEmpty
        ? {for (var w = 0; w < _numWeeks; w++) w}
        : Set<int>.from(slot.activeWeeks);
    if (mask.contains(week)) {
      if (mask.length <= 1) return; // never let a removal empty the mask
      mask.remove(week);
    } else {
      mask.add(week);
    }
    // Covers every week again → canonicalize back to empty ("all weeks").
    if (mask.length == _numWeeks) {
      mask.clear();
    }
    _markDirty();
    setState(() => slot.activeWeeks = mask);
  }

  void _onRestChanged(int dayIndex, int slotIndex, String value) {
    final seconds = int.tryParse(value.trim());
    _markDirty();
    setState(() => _days[dayIndex].slots[slotIndex].restSeconds = seconds ?? 0);
  }

  // ── Set operations ───────────────────────────────────────────────────────

  void _addSet(int dayIndex, int slotIndex) {
    _markDirty();
    setState(() {
      final sets = _days[dayIndex].slots[slotIndex].weeklySets[_selectedWeek];
      // Duplicate the last row's values — same "+ Agregar set" UX as mobile.
      // `type` is deliberately NOT carried over (it stays SetType.normal),
      // matching mobile's `clone()`: adding a set after a warm-up should give
      // you a working set, not a second warm-up.
      final last = sets.isEmpty ? null : sets.last;
      sets.add(_EditorSet()
        ..reps = last?.reps
        ..repsMin = last?.repsMin
        ..repsMax = last?.repsMax
        ..durationSeconds = last?.durationSeconds
        ..weightKg = last?.weightKg);
    });
  }

  void _removeSet(int dayIndex, int slotIndex, int setIndex) {
    final sets = _days[dayIndex].slots[slotIndex].weeklySets[_selectedWeek];
    if (sets.length <= 1) return; // at least one set per exercise per week
    _markDirty();
    setState(() => sets.removeAt(setIndex));
  }

  void _onSetRepsChanged(int dayIndex, int slotIndex, int setIndex, String v) {
    _markDirty();
    setState(() => _days[dayIndex]
        .slots[slotIndex]
        .weeklySets[_selectedWeek][setIndex]
        .reps = int.tryParse(v.trim()));
  }

  void _onSetRepsMinChanged(
      int dayIndex, int slotIndex, int setIndex, String v) {
    _markDirty();
    setState(() => _days[dayIndex]
        .slots[slotIndex]
        .weeklySets[_selectedWeek][setIndex]
        .repsMin = int.tryParse(v.trim()));
  }

  void _onSetRepsMaxChanged(
      int dayIndex, int slotIndex, int setIndex, String v) {
    _markDirty();
    setState(() => _days[dayIndex]
        .slots[slotIndex]
        .weeklySets[_selectedWeek][setIndex]
        .repsMax = int.tryParse(v.trim()));
  }

  void _onSetDurationChanged(
      int dayIndex, int slotIndex, int setIndex, String v) {
    _markDirty();
    setState(() => _days[dayIndex]
        .slots[slotIndex]
        .weeklySets[_selectedWeek][setIndex]
        .durationSeconds = int.tryParse(v.trim()));
  }

  /// Switches an exercise between fixed reps, a min–max range, and duration.
  /// Reps ↔ range values carry across so the trainer doesn't retype. Mode is
  /// per-slot (not per-week, REQ-PERIOD-017/ADR-PB-03), so the carry-across
  /// runs over EVERY week's sets — not just `_selectedWeek` — otherwise a
  /// week the trainer isn't currently viewing would keep stale/incompatible
  /// values (e.g. `reps` set but no `repsMin`/`repsMax` after switching to
  /// Rango) and fail validation invisibly.
  void _setSlotMode(
    int dayIndex,
    int slotIndex,
    ExerciseMode exerciseMode,
    RepMode repMode,
  ) {
    final slot = _days[dayIndex].slots[slotIndex];
    if (slot.exerciseMode == exerciseMode && slot.repMode == repMode) return;
    _markDirty();
    setState(() {
      slot.exerciseMode = exerciseMode;
      slot.repMode = repMode;
      if (exerciseMode == ExerciseMode.reps) {
        for (final week in slot.weeklySets) {
          for (final s in week) {
            if (repMode == RepMode.range) {
              s.repsMin ??= s.reps;
              s.repsMax ??= s.reps;
            } else {
              s.reps ??= s.repsMin ?? s.repsMax;
            }
          }
        }
      }
    });
  }

  // No setState: the notes TextField holds its own text and notes isn't
  // rendered anywhere else (mirrors _markDirty's own no-rebuild rationale).
  void _onNotesChanged(int dayIndex, int slotIndex, String value) {
    _markDirty();
    _days[dayIndex].slots[slotIndex].notes = value;
  }

  void _onSetWeightChanged(
      int dayIndex, int slotIndex, int setIndex, String v) {
    _markDirty();
    setState(() {
      _days[dayIndex]
          .slots[slotIndex]
          .weeklySets[_selectedWeek][setIndex]
          .weightKg = double.tryParse(v.trim().replaceAll(',', '.'));
    });
  }

  // ── Validation ───────────────────────────────────────────────────────────

  /// First unmet requirement, in fill order — mirrors mobile's
  /// `_firstValidationError` priority (name → split → exercise per day → reps).
  String? _firstValidationError() {
    if (_nameCtrl.text.trim().isEmpty) {
      return 'Ponele un nombre a la rutina.'; // i18n
    }
    if (_splitCtrl.text.trim().isEmpty) {
      return 'Contanos el split (ej: Push/Pull/Legs).'; // i18n
    }
    for (final day in _days) {
      final hasExercise = day.slots.any((s) => s.exercise != null);
      if (!hasExercise) {
        return 'El día "${day.name}" necesita al menos un ejercicio.'; // i18n
      }
      for (final slot in day.slots) {
        // Presence-mask backstop (Fase 4c): with the toggle's canonicalization
        // rules this should be unreachable, but a non-empty mask that names no
        // valid week would create an invisible ghost slot — refuse it.
        if (_numWeeks > 1 &&
            slot.activeWeeks.isNotEmpty &&
            !slot.activeWeeks.any((w) => w >= 0 && w < _numWeeks)) {
          final name = slot.exercise?.name ?? 'Un ejercicio'; // i18n
          return '$name no está en ninguna semana.'; // i18n
        }
        // Every week's sets must be complete (not just the currently viewed
        // one) — otherwise a trainer could save with an incomplete week
        // hidden behind an unvisited "Sem N" tab (Fase 4b). Weeks where the
        // exercise isn't scheduled are SKIPPED: those rows never get executed,
        // so demanding reps for them would block a perfectly valid plan
        // (Fase 4c presence mask; mirrors mobile's isPresentInWeek guard).
        for (var w = 0; w < slot.weeklySets.length; w++) {
          if (!slot.isPresentInWeek(w)) continue;
          final name = slot.exercise?.name ?? 'Un ejercicio'; // i18n
          // Name the offending week so the trainer knows where to look — only
          // meaningful once there's more than one week.
          final wk = _numWeeks > 1 ? ' en la Semana ${w + 1}' : ''; // i18n
          for (final set in slot.weeklySets[w]) {
            if (slot.exerciseMode == ExerciseMode.duration) {
              if (set.durationSeconds == null || set.durationSeconds! <= 0) {
                return '$name tiene una serie sin duración$wk.'; // i18n
              }
            } else if (slot.repMode == RepMode.range) {
              final min = set.repsMin, max = set.repsMax;
              if (min == null || min <= 0 || max == null || max < min) {
                return '$name tiene un rango de reps inválido (mín ≤ máx)$wk.'; // i18n
              }
            } else if (set.reps == null || set.reps! <= 0) {
              return '$name tiene una serie sin reps$wk.'; // i18n
            }
          }
        }
      }
    }
    return null;
  }

  // ── Submit ───────────────────────────────────────────────────────────────

  /// Derives the `supersetGroup` id for each slot in a day from the
  /// `linkedToNext` flags. Consecutive linked slots share an id; a group of a
  /// single slot normalizes to `null` (standalone), mirroring mobile.
  List<int?> _supersetGroups(List<_EditorSlot> slots) {
    final n = slots.length;
    // Assign a raw run id: a slot ends its run when it isn't linked to the next.
    final raw = List<int>.filled(n, 0);
    var run = 0;
    for (var i = 0; i < n; i++) {
      raw[i] = run;
      if (!slots[i].linkedToNext) run++;
    }
    final counts = <int, int>{};
    for (final r in raw) {
      counts[r] = (counts[r] ?? 0) + 1;
    }
    // Map runs with >= 2 members to stable positive ids; singletons → null.
    final ids = <int, int>{};
    var next = 1;
    return [
      for (var i = 0; i < n; i++)
        (counts[raw[i]] ?? 0) >= 2
            ? ids.putIfAbsent(raw[i], () => next++)
            : null,
    ];
  }

  RoutineSlot _buildSlot(_EditorSlot slot, int? supersetGroup) {
    final exercise = slot.exercise!;
    final isDuration = slot.exerciseMode == ExerciseMode.duration;
    final isRange = !isDuration && slot.repMode == RepMode.range;

    // Legacy fields + the `sets:` list stay derived from WEEK 0, mirroring
    // mobile's buildRoutineSlot — every non-week-aware consumer keeps reading
    // the first week's prescription (REQ-PERIOD-017, ADR-PB-03).
    final week0 = slot.weeklySets.first;

    // Legacy field derivation mirrors mobile's buildRoutineSlot.
    final int targetRepsMin;
    final int targetRepsMax;
    final List<int> targetReps;
    int? durationSeconds;
    if (isDuration) {
      targetRepsMin = 0;
      targetRepsMax = 0;
      targetReps = const [];
      durationSeconds = week0.isEmpty ? null : week0.first.durationSeconds;
    } else if (isRange) {
      final mins = week0.map((s) => s.repsMin ?? 0).toList();
      final maxs = week0.map((s) => s.repsMax ?? 0).toList();
      targetRepsMin = mins.isEmpty ? 0 : mins.reduce((a, b) => a < b ? a : b);
      targetRepsMax = maxs.isEmpty ? 0 : maxs.reduce((a, b) => a > b ? a : b);
      targetReps = const [];
    } else {
      final reps = week0.map((s) => s.reps ?? 0).toList();
      targetRepsMin = reps.isEmpty ? 0 : reps.reduce((a, b) => a < b ? a : b);
      targetRepsMax = reps.isEmpty ? 0 : reps.reduce((a, b) => a > b ? a : b);
      targetReps = reps;
    }

    // Mode is per-slot (not per-week), so the SAME conversion applies to
    // every week's rows.
    SetSpec toSpec(_EditorSet s) {
      if (isDuration) {
        return SetSpec(type: s.type, durationSeconds: s.durationSeconds);
      }
      if (isRange) {
        return SetSpec(
            type: s.type,
            repsMin: s.repsMin,
            repsMax: s.repsMax,
            weightKg: s.weightKg);
      }
      return SetSpec(type: s.type, reps: s.reps, weightKg: s.weightKg);
    }

    final week0Specs = week0.map(toSpec).toList();
    final notes = slot.notes.trim();

    return RoutineSlot(
      exerciseId: exercise.id,
      exerciseName: exercise.name,
      muscleGroup: exercise.muscleGroup,
      targetSets: week0Specs.length,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      restSeconds: slot.restSeconds,
      supersetGroup: supersetGroup,
      targetWeightKg:
          isDuration || week0Specs.isEmpty ? null : week0Specs.first.weightKg,
      targetReps: targetReps,
      durationSeconds: durationSeconds,
      exerciseMode: slot.exerciseMode,
      repMode: slot.repMode,
      notes: notes.isEmpty ? null : notes,
      sets: week0Specs,
      // Full per-week prescription — only written past the first week; a
      // single-week plan keeps weeklySets EMPTY (compact wire shape, parity
      // with Fase 4a). `sets:` above always carries week 0 as the legacy
      // fallback for non-week-aware readers.
      weeklySets: _numWeeks > 1
          ? slot.weeklySets.map((wk) => wk.map(toSpec).toList()).toList()
          : const [],
      // Presence mask: sorted for deterministic wire output. Empty stays
      // empty — present in all (the only) week (Fase 4c).
      activeWeeks: slot.activeWeeks.toList()..sort(),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final error = _firstValidationError();
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }
    final trainerUid = ref.read(currentUidProvider);
    if (trainerUid == null) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final days = _days.map((d) {
      // supersetGroup ids are derived per day from the linkedToNext flags, over
      // the exercise-bearing slots only (the ones that become RoutineDay.slots).
      final withExercise = d.slots.where((s) => s.exercise != null).toList();
      final groups = _supersetGroups(withExercise);
      return RoutineDay(
        dayNumber: d.dayNumber,
        name: d.name,
        slots: [
          for (var i = 0; i < withExercise.length; i++)
            _buildSlot(withExercise[i], groups[i]),
        ],
      );
    }).toList();

    final repo = ref.read(routineRepositoryProvider);
    try {
      if (_isEditing) {
        // Preserve the loaded routine's identity (id, assignedBy/To, source,
        // createdAt, …). updateAssigned only writes name/split/level/days/
        // numWeeks — `days` is rebuilt from a form that models 100% of
        // RoutineSlot's schema, so nothing is lost on re-save (Fase 4c).
        final draft = _loadedRoutine!.copyWith(
          name: _nameCtrl.text.trim(),
          split: _splitCtrl.text.trim(),
          level: _level,
          days: days,
          numWeeks: _numWeeks,
        );
        await repo.updateAssigned(uid: trainerUid, draft: draft);
      } else {
        final routine = Routine(
          id: '',
          name: _nameCtrl.text.trim(),
          split: _splitCtrl.text.trim(),
          level: _level,
          days: days,
          numWeeks: _numWeeks,
          source: RoutineSource.trainerAssigned,
          assignedBy: trainerUid,
          assignedTo: widget.athleteId,
          // REQUIRED by firestore.rules: a trainer-assigned plan must be
          // 'private' or 'shared' — the model default 'public' is rejected on
          // create (it's only valid for system templates). Mirrors mobile's
          // assignTemplateToAthlete.
          visibility: RoutineVisibility.private,
        );
        await repo.createAssigned(routine);
      }
      // assignedRoutinesProvider is a one-shot FutureProvider (not a stream) —
      // invalidate so the athlete detail's "Rutina activa" card picks up the
      // change on return.
      ref.invalidate(assignedRoutinesProvider(widget.athleteId));
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage =
              'No pudimos guardar la rutina. Probá de nuevo.'; // i18n
        });
      }
    }
  }

  // ── Discard guard ────────────────────────────────────────────────────────

  Future<void> _onBackTap() async {
    if (!_isDirty) {
      context.pop();
      return;
    }
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        title: Text('¿Descartar los cambios?', // i18n
            style: GoogleFonts.barlowCondensed(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        content: Text('Lo que armaste se va a perder.', // i18n
            style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Volver', // i18n
                style: GoogleFonts.barlow(color: palette.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Descartar', // i18n
                style: GoogleFonts.barlow(
                    color: palette.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) context.pop();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(widget.athleteId));
    final athleteName =
        profileAsync.valueOrNull?.displayName ?? 'el alumno'; // i18n

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackTap();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 24, 12),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(TreinoIcon.arrowLeft, color: palette.textMuted),
                  onPressed: _onBackTap,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEditing ? 'Editar rutina' : 'Nueva rutina', // i18n
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          letterSpacing: 0.8,
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        'Para $athleteName', // i18n
                        style: GoogleFonts.barlow(
                            color: palette.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.border),
          // ── Body: loading spinner / blocked notice / the form ───────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _fatalMessage != null
                    ? _FatalMessage(
                        message: _fatalMessage!,
                        palette: palette,
                        onBack: _onBackTap,
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_errorMessage != null) ...[
                                  _ErrorBanner(
                                      message: _errorMessage!,
                                      palette: palette),
                                  const SizedBox(height: 16),
                                ],
                                _FieldLabel('NOMBRE', palette), // i18n
                                const SizedBox(height: 6),
                                TextField(
                                  key: const Key('routine_editor_name_field'),
                                  controller: _nameCtrl,
                                  onChanged: (_) => _markDirty(),
                                  style: GoogleFonts.barlow(
                                      color: palette.textPrimary),
                                  decoration: _inputDecoration(
                                      palette, 'Ej: Fuerza 4x semana'), // i18n
                                ),
                                const SizedBox(height: 16),
                                _FieldLabel('SPLIT', palette), // i18n
                                const SizedBox(height: 6),
                                TextField(
                                  key: const Key('routine_editor_split_field'),
                                  controller: _splitCtrl,
                                  onChanged: (_) => _markDirty(),
                                  style: GoogleFonts.barlow(
                                      color: palette.textPrimary),
                                  decoration: _inputDecoration(
                                      palette, 'Ej: Push/Pull/Legs'), // i18n
                                ),
                                const SizedBox(height: 16),
                                _FieldLabel('NIVEL', palette), // i18n
                                const SizedBox(height: 8),
                                _LevelSelector(
                                  selected: _level,
                                  palette: palette,
                                  onChanged: (l) {
                                    _markDirty();
                                    setState(() => _level = l);
                                  },
                                ),
                                const SizedBox(height: 24),
                                _FieldLabel('SEMANAS', palette), // i18n
                                const SizedBox(height: 8),
                                _WeeksStepper(
                                  numWeeks: _numWeeks,
                                  palette: palette,
                                  onChanged: _setNumWeeks,
                                ),
                                const SizedBox(height: 24),
                                _FieldLabel('DÍAS', palette), // i18n
                                const SizedBox(height: 8),
                                // Global week switcher (Fase 4b) — one row for
                                // the whole plan since `_selectedWeek` isn't
                                // per-day. Hidden for single-week plans.
                                if (_numWeeks > 1) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _WeekTabs(
                                          numWeeks: _numWeeks,
                                          selectedWeek: _selectedWeek,
                                          palette: palette,
                                          onSelected: (w) =>
                                              setState(() => _selectedWeek = w),
                                        ),
                                      ),
                                      // Nothing to copy from on week 1.
                                      if (_selectedWeek > 0) ...[
                                        const SizedBox(width: 8),
                                        _DuplicateWeekButton(
                                          sourceWeek: _selectedWeek - 1,
                                          palette: palette,
                                          onPressed: _duplicateWeek,
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                for (var i = 0; i < _days.length; i++) ...[
                                  _DayCard(
                                    day: _days[i],
                                    palette: palette,
                                    selectedWeek: _selectedWeek,
                                    numWeeks: _numWeeks,
                                    canRemove: _days.length > 1,
                                    onNameChanged: (v) =>
                                        _onDayNameChanged(i, v),
                                    onRemove: () => _removeDay(i),
                                    onAddExercises: () => _addExercisesToDay(i),
                                    onRemoveSlot: (s) => _removeSlot(i, s),
                                    onMoveSlot: (s, dir) =>
                                        _moveSlot(i, s, dir),
                                    onRestChanged: (s, v) =>
                                        _onRestChanged(i, s, v),
                                    onAddSet: (s) => _addSet(i, s),
                                    onRemoveSet: (s, set) =>
                                        _removeSet(i, s, set),
                                    onSetRepsChanged: (s, set, v) =>
                                        _onSetRepsChanged(i, s, set, v),
                                    onSetRepsMinChanged: (s, set, v) =>
                                        _onSetRepsMinChanged(i, s, set, v),
                                    onSetRepsMaxChanged: (s, set, v) =>
                                        _onSetRepsMaxChanged(i, s, set, v),
                                    onSetDurationChanged: (s, set, v) =>
                                        _onSetDurationChanged(i, s, set, v),
                                    onSetWeightChanged: (s, set, v) =>
                                        _onSetWeightChanged(i, s, set, v),
                                    onModeChanged: (s, em, rm) =>
                                        _setSlotMode(i, s, em, rm),
                                    onNotesChanged: (s, v) =>
                                        _onNotesChanged(i, s, v),
                                    onToggleLink: (s) => _toggleSlotLink(i, s),
                                    onTogglePresence: (s, w) =>
                                        _toggleSlotWeekPresence(i, s, w),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (_days.length < _kMaxDays)
                                  OutlinedButton.icon(
                                    key: const Key(
                                        'routine_editor_add_day_button'),
                                    onPressed: _addDay,
                                    icon: Icon(TreinoIcon.plus,
                                        size: 18, color: palette.accent),
                                    label: Text('Agregar día', // i18n
                                        style: GoogleFonts.barlowCondensed(
                                            color: palette.accent,
                                            fontWeight: FontWeight.w700)),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: palette.accent),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
          ),
          // ── Footer (hidden while loading or when blocked) ───────────────
          if (!_loading && _fatalMessage == null)
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: palette.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting ? null : _onBackTap,
                    child: Text('Cancelar', // i18n
                        style: GoogleFonts.barlow(color: palette.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    key: const Key('routine_editor_submit_button'),
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.bg,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9999)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                    ),
                    child: Text(
                      _submitting
                          ? 'Guardando…'
                          : _isEditing
                              ? 'Guardar cambios'
                              : 'Asignar rutina', // i18n
                      style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

InputDecoration _inputDecoration(AppPalette palette, String hint) {
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, this.palette);
  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.barlowCondensed(
        color: palette.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.palette});
  final String message;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(TreinoIcon.warning, color: palette.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: GoogleFonts.barlow(color: palette.danger, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── Fatal notice (not-found / advanced-routine block) ───────────────────────

class _FatalMessage extends StatelessWidget {
  const _FatalMessage({
    required this.message,
    required this.palette,
    required this.onBack,
  });

  final String message;
  final AppPalette palette;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TreinoIcon.warning, color: palette.textMuted, size: 32),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onBack,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: palette.border),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Text('Volver', // i18n
                  style: GoogleFonts.barlowCondensed(
                      color: palette.textPrimary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Weeks stepper (periodización) ────────────────────────────────────────────

class _WeeksStepper extends StatelessWidget {
  const _WeeksStepper({
    required this.numWeeks,
    required this.palette,
    required this.onChanged,
  });

  final int numWeeks;
  final AppPalette palette;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepButton(
          label: '−',
          enabled: numWeeks > 1,
          palette: palette,
          onTap: () => onChanged(numWeeks - 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            numWeeks == 1 ? '1 semana' : '$numWeeks semanas', // i18n
            style: GoogleFonts.barlowCondensed(
                color: palette.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
        ),
        _StepButton(
          label: '+',
          enabled: numWeeks < _kMaxWeeks,
          palette: palette,
          onTap: () => onChanged(numWeeks + 1),
        ),
        const SizedBox(width: 14),
        if (numWeeks > 1)
          Expanded(
            child: Text(
              // Fase 4b hizo cada semana independiente — el cartel viejo
              // ("misma rutina cada semana") ya no era cierto.
              'Cada semana se carga por separado.', // i18n
              style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.label,
    required this.enabled,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
              color: enabled
                  ? palette.border
                  : palette.border.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: GoogleFonts.barlowCondensed(
            color: enabled ? palette.accent : palette.textMuted,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Level selector ─────────────────────────────────────────────────────────

class _LevelSelector extends StatelessWidget {
  const _LevelSelector({
    required this.selected,
    required this.palette,
    required this.onChanged,
  });

  final ExperienceLevel selected;
  final AppPalette palette;
  final ValueChanged<ExperienceLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final level in ExperienceLevel.values)
          GestureDetector(
            onTap: () => onChanged(level),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: selected == level ? palette.accent : palette.bgCard,
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(
                  color: selected == level ? palette.accent : palette.border,
                ),
              ),
              child: Text(
                level.displayNameEs,
                style: GoogleFonts.barlowCondensed(
                  color: selected == level ? palette.bg : palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Day card ───────────────────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.palette,
    required this.selectedWeek,
    required this.numWeeks,
    required this.canRemove,
    required this.onNameChanged,
    required this.onRemove,
    required this.onAddExercises,
    required this.onRemoveSlot,
    required this.onMoveSlot,
    required this.onRestChanged,
    required this.onAddSet,
    required this.onRemoveSet,
    required this.onSetRepsChanged,
    required this.onSetRepsMinChanged,
    required this.onSetRepsMaxChanged,
    required this.onSetDurationChanged,
    required this.onSetWeightChanged,
    required this.onModeChanged,
    required this.onNotesChanged,
    required this.onToggleLink,
    required this.onTogglePresence,
  });

  final _EditorDay day;
  final AppPalette palette;

  /// 0-based week whose `weeklySets` entry each slot card should render
  /// (Fase 4b) — threaded down to [_SlotCard].
  final int selectedWeek;

  /// Total plan weeks — threaded down to [_SlotCard] so it knows whether to
  /// render the presence chips row and whether to dim (Fase 4c).
  final int numWeeks;
  final bool canRemove;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onRemove;
  final VoidCallback onAddExercises;
  final void Function(int slotIndex) onRemoveSlot;
  final void Function(int slotIndex, int dir) onMoveSlot;
  final void Function(int slotIndex, String value) onRestChanged;
  final void Function(int slotIndex) onAddSet;
  final void Function(int slotIndex, int setIndex) onRemoveSet;
  final void Function(int slotIndex, int setIndex, String value)
      onSetRepsChanged;
  final void Function(int slotIndex, int setIndex, String value)
      onSetRepsMinChanged;
  final void Function(int slotIndex, int setIndex, String value)
      onSetRepsMaxChanged;
  final void Function(int slotIndex, int setIndex, String value)
      onSetDurationChanged;
  final void Function(int slotIndex, int setIndex, String value)
      onSetWeightChanged;
  final void Function(int slotIndex, ExerciseMode exerciseMode, RepMode repMode)
      onModeChanged;
  final void Function(int slotIndex, String value) onNotesChanged;
  final void Function(int slotIndex) onToggleLink;
  final void Function(int slotIndex, int week) onTogglePresence;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: day.name,
                  onChanged: onNameChanged,
                  style: GoogleFonts.barlowCondensed(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (canRemove)
                IconButton(
                  tooltip: 'Eliminar día', // i18n
                  icon: Icon(TreinoIcon.trash,
                      size: 18, color: palette.textMuted),
                  onPressed: onRemove,
                ),
            ],
          ),
          for (var i = 0; i < day.slots.length; i++) ...[
            const SizedBox(height: 8),
            _SlotCard(
              slot: day.slots[i],
              palette: palette,
              selectedWeek: selectedWeek,
              numWeeks: numWeeks,
              canMoveUp: i > 0,
              canMoveDown: i < day.slots.length - 1,
              canLink: i < day.slots.length - 1,
              linkedToNext: day.slots[i].linkedToNext,
              inSuperset:
                  (i < day.slots.length - 1 && day.slots[i].linkedToNext) ||
                      (i > 0 && day.slots[i - 1].linkedToNext),
              onRemove: () => onRemoveSlot(i),
              onMoveUp: () => onMoveSlot(i, -1),
              onMoveDown: () => onMoveSlot(i, 1),
              onRestChanged: (v) => onRestChanged(i, v),
              onAddSet: () => onAddSet(i),
              onRemoveSet: (set) => onRemoveSet(i, set),
              onSetRepsChanged: (set, v) => onSetRepsChanged(i, set, v),
              onSetRepsMinChanged: (set, v) => onSetRepsMinChanged(i, set, v),
              onSetRepsMaxChanged: (set, v) => onSetRepsMaxChanged(i, set, v),
              onSetDurationChanged: (set, v) => onSetDurationChanged(i, set, v),
              onSetWeightChanged: (set, v) => onSetWeightChanged(i, set, v),
              onModeChanged: (em, rm) => onModeChanged(i, em, rm),
              onNotesChanged: (v) => onNotesChanged(i, v),
              onToggleLink: () => onToggleLink(i),
              onTogglePresence: (w) => onTogglePresence(i, w),
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onAddExercises,
            icon: Icon(TreinoIcon.plus, size: 16, color: palette.accent),
            label: Text('Agregar ejercicio', // i18n
                style: GoogleFonts.barlowCondensed(
                    color: palette.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: palette.border),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Exercise slot card ─────────────────────────────────────────────────────

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.slot,
    required this.palette,
    required this.selectedWeek,
    required this.numWeeks,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canLink,
    required this.linkedToNext,
    required this.inSuperset,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRestChanged,
    required this.onAddSet,
    required this.onRemoveSet,
    required this.onSetRepsChanged,
    required this.onSetRepsMinChanged,
    required this.onSetRepsMaxChanged,
    required this.onSetDurationChanged,
    required this.onSetWeightChanged,
    required this.onModeChanged,
    required this.onNotesChanged,
    required this.onToggleLink,
    required this.onTogglePresence,
  });

  final _EditorSlot slot;
  final AppPalette palette;

  /// 0-based week whose `slot.weeklySets` entry this card renders (Fase 4b).
  final int selectedWeek;

  /// Total plan weeks. The presence chips row ("Semanas:") and the dimming of
  /// exercises absent from [selectedWeek] only apply when this is > 1
  /// (Fase 4c).
  final int numWeeks;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool canLink; // false for the last slot of a day (nothing to link to)
  final bool linkedToNext;
  final bool inSuperset; // part of a >=2 superset run → accent border
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final ValueChanged<String> onRestChanged;
  final VoidCallback onAddSet;
  final void Function(int setIndex) onRemoveSet;
  final void Function(int setIndex, String value) onSetRepsChanged;
  final void Function(int setIndex, String value) onSetRepsMinChanged;
  final void Function(int setIndex, String value) onSetRepsMaxChanged;
  final void Function(int setIndex, String value) onSetDurationChanged;
  final void Function(int setIndex, String value) onSetWeightChanged;
  final void Function(ExerciseMode exerciseMode, RepMode repMode) onModeChanged;
  final ValueChanged<String> onNotesChanged;
  final VoidCallback onToggleLink;
  final ValueChanged<int> onTogglePresence;

  @override
  Widget build(BuildContext context) {
    final exercise = slot.exercise;
    // The sets for the currently-viewed week only — other weeks' rows aren't
    // rendered while a different tab is selected (Fase 4b).
    final weekSets = slot.weeklySets[selectedWeek];
    final card = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(10),
        // Slots in a superset run share an accent-tinted border to read as a
        // group (the "link with next" toggle is what forms the run).
        border: inSuperset
            ? Border.all(color: palette.accent.withValues(alpha: 0.55))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise?.name ?? '—',
                  style: GoogleFonts.barlow(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                ),
              ),
              IconButton(
                tooltip: 'Subir', // i18n
                icon: Icon(TreinoIcon.chevronUp,
                    size: 16, color: palette.textMuted),
                onPressed: canMoveUp ? onMoveUp : null,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: 'Bajar', // i18n
                icon: Icon(TreinoIcon.chevronDown,
                    size: 16, color: palette.textMuted),
                onPressed: canMoveDown ? onMoveDown : null,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: 'Quitar ejercicio', // i18n
                icon:
                    Icon(TreinoIcon.trash, size: 16, color: palette.textMuted),
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Modo del ejercicio: reps fijas / rango (mín–máx) / tiempo (paridad
          // con mobile, Fases 1-2). exerciseMode + repMode combinados en 3 chips.
          Row(
            children: [
              _ModeChip(
                label: 'Reps', // i18n
                selected: slot.exerciseMode == ExerciseMode.reps &&
                    slot.repMode == RepMode.single,
                palette: palette,
                onTap: () => onModeChanged(ExerciseMode.reps, RepMode.single),
              ),
              const SizedBox(width: 6),
              _ModeChip(
                label: 'Rango', // i18n
                selected: slot.exerciseMode == ExerciseMode.reps &&
                    slot.repMode == RepMode.range,
                palette: palette,
                onTap: () => onModeChanged(ExerciseMode.reps, RepMode.range),
              ),
              const SizedBox(width: 6),
              _ModeChip(
                label: 'Tiempo', // i18n
                selected: slot.exerciseMode == ExerciseMode.duration,
                palette: palette,
                onTap: () =>
                    onModeChanged(ExerciseMode.duration, RepMode.single),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Presence mask (Fase 4c): which weeks this exercise is present in.
          // Only meaningful for multi-week plans.
          if (numWeeks > 1) ...[
            Row(
              children: [
                Text('Semanas:', // i18n
                    style: GoogleFonts.barlow(
                        color: palette.textMuted, fontSize: 12)),
                const SizedBox(width: 6),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var w = 0; w < numWeeks; w++)
                        _PresenceChip(
                          index: w,
                          present: slot.isPresentInWeek(w),
                          palette: palette,
                          onTap: () => onTogglePresence(w),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Text('Descanso (seg)', // i18n
                  style: GoogleFonts.barlow(
                      color: palette.textMuted, fontSize: 12)),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: TextFormField(
                  initialValue: slot.restSeconds.toString(),
                  keyboardType: TextInputType.number,
                  onChanged: onRestChanged,
                  style: GoogleFonts.barlow(
                      color: palette.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < weekSets.length; i++)
            _SetRow(
              // Key by week so switching weeks REBUILDS the fields fresh from
              // the model. Without it the uncontrolled TextFormFields keep the
              // previous week's controller text and show stale values.
              key: ValueKey('w${selectedWeek}s$i'),
              index: i,
              set: weekSets[i],
              palette: palette,
              exerciseMode: slot.exerciseMode,
              repMode: slot.repMode,
              canRemove: weekSets.length > 1,
              onRemove: () => onRemoveSet(i),
              onRepsChanged: (v) => onSetRepsChanged(i, v),
              onRepsMinChanged: (v) => onSetRepsMinChanged(i, v),
              onRepsMaxChanged: (v) => onSetRepsMaxChanged(i, v),
              onDurationChanged: (v) => onSetDurationChanged(i, v),
              onWeightChanged: (v) => onSetWeightChanged(i, v),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAddSet,
              icon: Icon(TreinoIcon.plus, size: 14, color: palette.accent),
              label: Text('Agregar set', // i18n
                  style: GoogleFonts.barlowCondensed(
                      color: palette.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ),
          ),
          // Coaching note for this exercise (optional). Located in tests via
          // its hint, not a Key — a Key would collide across slots.
          TextFormField(
            initialValue: slot.notes,
            onChanged: onNotesChanged,
            maxLength: 200,
            minLines: 1,
            maxLines: 3,
            style: GoogleFonts.barlow(color: palette.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Notas para el alumno (opcional)', // i18n
              hintStyle:
                  GoogleFonts.barlow(color: palette.textMuted, fontSize: 12),
              counterText: '',
            ),
          ),
          // Superset link — only offered when there IS a next exercise to link
          // to. A run of linked exercises becomes one superset block on save.
          if (canLink)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onToggleLink,
                icon: Icon(
                  linkedToNext ? TreinoIcon.check : TreinoIcon.plus,
                  size: 14,
                  color: linkedToNext ? palette.accent : palette.textMuted,
                ),
                label: Text(
                  linkedToNext
                      ? 'En superserie con el siguiente' // i18n
                      : 'Superserie con el siguiente', // i18n
                  style: GoogleFonts.barlowCondensed(
                    color: linkedToNext ? palette.accent : palette.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    // Dim (not hide) an exercise absent from the currently-viewed week so the
    // trainer still sees it and can re-add it via the presence chips above
    // (Fase 4c). Opacity alone doesn't block hit-testing, so the chips stay
    // tappable while dimmed.
    if (numWeeks > 1 && !slot.isPresentInWeek(selectedWeek)) {
      return Opacity(opacity: 0.45, child: card);
    }
    return card;
  }
}

// ── Set row ────────────────────────────────────────────────────────────────

class _SetRow extends StatelessWidget {
  const _SetRow({
    super.key,
    required this.index,
    required this.set,
    required this.palette,
    required this.exerciseMode,
    required this.repMode,
    required this.canRemove,
    required this.onRemove,
    required this.onRepsChanged,
    required this.onRepsMinChanged,
    required this.onRepsMaxChanged,
    required this.onDurationChanged,
    required this.onWeightChanged,
  });

  final int index;
  final _EditorSet set;
  final AppPalette palette;
  final ExerciseMode exerciseMode;
  final RepMode repMode;
  final bool canRemove;
  final VoidCallback onRemove;
  final ValueChanged<String> onRepsChanged;
  final ValueChanged<String> onRepsMinChanged;
  final ValueChanged<String> onRepsMaxChanged;
  final ValueChanged<String> onDurationChanged;
  final ValueChanged<String> onWeightChanged;

  @override
  Widget build(BuildContext context) {
    final isDuration = exerciseMode == ExerciseMode.duration;
    final isRange = !isDuration && repMode == RepMode.range;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text('${index + 1}',
                style: GoogleFonts.barlowCondensed(
                    color: palette.textMuted, fontWeight: FontWeight.w700)),
          ),
          if (isDuration)
            // Duration exercises (planks, cardio) have no weight — just seconds.
            Expanded(
              child: _numberField(
                  initial: set.durationSeconds?.toString() ?? '',
                  hint: 'seg', // i18n
                  onChanged: onDurationChanged),
            )
          else ...[
            if (isRange) ...[
              Expanded(
                child: _numberField(
                    initial: set.repsMin?.toString() ?? '',
                    hint: 'mín', // i18n
                    onChanged: onRepsMinChanged),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _numberField(
                    initial: set.repsMax?.toString() ?? '',
                    hint: 'máx', // i18n
                    onChanged: onRepsMaxChanged),
              ),
            ] else
              Expanded(
                child: _numberField(
                    initial: set.reps?.toString() ?? '',
                    hint: 'reps', // i18n
                    onChanged: onRepsChanged),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: _numberField(
                  initial: set.weightKg?.toString() ?? '',
                  hint: 'kg', // i18n
                  decimal: true,
                  onChanged: onWeightChanged),
            ),
          ],
          IconButton(
            tooltip: 'Quitar set', // i18n
            icon: Icon(TreinoIcon.close, size: 14, color: palette.textMuted),
            onPressed: canRemove ? onRemove : null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required String initial,
    required String hint,
    required ValueChanged<String> onChanged,
    bool decimal = false,
  }) {
    return TextFormField(
      initialValue: initial,
      keyboardType: decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      onChanged: onChanged,
      style: GoogleFonts.barlow(color: palette.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: GoogleFonts.barlow(color: palette.textMuted, fontSize: 12),
      ),
    );
  }
}

// ── Rep-mode chip (Reps fijas / Rango) ───────────────────────────────────────

class _ModeChip extends StatelessWidget {
  const _ModeChip({
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? palette.accent : palette.bgCard,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(color: selected ? palette.accent : palette.border),
        ),
        child: Text(
          label,
          style: GoogleFonts.barlowCondensed(
            color: selected ? palette.bg : palette.textMuted,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// ── Week tabs (prescripción por semana, Fase 4b) ─────────────────────────────

/// Plan-level week switcher shown above the days list when the routine spans
/// more than one week: one chip per week ("Sem 1".."Sem N"). Tapping a chip
/// changes which week's sets the day/slot cards render and edit
/// (`_selectedWeek`) — a single global row since the selection isn't per-day.
/// "Copiar Sem N acá" — pulls the previous week's prescription into the one
/// being viewed. Labelled with the SOURCE week (not just "duplicar") because
/// the direction is the whole point: a 4-week progression is built by copying
/// forward and tweaking a number, not by re-typing every row.
class _DuplicateWeekButton extends StatelessWidget {
  const _DuplicateWeekButton({
    required this.sourceWeek,
    required this.palette,
    required this.onPressed,
  });

  /// 0-based index of the week being copied FROM.
  final int sourceWeek;
  final AppPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const Key('duplicate_week_button'),
      onPressed: onPressed,
      icon: Icon(TreinoIcon.copy, size: 16, color: palette.textMuted),
      label: Text(
        'Copiar Sem ${sourceWeek + 1} acá', // i18n
        style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 13),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: palette.border),
        ),
      ),
    );
  }
}

class _WeekTabs extends StatelessWidget {
  const _WeekTabs({
    required this.numWeeks,
    required this.selectedWeek,
    required this.palette,
    required this.onSelected,
  });

  final int numWeeks;
  final int selectedWeek;
  final AppPalette palette;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var w = 0; w < numWeeks; w++) ...[
            _WeekChip(
              index: w,
              selected: w == selectedWeek,
              palette: palette,
              onTap: () => onSelected(w),
            ),
            if (w < numWeeks - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// One selectable week pill — accent-filled when [selected]. Mirrors
/// [_ModeChip]'s visual style.
class _WeekChip extends StatelessWidget {
  const _WeekChip({
    required this.index,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  /// 0-based week — rendered 1-based ("Sem 1").
  final int index;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('week_tab_$index'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? palette.accent : palette.bgCard,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(color: selected ? palette.accent : palette.border),
        ),
        child: Text(
          'Sem ${index + 1}', // i18n
          style: GoogleFonts.barlowCondensed(
            color: selected ? palette.bg : palette.textMuted,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// ── Presence chips (máscara de presencia por semana, Fase 4c) ───────────────

/// One per-exercise week-presence toggle — filled/accent when the slot is
/// present in that week ([_SlotCard.slot.isPresentInWeek]), outlined/muted
/// otherwise. Visually mirrors [_WeekChip]/[_ModeChip], just more compact
/// since up to `_kMaxWeeks` (16) of these can render per exercise.
class _PresenceChip extends StatelessWidget {
  const _PresenceChip({
    required this.index,
    required this.present,
    required this.palette,
    required this.onTap,
  });

  /// 0-based week — rendered 1-based ("1".."N").
  final int index;
  final bool present;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('presence_chip_$index'),
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: present ? palette.accent : palette.bgCard,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(color: present ? palette.accent : palette.border),
        ),
        child: Text(
          '${index + 1}',
          style: GoogleFonts.barlowCondensed(
            color: present ? palette.bg : palette.textMuted,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
