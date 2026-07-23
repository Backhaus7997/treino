import 'package:flutter/material.dart';

import '../primitives.dart';
import '../../app_palette.dart';

/// Capa 3 — Tokens de componente para KpiCard Coach Hub Web.
///
/// Sigue el patrón `factory of(BuildContext)`: lee [AppPalette.of(ctx)]
/// para colores dependientes del tema. NUNCA usa hex inline.
///
/// Uso:
/// ```dart
/// final t = TreinoKpiCardTokens.of(context);
/// Container(
///   decoration: BoxDecoration(
///     color: t.background,
///     border: Border.all(color: t.border),
///     borderRadius: BorderRadius.circular(t.borderRadius),
///   ),
/// )
/// ```
@immutable
class TreinoKpiCardTokens {
  const TreinoKpiCardTokens._({
    required this.background,
    required this.border,
    required this.titleColor,
    required this.valueColor,
    required this.variationPositiveColor,
    required this.variationNegativeColor,
    required this.iconColor,
  });

  /// Fondo de la KPI card — delega a `AppPalette.bgCard`.
  final Color background;

  /// Borde de la KPI card — delega a `AppPalette.border`.
  final Color border;

  /// Color del título/etiqueta de la métrica — delega a `AppPalette.textMuted`.
  final Color titleColor;

  /// Color del valor principal de la métrica — delega a `AppPalette.textPrimary`.
  final Color valueColor;

  /// Color de variación positiva — delega a `AppPalette.accent`.
  final Color variationPositiveColor;

  /// Color de variación negativa (caída) — delega a `AppPalette.danger`.
  final Color variationNegativeColor;

  /// Color del ícono decorativo — delega a `AppPalette.textMuted`.
  final Color iconColor;

  /// Radio de borde de la KPI card — `AppRadius.md` = 16.0.
  static const double borderRadius = AppRadius.md;

  /// Padding interno de la KPI card — `AppSpacing.s20` = 20.0.
  static const double padding = AppSpacing.s20;

  /// Resuelve los tokens de color según el tema activo.
  factory TreinoKpiCardTokens.of(BuildContext ctx) {
    final p = AppPalette.of(ctx);
    return TreinoKpiCardTokens._(
      background: p.bgCard,
      border: p.border,
      titleColor: p.textMuted,
      valueColor: p.textPrimary,
      variationPositiveColor: p.accent,
      variationNegativeColor: p.danger,
      iconColor: p.textMuted,
    );
  }
}
