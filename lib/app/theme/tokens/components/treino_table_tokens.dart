import 'package:flutter/material.dart';

import '../primitives.dart';
import '../../app_palette.dart';

/// Capa 3 — Tokens de componente para CoachHubDataTable Coach Hub Web.
///
/// Tabla de datos web con columnas ordenables, hover de fila, estados de
/// carga/vacío/error y scroll horizontal. Consumida en Fases 3 (Alumnos),
/// 9 (Pagos), 10 (Planes).
///
/// Uso:
/// ```dart
/// final t = TreinoTableTokens.of(context);
/// Container(
///   color: isHeader ? t.headerBackground : t.rowBackground,
///   child: Padding(
///     padding: EdgeInsets.symmetric(
///       horizontal: t.cellPaddingH,
///       vertical: t.cellPaddingV,
///     ),
///     child: child,
///   ),
/// )
/// ```
@immutable
class TreinoTableTokens {
  const TreinoTableTokens._({
    required this.headerBackground,
    required this.headerTextColor,
    required this.rowBackground,
    required this.rowAltBackground,
    required this.rowHoverBackground,
    required this.borderColor,
    required this.sortIndicatorColor,
  });

  /// Fondo del encabezado de la tabla — delega a `AppPalette.bgCard`.
  final Color headerBackground;

  /// Color de texto del encabezado — delega a `AppPalette.textMuted`.
  final Color headerTextColor;

  /// Fondo de las filas pares — delega a `AppPalette.bg`.
  final Color rowBackground;

  /// Fondo de las filas impares (alternado) — delega a `AppPalette.bgCard`.
  final Color rowAltBackground;

  /// Fondo de fila en hover — acento con 6% de opacidad.
  final Color rowHoverBackground;

  /// Color del borde entre filas — delega a `AppPalette.border`.
  final Color borderColor;

  /// Color del indicador de columna ordenada — delega a `AppPalette.accent`.
  final Color sortIndicatorColor;

  /// Radio de borde de la tabla — `AppRadius.md` = 16.0.
  static const double borderRadius = AppRadius.md;

  /// Padding horizontal de celda — `AppSpacing.s14` = 14.0.
  static const double cellPaddingH = AppSpacing.s14;

  /// Padding vertical de celda — `AppSpacing.s12` = 12.0.
  static const double cellPaddingV = AppSpacing.s12;

  /// Altura de fila — `48.0 px` (spec ADR-SH-003).
  static const double rowHeight = 48.0;

  /// Resuelve los tokens de color según el tema activo.
  factory TreinoTableTokens.of(BuildContext ctx) {
    final p = AppPalette.of(ctx);
    return TreinoTableTokens._(
      headerBackground: p.bgCard,
      headerTextColor: p.textMuted,
      rowBackground: p.bg,
      rowAltBackground: p.bgCard,
      // 6% de opacidad sobre el acento: sutil para no competir con la selección.
      rowHoverBackground: p.accent.withValues(alpha: 0.06),
      borderColor: p.border,
      sortIndicatorColor: p.accent,
    );
  }
}
