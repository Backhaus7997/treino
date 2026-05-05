import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

/// Welcome-screen variant of the TREINO logo with a "glitch" aesthetic:
/// - Small accent dash above the text (mimicking the horizontal rule in the
///   mockup).
/// - Base text "TREIN" in textPrimary + "O" in accent (Barlow Condensed 700 UC).
/// - Thin horizontal strike line at ~60% height, rendered in bg color so it
///   "breaks" the letterforms — exactly as in the mockup.
///
/// Only use in WelcomeScreen. Other screens use [TreinoLogo].
class WelcomeGlitchLogo extends StatelessWidget {
  const WelcomeGlitchLogo({super.key, this.fontSize = 52});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final style = GoogleFonts.barlowCondensed(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.0,
      height: 1.0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Accent dash above the logo
        Container(
          width: 28,
          height: 2,
          color: palette.accent,
        ),
        const SizedBox(height: 6),
        // Logo text with strike overlay
        Stack(
          children: [
            // Base text: "TREIN" + "O" (O in accent)
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'TREIN',
                    style: style.copyWith(color: palette.textPrimary),
                  ),
                  TextSpan(
                    text: 'O',
                    style: style.copyWith(color: palette.accent),
                  ),
                ],
              ),
            ),
            // Horizontal strike at ~60% of font height — bg color masks letters
            Positioned(
              // 60% from top of the em-square
              top: fontSize * 0.58,
              left: 0,
              right: 0,
              child: Container(
                height: 3,
                color: palette.bg,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
