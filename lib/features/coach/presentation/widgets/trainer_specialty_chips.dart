import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../domain/trainer_specialty.dart';
import '../../../../l10n/app_l10n.dart';

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
/// First chip is "Todos" (empty set). Then one chip per
/// [TrainerSpecialty] value in declaration order.
///
/// **Multi-select** (cambió de single-select post-Fase 6 polish):
/// - Tap en "Todos" limpia el set (sin filtro).
/// - Tap en una specialty toggle in/out del set.
/// - Multiple specialties pueden estar seleccionadas a la vez.
///
/// Visual: selected chip uses [AppPalette.accent]; unselected uses
/// [AppPalette.bgCard] background.
///
/// Per design D11. REQ-COACH-DISC-UI-007, REQ-COACH-DISC-UI-008.
/// SCENARIO-430, SCENARIO-431.
class TrainerSpecialtyChips extends StatelessWidget {
  const TrainerSpecialtyChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  /// Currently selected specialties. Empty set = "Todos" (no filter).
  final Set<TrainerSpecialty> selected;

  /// Called when the user taps a chip. Receives the next desired set
  /// (with the tapped specialty toggled in/out). "Todos" passes empty set.
  final ValueChanged<Set<TrainerSpecialty>> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _buildChip(
            context: context,
            palette: palette,
            label: l10n.coachSpecialtyAll,
            isSelected: selected.isEmpty,
            onTap: () => onChanged(const <TrainerSpecialty>{}),
          ),
          ...TrainerSpecialty.values.map(
            (s) => _buildChip(
              context: context,
              palette: palette,
              label: SpecialtyLabels.of(s),
              isSelected: selected.contains(s),
              onTap: () {
                final next = Set<TrainerSpecialty>.from(selected);
                if (next.contains(s)) {
                  next.remove(s);
                } else {
                  next.add(s);
                }
                onChanged(next);
              },
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
        backgroundColor: palette.bgCard,
        side: BorderSide(
          color: isSelected ? palette.accent : palette.border,
        ),
        shape: const StadiumBorder(),
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
