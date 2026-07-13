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
import '../../../../workout/domain/set_spec.dart';
import '../../widgets/exercise_picker_dialog.dart';
import 'routine_web_editability.dart';

/// Web MVP del editor de rutinas — crea o edita la rutina de UN alumno
/// (mirrors mobile's `RoutineEditorScreen(TrainerAssigning)`, alcance reducido
/// a pedido: **una sola semana, sets normales** — sin supersets, sin
/// periodización por semana, sin modos duración/rango de reps). El editor
/// completo de mobile (~4900 líneas entre editor + picker) tiene un sistema
/// de periodización real (REQ-PERIOD-*, ADR-WPRES-*); portarlo entero es un
/// desarrollo mucho más grande, deferido a propósito.
///
/// **Modo edición** (`routineId != null`): carga la rutina y la abre en el
/// form. Como `updateAssigned` pisa el array `days` entero, editar una rutina
/// con periodización/supersets desde acá la truncaría silenciosamente — por eso
/// [isRoutineWebEditable] actúa de compuerta: si la rutina usa campos avanzados,
/// el editor NO la carga y muestra un aviso para editarla en la app mobile.
/// Las rutinas creadas en web son siempre simples, así que se editan sin drama.
///
/// La `Routine` que este editor escribe es 100% válida para el modelo de
/// dominio completo (numWeeks: 1, weeklySets/activeWeeks vacíos = "todas las
/// semanas", exerciseMode/repMode en sus defaults) — mobile puede leerla y
/// editarla sin problema; lo que este editor NO expone es control fino sobre
/// esos campos avanzados.
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
  int? reps;
}

class _EditorSlot {
  Exercise? exercise;
  int restSeconds = 0;
  List<_EditorSet> sets = [_EditorSet()];
}

class _EditorDay {
  _EditorDay({required this.dayNumber, required this.name});
  int dayNumber;
  String name;
  List<_EditorSlot> slots = [];
}

const _kMaxDays = 7; // mirrors mobile's _kMaxDays

class _RoutineEditorWebScreenState
    extends ConsumerState<RoutineEditorWebScreen> {
  final _nameCtrl = TextEditingController();
  final _splitCtrl = TextEditingController();
  ExperienceLevel _level = ExperienceLevel.beginner;
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
    _days
      ..clear()
      ..addAll(routine.days.map(_editorDayFrom));
    if (_days.isEmpty) {
      _days.add(_EditorDay(dayNumber: 1, name: 'Día 1')); // i18n
    }
  }

  _EditorDay _editorDayFrom(RoutineDay day) {
    return _EditorDay(dayNumber: day.dayNumber, name: day.name)
      ..slots = day.slots.map(_editorSlotFrom).toList();
  }

  _EditorSlot _editorSlotFrom(RoutineSlot slot) {
    final sets = slot.effectiveSets
        .map((s) => _EditorSet()
          ..reps = s.reps
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
          if (set.reps == null || set.reps! <= 0) {
            return '${slot.exercise?.name ?? 'Un ejercicio'} tiene una serie sin reps.'; // i18n
          }
        }
      }
    }
    return null;
  }

  // ── Submit ───────────────────────────────────────────────────────────────

  RoutineSlot _buildSlot(_EditorSlot slot) {
    final exercise = slot.exercise!;
    final specs = slot.sets
        .map((s) => SetSpec(reps: s.reps, weightKg: s.weightKg))
        .toList();
    final reps = specs.map((s) => s.reps ?? 0).toList();
    return RoutineSlot(
      exerciseId: exercise.id,
      exerciseName: exercise.name,
      muscleGroup: exercise.muscleGroup,
      targetSets: specs.length,
      targetRepsMin: reps.isEmpty ? 0 : reps.reduce((a, b) => a < b ? a : b),
      targetRepsMax: reps.isEmpty ? 0 : reps.reduce((a, b) => a > b ? a : b),
      restSeconds: slot.restSeconds,
      targetWeightKg: specs.isEmpty ? null : specs.first.weightKg,
      targetReps: reps,
      sets: specs,
      // exerciseMode/repMode default to reps/single; weeklySets/activeWeeks
      // default to empty ([] = single-week / "present in all weeks").
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

    final days = _days
        .map((d) => RoutineDay(
              dayNumber: d.dayNumber,
              name: d.name,
              slots: d.slots
                  .where((s) => s.exercise != null)
                  .map(_buildSlot)
                  .toList(),
            ))
        .toList();

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
          numWeeks: 1,
        );
        await repo.updateAssigned(uid: trainerUid, draft: draft);
      } else {
        final routine = Routine(
          id: '',
          name: _nameCtrl.text.trim(),
          split: _splitCtrl.text.trim(),
          level: _level,
          days: days,
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
                                    onSetWeightChanged: (s, set, v) =>
                                        _onSetWeightChanged(i, s, set, v),
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
    required this.onSetWeightChanged,
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
      onSetWeightChanged;

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
              onRemove: () => onRemoveSlot(i),
              onMoveUp: () => onMoveSlot(i, -1),
              onMoveDown: () => onMoveSlot(i, 1),
              onRestChanged: (v) => onRestChanged(i, v),
              onAddSet: () => onAddSet(i),
              onRemoveSet: (set) => onRemoveSet(i, set),
              onSetRepsChanged: (set, v) => onSetRepsChanged(i, set, v),
              onSetWeightChanged: (set, v) => onSetWeightChanged(i, set, v),
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
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRestChanged,
    required this.onAddSet,
    required this.onRemoveSet,
    required this.onSetRepsChanged,
    required this.onSetWeightChanged,
  });

  final _EditorSlot slot;
  final AppPalette palette;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final ValueChanged<String> onRestChanged;
  final VoidCallback onAddSet;
  final void Function(int setIndex) onRemoveSet;
  final void Function(int setIndex, String value) onSetRepsChanged;
  final void Function(int setIndex, String value) onSetWeightChanged;

  @override
  Widget build(BuildContext context) {
    final exercise = slot.exercise;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(10),
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
              canRemove: slot.sets.length > 1,
              onRemove: () => onRemoveSet(i),
              onRepsChanged: (v) => onSetRepsChanged(i, v),
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
    required this.canRemove,
    required this.onRemove,
    required this.onRepsChanged,
    required this.onWeightChanged,
  });

  final int index;
  final _EditorSet set;
  final AppPalette palette;
  final bool canRemove;
  final VoidCallback onRemove;
  final ValueChanged<String> onRepsChanged;
  final ValueChanged<String> onWeightChanged;

  @override
  Widget build(BuildContext context) {
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
          Expanded(
            child: TextFormField(
              initialValue: set.reps?.toString() ?? '',
              keyboardType: TextInputType.number,
              onChanged: onRepsChanged,
              style:
                  GoogleFonts.barlow(color: palette.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'reps', // i18n
                hintStyle:
                    GoogleFonts.barlow(color: palette.textMuted, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: set.weightKg?.toString() ?? '',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: onWeightChanged,
              style:
                  GoogleFonts.barlow(color: palette.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'kg', // i18n
                hintStyle:
                    GoogleFonts.barlow(color: palette.textMuted, fontSize: 12),
              ),
            ),
          ),
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
}
