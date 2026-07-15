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
import 'routine_web_editability.dart';

/// Editor de rutinas web — crea o edita la rutina de UN alumno (mirrors
/// mobile's `RoutineEditorScreen(TrainerAssigning)`). Soporta, por ejercicio:
/// reps fijas o rango (mín–máx), duración (por tiempo), notas para el alumno,
/// supersets y N semanas con la misma prescripción (paridad Fases 1-4a). Todavía
/// NO: prescripción distinta por semana (Fase 4b) ni máscara de presencia por
/// semana (Fase 4c) — esas rutinas se siguen editando en mobile.
///
/// **Modo edición** (`routineId != null`): carga la rutina y la abre en el
/// form. Como `updateAssigned` pisa el array `days` entero, editar una rutina
/// con prescripción por-semana desde acá la truncaría silenciosamente — por eso
/// [isRoutineWebEditable] actúa de compuerta: si la rutina usa un campo aún no
/// soportado, el editor NO la carga y muestra un aviso para editarla en mobile.
/// Las rutinas creadas en web están siempre dentro de scope, así que
/// round-tripean sin drama.
///
/// La `Routine` que este editor escribe es 100% válida para el modelo de
/// dominio completo (weeklySets/activeWeeks vacíos = "misma prescripción todas
/// las semanas") — mobile puede leerla y editarla sin problema.
class RoutineEditorWebScreen extends ConsumerStatefulWidget {
  const RoutineEditorWebScreen({
    super.key,
    required this.athleteId,
    this.routineId,
  });

  final String athleteId;

  /// When non-null, the editor loads this existing routine and saves via
  /// `updateAssigned` instead of `createAssigned`. Only routines that pass
  /// [isRoutineWebEditable] are loaded; advanced ones are refused.
  final String? routineId;

  @override
  ConsumerState<RoutineEditorWebScreen> createState() =>
      _RoutineEditorWebScreenState();
}

// ── Mutable editor state (web MVP) ────────────────────────────────────────────

class _EditorSet {
  double? weightKg;
  int? reps; // used when repMode == single
  int? repsMin; // used when repMode == range
  int? repsMax; // used when repMode == range
  int? durationSeconds; // used when exerciseMode == duration
}

class _EditorSlot {
  Exercise? exercise;
  int restSeconds = 0;
  ExerciseMode exerciseMode = ExerciseMode.reps;
  RepMode repMode = RepMode.single;
  String notes = '';
  // True when this exercise is supersetted with the NEXT one in the day. A run
  // of linked slots becomes one superset group (id derived at build time).
  bool linkedToNext = false;
  List<_EditorSet> sets = [_EditorSet()];
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

  /// Non-null when the form can't be shown: routine not found, or it uses
  /// advanced fields the web editor would truncate ([isRoutineWebEditable]).
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
      // GATE: refuse to load a routine we'd silently truncate on save.
      if (!isRoutineWebEditable(routine)) {
        setState(() {
          _loading = false;
          _fatalMessage =
              'Esta rutina tiene periodización o supersets. Editala desde la app mobile para no perder esa configuración.'; // i18n
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
    final effective = slot.effectiveSets;
    // Derive the mode from the actual set data — robust against stale
    // exerciseMode/repMode fields (mirrors mobile's _repModeFromHydratedSets).
    final isDuration = effective.any((s) => (s.durationSeconds ?? 0) > 0);
    final isRange = !isDuration &&
        effective.any((s) => s.repsMin != null || s.repsMax != null);
    final sets = effective
        .map((s) => _EditorSet()
          ..reps = s.reps
          ..repsMin = s.repsMin
          ..repsMax = s.repsMax
          ..durationSeconds = s.durationSeconds
          ..weightKg = s.weightKg)
        .toList();
    return _EditorSlot()
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
      ..sets = sets.isEmpty ? [_EditorSet()] : sets;
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

  // ── Week operations (periodización) ───────────────────────────────────────

  void _setNumWeeks(int value) {
    final clamped = value.clamp(1, _kMaxWeeks);
    if (clamped == _numWeeks) return;
    _markDirty();
    setState(() => _numWeeks = clamped);
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
        day.slots.add(_EditorSlot()..exercise = exercise);
      }
    });
  }

  void _removeSlot(int dayIndex, int slotIndex) {
    _markDirty();
    setState(() => _days[dayIndex].slots.removeAt(slotIndex));
  }

  void _moveSlot(int dayIndex, int slotIndex, int dir) {
    final slots = _days[dayIndex].slots;
    final target = slotIndex + dir;
    if (target < 0 || target >= slots.length) return;
    _markDirty();
    setState(() {
      final tmp = slots[slotIndex];
      slots[slotIndex] = slots[target];
      slots[target] = tmp;
    });
  }

  // Links / unlinks this exercise with the next one into a superset.
  void _toggleSlotLink(int dayIndex, int slotIndex) {
    _markDirty();
    setState(() {
      final slot = _days[dayIndex].slots[slotIndex];
      slot.linkedToNext = !slot.linkedToNext;
    });
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
      final sets = _days[dayIndex].slots[slotIndex].sets;
      // Duplicate the last row's values — same "+ Agregar set" UX as mobile.
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
    final sets = _days[dayIndex].slots[slotIndex].sets;
    if (sets.length <= 1) return; // at least one set per exercise
    _markDirty();
    setState(() => sets.removeAt(setIndex));
  }

  void _onSetRepsChanged(int dayIndex, int slotIndex, int setIndex, String v) {
    _markDirty();
    setState(() => _days[dayIndex].slots[slotIndex].sets[setIndex].reps =
        int.tryParse(v.trim()));
  }

  void _onSetRepsMinChanged(
      int dayIndex, int slotIndex, int setIndex, String v) {
    _markDirty();
    setState(() => _days[dayIndex].slots[slotIndex].sets[setIndex].repsMin =
        int.tryParse(v.trim()));
  }

  void _onSetRepsMaxChanged(
      int dayIndex, int slotIndex, int setIndex, String v) {
    _markDirty();
    setState(() => _days[dayIndex].slots[slotIndex].sets[setIndex].repsMax =
        int.tryParse(v.trim()));
  }

  void _onSetDurationChanged(
      int dayIndex, int slotIndex, int setIndex, String v) {
    _markDirty();
    setState(() => _days[dayIndex]
        .slots[slotIndex]
        .sets[setIndex]
        .durationSeconds = int.tryParse(v.trim()));
  }

  /// Switches an exercise between fixed reps, a min–max range, and duration.
  /// Reps ↔ range values carry across so the trainer doesn't retype.
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
        for (final s in slot.sets) {
          if (repMode == RepMode.range) {
            s.repsMin ??= s.reps;
            s.repsMax ??= s.reps;
          } else {
            s.reps ??= s.repsMin ?? s.repsMax;
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
      _days[dayIndex].slots[slotIndex].sets[setIndex].weightKg =
          double.tryParse(v.trim().replaceAll(',', '.'));
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
        for (final set in slot.sets) {
          final name = slot.exercise?.name ?? 'Un ejercicio'; // i18n
          if (slot.exerciseMode == ExerciseMode.duration) {
            if (set.durationSeconds == null || set.durationSeconds! <= 0) {
              return '$name tiene una serie sin duración.'; // i18n
            }
          } else if (slot.repMode == RepMode.range) {
            final min = set.repsMin, max = set.repsMax;
            if (min == null || min <= 0 || max == null || max < min) {
              return '$name tiene un rango de reps inválido (mín ≤ máx).'; // i18n
            }
          } else if (set.reps == null || set.reps! <= 0) {
            return '$name tiene una serie sin reps.'; // i18n
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

    // Legacy field derivation mirrors mobile's buildRoutineSlot.
    final int targetRepsMin;
    final int targetRepsMax;
    final List<int> targetReps;
    int? durationSeconds;
    if (isDuration) {
      targetRepsMin = 0;
      targetRepsMax = 0;
      targetReps = const [];
      durationSeconds =
          slot.sets.isEmpty ? null : slot.sets.first.durationSeconds;
    } else if (isRange) {
      final mins = slot.sets.map((s) => s.repsMin ?? 0).toList();
      final maxs = slot.sets.map((s) => s.repsMax ?? 0).toList();
      targetRepsMin = mins.isEmpty ? 0 : mins.reduce((a, b) => a < b ? a : b);
      targetRepsMax = maxs.isEmpty ? 0 : maxs.reduce((a, b) => a > b ? a : b);
      targetReps = const [];
    } else {
      final reps = slot.sets.map((s) => s.reps ?? 0).toList();
      targetRepsMin = reps.isEmpty ? 0 : reps.reduce((a, b) => a < b ? a : b);
      targetRepsMax = reps.isEmpty ? 0 : reps.reduce((a, b) => a > b ? a : b);
      targetReps = reps;
    }

    final specs = slot.sets.map((s) {
      if (isDuration) return SetSpec(durationSeconds: s.durationSeconds);
      if (isRange) {
        return SetSpec(
            repsMin: s.repsMin, repsMax: s.repsMax, weightKg: s.weightKg);
      }
      return SetSpec(reps: s.reps, weightKg: s.weightKg);
    }).toList();
    final notes = slot.notes.trim();

    return RoutineSlot(
      exerciseId: exercise.id,
      exerciseName: exercise.name,
      muscleGroup: exercise.muscleGroup,
      targetSets: specs.length,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      restSeconds: slot.restSeconds,
      supersetGroup: supersetGroup,
      targetWeightKg: isDuration || specs.isEmpty ? null : specs.first.weightKg,
      targetReps: targetReps,
      durationSeconds: durationSeconds,
      exerciseMode: slot.exerciseMode,
      repMode: slot.repMode,
      notes: notes.isEmpty ? null : notes,
      sets: specs,
      // weeklySets/activeWeeks default to empty ([] = single-week / all weeks).
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
        // numWeeks — the guard [isRoutineWebEditable] already ensured the plan
        // had no advanced `days` data to lose.
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
                                for (var i = 0; i < _days.length; i++) ...[
                                  _DayCard(
                                    day: _days[i],
                                    palette: palette,
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
              'Misma rutina cada semana.', // i18n
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
  });

  final _EditorDay day;
  final AppPalette palette;
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
  });

  final _EditorSlot slot;
  final AppPalette palette;
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

  @override
  Widget build(BuildContext context) {
    final exercise = slot.exercise;
    return Container(
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
          for (var i = 0; i < slot.sets.length; i++)
            _SetRow(
              index: i,
              set: slot.sets[i],
              palette: palette,
              exerciseMode: slot.exerciseMode,
              repMode: slot.repMode,
              canRemove: slot.sets.length > 1,
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
  }
}

// ── Set row ────────────────────────────────────────────────────────────────

class _SetRow extends StatelessWidget {
  const _SetRow({
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
