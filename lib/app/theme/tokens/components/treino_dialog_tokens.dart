import 'package:flutter/material.dart';

import '../primitives.dart';
import '../../app_palette.dart';

/// Capa 3 — Tokens de componente para Dialog Coach Hub Web.
///
/// Dialog con estados: normal, destructive (CTA en danger), loading (spinner
/// en botón), error inline. Animación de apertura respeta reduceMotion vía
/// AppMotionTokens.resolve.
///
/// Uso:
/// ```dart
/// final t = TreinoDialogTokens.of(context);
/// Container(
///   decoration: BoxDecoration(
///     color: t.background,
///     borderRadius: BorderRadius.circular(t.borderRadius),
///   ),
///   constraints: BoxConstraints(maxWidth: TreinoDialogTokens.maxWidth),
/// )
/// ```
@immutable
class TreinoDialogTokens {
  const TreinoDialogTokens._({
    required this.background,
    required this.titleColor,
    required this.contentColor,
    required this.overlayColor,
    required this.destructiveColor,
  });

  /// Fondo del dialog — delega a `AppPalette.bgCard`.
  final Color background;

  /// Color del título del dialog — delega a `AppPalette.textPrimary`.
  final Color titleColor;

  /// Color del contenido/cuerpo del dialog — delega a `AppPalette.textMuted`.
  final Color contentColor;

  /// Color del overlay/scrim detrás del dialog — delega a `AppPalette.scrimDark`.
  final Color overlayColor;

  /// Color del CTA destructivo — delega a `AppPalette.danger`.
  final Color destructiveColor;

  /// Radio del dialog — `AppRadius.lg` = 20.0.
  static const double borderRadius = AppRadius.lg;

  /// Ancho máximo del dialog — `480.0 px` (spec ADR-SH-003).
  static const double maxWidth = 480.0;

  /// Resuelve los tokens de color según el tema activo.
  factory TreinoDialogTokens.of(BuildContext ctx) {
    final p = AppPalette.of(ctx);
    return TreinoDialogTokens._(
      background: p.bgCard,
      titleColor: p.textPrimary,
      contentColor: p.textMuted,
      overlayColor: p.scrimDark,
      destructiveColor: p.danger,
    );
  }
}
