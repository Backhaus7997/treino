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
import '../../../workout/presentation/custom_exercise_editor_screen.dart';
import '../../../workout/presentation/exercise_detail_screen.dart';
import '../../../../l10n/app_l10n.dart';
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
///
/// Search uses [foldSearch] from `exercise_filter.dart` — lowercases and
/// strips Spanish diacritics (ADR-BIBW-01 extraction).

Future<List<Exercise>?> showExercisePicker(
  BuildContext context, {
  Set<String> alreadySelectedIds = const {},
}) {
  return showModalBottomSheet<List<Exercise>>(
    context: context,
    useRootNavigator: true,
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

  void _clearQuery() {
    _searchController.clear();
    setState(() => _query = '');
  }

  // ── Filter predicate ───────────────────────────────────────────────────────

  // Thin delegate — logic lives in exercise_filter.dart (ADR-BIBW-01).
  bool _matches(Exercise e) => exerciseMatchesFilters(
        e,
        query: _query,
        muscles: _muscleFilters,
        equipment: _equipmentFilters,
      );

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
    final picked = await showMuscleFilterSheet(ctx, current: _muscleFilters);
    if (!mounted || picked == null) return;
    setState(() => _muscleFilters = picked);
  }

  Future<void> _openEquipmentSheet(BuildContext ctx) async {
    final picked =
        await showEquipmentFilterSheet(ctx, current: _equipmentFilters);
    if (!mounted || picked == null) return;
    setState(() => _equipmentFilters = picked);
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
    final l10n = AppL10n.of(context);
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

        return Padding(
          // Lift the whole sheet above the keyboard so the exercise list
          // stays visible while filtering by name (device feedback
          // 2026-06-11).
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom),
          child: Container(
            decoration: BoxDecoration(
              // Was palette.espresso (#3C3534) — too warm, read as gray over
              // the near-black bg behind it. Using `bg` (#0A0A0A) so the sheet
              // sits flush in the dark theme; the rounded top + drag handle
              // mark the sheet edge instead of color contrast.
              color: palette.bg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
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
                    controller: _searchController,
                    autofocus: false,
                    style: GoogleFonts.barlow(
                        color: palette.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      prefixIcon:
                          Icon(TreinoIcon.search, color: palette.textMuted),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: Icon(TreinoIcon.close,
                                  color: palette.textMuted, size: 18),
                              tooltip: 'Borrar',
                              splashRadius: 18,
                              onPressed: _clearQuery,
                            ),
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

                // ── Filter buttons row (more visible than chips) ──────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _FilterButton(
                          baseLabel: l10n.workoutPickerMuscleFilter,
                          count: _muscleFilters.length,
                          palette: palette,
                          onTap: () => _openMuscleSheet(sheetCtx),
                          onClear: _muscleFilters.isNotEmpty
                              ? () => setState(_muscleFilters.clear)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FilterButton(
                          baseLabel: l10n.workoutPickerEquipmentFilter,
                          count: _equipmentFilters.length,
                          palette: palette,
                          onTap: () => _openEquipmentSheet(sheetCtx),
                          onClear: _equipmentFilters.isNotEmpty
                              ? () => setState(_equipmentFilters.clear)
                              : null,
                        ),
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
                    l10n: l10n,
                    defaults: defaultsAsync,
                    customs: customsAsync,
                    uid: uid,
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
          ),
        );
      },
    );
  }

  Widget _buildList({
    required ScrollController scrollController,
    required AppPalette palette,
    required AppL10n l10n,
    required AsyncValue<List<Exercise>> defaults,
    required AsyncValue<List<CustomExercise>> customs,
    required String uid,
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
                l10n.workoutPickerEmptyFiltered,
                textAlign: TextAlign.center,
                style: GoogleFonts.barlow(
                    color: palette.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.workoutPickerEmptyFilteredHint,
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
              subtitle: c.muscleGroup.isEmpty
                  ? null
                  : muscleGroupLabel(c.muscleGroup),
              badge: 'MÍO',
              isCustom: true,
              ownerId: uid,
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

// ── Sub-widgets ───────────────────────────────────────────────────────────────

/// A single exercise row with multi-select visual state + illustration + a
/// detail button (Hevy-style).
/// Selected: blue 3px left border + accent tint + checkmark overlay on the
/// illustration. The trailing chartBar IconButton navigates to the exercise
/// detail screen, independent of the row's tap-to-select behaviour.
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

  void _openDetail(BuildContext context) {
    // ExerciseDetailScreen brings no Scaffold/background of its own — those are
    // provided by _ShellScaffold in the shell flow. Opening it from inside this
    // modal sheet via go_router's `context.push` mounts it in a context where it
    // never renders → full black screen (device feedback 2026-06-12). Push it
    // imperatively with its own Scaffold host instead, mirroring _openCreateNew.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: AppPalette.of(context).bg,
          body: SafeArea(
            child: ExerciseDetailScreen(
              exerciseId: id,
              ownerId: isCustom && ownerId != null && ownerId!.isNotEmpty
                  ? ownerId
                  : null,
            ),
          ),
        ),
      ),
    );
  }

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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: _ExerciseThumbnail(
            id: id,
            isCustom: isCustom,
            selected: selected,
            palette: palette,
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
              ? Text(
                  subtitle!,
                  style: GoogleFonts.barlow(
                      color: palette.textMuted, fontSize: 12),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge != null) ...[
                _Badge(label: badge!, palette: palette),
                const SizedBox(width: 8),
              ],
              IconButton(
                onPressed: () => _openDetail(context),
                icon: Icon(
                  TreinoIcon.chartBar,
                  size: 18,
                  color: palette.textMuted,
                ),
                tooltip: 'Ver detalle',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular thumbnail for an exercise row. Uses the bundled PNG illustration
/// from `assets/exercises/{id}.png` when available; falls back to a neutral
/// icon when the asset is missing (e.g. for custom exercises or unseeded ids).
/// Adds a small checkmark badge overlay when selected.
class _ExerciseThumbnail extends StatelessWidget {
  const _ExerciseThumbnail({
    required this.id,
    required this.isCustom,
    required this.selected,
    required this.palette,
  });

  final String id;
  final bool isCustom;
  final bool selected;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: Container(
              width: 44,
              height: 44,
              color: palette.bgCard,
              alignment: Alignment.center,
              child: isCustom
                  ? Icon(
                      TreinoIcon.dumbbell,
                      size: 22,
                      color: palette.textMuted,
                    )
                  : Image.asset(
                      'assets/exercises/$id.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        TreinoIcon.dumbbell,
                        size: 22,
                        color: palette.textMuted,
                      ),
                    ),
            ),
          ),
          if (selected)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: palette.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.espresso, width: 2),
                ),
                child: Icon(
                  TreinoIcon.check,
                  size: 10,
                  color: palette.bg,
                ),
              ),
            ),
        ],
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
        // Matches the sheet bg (was espresso). The top border line keeps
        // the sticky CTA visually separated from the list above it.
        color: palette.bg,
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
            AppL10n.of(context).workoutPickerAddButton(count),
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

/// Filter button — bigger and more visible than the previous pill-shaped chip.
/// Width is driven by parent (Expanded). Active state (count > 0) uses
/// accent border + filled tint + accent text; idle state is bgCard + border.
/// Label shows count when active, e.g. "Músculos (3)".
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.baseLabel,
    required this.count,
    required this.palette,
    required this.onTap,
    this.onClear,
  });

  final String baseLabel;
  final int count;
  final AppPalette palette;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    final label = active ? '$baseLabel ($count)' : baseLabel;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? palette.accent : palette.border,
            width: active ? 1.5 : 1,
          ),
          color:
              active ? palette.accent.withValues(alpha: 0.12) : palette.bgCard,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.barlowCondensed(
                  color: active ? palette.accent : palette.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (active && onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  TreinoIcon.close,
                  size: 14,
                  color: palette.accent,
                ),
              )
            else
              Icon(
                TreinoIcon.chevronDown,
                size: 14,
                color: active ? palette.accent : palette.textMuted,
              ),
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

/// Lossy adapter — delegates to [customToExercise] from exercise_filter.dart
/// (ADR-BIBW-01 extraction). Kept as a private forwarder so all internal
/// call-sites in this file compile without changes.
Exercise _toExercise(CustomExercise c) => customToExercise(c);

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
