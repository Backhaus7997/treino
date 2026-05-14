import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import 'home_cta_button.dart';

/// Hardcoded "Empezar Entrenamiento" card.
/// All strings are private static const — ready for provider-driven swap
/// without renaming the widget. Zero constructor params; no ref.watch / ref.read.
class EmpezarEntrenamientoCard extends StatelessWidget {
  const EmpezarEntrenamientoCard({super.key});

  static const _dayLabel = 'HOY · JUEVES';
  static const _heroLabel = 'PUSH';
  static const _subtitle = 'Pecho · Hombros · Tríceps';
  static const _exerciseCount = '6 ejercicios';
  static const _duration = '~55 min';
  static const _ctaLabel = 'EMPEZAR ENTRENAMIENTO';

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day label
            Text(
              _dayLabel,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                letterSpacing: 1.4,
                color: palette.accent,
              ),
            ),
            const SizedBox(height: 8),
            // Hero workout name
            Text(
              _heroLabel,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 36,
                letterSpacing: 0.5,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            // Muscle groups subtitle
            Text(
              _subtitle,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            // Stat row
            Row(
              children: [
                Icon(TreinoIcon.tabWorkout, size: 16, color: palette.textMuted),
                const SizedBox(width: 8),
                Text(
                  _exerciseCount,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(width: 18),
                Icon(TreinoIcon.clock, size: 16, color: palette.textMuted),
                const SizedBox(width: 8),
                Text(
                  _duration,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            HomeCTAButton(
              label: _ctaLabel,
              leadingIcon: TreinoIcon.play,
              onPressed: () => context.go('/workout'),
            ),
          ],
        ),
      ),
    );
  }
}
