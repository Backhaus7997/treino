import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../insights/domain/muscle_group.dart';
import '../../../workout/presentation/workout_strings.dart';

/// Shows a single-select bottom sheet for filtering exercises by muscle group.
///
/// Returns the chosen [MuscleGroupDisplay], or `null` if the user taps
/// "Todos los músculos" (reset) or dismisses the sheet.
///
/// REQ-RER-005, REQ-RER-008, ADR-RER-06.
Future<MuscleGroupDisplay?> showMuscleFilterSheet(
  BuildContext context, {
  MuscleGroupDisplay? current,
}) {
  return showModalBottomSheet<MuscleGroupDisplay>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MuscleFilterSheetContent(current: current),
  );
}

class _MuscleFilterSheetContent extends StatelessWidget {
  const _MuscleFilterSheetContent({this.current});

  final MuscleGroupDisplay? current;

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
                  WorkoutStrings.pickerMuscleSheetTitle,
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
                        WorkoutStrings.pickerMuscleAll,
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
                    // One row per muscle group
                    for (final group in MuscleGroupDisplay.displayOrder)
                      ListTile(
                        leading: Image.asset(
                          _MuscleAsset.of(group),
                          width: 28,
                          height: 28,
                        ),
                        title: Text(
                          group.displayLabel,
                          style: GoogleFonts.barlow(
                            color: palette.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: current == group
                            ? Icon(
                                Icons.check,
                                size: 16,
                                color: palette.accent,
                              )
                            : null,
                        onTap: () => Navigator.of(context).pop(group),
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
