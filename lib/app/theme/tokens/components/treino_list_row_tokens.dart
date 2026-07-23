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
    required this.titleColor,
    required this.subtitleColor,
    required this.disabledColor,
  });

  /// Fondo de la row en estado normal — delega a `AppPalette.bg`.
  final Color background;

  /// Fondo de la row en estado hover — delega a `AppPalette.bgCard`.
  final Color hoverBackground;

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
      background: p.bg,
      hoverBackground: p.bgCard,
      titleColor: p.textPrimary,
      subtitleColor: p.textMuted,
      disabledColor: p.textMuted,
    );
  }
}
