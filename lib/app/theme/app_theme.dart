import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';

class AppTheme {
  // ---------------------------------------------------------------------------
  // Private helpers shared by both factories (ADR-LM-010)
  // ---------------------------------------------------------------------------

  static TextTheme _buildTextTheme(AppPalette palette, TextTheme base) {
    final condensed = GoogleFonts.barlowCondensedTextTheme(base);
    return base.copyWith(
      displayLarge: condensed.displayLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
      displayMedium: condensed.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
      headlineLarge: condensed.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
      headlineMedium: condensed.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
      headlineSmall: condensed.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
      titleLarge: condensed.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
    );
  }

  static InputDecorationTheme _buildInputDecoration(
    AppPalette palette,
    Color errorColor,
  ) {
    return InputDecorationTheme(
      filled: true,
      fillColor: palette.bgCard,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 18,
      ),
      labelStyle: GoogleFonts.barlow(
        color: palette.textMuted,
        fontWeight: FontWeight.w400,
      ),
      hintStyle: GoogleFonts.barlow(color: palette.textMuted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: errorColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: errorColor, width: 1.5),
      ),
      errorStyle: GoogleFonts.barlow(
        color: errorColor,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Public factories
  // ---------------------------------------------------------------------------

  static ThemeData dark({AppPalette palette = AppPalette.mintMagenta}) {
    final base = GoogleFonts.barlowTextTheme(ThemeData.dark().textTheme);
    final textTheme = _buildTextTheme(palette, base);
    final errorColor = const ColorScheme.dark().error;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: palette.bg,
      colorScheme: ColorScheme.dark(
        primary: palette.accent,
        onPrimary: palette.bg,
        secondary: palette.highlight,
        onSecondary: palette.textPrimary,
        surface: palette.bgCard,
        onSurface: palette.textPrimary,
      ),
      inputDecorationTheme: _buildInputDecoration(palette, errorColor),
      textTheme: textTheme,
      extensions: [palette],
    );
  }

  static ThemeData light({AppPalette palette = AppPalette.mintMagentaLight}) {
    final base = GoogleFonts.barlowTextTheme(ThemeData.light().textTheme);
    final textTheme = _buildTextTheme(palette, base);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: palette.bg,
      colorScheme: ColorScheme.light(
        primary: palette.accent,
        onPrimary: palette.bg,
        secondary: palette.highlight,
        onSecondary: palette.textPrimary,
        surface: palette.bgCard,
        onSurface: palette.textPrimary,
        error: palette.danger,
        onError: palette.onDanger,
      ),
      inputDecorationTheme: _buildInputDecoration(palette, palette.danger),
      textTheme: textTheme,
      extensions: [palette],
    );
  }
}
