import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../l10n/app_l10n.dart';

/// "DE TU COACH" pill — marks trainer-sourced routines/templates across the
/// workout surfaces (unified RUTINAS list, PLANTILLAS grid). Highlight color
/// on purpose: coach ownership speaks magenta, the ACTIVA state speaks mint.
///
/// Extracted from RutinasSection's private chip (workout redesign slice 1) so
/// the PLANTILLAS grid badge reuses the exact same visual + l10n key.
class CoachChip extends StatelessWidget {
  const CoachChip({required this.routineId, super.key});

  final String routineId;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: Key('routine_coach_chip_$routineId'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: palette.highlight.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: palette.highlight.withValues(alpha: 0.5)),
      ),
      child: Text(
        AppL10n.of(context).workoutRutinasCoachChip,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 1.2,
          color: palette.highlight,
        ),
      ),
    );
  }
}
