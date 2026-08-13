import 'package:flutter/material.dart';

import '../primitives.dart';
import '../../app_palette.dart';

/// Capa 3 — Tokens de componente para badges numéricos TREINO.
///
/// Los badges aparecen sobre ítems del sidebar (Pagos, Chat) indicando
/// cantidad no leída. Color magenta highlight, forma pill completa.
///
/// Uso:
/// ```dart
/// final t = TreinoBadgeTokens.of(context);
/// Container(
///   decoration: BoxDecoration(
///     color: t.background,
///     borderRadius: BorderRadius.circular(TreinoBadgeTokens.borderRadius),
///   ),
///   child: Text('$count', style: TextStyle(color: t.foreground)),
/// )
/// ```
@immutable
class TreinoBadgeTokens {
  const TreinoBadgeTokens._({
    required this.background,
    required this.foreground,
  });

  /// Fondo del badge — delega a `AppPalette.highlight` (magenta).
  final Color background;

  /// Color del texto del badge — delega a `AppPalette.onDanger` (blanco).
  ///
  /// Se reutiliza `onDanger` porque garantiza contraste sobre fondos vibrantes
  /// (magenta y danger comparten la misma luminosidad). No hay `onHighlight`
  /// en la paleta por decisión de ADR-SH-003.
  final Color foreground;

  /// Radio del badge — `AppRadius.full` = 9999.0 (pill completa).
  static const double borderRadius = AppRadius.full;

  /// Tamaño mínimo del badge (diámetro) — `16.0 px` (spec REQ-SH-003).
  static const double size = 16.0;

  /// Resuelve los tokens de color según el tema activo.
  factory TreinoBadgeTokens.of(BuildContext ctx) {
    final p = AppPalette.of(ctx);
    return TreinoBadgeTokens._(
      background: p.highlight,
      foreground: p.onDanger,
    );
  }
}
