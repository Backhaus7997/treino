import 'package:flutter/material.dart';

import '../primitives.dart';
import '../../app_palette.dart';

/// Capa 3 — Tokens de componente para SectionHeader Coach Hub Web.
///
/// SectionHeader reemplaza al `section_header.dart` del shell. Cabeceras
/// de sección con tipografía Barlow Condensed 700 UPPERCASE.
///
/// Uso:
/// ```dart
/// final t = TreinoSectionHeaderTokens.of(context);
/// Text(
///   label.toUpperCase(),
///   style: TextStyle(
///     color: t.titleColor,
///     fontSize: t.fontSize,
///     fontFamily: t.fontFamily,
///     fontWeight: t.fontWeight,
///   ),
/// )
/// ```
@immutable
class TreinoSectionHeaderTokens {
  const TreinoSectionHeaderTokens._({
    required this.titleColor,
    required this.actionColor,
    required this.disabledColor,
  });

  /// Color del título de sección — delega a `AppPalette.textPrimary`.
  final Color titleColor;

  /// Color del botón de acción opcional — delega a `AppPalette.accent`.
  final Color actionColor;

  /// Color en estado deshabilitado — delega a `AppPalette.textMuted`.
  final Color disabledColor;

  /// Tamaño de fuente del título — 12.0 px (Barlow Condensed 700 UPPERCASE).
  static const double fontSize = 12.0;

  /// Familia tipográfica del título — `AppFonts.barlowCondensed`.
  static const String fontFamily = AppFonts.barlowCondensed;

  /// Peso de fuente del título — `AppFonts.w700`.
  static const FontWeight fontWeight = AppFonts.w700;

  /// Resuelve los tokens de color según el tema activo.
  factory TreinoSectionHeaderTokens.of(BuildContext ctx) {
    final p = AppPalette.of(ctx);
    return TreinoSectionHeaderTokens._(
      titleColor: p.textPrimary,
      actionColor: p.accent,
      disabledColor: p.textMuted,
    );
  }
}
