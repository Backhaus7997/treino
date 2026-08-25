import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../l10n/app_l10n.dart';

/// "DE TU COACH" pill — marks trainer-sourced routines/templates across the
/// workout surfaces (unified RUTINAS list, PLANTILLAS grid). Highlight color
/// on purpose: coach ownership speaks magenta, the ACTIVA state speaks mint.
///
/// Extracted from RutinasSection's private chip (workout redesign slice 1) so
/// the PLANTILLAS grid badge reuses the exact same visual + l10n key.
///
/// [variant] distinguishes MY coach from any trainer in the community
/// catalogue (slice 3): same pill, different label and color, so the athlete
/// can tell "the person who trains me" from "someone else's trainer".
class CoachChip extends StatelessWidget {
  const CoachChip({
    required this.routineId,
    this.variant = CoachChipVariant.myCoach,
    super.key,
  });

  final String routineId;
  final CoachChipVariant variant;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isMyCoach = variant == CoachChipVariant.myCoach;
    // Community templates speak accent (mint): they are catalogue content,
    // not the personal-coach relationship magenta stands for.
    final color = isMyCoach ? palette.highlight : palette.accent;
    return Container(
      key: Key(
        isMyCoach
            ? 'routine_coach_chip_$routineId'
            : 'routine_trainer_chip_$routineId',
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        isMyCoach
            ? AppL10n.of(context).workoutRutinasCoachChip
            : AppL10n.of(context).workoutPlantillasTrainerChip,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 1.2,
          color: color,
        ),
      ),
    );
  }
}

/// Which kind of trainer authored the badged template.
enum CoachChipVariant {
  /// The athlete's own linked trainer → "DE TU COACH" (magenta).
  myCoach,

  /// Any trainer who published to the community catalogue → "ENTRENADOR".
  communityTrainer,
}
