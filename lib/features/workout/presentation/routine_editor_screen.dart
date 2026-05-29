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
import '../domain/exercise.dart';
import '../domain/routine.dart';
import '../domain/routine_day.dart';
import '../domain/routine_slot.dart';
import '../domain/routine_source.dart';
import '../domain/routine_visibility.dart';

// ── Mutable local state classes ───────────────────────────────────────────────

class _EditableSlot {
  Exercise? exercise;
  int targetSets = 3;
  int targetRepsMin = 8;
  int targetRepsMax = 12;
  int restSeconds = 60;

  _EditableSlot();
}

class _EditableDay {
  int dayNumber;
  String name;
  List<_EditableSlot> slots = [];

  _EditableDay({required this.dayNumber, required this.name});
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// Full-screen plan builder for trainers.
///
/// Lives inside the ShellRoute — NO own Scaffold (bottom bar provided by
/// shell). Uses local StatefulWidget state for the mutable form. Submits via
/// `RoutineRepository.createAssigned` and pops back on success.
///
/// REQ-COACH-PLANS-023..028 · SCENARIO-457..463.
class RoutineEditorScreen extends StatefulWidget {
  const RoutineEditorScreen({super.key, required this.athleteId});

  final String athleteId;

  @override
  State<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends State<RoutineEditorScreen> {
  String _name = '';
  String _split = '';
  int _daysPerWeek = 3;
  ExperienceLevel _level = ExperienceLevel.beginner;
  List<_EditableDay> _days = [_EditableDay(dayNumber: 1, name: 'Día 1')];
  bool _submitting = false;

  bool get _isValid {
    if (_name.trim().isEmpty || _split.trim().isEmpty) return false;
    if (_days.isEmpty) return false;
    for (final day in _days) {
      if (day.slots.isEmpty) return false;
      for (final slot in day.slots) {
        if (slot.exercise == null) return false;
        if (slot.targetSets < 1) return false;
        if (slot.targetRepsMin < 1) return false;
        if (slot.targetRepsMax < slot.targetRepsMin) return false;
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

  void _addSlot(int dayIndex) {
    setState(() {
      _days[dayIndex].slots = [..._days[dayIndex].slots, _EditableSlot()];
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

  Future<void> _pickExercise(
      BuildContext context, int dayIndex, int slotIndex) async {
    final exercise = await showExercisePicker(context);
    if (exercise != null && mounted) {
      setState(() {
        _days[dayIndex].slots[slotIndex].exercise = exercise;
      });
    }
  }

  Future<void> _submit(WidgetRef ref) async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);

    final trainerUid = ref.read(currentUidProvider) ?? '';
    final routine = Routine(
      id: '',
      name: _name.trim(),
      split: _split.trim(),
      level: _level,
      days: _days
          .map((d) => RoutineDay(
                dayNumber: d.dayNumber,
                name: d.name,
                slots: d.slots
                    .map((s) => RoutineSlot(
                          exerciseId: s.exercise!.id,
                          exerciseName: s.exercise!.name,
                          muscleGroup: s.exercise!.muscleGroup,
                          targetSets: s.targetSets,
                          targetRepsMin: s.targetRepsMin,
                          targetRepsMax: s.targetRepsMax,
                          restSeconds: s.restSeconds,
                        ))
                    .toList(),
              ))
          .toList(),
      source: RoutineSource.trainerAssigned,
      assignedBy: trainerUid,
      assignedTo: widget.athleteId,
      visibility: RoutineVisibility.private,
    );

    try {
      final created =
          await ref.read(routineRepositoryProvider).createAssigned(routine);
      ref.read(analyticsServiceProvider).logPlanAssigned(
            routineId: created.id,
            assignedBy: trainerUid,
            assignedTo: widget.athleteId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(CoachStrings.createPlanSuccess)),
      );
      context.pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(CoachStrings.createPlanError)),
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
                    CoachStrings.editorTitle,
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
                  // ── Row: Name + Split (side by side to save vertical space) ─
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
                              style: GoogleFonts.barlow(
                                color: palette.textPrimary,
                                fontSize: 13,
                              ),
                              decoration: _inputDecoration(
                                palette,
                                hint: 'Ej: Fuerza PPL',
                              ),
                              onChanged: (v) => setState(() => _name = v),
                            ),
                          ],
                        ),
                      ),
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
                              style: GoogleFonts.barlow(
                                color: palette.textPrimary,
                                fontSize: 13,
                              ),
                              decoration: _inputDecoration(
                                palette,
                                hint: 'PPL / Full Body',
                              ),
                              onChanged: (v) => setState(() => _split = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── Row: Days/week + Level (side by side) ─────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionLabel(label: 'DÍAS/SEM', palette: palette),
                            const SizedBox(height: 4),
                            _DaysPerWeekSelector(
                              value: _daysPerWeek,
                              palette: palette,
                              onChanged: (v) =>
                                  setState(() => _daysPerWeek = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
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
                  const SizedBox(height: 12),

                  // ── Días del plan ─────────────────────────────────────────
                  _SectionLabel(label: 'DÍAS DEL PLAN', palette: palette),
                  const SizedBox(height: 6),

                  for (int di = 0; di < _days.length; di++) ...[
                    _DayExpansionTile(
                      day: _days[di],
                      palette: palette,
                      onAddSlot: () => _addSlot(di),
                      onRemoveSlot: (si) => _removeSlot(di, si),
                      onPickExercise: (si) => _pickExercise(context, di, si),
                      onRemoveDay:
                          _days.length > 1 ? () => _removeDay(di) : null,
                      onSlotChanged: () => setState(() {}),
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
                          CoachStrings.editorSubmit,
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
    required this.onPickExercise,
    required this.onRemoveDay,
    required this.onSlotChanged,
  });

  final _EditableDay day;
  final AppPalette palette;
  final VoidCallback onAddSlot;
  final void Function(int slotIndex) onRemoveSlot;
  final void Function(int slotIndex) onPickExercise;
  final VoidCallback? onRemoveDay;
  final VoidCallback onSlotChanged;

  @override
  State<_DayExpansionTile> createState() => _DayExpansionTileState();
}

class _DayExpansionTileState extends State<_DayExpansionTile> {
  bool _expanded = true;

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
                  for (int si = 0; si < widget.day.slots.length; si++) ...[
                    _SlotEditor(
                      slot: widget.day.slots[si],
                      palette: palette,
                      onPickExercise: () => widget.onPickExercise(si),
                      onRemove: () => widget.onRemoveSlot(si),
                      onChanged: widget.onSlotChanged,
                    ),
                    const SizedBox(height: 8),
                  ],
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
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Slot editor row ───────────────────────────────────────────────────────────

class _SlotEditor extends StatelessWidget {
  const _SlotEditor({
    required this.slot,
    required this.palette,
    required this.onPickExercise,
    required this.onRemove,
    required this.onChanged,
  });

  final _EditableSlot slot;
  final AppPalette palette;
  final VoidCallback onPickExercise;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
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
                child: InkWell(
                  onTap: onPickExercise,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
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
              ),
              const SizedBox(width: 6),
              IconButton(
                icon:
                    Icon(TreinoIcon.trash, size: 16, color: palette.textMuted),
                onPressed: onRemove,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _SmallIntField(
                label: 'Series',
                value: slot.targetSets,
                palette: palette,
                onChanged: (v) {
                  slot.targetSets = v;
                  onChanged();
                },
              ),
              const SizedBox(width: 6),
              _SmallIntField(
                label: 'Rep min',
                value: slot.targetRepsMin,
                palette: palette,
                onChanged: (v) {
                  slot.targetRepsMin = v;
                  onChanged();
                },
              ),
              const SizedBox(width: 6),
              _SmallIntField(
                label: 'Rep max',
                value: slot.targetRepsMax,
                palette: palette,
                onChanged: (v) {
                  slot.targetRepsMax = v;
                  onChanged();
                },
              ),
              const SizedBox(width: 6),
              _SmallIntField(
                label: 'Descanso',
                value: slot.restSeconds,
                palette: palette,
                onChanged: (v) {
                  slot.restSeconds = v;
                  onChanged();
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

// ── Days per week selector ────────────────────────────────────────────────────

class _DaysPerWeekSelector extends StatelessWidget {
  const _DaysPerWeekSelector({
    required this.value,
    required this.palette,
    required this.onChanged,
  });

  final int value;
  final AppPalette palette;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: List.generate(7, (i) {
        final day = i + 1;
        final selected = day == value;
        return GestureDetector(
          onTap: () => onChanged(day),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? palette.accent : palette.bgCard,
              border: Border.all(
                color: selected ? palette.accent : palette.border,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '$day',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: selected ? palette.bg : palette.textPrimary,
              ),
            ),
          ),
        );
      }),
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
