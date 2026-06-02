import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../insights/domain/muscle_group.dart';
import '../../../workout/application/custom_exercise_providers.dart';
import '../../../workout/application/exercise_providers.dart';
import '../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../../workout/domain/custom_exercise.dart';
import '../../../workout/domain/equipment_type.dart';
import '../../../workout/domain/exercise.dart';
import '../../../workout/presentation/custom_exercise_editor_screen.dart';
import '../../../workout/presentation/workout_strings.dart';
import 'equipment_filter_sheet.dart';
import 'muscle_filter_sheet.dart';

/// Shows a modal bottom sheet for picking one or more exercises (multi-select).
///
/// Returns the confirmed [List<Exercise>], or `null` if dismissed.
/// - `null` means the user cancelled (drag-down / tap outside).
/// - Non-null means confirmed; list always has length >= 1 because the CTA is
///   disabled at count == 0.
///
/// [alreadySelectedIds] pre-marks exercises that are already in the day so
/// the user sees existing context when re-opening the picker.
///
/// ADR-RER-01, REQ-RER-001..004, REQ-RER-017.
Future<List<Exercise>?> showExercisePicker(
  BuildContext context, {
  Set<String> alreadySelectedIds = const {},
}) {
  return showModalBottomSheet<List<Exercise>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _ExercisePickerSheetContent(alreadySelectedIds: alreadySelectedIds),
  );
}

// ── Sheet content ─────────────────────────────────────────────────────────────

class _ExercisePickerSheetContent extends ConsumerStatefulWidget {
  const _ExercisePickerSheetContent({required this.alreadySelectedIds});

  final Set<String> alreadySelectedIds;

  @override
  ConsumerState<_ExercisePickerSheetContent> createState() =>
      _ExercisePickerSheetContentState();
}

class _ExercisePickerSheetContentState
    extends ConsumerState<_ExercisePickerSheetContent> {
  String _query = '';
  MuscleGroupDisplay? _muscleFilter;
  EquipmentType? _equipmentFilter;
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.alreadySelectedIds};
  }

  // ── Filter predicate ───────────────────────────────────────────────────────

  bool _matches(Exercise e) {
    final q = _query.toLowerCase().trim();
    if (q.isNotEmpty) {
      final nameMatch = e.name.toLowerCase().contains(q);
      final aliasMatch = e.aliases.any((a) => a.toLowerCase().contains(q));
      if (!nameMatch && !aliasMatch) return false;
    }
    if (_muscleFilter != null &&
        e.muscleGroup.toDisplayGroup() != _muscleFilter) {
      return false;
    }
    // ADR-RER-05: EXCLUDE exercises with null equipment when a filter is active.
    if (_equipmentFilter != null) {
      if (e.equipment == null) return false;
      if (e.equipment != _equipmentFilter) return false;
    }
    return true;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _openMuscleSheet(BuildContext ctx) async {
    final picked = await showMuscleFilterSheet(ctx, current: _muscleFilter);
    if (!mounted) return;
    setState(() => _muscleFilter = picked);
  }

  Future<void> _openEquipmentSheet(BuildContext ctx) async {
    final picked =
        await showEquipmentFilterSheet(ctx, current: _equipmentFilter);
    if (!mounted) return;
    setState(() => _equipmentFilter = picked);
  }

  void _confirm(
    List<Exercise> defaults,
    List<CustomExercise> customs,
  ) {
    final result = <Exercise>[];
    for (final id in _selected) {
      final fromDefaults = defaults.firstWhereOrNull((e) => e.id == id);
      if (fromDefaults != null) {
        result.add(fromDefaults);
        continue;
      }
      final fromCustoms = customs.firstWhereOrNull((c) => c.id == id);
      if (fromCustoms != null) {
        result.add(_toExercise(fromCustoms));
      }
    }
    Navigator.of(context).pop(result);
  }

  Future<void> _openCreateNew(
    BuildContext sheetContext,
    List<Exercise> defaults,
    List<CustomExercise> customs,
  ) async {
    final created = await Navigator.of(sheetContext).push<CustomExercise?>(
      MaterialPageRoute<CustomExercise?>(
        builder: (_) => Scaffold(
          backgroundColor: AppPalette.of(sheetContext).bg,
          body: const SafeArea(
            child: CustomExerciseEditorScreen(exerciseId: 'new'),
          ),
        ),
      ),
    );
    if (created != null && sheetContext.mounted) {
      Navigator.of(sheetContext).pop([_toExercise(created)]);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';
    final defaultsAsync = ref.watch(exercisesProvider);
    final customsAsync = uid.isEmpty
        ? const AsyncValue<List<CustomExercise>>.data(<CustomExercise>[])
        : ref.watch(customExercisesForTrainerStreamProvider(uid));

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (sheetCtx, scrollController) {
        final defaults = defaultsAsync.valueOrNull ?? const <Exercise>[];
        final customs = customsAsync.valueOrNull ?? const <CustomExercise>[];

        return Container(
          decoration: BoxDecoration(
            color: palette.espresso,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // ── Drag handle ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Search field ──────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  autofocus: true,
                  style: GoogleFonts.barlow(
                      color: palette.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    prefixIcon:
                        Icon(TreinoIcon.search, color: palette.textMuted),
                    hintText: 'Buscar ejercicio…',
                    hintStyle: GoogleFonts.barlow(
                        color: palette.textMuted, fontSize: 14),
                    filled: true,
                    fillColor: palette.bgCard,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
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
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),

              // ── Filter chips row ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    _FilterChip(
                      label: _muscleFilter != null
                          ? _muscleFilter!.displayLabel
                          : WorkoutStrings.pickerMuscleFilter,
                      active: _muscleFilter != null,
                      palette: palette,
                      onTap: () => _openMuscleSheet(sheetCtx),
                      onClear: _muscleFilter != null
                          ? () => setState(() => _muscleFilter = null)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: _equipmentFilter != null
                          ? _equipmentFilter!.label
                          : WorkoutStrings.pickerEquipmentFilter,
                      active: _equipmentFilter != null,
                      palette: palette,
                      onTap: () => _openEquipmentSheet(sheetCtx),
                      onClear: _equipmentFilter != null
                          ? () => setState(() => _equipmentFilter = null)
                          : null,
                    ),
                  ],
                ),
              ),

              // ── Create new CTA ────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: _CreateNewTile(
                  palette: palette,
                  enabled: uid.isNotEmpty,
                  onTap: uid.isEmpty
                      ? null
                      : () => _openCreateNew(sheetCtx, defaults, customs),
                ),
              ),

              // ── Exercise list ─────────────────────────────────────────────
              Expanded(
                child: _buildList(
                  scrollController: scrollController,
                  palette: palette,
                  defaults: defaultsAsync,
                  customs: customsAsync,
                ),
              ),

              // ── Sticky add CTA ────────────────────────────────────────────
              if (_selected.isNotEmpty)
                _StickyAddBar(
                  count: _selected.length,
                  palette: palette,
                  onTap: () => _confirm(defaults, customs),
                ),

              SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList({
    required ScrollController scrollController,
    required AppPalette palette,
    required AsyncValue<List<Exercise>> defaults,
    required AsyncValue<List<CustomExercise>> customs,
  }) {
    if (defaults.isLoading || customs.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: palette.accent),
      );
    }
    if (defaults.hasError) {
      return Center(
        child: Text(
          'No pudimos cargar ejercicios.',
          style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
        ),
      );
    }
    final defaultList = defaults.value ?? const <Exercise>[];
    final customList = customs.value ?? const <CustomExercise>[];

    final filteredCustoms =
        customList.where((c) => _matches(_toExercise(c))).toList();
    final filteredDefaults = defaultList.where(_matches).toList();

    if (filteredCustoms.isEmpty && filteredDefaults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                WorkoutStrings.pickerEmptyFiltered,
                textAlign: TextAlign.center,
                style: GoogleFonts.barlow(
                    color: palette.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                WorkoutStrings.pickerEmptyFilteredHint,
                textAlign: TextAlign.center,
                style:
                    GoogleFonts.barlow(color: palette.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (filteredCustoms.isNotEmpty) ...[
          _SectionHeader('Tus ejercicios', palette: palette),
          for (final c in filteredCustoms)
            _ExerciseRow(
              id: c.id,
              name: c.name,
              subtitle: c.muscleGroup.isEmpty ? null : c.muscleGroup,
              badge: 'MÍO',
              selected: _selected.contains(c.id),
              palette: palette,
              onTap: () => _toggle(c.id),
            ),
        ],
        if (filteredDefaults.isNotEmpty) ...[
          _SectionHeader('Catálogo', palette: palette),
          for (final e in filteredDefaults)
            _ExerciseRow(
              id: e.id,
              name: e.name,
              subtitle: e.muscleGroup,
              badge: null,
              selected: _selected.contains(e.id),
              palette: palette,
              onTap: () => _toggle(e.id),
            ),
        ],
      ],
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

/// A single exercise row with multi-select visual state.
/// Selected: blue 3px left border + accent tint + checkmark badge.
class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.badge,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String id;
  final String name;
  final String? subtitle;
  final String? badge;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: selected
              ? palette.accent.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: selected ? palette.accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: ListTile(
          title: Text(
            name,
            style: GoogleFonts.barlow(
              color: palette.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: subtitle != null && subtitle!.isNotEmpty
              ? Text(
                  subtitle!,
                  style: GoogleFonts.barlow(
                      color: palette.textMuted, fontSize: 12),
                )
              : null,
          trailing: selected
              ? Icon(
                  TreinoIcon.checkCircleFill,
                  size: 18,
                  color: palette.accent,
                )
              : badge != null
                  ? _Badge(label: badge!, palette: palette)
                  : null,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.palette});
  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          color: palette.accent,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Sticky CTA bar pinned at the bottom of the sheet.
class _StickyAddBar extends StatelessWidget {
  const _StickyAddBar({
    required this.count,
    required this.palette,
    required this.onTap,
  });

  final int count;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: palette.espresso,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: count > 0 ? onTap : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: palette.bg,
            disabledBackgroundColor: palette.accent.withAlpha(80),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
          child: Text(
            WorkoutStrings.pickerAddButton(count),
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill-shaped filter chip. Active state shows accent border + label is the
/// selected value name. Trailing × clears the filter without opening the sheet.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.palette,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final bool active;
  final AppPalette palette;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? palette.accent : palette.border,
            width: active ? 1.5 : 1,
          ),
          color: active
              ? palette.accent.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.barlowCondensed(
                color: active ? palette.accent : palette.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (active && onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  TreinoIcon.close,
                  size: 12,
                  color: palette.accent,
                ),
              ),
            ] else ...[
              const SizedBox(width: 4),
              Icon(
                TreinoIcon.chevronDown,
                size: 12,
                color: palette.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, {required this.palette});

  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.barlowCondensed(
          color: palette.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _CreateNewTile extends StatelessWidget {
  const _CreateNewTile({
    required this.palette,
    required this.enabled,
    required this.onTap,
  });

  final AppPalette palette;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.accent, width: 1),
          ),
          child: Row(
            children: [
              Icon(TreinoIcon.plus, size: 18, color: palette.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Crear ejercicio nuevo',
                  style: GoogleFonts.barlow(
                    color: palette.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(TreinoIcon.chevronRight,
                  size: 14, color: palette.accent.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lossy adapter — projects the fields the routine slot needs and stamps
/// `category: 'custom'` so downstream code can distinguish custom exercises.
Exercise _toExercise(CustomExercise c) {
  return Exercise(
    id: c.id,
    name: c.name,
    muscleGroup: c.muscleGroup,
    category: 'custom',
    techniqueInstructions: null,
    videoUrl: c.videoUrl,
    defaultRestSeconds: c.defaultRestSeconds,
    equipment: c.equipment,
  );
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
