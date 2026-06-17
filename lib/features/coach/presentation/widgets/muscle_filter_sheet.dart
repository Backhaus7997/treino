import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../workout/domain/muscle_group.dart';
import '../../../../l10n/app_l10n.dart';

/// Shows a MULTI-select bottom sheet for filtering exercises by muscle group.
///
/// The sheet accumulates selections — tap to toggle each muscle in/out, then
/// tap "Aplicar" to apply and close. Tap "Limpiar" to reset all and apply.
/// Returns the chosen set of muscles, or `null` if the user dismisses the
/// sheet (in which case the caller keeps the previous filter state).
///
/// REQ-RER-005, REQ-RER-008, ADR-RER-06 (refined for multi-select per user
/// feedback during PR2 smoke).
Future<Set<MuscleGroup>?> showMuscleFilterSheet(
  BuildContext context, {
  Set<MuscleGroup> current = const {},
}) {
  return showModalBottomSheet<Set<MuscleGroup>>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MuscleFilterSheetContent(current: current),
  );
}

class _MuscleFilterSheetContent extends StatefulWidget {
  const _MuscleFilterSheetContent({required this.current});

  final Set<MuscleGroup> current;

  @override
  State<_MuscleFilterSheetContent> createState() =>
      _MuscleFilterSheetContentState();
}

class _MuscleFilterSheetContentState extends State<_MuscleFilterSheetContent> {
  late Set<MuscleGroup> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.current};
  }

  void _toggle(MuscleGroup group) {
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
    final l10n = AppL10n.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            // Matches the parent exercise picker bg (was espresso).
            color: palette.bg,
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
                        l10n.workoutPickerMuscleSheetTitle,
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
                          l10n.workoutPickerSheetClear,
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
                    for (final group in MuscleGroup.displayOrder)
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
                          ? l10n.workoutPickerSheetApplyAll
                          : l10n.workoutPickerSheetApply(_selected.length),
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

  final MuscleGroup group;
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
            SizedBox(
              width: 28,
              height: 28,
              child: group.assetPath != null
                  ? Image.asset(group.assetPath!, width: 28, height: 28)
                  : Icon(TreinoIcon.dumbbell,
                      size: 24, color: palette.textMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                group.label.toUpperCase(),
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
