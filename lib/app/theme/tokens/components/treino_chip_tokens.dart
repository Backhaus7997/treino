import 'package:flutter/material.dart';

import '../primitives.dart';
import '../../app_palette.dart';

/// Capa 3 — Tokens de componente para FilterChips Coach Hub Web.
///
/// FilterChips agrupan opciones de filtro con estados por chip: normal,
/// selected (accent), hover (web), disabled, focus (ring teclado).
///
/// Uso:
/// ```dart
/// final t = TreinoChipTokens.of(context);
/// Container(
///   decoration: BoxDecoration(
///     color: isSelected ? t.selectedBackground : t.defaultBackground,
///     border: Border.all(
///       color: isSelected ? t.selectedBorder : Colors.transparent,
///     ),
///     borderRadius: BorderRadius.circular(t.borderRadius),
///   ),
///   child: Text(label, style: TextStyle(
///     color: isSelected ? t.selectedForeground : t.defaultForeground,
///   )),
/// )
/// ```
@immutable
class TreinoChipTokens {
  const TreinoChipTokens._({
    required this.defaultBackground,
    required this.defaultForeground,
    required this.selectedBackground,
    required this.selectedForeground,
    required this.selectedBorder,
    required this.disabledForeground,
    required this.hoverBackground,
  });

  /// Fondo del chip en estado normal — delega a `AppPalette.bgCard`.
  final Color defaultBackground;

  /// Color de texto en estado normal — delega a `AppPalette.textPrimary`.
  final Color defaultForeground;

  /// Fondo del chip seleccionado — acento con 15% de opacidad.
  final Color selectedBackground;

  /// Color de texto del chip seleccionado — delega a `AppPalette.accent`.
  final Color selectedForeground;

  /// Borde del chip seleccionado — delega a `AppPalette.accent`.
  final Color selectedBorder;

  /// Color de texto deshabilitado — delega a `AppPalette.textMuted`.
  final Color disabledForeground;

  /// Fondo en hover — acento con 8% de opacidad.
  final Color hoverBackground;

  /// Radio del chip — `AppRadius.full` = 9999.0 (pill completa).
  static const double borderRadius = AppRadius.full;

  /// Resuelve los tokens de color según el tema activo.
  factory TreinoChipTokens.of(BuildContext ctx) {
    final p = AppPalette.of(ctx);
    return TreinoChipTokens._(
      defaultBackground: p.bgCard,
      defaultForeground: p.textPrimary,
      // 15% de opacidad sobre el acento.
      selectedBackground: p.accent.withValues(alpha: 0.15),
      selectedForeground: p.accent,
      selectedBorder: p.accent,
      disabledForeground: p.textMuted,
      // 8% de opacidad sobre el acento (igual que sidebar item hover).
      hoverBackground: p.accent.withValues(alpha: 0.08),
    );
  }
}
