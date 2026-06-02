import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../insights/domain/muscle_group.dart';
import '../../../workout/presentation/workout_strings.dart';

/// Shows a MULTI-select bottom sheet for filtering exercises by muscle group.
///
/// The sheet accumulates selections — tap to toggle each muscle in/out, then
/// tap "Aplicar" to apply and close. Tap "Limpiar" to reset all and apply.
/// Returns the chosen set of muscles, or `null` if the user dismisses the
/// sheet (in which case the caller keeps the previous filter state).
///
/// REQ-RER-005, REQ-RER-008, ADR-RER-06 (refined for multi-select per user
/// feedback during PR2 smoke).
Future<Set<MuscleGroupDisplay>?> showMuscleFilterSheet(
  BuildContext context, {
  Set<MuscleGroupDisplay> current = const {},
}) {
  return showModalBottomSheet<Set<MuscleGroupDisplay>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MuscleFilterSheetContent(current: current),
  );
}

class _MuscleFilterSheetContent extends StatefulWidget {
  const _MuscleFilterSheetContent({required this.current});

  final Set<MuscleGroupDisplay> current;

  @override
  State<_MuscleFilterSheetContent> createState() =>
      _MuscleFilterSheetContentState();
}

class _MuscleFilterSheetContentState extends State<_MuscleFilterSheetContent> {
  late Set<MuscleGroupDisplay> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.current};
  }

  void _toggle(MuscleGroupDisplay group) {
    setState(() {
      if (_selected.contains(group)) {
        _selected.remove(group);
      } else {
        _selected.add(group);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: palette.espresso,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
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
              // Title row + Limpiar button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        WorkoutStrings.pickerMuscleSheetTitle,
                        style: GoogleFonts.barlowCondensed(
                          color: palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                    if (_selected.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(_selected.clear),
                        child: Text(
                          WorkoutStrings.pickerSheetClear,
                          style: GoogleFonts.barlow(
                            color: palette.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: palette.border),
              // Scrollable list of muscle groups (multi-select)
              Flexible(
                child: ListView(
                  controller: scrollController,
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    for (final group in MuscleGroupDisplay.displayOrder)
                      _MuscleRow(
                        group: group,
                        selected: _selected.contains(group),
                        onTap: () => _toggle(group),
                        palette: palette,
                      ),
                  ],
                ),
              ),
              // Sticky Aplicar button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.bg,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: Text(
                      _selected.isEmpty
                          ? WorkoutStrings.pickerSheetApplyAll
                          : WorkoutStrings.pickerSheetApply(_selected.length),
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MuscleRow extends StatelessWidget {
  const _MuscleRow({
    required this.group,
    required this.selected,
    required this.onTap,
    required this.palette,
  });

  final MuscleGroupDisplay group;
  final bool selected;
  final VoidCallback onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? palette.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? palette.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Image.asset(
              _MuscleAsset.of(group),
              width: 28,
              height: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                group.displayLabel,
                style: GoogleFonts.barlow(
                  color: palette.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (selected)
              Icon(
                TreinoIcon.check,
                size: 18,
                color: palette.accent,
              ),
          ],
        ),
      ),
    );
  }
}

/// Maps a [MuscleGroupDisplay] to its PNG asset path.
/// Assets are declared in pubspec.yaml under assets/muscles/.
class _MuscleAsset {
  static String of(MuscleGroupDisplay group) => switch (group) {
        MuscleGroupDisplay.pecho => 'assets/muscles/chest.png',
        MuscleGroupDisplay.espalda => 'assets/muscles/back.png',
        MuscleGroupDisplay.piernas => 'assets/muscles/quads.png',
        MuscleGroupDisplay.brazos => 'assets/muscles/biceps.png',
        MuscleGroupDisplay.hombros => 'assets/muscles/shoulders.png',
        MuscleGroupDisplay.core => 'assets/muscles/core.png',
      };
}
