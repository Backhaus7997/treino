import 'package:flutter/material.dart';

import '../../app_palette.dart';

/// Capa 3 — Tokens de componente para EmptyState Coach Hub Web.
///
/// EmptyState se usa en todas las secciones cuando no hay datos disponibles.
/// Estados: normal (ícono + título + descripción), con CTA, loading.
///
/// Uso:
/// ```dart
/// final t = TreinoEmptyStateTokens.of(context);
/// Column(
///   children: [
///     Icon(icon, color: t.iconColor, size: TreinoEmptyStateTokens.iconSize),
///     Text(title, style: TextStyle(color: t.titleColor)),
///     Text(description, style: TextStyle(color: t.descriptionColor)),
///   ],
/// )
/// ```
@immutable
class TreinoEmptyStateTokens {
  const TreinoEmptyStateTokens._({
    required this.iconColor,
    required this.titleColor,
    required this.descriptionColor,
    required this.ctaColor,
  });

  /// Color del ícono decorativo — delega a `AppPalette.textMuted`.
  final Color iconColor;

  /// Color del título del estado vacío — delega a `AppPalette.textPrimary`.
  final Color titleColor;

  /// Color de la descripción — delega a `AppPalette.textMuted`.
  final Color descriptionColor;

  /// Color del botón de acción (CTA) — delega a `AppPalette.accent`.
  final Color ctaColor;

  /// Tamaño del ícono — `48.0 px` (spec REQ-CK-005).
  // ignore: avoid_unused_parameters (valor de layout constante sin primitivo equivalente)
  static const double iconSize = 48.0;

  /// Resuelve los tokens de color según el tema activo.
  factory TreinoEmptyStateTokens.of(BuildContext ctx) {
    final p = AppPalette.of(ctx);
    return TreinoEmptyStateTokens._(
      iconColor: p.textMuted,
      titleColor: p.textPrimary,
      descriptionColor: p.textMuted,
      ctaColor: p.accent,
    );
  }
}
