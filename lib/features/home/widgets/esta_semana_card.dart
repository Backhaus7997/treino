import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';

/// Placeholder "Esta semana" card (Etapa 1).
/// Shows a static message — streak, week dots, and muscle-map SVG are
/// deferred to Etapa 5. Zero constructor params; all content is inline.
class EstaSemanaCard extends StatelessWidget {
  const EstaSemanaCard({super.key});

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
            Text(
              'ESTA SEMANA',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 1.4,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Todavía no entrenaste esta semana.',
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
