import 'package:flutter/material.dart';

import '../primitives.dart';
import '../../app_palette.dart';

/// Capa 3 — Tokens de componente para los ítems del sidebar Coach Hub Web.
///
/// Sigue el patrón `factory of(BuildContext)`: lee [AppPalette.of(ctx)]
/// para colores dependientes del tema. Los tokens de dimensión son
/// `static const` (no dependen de tema).
///
/// Uso:
/// ```dart
/// final t = CoachHubSidebarItemTokens.of(context);
/// Container(
///   color: isActive ? t.activeBackground : Colors.transparent,
///   child: Text(label, style: TextStyle(color: isActive
///     ? t.activeForeground
///     : t.inactiveForeground)),
/// )
/// ```
@immutable
class CoachHubSidebarItemTokens {
  const CoachHubSidebarItemTokens._({
    required this.activeBackground,
    required this.activeForeground,
    required this.inactiveForeground,
    required this.hoverBackground,
    required this.badgeBackground,
  });

  /// Fondo del ítem activo (píldora) — tinte de acento al 16%.
  final Color activeBackground;

  /// Color de texto/ícono sobre el ítem activo — `AppPalette.accentText`,
  /// que es el acento LEGIBLE COMO TEXTO (en claro difiere de `accent`).
  final Color activeForeground;

  /// Color de texto/ícono sobre un ítem inactivo — delega a `AppPalette.textPrimary`.
  final Color inactiveForeground;

  /// Fondo en estado hover — lavado neutro (`AppPalette.surfaceSubtle`).
  /// Deliberadamente SIN acento: el acento es la marca del ítem activo.
  final Color hoverBackground;

  /// Fondo del badge numérico — delega a `AppPalette.highlight` (magenta).
  final Color badgeBackground;

  /// Radio de borde del ítem (píldora) — `AppRadius.sm` = 12.0.
  static const double borderRadius = AppRadius.sm;

  /// Padding horizontal del ítem — `AppSpacing.s14` = 14.0.
  static const double paddingH = AppSpacing.s14;

  /// Padding vertical del ítem — `AppSpacing.s12` = 12.0.
  static const double paddingV = AppSpacing.s12;

  /// Resuelve los tokens de color según el tema activo.
  factory CoachHubSidebarItemTokens.of(BuildContext ctx) {
    final p = AppPalette.of(ctx);
    return CoachHubSidebarItemTokens._(
      // EL ACTIVO LLEVA EL ACENTO; EL HOVER, NO. Antes era al revés de lo que
      // el ojo necesita: el activo era `bgCard` —en claro, BLANCO sobre un
      // sidebar `paper50`, o sea 1,04:1, invisible— y el hover era acento al
      // 8%, un verde que sí se ve. Resultado: el item que estabas apuntando se
      // leía como el seleccionado, y el seleccionado no se leía. El PF lo
      // reportó como «parece que hay más de uno seleccionado a la vez».
      //
      // Quien separa los dos estados es el TONO, no la luminancia: un tinte de
      // acento y un lavado neutro tienen contraste parecido contra el fondo
      // (1,09 y 1,14) y aun así no se confunden nunca, porque uno tiene color
      // y el otro no.
      activeBackground: p.accent.withValues(alpha: 0.16),
      // `accentText` y NO `accent`. En claro son colores distintos y este es
      // texto: `accent` (mint500) sobre el fondo del item mide 1,64:1 contra
      // los 4,5 que pide WCAG AA — el label del item activo era ilegible. En
      // oscuro los dos son mint500, así que esto no toca el tema oscuro.
      activeForeground: p.accentText,
      inactiveForeground: p.textPrimary,
      // Lavado NEUTRO (negro 6% en claro, blanco 6% en oscuro): dice «estás
      // apuntando acá» sin pedir prestada la señal de «acá estás».
      hoverBackground: p.surfaceSubtle,
      badgeBackground: p.highlight,
    );
  }
}
