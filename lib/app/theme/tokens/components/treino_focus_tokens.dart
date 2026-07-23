import 'package:flutter/material.dart';

import '../../app_palette.dart';

/// Capa 3 — Tokens de componente para el anillo de foco de teclado TREINO.
///
/// El anillo de foco se pinta por el consumidor (no por TreinoInteractiveState)
/// usando `TreinoFocusTokens.of(ctx).ring` como color. El acento siempre
/// es visible sobre todos los fondos del sistema (mint vs ink/paper).
///
/// Uso:
/// ```dart
/// final t = TreinoFocusTokens.of(context);
/// Container(
///   decoration: BoxDecoration(
///     border: Border.all(color: t.ring, width: TreinoFocusTokens.ringWidth),
///     borderRadius: BorderRadius.circular(borderRadius),
///   ),
/// )
/// ```
@immutable
class TreinoFocusTokens {
  const TreinoFocusTokens._({required this.ring});

  /// Color del anillo de foco — delega a `AppPalette.accent` (mint).
  ///
  /// El acento mint es el mismo en dark y light — contrasta bien sobre ink950
  /// y sobre paper50 por su saturación.
  final Color ring;

  /// Ancho del anillo de foco — `2.0 px`.
  static const double ringWidth = 2.0;

  /// Resuelve los tokens de color según el tema activo.
  factory TreinoFocusTokens.of(BuildContext ctx) {
    final p = AppPalette.of(ctx);
    return TreinoFocusTokens._(ring: p.accent);
  }
}
