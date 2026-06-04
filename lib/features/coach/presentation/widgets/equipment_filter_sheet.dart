import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../workout/domain/equipment_type.dart';
import '../../../workout/presentation/workout_strings.dart';

/// Shows a MULTI-select bottom sheet for filtering exercises by equipment.
///
/// Accumulates selections — tap to toggle each type in/out, then tap
/// "Aplicar" to apply and close. Tap "Limpiar" to reset.
/// Returns the chosen set of equipment types, or `null` if dismissed.
///
/// REQ-RER-006, REQ-RER-009, ADR-RER-06 (refined for multi-select per user
/// feedback during PR2 smoke).
Future<Set<EquipmentType>?> showEquipmentFilterSheet(
  BuildContext context, {
  Set<EquipmentType> current = const {},
}) {
  return showModalBottomSheet<Set<EquipmentType>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EquipmentFilterSheetContent(current: current),
  );
}

class _EquipmentFilterSheetContent extends StatefulWidget {
  const _EquipmentFilterSheetContent({required this.current});

  final Set<EquipmentType> current;

  @override
  State<_EquipmentFilterSheetContent> createState() =>
      _EquipmentFilterSheetContentState();
}

class _EquipmentFilterSheetContentState
    extends State<_EquipmentFilterSheetContent> {
  late Set<EquipmentType> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.current};
  }

  void _toggle(EquipmentType type) {
    setState(() {
      if (_selected.contains(type)) {
        _selected.remove(type);
      } else {
        _selected.add(type);
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
                        WorkoutStrings.pickerEquipmentSheetTitle,
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
              // Scrollable list of equipment types (multi-select)
              Flexible(
                child: ListView(
                  controller: scrollController,
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    for (final type in EquipmentType.values)
                      _EquipmentRow(
                        type: type,
                        selected: _selected.contains(type),
                        onTap: () => _toggle(type),
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

class _EquipmentRow extends StatelessWidget {
  const _EquipmentRow({
    required this.type,
    required this.selected,
    required this.onTap,
    required this.palette,
  });

  final EquipmentType type;
  final bool selected;
  final VoidCallback onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            Icon(
              _EquipmentIcon.of(type),
              size: 22,
              color: palette.textPrimary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                type.label,
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

/// Maps an [EquipmentType] to a [TreinoIcon] alias.
/// equipDumbbell and equipBarbell share the same Phosphor barbell icon;
/// the row label disambiguates.
class _EquipmentIcon {
  static IconData of(EquipmentType type) => switch (type) {
        EquipmentType.mancuerna => TreinoIcon.equipDumbbell,
        EquipmentType.barra => TreinoIcon.equipBarbell,
        EquipmentType.maquina => TreinoIcon.equipMachine,
        EquipmentType.cable => TreinoIcon.equipCable,
        EquipmentType.banda => TreinoIcon.equipBand,
        EquipmentType.pesoCorporal => TreinoIcon.equipBodyweight,
        EquipmentType.cardio => TreinoIcon.equipCardio,
        EquipmentType.otro => TreinoIcon.equipOther,
        EquipmentType.ninguno => TreinoIcon.equipNone,
      };
}
