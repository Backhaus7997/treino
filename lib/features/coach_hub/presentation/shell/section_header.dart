import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';

/// Título de sección del Coach Hub web (Barlow Condensed, peso 700).
///
/// Usado por las pantallas de sección y por [ProximamenteScreen]. Toma el color
/// de `AppPalette.of(context)` — sin HEX literales.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      title,
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w700,
        fontSize: 20,
        letterSpacing: 0.8,
        color: palette.textPrimary,
      ),
    );
  }
}
