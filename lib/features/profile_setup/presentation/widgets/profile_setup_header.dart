import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

/// Header común a los 4 steps:
/// - 4 segmentos arriba que se llenan en accent al avanzar.
/// - Etiqueta `PASO N DE 4` chiquita en condensed.
/// - Título grande en Barlow Condensed UPPERCASE (multilinea).
class ProfileSetupHeader extends StatelessWidget {
  const ProfileSetupHeader({
    super.key,
    required this.currentStep,
    required this.title,
  });

  /// Step 0-indexed (0..3).
  final int currentStep;

  /// Título del step (ej. "¿CÓMO TE LLAMÁS?", "PESO Y ALTURA"). Puede tener
  /// salto de línea para matchear el mockup.
  final String title;

  static const _totalSteps = 4;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(_totalSteps, (i) {
            final filled = i <= currentStep;
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i == _totalSteps - 1 ? 0 : 8),
                height: 4,
                decoration: BoxDecoration(
                  color: filled ? palette.accent : palette.border,
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 20),
        Text(
          'PASO ${currentStep + 1} DE $_totalSteps',
          style: GoogleFonts.barlowCondensed(
            color: palette.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: GoogleFonts.barlowCondensed(
            color: palette.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}
