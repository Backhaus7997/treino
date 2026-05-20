import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../coach_strings.dart';

/// Stub CTA button for requesting a trainer-athlete link.
///
/// Shows a SnackBar "Próximamente — Etapa 3" on press.
/// Real implementation deferred to Etapa 3 per spec.
///
/// REQ-COACH-DISC-UI-016. SCENARIO-434.
class TrainerContactCtaStub extends StatelessWidget {
  const TrainerContactCtaStub({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return OutlinedButton(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(CoachStrings.ctaProximamente)),
        );
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.accent,
        side: BorderSide(color: palette.accent),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      ),
      child: Text(
        CoachStrings.ctaLabel,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
