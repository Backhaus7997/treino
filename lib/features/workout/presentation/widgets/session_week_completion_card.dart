import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../l10n/app_l10n.dart';

/// Tarjeta "¡Semana cumplida!" del resumen post-entreno: la sesión que se
/// acaba de cerrar fue la que completó el objetivo de la semana en curso (ver
/// `deriveWeekCompletion`).
///
/// Es presentacional a propósito: [streak] y [onViewWeek] llegan de afuera, así
/// que la pantalla decide cuándo se muestra y adónde lleva el botón, y este
/// widget sólo dibuja. Con [streak] == 1 el subtítulo celebra la primera semana
/// en vez de hablar de una "racha de 1 semana".
class SessionWeekCompletionCard extends StatelessWidget {
  const SessionWeekCompletionCard({
    super.key,
    required this.streak,
    required this.onViewWeek,
  });

  /// Racha semanal que queda después de esta sesión (>= 1).
  final int streak;

  /// Abre el resumen de la semana (Insights).
  final VoidCallback onViewWeek;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        // `accentText` (tinta), no `accent` (relleno): en light el mint pleno
        // compone 1,57:1 contra el papel y el borde y el label del botón se
        // perderían. En dark los dos tokens son el mismo mint.
        border: Border.all(color: palette.accentText),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.workoutWeekCompletedTitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: AppTextSize.heading,
              height: 1.05,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            l10n.workoutWeekCompletedStreak(streak),
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontSize: AppTextSize.bodyDense,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.s14),
          OutlinedButton(
            onPressed: onViewWeek,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: palette.accentText),
              foregroundColor: palette.accentText,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
            child: Text(
              l10n.workoutWeekCompletedAction,
              textAlign: TextAlign.center,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: AppTextSize.bodyDense,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
