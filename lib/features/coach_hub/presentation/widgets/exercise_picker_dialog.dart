// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../workout/application/custom_exercise_providers.dart';
import '../../../workout/application/exercise_filter.dart';
import '../../../workout/application/exercise_providers.dart';
import '../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../../workout/domain/custom_exercise.dart';
import '../../../workout/domain/equipment_type.dart';
import '../../../workout/domain/exercise.dart';
import '../../../workout/domain/muscle_group.dart';
import '../sections/biblioteca/widgets/exercise_detail_dialog.dart'
    show showExerciseDetailDialog;

/// Web equivalent of [showExercisePicker] (mobile's `exercise_picker_sheet.dart`
/// bottom sheet) — a multi-select exercise picker for the Coach Hub routine
/// editor. Same contract: returns the confirmed [List<Exercise>], or `null` if
/// dismissed without confirming.
///
/// ADR-CHW-005: no bottom sheet on web — muscle/equipment filters render as
/// INLINE chips (mirrors [BibliotecaFilterChips]' visual language) with LOCAL
/// widget state, not the global `bibliotecaMuscleFilterProvider` /
/// `bibliotecaEquipmentFilterProvider` — those are scoped to the Biblioteca
/// section's own lifecycle and would leak stale filter state into an
/// independently-opened dialog.
///
/// Reuses the same low-level building blocks as the mobile picker
/// (`exerciseMatchesFilters`, `customToExercise`, `exercisesProvider`,
/// `customExercisesForTrainerStreamProvider`) so search/filter BEHAVIOR is
/// identical — only the presentation container (dialog vs. sheet) differs.
///
/// NOT ported in this pass: inline "crear ejercicio nuevo" (mobile opens
/// `CustomExerciseEditorScreen`, an 892-line mobile-styled screen) — deferred;
/// trainers can still browse existing custom exercises here, just not create
/// one from inside the picker yet.
Future<List<Exercise>?> showExercisePickerDialog(
  BuildContext context, {
  Set<String> alreadySelectedIds = const {},
}) {
  return showDialog<List<Exercise>>(
    context: context,
    builder: (_) =>
        _ExercisePickerDialog(alreadySelectedIds: alreadySelectedIds),
  );
}

class _ExercisePickerDialog extends ConsumerStatefulWidget {
  const _ExercisePickerDialog({required this.alreadySelectedIds});

  final Set<String> alreadySelectedIds;

  @override
  ConsumerState<_ExercisePickerDialog> createState() =>
      _ExercisePickerDialogState();
}

class _ExercisePickerDialogState extends ConsumerState<_ExercisePickerDialog> {
  String _query = '';
  Set<MuscleGroup> _muscleFilters = {};
  Set<EquipmentType> _equipmentFilters = {};
  late Set<String> _selected;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = {...widget.alreadySelectedIds};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(Exercise e) => exerciseMatchesFilters(
        e,
        query: _query,
        muscles: _muscleFilters,
        equipment: _equipmentFilters,
      );

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _confirm(List<Exercise> defaults, List<CustomExercise> customs) {
    final result = <Exercise>[];
    for (final id in _selected) {
      final fromDefaults = _exerciseWithId(defaults, id);
      if (fromDefaults != null) {
        result.add(fromDefaults);
        continue;
      }
      final fromCustom = _customWithId(customs, id);
      if (fromCustom != null) {
        result.add(customToExercise(fromCustom));
      }
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';
    final defaultsAsync = ref.watch(exercisesProvider);
    final customsAsync = uid.isEmpty
        ? const AsyncValue<List<CustomExercise>>.data(<CustomExercise>[])
        : ref.watch(customExercisesForTrainerStreamProvider(uid));

    // 10 muscle groups + 13 equipment types wrap into several chip rows at
    // this dialog's width — a fixed height doesn't leave the exercise list
    // enough room. Size against the viewport (capped) so the Expanded list
    // always gets adequate space regardless of how many rows the chips wrap
    // into.
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final dialogHeight = (viewportHeight * 0.85).clamp(520.0, 780.0);

    return Dialog(
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: SizedBox(
        width: 560,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Elegir ejercicios', // i18n
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar', // i18n
                    icon: Icon(TreinoIcon.close, color: palette.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // ── Search ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.barlow(
                    color: palette.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  prefixIcon: Icon(TreinoIcon.search, color: palette.textMuted),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(TreinoIcon.close,
                              color: palette.textMuted, size: 18),
                          tooltip: 'Borrar', // i18n
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  hintText: 'Buscar ejercicio…', // i18n
                  hintStyle: GoogleFonts.barlow(
                      color: palette.textMuted, fontSize: 14),
                  filled: true,
                  fillColor: palette.bg,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
            // ── Inline filter chips (ADR-CHW-005 — no bottom sheet) ────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: _InlineFilters(
                palette: palette,
                muscleFilters: _muscleFilters,
                equipmentFilters: _equipmentFilters,
                onMuscleChanged: (v) => setState(() => _muscleFilters = v),
                onEquipmentChanged: (v) =>
                    setState(() => _equipmentFilters = v),
              ),
            ),
            const Divider(height: 1),
            // ── List ─────────────────────────────────────────────────────
            Expanded(
              child: _buildList(
                palette: palette,
                defaults: defaultsAsync,
                customs: customsAsync,
              ),
            ),
            // ── Footer ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: palette.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancelar', // i18n
                      style: GoogleFonts.barlow(color: palette.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => _confirm(
                              defaultsAsync.valueOrNull ?? const [],
                              customsAsync.valueOrNull ?? const [],
                            ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.bg,
                      disabledBackgroundColor:
                          palette.accent.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    child: Text(
                      _selected.isEmpty
                          ? 'Agregar' // i18n
                          : 'Agregar (${_selected.length})', // i18n
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList({
    required AppPalette palette,
    required AsyncValue<List<Exercise>> defaults,
    required AsyncValue<List<CustomExercise>> customs,
  }) {
    if (defaults.isLoading || customs.isLoading) {
      return Center(child: CircularProgressIndicator(color: palette.accent));
    }
    if (defaults.hasError) {
      return Center(
        child: Text(
          'No pudimos cargar ejercicios.', // i18n
          style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
        ),
      );
    }
    final defaultList = defaults.value ?? const <Exercise>[];
    final customList = customs.value ?? const <CustomExercise>[];

    final filteredCustoms =
        customList.where((c) => _matches(customToExercise(c))).toList();
    final filteredDefaults = defaultList.where(_matches).toList();

    if (filteredCustoms.isEmpty && filteredDefaults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'No encontramos ejercicios con esos filtros.', // i18n
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        if (filteredCustoms.isNotEmpty) ...[
          _SectionHeader('Tus ejercicios', palette: palette), // i18n
          for (final c in filteredCustoms)
            _ExerciseRow(
              id: c.id,
              name: c.name,
              subtitle: c.muscleGroup.isEmpty
                  ? null
                  : muscleGroupLabel(c.muscleGroup),
              badge: 'MÍO', // i18n
              isCustom: true,
              ownerId: ref.watch(currentUidProvider),
              selected: _selected.contains(c.id),
              palette: palette,
              onTap: () => _toggle(c.id),
            ),
        ],
        if (filteredDefaults.isNotEmpty) ...[
          _SectionHeader('Catálogo', palette: palette), // i18n
          for (final e in filteredDefaults)
            _ExerciseRow(
              id: e.id,
              name: e.name,
              subtitle: muscleGroupLabel(e.muscleGroup),
              badge: null,
              isCustom: false,
              ownerId: null,
              selected: _selected.contains(e.id),
              palette: palette,
              onTap: () => _toggle(e.id),
            ),
        ],
      ],
    );
  }
}

// ── Inline filters (ADR-CHW-005) ──────────────────────────────────────────────

class _InlineFilters extends StatelessWidget {
  const _InlineFilters({
    required this.palette,
    required this.muscleFilters,
    required this.equipmentFilters,
    required this.onMuscleChanged,
    required this.onEquipmentChanged,
  });

  final AppPalette palette;
  final Set<MuscleGroup> muscleFilters;
  final Set<EquipmentType> equipmentFilters;
  final ValueChanged<Set<MuscleGroup>> onMuscleChanged;
  final ValueChanged<Set<EquipmentType>> onEquipmentChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Chip(
              label: 'TODOS', // i18n
              active: muscleFilters.isEmpty,
              palette: palette,
              onTap: () => onMuscleChanged(const {}),
            ),
            for (final muscle in MuscleGroup.displayOrder)
              _Chip(
                label: muscle.label.toUpperCase(), // i18n
                active: muscleFilters.contains(muscle),
                palette: palette,
                onTap: () {
                  final next = Set<MuscleGroup>.from(muscleFilters);
                  if (!next.remove(muscle)) next.add(muscle);
                  onMuscleChanged(next);
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Chip(
              label: 'TODOS', // i18n
              active: equipmentFilters.isEmpty,
              palette: palette,
              onTap: () => onEquipmentChanged(const {}),
            ),
            for (final equip in EquipmentType.values)
              _Chip(
                label: equip.label.toUpperCase(), // i18n
                active: equipmentFilters.contains(equip),
                palette: palette,
                onTap: () {
                  final next = Set<EquipmentType>.from(equipmentFilters);
                  if (!next.remove(equip)) next.add(equip);
                  onEquipmentChanged(next);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool active;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? palette.accent : palette.border,
            width: active ? 1.5 : 1,
          ),
          color: active ? palette.accent.withValues(alpha: 0.12) : palette.bg,
        ),
        child: Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: active ? palette.accent : palette.textMuted,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

// ── Exercise row ───────────────────────────────────────────────────────────

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.badge,
    required this.isCustom,
    required this.ownerId,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String id;
  final String name;
  final String? subtitle;
  final String? badge;
  final bool isCustom;
  final String? ownerId;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: Icon(
            selected ? TreinoIcon.check : TreinoIcon.dumbbell,
            color: selected ? palette.accent : palette.textMuted,
            size: 20,
          ),
          title: Text(
            name,
            style: GoogleFonts.barlow(
              color: palette.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: subtitle != null && subtitle!.isNotEmpty
              ? Text(subtitle!,
                  style: GoogleFonts.barlow(
                      color: palette.textMuted, fontSize: 12))
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge!,
                    style: GoogleFonts.barlowCondensed(
                      color: palette.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              IconButton(
                tooltip: 'Ver detalle', // i18n
                icon: Icon(TreinoIcon.chartBar,
                    size: 16, color: palette.textMuted),
                visualDensity: VisualDensity.compact,
                onPressed: () => showExerciseDetailDialog(
                  context,
                  exerciseId: id,
                  ownerId: isCustom ? ownerId : null,
                  exerciseName: name,
                ),
              ),
            ],
          ),
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
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.barlowCondensed(
          color: palette.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// No `package:collection` dependency in this project (mirrors the mobile
// picker's own `_FirstWhereOrNull` extension) — plain manual lookups instead.
Exercise? _exerciseWithId(List<Exercise> items, String id) {
  for (final e in items) {
    if (e.id == id) return e;
  }
  return null;
}

CustomExercise? _customWithId(List<CustomExercise> items, String id) {
  for (final c in items) {
    if (c.id == id) return c;
  }
  return null;
}
