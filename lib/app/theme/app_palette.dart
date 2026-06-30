import 'package:flutter/material.dart';

/// Tokens de color del sistema de diseño TREINO.
///
/// El producto usa una única paleta oficial: **Mint Magenta** (definida en
/// `docs/design-system.md` y en el PDF de marca de mayo 2026).
/// Ningún widget debe usar HEX literales — siempre vía `AppPalette.of(context)`.
class AppColors {
  static const ink = Color(0xFF0A0A0A);
  static const espresso = Color(0xFF3C3534);
  static const sage = Color(0xFF4F6358);
  static const bone = Color(0xFFFFFFFF);

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
    required this.borderHover,
    required this.textPrimary,
    required this.textMuted,
    required this.sage,
    required this.espresso,
    required this.danger,
    required this.warning,
    required this.onDanger,
    required this.scrimDark,
  });

  final Color accent;
  final Color highlight;
  final Color bg;
  final Color bgCard;
  final Color border;

  /// Border at a brighter alpha for hover states (eg. Coach Hub web sidebar
  /// rows). Additive over [border]; mobile never references it.
  final Color borderHover;

  final Color textPrimary;
  final Color textMuted;

  /// Sage green — secondary cards, subtle outlines.
  final Color sage;

  /// Espresso — elevated surfaces, sheets.
  final Color espresso;

  /// Danger red — inline error states, char-limit exceeded indicator.
  final Color danger;

  /// Warning amber — non-blocking caution states (eg. import partial match,
  /// rate limit close to cap). Distinct hue from `danger` so the user can
  /// tell at a glance whether action is required or just attention.
  final Color warning;

  /// Foreground (text/icon) rendered on top of [danger] backgrounds.
  /// Achieves ≥ 4.5:1 contrast ratio against [danger] (WCAG AA).
  final Color onDanger;

  /// Pure-black token for overlay scrims; apply opacity at call site via
  /// `withValues(alpha: x)`. Constant across both themes — scrims are always
  /// dark for image/video legibility.
  final Color scrimDark;

  static const mintMagenta = AppPalette(
    accent: AppColors.mint,
    highlight: AppColors.magenta,
    bg: AppColors.ink,
    bgCard: Color(0xFF0F1513),
    border: Color(0x1AFFFFFF),
    borderHover: Color(0x33FFFFFF),
    textPrimary: AppColors.bone,
    textMuted: Color(0x8CFFFFFF),
    sage: AppColors.sage,
    espresso: AppColors.espresso,
    danger: Color(0xFFE53935),
    warning: Color(0xFFFFB300),
    onDanger: Color(0xFFFFFFFF),
    scrimDark: Color(0xFF000000),
  );

  static const mintMagentaLight = AppPalette(
    accent: Color(0xFF2CE5A2),
    highlight: Color(0xFFC123E0),
    bg: Color(0xFFFAFAFA),
    bgCard: Color(0xFFFFFFFF),
    border: Color(0x1A000000),
    borderHover: Color(0x33000000),
    textPrimary: Color(0xFF0F1513),
    textMuted: Color(0x99000000),
    sage: Color(0xFFDDE5DF),
    espresso: Color(0xFFEDE5E2),
    danger: Color(0xFFD32F2F),
    warning: Color(0xFFFB8C00),
    onDanger: Color(0xFFFFFFFF),
    scrimDark: Color(0xFF000000),
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
    Color? borderHover,
    Color? textPrimary,
    Color? textMuted,
    Color? sage,
    Color? espresso,
    Color? danger,
    Color? warning,
    Color? onDanger,
    Color? scrimDark,
  }) =>
      AppPalette(
        accent: accent ?? this.accent,
        highlight: highlight ?? this.highlight,
        bg: bg ?? this.bg,
        bgCard: bgCard ?? this.bgCard,
        border: border ?? this.border,
        borderHover: borderHover ?? this.borderHover,
        textPrimary: textPrimary ?? this.textPrimary,
        textMuted: textMuted ?? this.textMuted,
        sage: sage ?? this.sage,
        espresso: espresso ?? this.espresso,
        danger: danger ?? this.danger,
        warning: warning ?? this.warning,
        onDanger: onDanger ?? this.onDanger,
        scrimDark: scrimDark ?? this.scrimDark,
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
      borderHover: Color.lerp(borderHover, other.borderHover, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      espresso: Color.lerp(espresso, other.espresso, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      scrimDark: Color.lerp(scrimDark, other.scrimDark, t)!,
    );
  }
}
