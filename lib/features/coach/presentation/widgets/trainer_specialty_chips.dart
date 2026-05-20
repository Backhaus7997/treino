import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../domain/trainer_specialty.dart';
import '../coach_strings.dart';

/// Spanish UI labels for each [TrainerSpecialty].
///
/// Used by [TrainerSpecialtyChips] and [TrainerProfileHero].
/// Capitalized display form per design D11 and task T29.
abstract final class SpecialtyLabels {
  static const Map<TrainerSpecialty, String> _labels = {
    TrainerSpecialty.powerlifting: 'Powerlifting',
    TrainerSpecialty.crossfit: 'CrossFit',
    TrainerSpecialty.bodybuilding: 'Bodybuilding',
    TrainerSpecialty.hipertrofia: 'Hipertrofia',
    TrainerSpecialty.wellness: 'Wellness',
    TrainerSpecialty.kinesiologia: 'Kinesiología',
    TrainerSpecialty.funcional: 'Funcional',
    TrainerSpecialty.running: 'Running',
    TrainerSpecialty.yoga: 'Yoga',
    TrainerSpecialty.calistenia: 'Calistenia',
  };

  /// Returns the Spanish display label for [specialty].
  static String of(TrainerSpecialty specialty) => _labels[specialty]!;
}

/// Horizontal scrollable row of specialty filter chips.
///
/// First chip is "Todos" (null selection). Then one chip per
/// [TrainerSpecialty] value in declaration order.
///
/// Single-select: [onChanged] is called with `null` when "Todos" is tapped,
/// or with the [TrainerSpecialty] when a specialty chip is tapped.
///
/// Visual: selected chip uses [AppPalette.accent]; unselected uses
/// [AppPalette.espresso] background.
///
/// Per design D11. REQ-COACH-DISC-UI-007, REQ-COACH-DISC-UI-008.
/// SCENARIO-430, SCENARIO-431.
class TrainerSpecialtyChips extends StatelessWidget {
  const TrainerSpecialtyChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  /// Currently selected specialty, or null for "Todos".
  final TrainerSpecialty? selected;

  /// Called when the user taps a chip. Passes null for "Todos".
  final ValueChanged<TrainerSpecialty?> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _buildChip(
            context: context,
            palette: palette,
            label: CoachStrings.specialtyAll,
            isSelected: selected == null,
            onTap: () => onChanged(null),
          ),
          ...TrainerSpecialty.values.map(
            (s) => _buildChip(
              context: context,
              palette: palette,
              label: SpecialtyLabels.of(s),
              isSelected: selected == s,
              onTap: () => onChanged(s),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required BuildContext context,
    required AppPalette palette,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.3,
            color: isSelected ? palette.bg : palette.textPrimary,
          ),
        ),
        selected: isSelected,
        selectedColor: palette.accent,
        backgroundColor: palette.espresso,
        side: BorderSide(
          color: isSelected ? palette.accent : palette.border,
        ),
        // Pass both true/false cases — fires regardless of current selection
        onSelected: (bool newValue) {
          // Always fire callback; parent is responsible for state management.
          // When already selected, ChoiceChip passes false (deselect). For
          // "Todos" re-tap this is harmless (null→null). For specialty re-tap
          // it keeps the same selection (parent decides if it's a no-op).
          onTap();
        },
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        showCheckmark: false,
      ),
    );
  }
}
