import 'package:flutter/material.dart';

/// Capa 1 — Tokens primitivos de color del sistema de diseño TREINO.
///
/// Contiene valores absolutos con nombres escala-neutrales (ej. `mint500`,
/// `ink950`). Esta capa es insumo EXCLUSIVO de [AppPalette] (capa semántica).
/// Ningún widget debe referenciarla directamente.
///
/// No requiere [BuildContext] — todas las constantes son `static const`.
abstract final class AppColorPrimitives {
  // ---------------------------------------------------------------------------
  // Familia Mint (verde esmeralda — acento primario)
  // ---------------------------------------------------------------------------

  /// `#2CE5A2` — Mint esmeralda, acento primario TREINO.
  static const Color mint500 = Color(0xFF2CE5A2);

  // ---------------------------------------------------------------------------
  // Familia Magenta (destaque secundario)
  // ---------------------------------------------------------------------------

  /// `#C123E0` — Magenta vibrante, destaque/highlight.
  static const Color magenta500 = Color(0xFFC123E0);

  // ---------------------------------------------------------------------------
  // Familia Ink (fondos oscuros)
  // ---------------------------------------------------------------------------

  /// `#0A0A0A` — Ink más profundo, fondo de pantalla dark.
  static const Color ink950 = Color(0xFF0A0A0A);

  /// `#0F1513` — Ink profundo con tinte mint, fondo de card dark.
  static const Color ink900 = Color(0xFF0F1513);

  // ---------------------------------------------------------------------------
  // Familia Bone (texto claro)
  // ---------------------------------------------------------------------------

  /// `#FFFFFF` — Blanco puro, texto primario sobre dark.
  static const Color bone = Color(0xFFFFFFFF);

  // ---------------------------------------------------------------------------
  // Familia Sage (verde salvia — superficies secundarias)
  // ---------------------------------------------------------------------------

  /// `#4F6358` — Sage oscuro, superficies secundarias dark.
  static const Color sage500 = Color(0xFF4F6358);

  /// `#DDE5DF` — Sage claro / tint, superficies secundarias light.
  static const Color sageTint50 = Color(0xFFDDE5DF);

  // ---------------------------------------------------------------------------
  // Familia Espresso (superficies elevadas)
  // ---------------------------------------------------------------------------

  /// `#3C3534` — Espresso oscuro, sheets y superficies elevadas dark.
  static const Color espresso500 = Color(0xFF3C3534);

  /// `#EDE5E2` — Espresso claro / tint, superficies elevadas light.
  static const Color espressoTint50 = Color(0xFFEDE5E2);

  // ---------------------------------------------------------------------------
  // Familia Danger (rojo)
  // ---------------------------------------------------------------------------

  /// `#E53935` — Rojo de error/peligro, estado dark.
  static const Color dangerRed = Color(0xFFE53935);

  /// `#D32F2F` — Rojo de error/peligro, estado light (mayor contraste).
  static const Color dangerRedDark = Color(0xFFD32F2F);

  // ---------------------------------------------------------------------------
  // Familia Warning (ámbar)
  // ---------------------------------------------------------------------------

  /// `#FFB300` — Ámbar de advertencia, estado dark.
  static const Color warningAmber = Color(0xFFFFB300);

  /// `#FB8C00` — Ámbar de advertencia, estado light.
  static const Color warningAmberDark = Color(0xFFFB8C00);

  // ---------------------------------------------------------------------------
  // Colores neutros absolutos
  // ---------------------------------------------------------------------------

  /// `#FFFFFF` — Blanco absoluto (onDanger, fondo light-card).
  static const Color white = Color(0xFFFFFFFF);

  /// `#000000` — Negro absoluto (scrims).
  static const Color black = Color(0xFF000000);

  // ---------------------------------------------------------------------------
  // Blancos con alpha (overlays sobre dark)
  // ---------------------------------------------------------------------------

  /// `0x1AFFFFFF` — Blanco ~10% alpha, borde en dark.
  static const Color white10 = Color(0x1AFFFFFF);

  /// `0x33FFFFFF` — Blanco ~20% alpha, borde hover en dark.
  static const Color white20 = Color(0x33FFFFFF);

  /// `0x8CFFFFFF` — Blanco ~55% alpha, texto mutado en dark.
  static const Color white55 = Color(0x8CFFFFFF);

  // ---------------------------------------------------------------------------
  // Negros con alpha (overlays sobre light)
  // ---------------------------------------------------------------------------

  /// `0x1A000000` — Negro ~10% alpha, borde en light.
  static const Color black10 = Color(0x1A000000);

  /// `0x33000000` — Negro ~20% alpha, borde hover en light.
  static const Color black20 = Color(0x33000000);

  /// `0x99000000` — Negro ~60% alpha, texto mutado en light.
  static const Color black60 = Color(0x99000000);

  // ---------------------------------------------------------------------------
  // Familia Paper (fondos claros)
  // ---------------------------------------------------------------------------

  /// `#FAFAFA` — Fondo de pantalla light.
  static const Color paper50 = Color(0xFFFAFAFA);

  // ---------------------------------------------------------------------------
  // Familia InkText (texto sobre light)
  // ---------------------------------------------------------------------------

  /// `#0F1513` — Texto primario sobre fondos light.
  static const Color inkText900 = Color(0xFF0F1513);
}

/// Capa 1 — Tokens de spacing del sistema de diseño TREINO.
///
/// Escala CERRADA: `8 · 12 · 14 · 18 · 20`. No existen `s4`, `s16` ni `s24`.
/// Ver `docs/design-system.md` — escala de espaciado.
abstract final class AppSpacing {
  /// `8.0` — Espaciado mínimo (chips, gap interno de rows densas).
  static const double s8 = 8.0;

  /// `12.0` — Espaciado pequeño (padding interno de cards).
  static const double s12 = 12.0;

  /// `14.0` — Espaciado mediano-bajo (padding de secciones compactas).
  static const double s14 = 14.0;

  /// `18.0` — Espaciado mediano (padding horizontal de pantallas).
  static const double s18 = 18.0;

  /// `20.0` — Espaciado grande (padding de hero cards, secciones amplias).
  static const double s20 = 20.0;
}

/// Capa 1 — Tokens de radio de borde del sistema de diseño TREINO.
///
/// Valores: `sm=12 · md=16 · lg=20 · full=9999`.
abstract final class AppRadius {
  /// `12.0` — Radio pequeño (chips, badges, inputs).
  static const double sm = 12.0;

  /// `16.0` — Radio mediano (cards, dialogs).
  static const double md = 16.0;

  /// `20.0` — Radio grande (bottom sheets, modales).
  static const double lg = 20.0;

  /// `9999.0` — Radio completamente redondeado (pills, avatares).
  static const double full = 9999.0;
}

/// Capa 1 — Tokens tipográficos del sistema de diseño TREINO.
///
/// Solo expone familias y pesos. Los [TextStyle] completos viven en
/// `app_theme.dart` (ADR-DS2-009).
abstract final class AppFonts {
  /// Familia de cuerpo de texto: `'Barlow'` (pesos 400/600/700).
  static const String barlow = 'Barlow';

  /// Familia de headings: `'Barlow Condensed'` (peso 700, UPPERCASE).
  static const String barlowCondensed = 'Barlow Condensed';

  // Pesos semánticos.

  /// `400` — Peso regular de cuerpo.
  static const FontWeight w400 = FontWeight.w400;

  /// `600` — Peso semibold (labels, subtítulos).
  static const FontWeight w600 = FontWeight.w600;

  /// `700` — Peso bold (headings, CTAs).
  static const FontWeight w700 = FontWeight.w700;

  /// `0.5` — Letter-spacing de headings condensados.
  static const double headingTracking = 0.5;
}
