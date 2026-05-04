import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

/// TREINO logo rendered as "TREIN" (textPrimary) + "O" (accent).
/// Uses Barlow Condensed 700 UC with letter-spacing — per design system.
class TreinoLogo extends StatelessWidget {
  const TreinoLogo({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final style = GoogleFonts.barlowCondensed(
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      height: 1.0,
    );

    return RichText(
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
    );
  }
}
