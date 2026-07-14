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

  /// Fondo del ítem activo (píldora) — delega a `AppPalette.bgCard`.
  final Color activeBackground;

  /// Color de texto/ícono sobre el ítem activo — delega a `AppPalette.accent`.
  final Color activeForeground;

  /// Color de texto/ícono sobre un ítem inactivo — delega a `AppPalette.textPrimary`.
  final Color inactiveForeground;

  /// Fondo en estado hover — acento con 8% de opacidad (`accent.withValues(alpha: 0.08)`).
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
      activeBackground: p.bgCard,
      activeForeground: p.accent,
      inactiveForeground: p.textPrimary,
      // 8% de opacidad sobre el acento: alpha = round(0.08 × 255) = 20 (0x14).
      hoverBackground: p.accent.withValues(alpha: 0.08),
      badgeBackground: p.highlight,
    );
  }
}
