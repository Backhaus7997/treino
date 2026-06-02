import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../workout/domain/equipment_type.dart';
import '../../../workout/presentation/workout_strings.dart';

/// Shows a single-select bottom sheet for filtering exercises by equipment type.
///
/// Returns the chosen [EquipmentType], or `null` if the user taps
/// "Todo el equipamiento" (reset) or dismisses the sheet.
///
/// REQ-RER-006, REQ-RER-009, ADR-RER-06.
Future<EquipmentType?> showEquipmentFilterSheet(
  BuildContext context, {
  EquipmentType? current,
}) {
  return showModalBottomSheet<EquipmentType>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EquipmentFilterSheetContent(current: current),
  );
}

class _EquipmentFilterSheetContent extends StatelessWidget {
  const _EquipmentFilterSheetContent({this.current});

  final EquipmentType? current;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
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
              // Title
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
              Divider(height: 1, color: palette.border),
              // Scrollable list
              Flexible(
                child: ListView(
                  controller: scrollController,
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    // Reset row
                    ListTile(
                      leading: Icon(
                        TreinoIcon.close,
                        size: 16,
                        color: palette.textMuted,
                      ),
                      title: Text(
                        WorkoutStrings.pickerEquipmentAll,
                        style: GoogleFonts.barlow(
                          color: current == null
                              ? palette.textPrimary
                              : palette.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: current == null
                          ? Icon(
                              Icons.check,
                              size: 16,
                              color: palette.accent,
                            )
                          : null,
                      onTap: () => Navigator.of(context).pop(null),
                    ),
                    // One row per EquipmentType value
                    for (final type in EquipmentType.values)
                      ListTile(
                        leading: Icon(
                          _EquipmentIcon.of(type),
                          size: 24,
                          color: palette.textPrimary,
                        ),
                        title: Text(
                          type.label,
                          style: GoogleFonts.barlow(
                            color: palette.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: current == type
                            ? Icon(
                                Icons.check,
                                size: 16,
                                color: palette.accent,
                              )
                            : null,
                        onTap: () => Navigator.of(context).pop(type),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
