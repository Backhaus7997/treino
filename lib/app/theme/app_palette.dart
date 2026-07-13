import 'package:flutter/material.dart';

import 'tokens/primitives.dart';

/// Tokens de color del sistema de diseño TREINO.
///
/// El producto usa una única paleta oficial: **Mint Magenta** (definida en
/// `docs/design-system.md` y en el PDF de marca de mayo 2026).
/// Ningún widget debe usar HEX literales — siempre vía `AppPalette.of(context)`.
///
/// @Deprecated: usar [AppPalette.of(context)] — esta clase queda como alias
/// a los primitivos para retrocompatibilidad de call sites legacy.
@Deprecated(
  'Usar AppPalette.of(context). AppColors es alias legacy a AppColorPrimitives.',
)
class AppColors {
  static const ink = AppColorPrimitives.ink950;
  static const espresso = AppColorPrimitives.espresso500;
  static const sage = AppColorPrimitives.sage500;
  static const bone = AppColorPrimitives.bone;

  static const magenta = AppColorPrimitives.magenta500;
  static const mint = AppColorPrimitives.mint500;
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

  /// Paleta oscura — identidad de marca TREINO (default).
  static const mintMagenta = AppPalette(
    accent: AppColorPrimitives.mint500,
    highlight: AppColorPrimitives.magenta500,
    bg: AppColorPrimitives.ink950,
    bgCard: AppColorPrimitives.ink900,
    border: AppColorPrimitives.white10,
    borderHover: AppColorPrimitives.white20,
    textPrimary: AppColorPrimitives.bone,
    textMuted: AppColorPrimitives.white55,
    sage: AppColorPrimitives.sage500,
    espresso: AppColorPrimitives.espresso500,
    danger: AppColorPrimitives.dangerRed,
    warning: AppColorPrimitives.warningAmber,
    onDanger: AppColorPrimitives.white,
    scrimDark: AppColorPrimitives.black,
  );

  /// Paleta clara — soportada como alternativa al dark (dark = identidad).
  static const mintMagentaLight = AppPalette(
    accent: AppColorPrimitives.mint500,
    highlight: AppColorPrimitives.magenta500,
    bg: AppColorPrimitives.paper50,
    bgCard: AppColorPrimitives.white,
    border: AppColorPrimitives.black10,
    borderHover: AppColorPrimitives.black20,
    textPrimary: AppColorPrimitives.inkText900,
    textMuted: AppColorPrimitives.black60,
    sage: AppColorPrimitives.sageTint50,
    espresso: AppColorPrimitives.espressoTint50,
    danger: AppColorPrimitives.dangerRedDark,
    warning: AppColorPrimitives.warningAmberDark,
    onDanger: AppColorPrimitives.white,
    scrimDark: AppColorPrimitives.black,
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
