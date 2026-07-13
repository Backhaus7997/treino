import 'package:flutter/material.dart';

import '../primitives.dart';
import '../../app_palette.dart';

/// Capa 3 — Tokens de componente para botones primarios TREINO.
///
/// Sigue el patrón `static T method(BuildContext)`: lee [AppPalette.of(ctx)]
/// para color y [AppRadius] para forma. NUNCA usa hex inline.
///
/// Uso:
/// ```dart
/// Container(
///   color: TreinoButtonTokens.background(context),
///   child: Text('Guardar', style: TextStyle(color: TreinoButtonTokens.foreground(context))),
/// )
/// ```
abstract final class TreinoButtonTokens {
  /// Color de fondo del botón primario — delega a `AppPalette.accent`.
  static Color background(BuildContext ctx) => AppPalette.of(ctx).accent;

  /// Color de texto/icono sobre el botón primario.
  ///
  /// El acento mint es claro, entonces usamos el ink más profundo para
  /// garantizar contraste WCAG AA sobre el fondo mint.
  // ignore: avoid_unused_parameters
  static Color foreground(BuildContext ctx) {
    // El acento (mint) es el mismo en dark y light, pero el ink de fondo
    // varía — usamos ink950 como foreground absoluto para CTA.
    return AppColorPrimitives.ink950;
  }

  /// Radio de borde del botón primario (referencias a [AppRadius]).
  static const double borderRadius = AppRadius.sm;
}
