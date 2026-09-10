import 'package:flutter/material.dart';

import '../primitives.dart';
import '../../app_palette.dart';

/// Capa 3 — Tokens de componente para ListRow Coach Hub Web.
///
/// ListRow es la fila genérica de lista con estados (normal, hover, pressed,
/// disabled, loading). Diseñada para consumo en Fase 3 (Alumnos) y Fase 7
/// (Biblioteca).
///
/// Uso:
/// ```dart
/// final t = TreinoListRowTokens.of(context);
/// AnimatedContainer(
///   color: isHovered ? t.hoverBackground : t.background,
///   height: t.height,
/// )
/// ```
@immutable
class TreinoListRowTokens {
  const TreinoListRowTokens._({
    required this.background,
    required this.hoverBackground,
    required this.skeletonBackground,
    required this.titleColor,
    required this.subtitleColor,
    required this.disabledColor,
  });

  /// Fondo de la row en estado normal — **transparente**, hereda el contenedor.
  ///
  /// Antes era `AppPalette.bg` y eso obligaba a la fila a adivinar sobre qué la
  /// iban a poner. Adentro de una card (`bgCard`) la suposición era falsa: la
  /// fila pintaba `#FAFAFA` sobre `#FFFFFF` y se veía como una banda gris que
  /// nadie pidió. Heredando, la fila se apoya en el fondo que le toque.
  final Color background;

  /// Fondo de la row en estado hover — acento al 6 %, **el mismo tinte que
  /// `TreinoTableTokens.rowHoverBackground`**.
  ///
  /// Antes era `AppPalette.bgCard`, o sea el color de la card que la contiene:
  /// en tema claro el hover llevaba la fila de `#FAFAFA` a `#FFFFFF` y la
  /// **borraba** en vez de destacarla; en oscuro, `ink950 -> ink900` es 1,06:1,
  /// imperceptible. El PF lo reportó como «parpadeo al pasar el cursor por los
  /// items de la lista»: barriendo cinco filas, las bandas se apagaban y se
  /// prendían una tras otra. Con acento al 6 % el hover se lee, y además la
  /// lista y la tabla pasan a hablar el mismo idioma.
  final Color hoverBackground;

  /// Fondo de los bloques del skeleton — delega a `AppPalette.surfaceSubtle`.
  ///
  /// Existe porque el skeleton se colgaba de `hoverBackground`, y con el hover
  /// tintado de acento las barras de carga salían color menta. Un relleno
  /// neutro es un token propio, no el sobrante de otro estado.
  final Color skeletonBackground;

  /// Color del texto principal de la row — delega a `AppPalette.textPrimary`.
  final Color titleColor;

  /// Color del subtítulo de la row — delega a `AppPalette.textMuted`.
  final Color subtitleColor;

  /// Color en estado deshabilitado — delega a `AppPalette.textMuted`.
  final Color disabledColor;

  /// Radio de borde de la row — `AppRadius.sm` = 12.0.
  static const double borderRadius = AppRadius.sm;

  /// Altura de la row — `48.0 px`.
  static const double height = 48.0;

  /// Padding horizontal — `AppSpacing.s14` = 14.0.
  static const double paddingH = AppSpacing.s14;

  /// Padding vertical — `AppSpacing.s12` = 12.0.
  static const double paddingV = AppSpacing.s12;

  /// Resuelve los tokens de color según el tema activo.
  factory TreinoListRowTokens.of(BuildContext ctx) {
    final p = AppPalette.of(ctx);
    return TreinoListRowTokens._(
      background: Colors.transparent,
      hoverBackground: p.accent.withValues(alpha: 0.06),
      skeletonBackground: p.surfaceSubtle,
      titleColor: p.textPrimary,
      subtitleColor: p.textMuted,
      disabledColor: p.textMuted,
    );
  }
}
