import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';

class AppTheme {
  static ThemeData dark({AppPalette palette = AppPalette.mintMagenta}) {
    final body = GoogleFonts.barlowTextTheme(ThemeData.dark().textTheme);
    final condensed = GoogleFonts.barlowCondensedTextTheme(
      ThemeData.dark().textTheme,
    );

    final textTheme = body.copyWith(
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

    const colorScheme = ColorScheme.dark();
    final errorColor = colorScheme.error;

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
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
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
      ),
      textTheme: textTheme,
      extensions: [palette],
    );
  }
}
