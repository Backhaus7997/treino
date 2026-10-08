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
    required this.accentText,
    required this.highlight,
    required this.bg,
    required this.bgCard,
    required this.bgElevated,
    required this.surfaceSubtle,
    required this.border,
    required this.borderHover,
    required this.borderStrong,
    required this.textPrimary,
    required this.textMuted,
    required this.textFaint,
    required this.sage,
    required this.espresso,
    required this.danger,
    required this.warning,
    required this.reactionLike,
    required this.reactionFire,
    required this.reactionClap,
    required this.podiumGold,
    required this.podiumSilver,
    required this.podiumBronze,
    required this.onDanger,
    required this.scrimDark,
  });

  final Color accent;

  /// Acento en su versión para TEXTO e ÍCONOS, no para rellenos.
  ///
  /// [accent] es un color de fondo: en light compone 1,57:1 contra `bg`, así
  /// que un label pintado con él es ilegible aunque el mismo mint sirva
  /// perfecto como relleno de un CTA con texto ink encima. Este token resuelve
  /// esa bifurcación una sola vez —mint pleno en dark, `mintText700` en
  /// light— para que el widget escriba `palette.accentText` y no ramifique por
  /// `Theme.of(context).brightness`.
  ///
  /// Regla: si el acento va como FONDO → [accent] (y el texto encima sale de
  /// `TreinoButtonTokens.foreground`). Si va como TINTA → [accentText].
  final Color accentText;

  final Color highlight;
  final Color bg;
  final Color bgCard;

  /// Superficie que FLOTA sobre el contenido, un escalón por encima de
  /// [bgCard]: bottom sheets y la barra de accesorio anclada al teclado.
  ///
  /// En dark sube el valor del relleno (`ink850`). En light coincide con
  /// [bgCard] a propósito —no hay nada más claro que el papel— y la capa se
  /// lee por el filo superior, no por el relleno.
  final Color bgElevated;

  /// Relleno MÍNIMO con el que un control chico se despega de la superficie
  /// que lo contiene, sin dibujarle un marco: chip de set en estado normal,
  /// botón circular del app bar, pill de acción secundaria.
  ///
  /// Nace de un bug concreto: el chip de número de set usaba [bgCard], el
  /// mismo color de su card contenedora, y era literalmente invisible.
  final Color surfaceSubtle;

  final Color border;

  /// Border at a brighter alpha for hover states (eg. Coach Hub web sidebar
  /// rows). Additive over [border]; mobile never references it.
  final Color borderHover;

  /// Filo con el que una superficie GRANDE se separa del fondo de la app.
  ///
  /// [border] es un borde decorativo: sobre una card, que ya se distingue por
  /// su propio relleno, alcanza. Pero una superficie translúcida apoyada
  /// directamente sobre `bg` no tiene relleno propio que la delate —el
  /// `bgCard` de la bottom bar compone 1,05:1 contra `bg` en dark y 1,15:1 en
  /// light, o sea NADA— y ahí el filo es lo único que dice dónde empieza el
  /// contenedor. Con [border] ese filo medía 1,37:1 (dark) y 1,15:1 (light):
  /// el usuario no veía la barra y leía el pill mint del tab activo como un
  /// elemento suelto tapando el contenido de arriba (#821).
  ///
  /// Está calibrado contra el mínimo de WCAG 2.2 SC 1.4.11 (Non-text Contrast,
  /// 3:1) para el LÍMITE de un componente de interfaz. Ese piso lo verifica
  /// `test/core/widgets/treino_bottom_bar_containment_test.dart` sobre píxeles
  /// rasterizados, no sobre el color declarado: el filo real sale de tres capas
  /// encimadas (relleno + borde + reflejo especular).
  ///
  /// Úsalo SOLO donde una superficie se apoya sobre el fondo desnudo. Para
  /// bordes internos —celdas, divisores, cards sobre cards— sigue siendo
  /// [border]: subirle el contraste a todo convierte la UI en un wireframe.
  final Color borderStrong;

  final Color textPrimary;
  final Color textMuted;

  /// Tercer escalón de texto, por debajo de [textMuted]: headers de columna
  /// (`SET`/`KG`/`REPS`), hints de campo, ayudas al pie de una sección.
  ///
  /// Sigue siendo TEXTO, así que cumple 4,5:1 contra `bg` en las dos paletas
  /// —ver `AppColorPrimitives.white46` para la medición. No usarlo para
  /// bordes ni rellenos: para eso están [border] y [surfaceSubtle].
  final Color textFaint;

  /// Sage green — secondary cards, subtle outlines.
  final Color sage;

  /// Espresso — tono cálido de marca.
  ///
  /// Su dartdoc decía "elevated surfaces, sheets" hasta que [bgElevated] tomó
  /// ese rol con un token semántico de la familia `bg`. Cuatro pantallas lo
  /// siguen usando para superficies elevadas (`athlete_picker_sheet`,
  /// `exercise_picker_sheet`, `location_permission_rationale_sheet`,
  /// `exercise_detail_screen`): son anteriores y quedan como están.
  ///
  /// Para una superficie elevada NUEVA va [bgElevated], no este. Dos tokens
  /// para el mismo rol con colores de familias distintas —marrón cálido vs.
  /// ink frío— es una divergencia que hay que cerrar, no ampliar.
  final Color espresso;

  /// Danger red — inline error states, char-limit exceeded indicator.
  final Color danger;

  /// Warning amber — non-blocking caution states (eg. import partial match,
  /// rate limit close to cap). Distinct hue from `danger` so the user can
  /// tell at a glance whether action is required or just attention.
  final Color warning;

  /// Active feed reaction colors. These are expressive tokens, intentionally
  /// separate from semantic status colors such as [danger] and [warning].
  final Color reactionLike;
  final Color reactionFire;
  final Color reactionClap;

  /// Metálicos del podio — numeral de puesto de las 3 primeras filas de
  /// Rankings (1º oro, 2º plata, 3º bronce). Expresivos como los `reaction*`,
  /// no semánticos: fuera del podio no se usan.
  ///
  /// Los tres se miden como TEXTO CHICO (4,5:1) contra `bgCard` y contra la
  /// fila propia (`bgCard` + `accent` al 8%), en las DOS paletas —
  /// `podium_contrast_test.dart`. El color es refuerzo redundante: el numeral
  /// del puesto ya dice la posición, así que nadie depende del tono.
  final Color podiumGold;
  final Color podiumSilver;
  final Color podiumBronze;

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
    accentText: AppColorPrimitives.mint500,
    highlight: AppColorPrimitives.magenta500,
    bg: AppColorPrimitives.ink950,
    bgCard: AppColorPrimitives.ink900,
    bgElevated: AppColorPrimitives.ink850,
    surfaceSubtle: AppColorPrimitives.white06,
    border: AppColorPrimitives.white10,
    borderHover: AppColorPrimitives.white20,
    borderStrong: AppColorPrimitives.white35,
    textPrimary: AppColorPrimitives.bone,
    textMuted: AppColorPrimitives.white55,
    textFaint: AppColorPrimitives.white46,
    sage: AppColorPrimitives.sage500,
    espresso: AppColorPrimitives.espresso500,
    danger: AppColorPrimitives.dangerRed,
    warning: AppColorPrimitives.warningAmber,
    reactionLike: AppColorPrimitives.reactionLike,
    reactionFire: AppColorPrimitives.reactionFire,
    reactionClap: AppColorPrimitives.reactionClap,
    podiumGold: AppColorPrimitives.podiumGold,
    podiumSilver: AppColorPrimitives.podiumSilver,
    podiumBronze: AppColorPrimitives.podiumBronze,
    onDanger: AppColorPrimitives.white,
    scrimDark: AppColorPrimitives.black,
  );

  /// Paleta clara — soportada como alternativa al dark (dark = identidad).
  static const mintMagentaLight = AppPalette(
    accent: AppColorPrimitives.mint500,
    accentText: AppColorPrimitives.mintText700,
    highlight: AppColorPrimitives.magenta500,
    bg: AppColorPrimitives.paper50,
    bgCard: AppColorPrimitives.white,
    bgElevated: AppColorPrimitives.white,
    surfaceSubtle: AppColorPrimitives.black06,
    border: AppColorPrimitives.black10,
    borderHover: AppColorPrimitives.black20,
    borderStrong: AppColorPrimitives.black50,
    textPrimary: AppColorPrimitives.inkText900,
    textMuted: AppColorPrimitives.black60,
    textFaint: AppColorPrimitives.black55,
    sage: AppColorPrimitives.sageTint50,
    espresso: AppColorPrimitives.espressoTint50,
    danger: AppColorPrimitives.dangerRedDark,
    warning: AppColorPrimitives.warningAmberDark,
    reactionLike: AppColorPrimitives.reactionLikeDark,
    reactionFire: AppColorPrimitives.reactionFireDark,
    reactionClap: AppColorPrimitives.reactionClapDark,
    podiumGold: AppColorPrimitives.podiumGoldDark,
    podiumSilver: AppColorPrimitives.podiumSilverDark,
    podiumBronze: AppColorPrimitives.podiumBronzeDark,
    onDanger: AppColorPrimitives.white,
    scrimDark: AppColorPrimitives.black,
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? mintMagenta;

  @override
  AppPalette copyWith({
    Color? accent,
    Color? accentText,
    Color? highlight,
    Color? bg,
    Color? bgCard,
    Color? bgElevated,
    Color? surfaceSubtle,
    Color? border,
    Color? borderHover,
    Color? borderStrong,
    Color? textPrimary,
    Color? textMuted,
    Color? textFaint,
    Color? sage,
    Color? espresso,
    Color? danger,
    Color? warning,
    Color? reactionLike,
    Color? reactionFire,
    Color? reactionClap,
    Color? podiumGold,
    Color? podiumSilver,
    Color? podiumBronze,
    Color? onDanger,
    Color? scrimDark,
  }) =>
      AppPalette(
        accent: accent ?? this.accent,
        accentText: accentText ?? this.accentText,
        highlight: highlight ?? this.highlight,
        bg: bg ?? this.bg,
        bgCard: bgCard ?? this.bgCard,
        bgElevated: bgElevated ?? this.bgElevated,
        surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
        border: border ?? this.border,
        borderHover: borderHover ?? this.borderHover,
        borderStrong: borderStrong ?? this.borderStrong,
        textPrimary: textPrimary ?? this.textPrimary,
        textMuted: textMuted ?? this.textMuted,
        textFaint: textFaint ?? this.textFaint,
        sage: sage ?? this.sage,
        espresso: espresso ?? this.espresso,
        danger: danger ?? this.danger,
        warning: warning ?? this.warning,
        reactionLike: reactionLike ?? this.reactionLike,
        reactionFire: reactionFire ?? this.reactionFire,
        reactionClap: reactionClap ?? this.reactionClap,
        podiumGold: podiumGold ?? this.podiumGold,
        podiumSilver: podiumSilver ?? this.podiumSilver,
        podiumBronze: podiumBronze ?? this.podiumBronze,
        onDanger: onDanger ?? this.onDanger,
        scrimDark: scrimDark ?? this.scrimDark,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      accent: Color.lerp(accent, other.accent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      bgCard: Color.lerp(bgCard, other.bgCard, t)!,
      bgElevated: Color.lerp(bgElevated, other.bgElevated, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderHover: Color.lerp(borderHover, other.borderHover, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      espresso: Color.lerp(espresso, other.espresso, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      reactionLike: Color.lerp(reactionLike, other.reactionLike, t)!,
      reactionFire: Color.lerp(reactionFire, other.reactionFire, t)!,
      reactionClap: Color.lerp(reactionClap, other.reactionClap, t)!,
      podiumGold: Color.lerp(podiumGold, other.podiumGold, t)!,
      podiumSilver: Color.lerp(podiumSilver, other.podiumSilver, t)!,
      podiumBronze: Color.lerp(podiumBronze, other.podiumBronze, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      scrimDark: Color.lerp(scrimDark, other.scrimDark, t)!,
    );
  }
}
