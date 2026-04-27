import 'package:flutter/material.dart';

/// Tokens de color del sistema de diseño TREINO.
///
/// El producto soporta dos paletas (mintMagenta default, electricViolet alterna).
/// Los neutros (ink, sage, espresso, bone) se comparten entre ambas.
/// Ningún widget debe usar HEX literales — siempre vía `AppPalette.of(context)`.
class AppColors {
  static const ink = Color(0xFF0A0A0A);
  static const espresso = Color(0xFF3C3534);
  static const sage = Color(0xFF4F6358);
  static const bone = Color(0xFFFFFFFF);

  static const violet = Color(0xFF7C3AED);
  static const green = Color(0xFF34E062);

  static const magenta = Color(0xFFC123E0);
  static const mint = Color(0xFF2CE5A2);
}

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.accent,
    required this.highlight,
    required this.bg,
    required this.bgCard,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
  });

  final Color accent;
  final Color highlight;
  final Color bg;
  final Color bgCard;
  final Color border;
  final Color textPrimary;
  final Color textMuted;

  static const mintMagenta = AppPalette(
    accent: AppColors.mint,
    highlight: AppColors.magenta,
    bg: AppColors.ink,
    bgCard: Color(0xFF0F1513),
    border: Color(0x1AFFFFFF),
    textPrimary: AppColors.bone,
    textMuted: Color(0x8CFFFFFF),
  );

  static const electricViolet = AppPalette(
    accent: AppColors.green,
    highlight: AppColors.violet,
    bg: AppColors.ink,
    bgCard: Color(0xFF111413),
    border: Color(0x1AFFFFFF),
    textPrimary: AppColors.bone,
    textMuted: Color(0x8CFFFFFF),
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? mintMagenta;

  @override
  AppPalette copyWith({
    Color? accent,
    Color? highlight,
    Color? bg,
    Color? bgCard,
    Color? border,
    Color? textPrimary,
    Color? textMuted,
  }) =>
      AppPalette(
        accent: accent ?? this.accent,
        highlight: highlight ?? this.highlight,
        bg: bg ?? this.bg,
        bgCard: bgCard ?? this.bgCard,
        border: border ?? this.border,
        textPrimary: textPrimary ?? this.textPrimary,
        textMuted: textMuted ?? this.textMuted,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      accent: Color.lerp(accent, other.accent, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      bgCard: Color.lerp(bgCard, other.bgCard, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }
}
