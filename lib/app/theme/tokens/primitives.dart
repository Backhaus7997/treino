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
  // Familia Reactions (reacciones del feed)
  // ---------------------------------------------------------------------------

  /// `#FF4D6D` — Rosa de "me gusta", estado dark.
  static const Color reactionLike = Color(0xFFFF4D6D);

  /// `#E63950` — Rosa de "me gusta", estado light (mayor contraste).
  static const Color reactionLikeDark = Color(0xFFE63950);

  /// `#FF7A2F` — Naranja de "fuego", estado dark.
  static const Color reactionFire = Color(0xFFFF7A2F);

  /// `#F4630C` — Naranja de "fuego", estado light (mayor contraste).
  static const Color reactionFireDark = Color(0xFFF4630C);

  /// `#FFC93C` — Ámbar de "aplauso", estado dark.
  static const Color reactionClap = Color(0xFFFFC93C);

  /// `#D99000` — Ámbar dorado de "aplauso", estado light.
  ///
  /// Es ámbar dorado y no el mostaza `#B87500` que salía de maximizar
  /// contraste: a ese tono los aplausos se leían apagados y no como el emoji
  /// 👏.
  ///
  /// Da ~3:1 sobre `bgCard`, algo menos que los otros dos, y es aceptable acá
  /// porque el color NO es el único indicador de estado: la reacción propia
  /// además cambia de contorno a relleno. Un daltónico distingue el estado por
  /// la forma sin depender del tono. Ver `_iconFor` en `post_reactions_row.dart`.
  static const Color reactionClapDark = Color(0xFFD99000);

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
  // Transparente (evita `Colors.transparent` crudo en el kit)
  // ---------------------------------------------------------------------------

  /// `0x00000000` — Transparente absoluto. Usar en vez de `Colors.transparent`
  /// crudo en decoraciones del kit (ej. `Border.all` invisible).
  static const Color transparent = Color(0x00000000);

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

/// Capa 1 — Paletas DECORATIVAS multi-tono.
///
/// A diferencia de [AppColorPrimitives], que es insumo exclusivo de la capa
/// semántica, estas paletas SÍ pueden referenciarse desde un widget: no
/// representan un rol semántico (acento, peligro, borde) sino un conjunto
/// arbitrario de tonos usado por su variedad, no por su significado.
///
/// Viven acá por una razón mecánica: `no_hex_scan_test` permite hex literal
/// únicamente en este archivo, y su ratchet prohíbe agrandar la allowlist. Que
/// el hex viva acá mantiene una sola fuente de verdad de valores crudos sin
/// contaminar el contrato de [AppColorPrimitives].
abstract final class AppDecorativePalettes {
  /// Paleta del confeti de festejo (`TreinoConfetti`).
  ///
  /// Set fijo y variado, **deliberadamente NO ligado a Mint Magenta**: si el
  /// festejo usara los acentos de marca se sentiría como "dos tonos de la
  /// marca otra vez" en vez de una celebración. Esa era la excepción que el
  /// autor de `treino_confetti.dart` documentó a mano; se preserva el criterio
  /// y sólo se muda el valor.
  static const List<Color> confetti = [
    Color(0xFFFF6B6B), // rojo coral
    Color(0xFFFFD93D), // amarillo
    Color(0xFF6BCB77), // verde
    Color(0xFF4D96FF), // azul
    Color(0xFFB983FF), // violeta
    Color(0xFFFF9F45), // naranja
    Color(0xFFFF6FB5), // rosa
  ];

  /// Paleta de avatares del chat del Coach Hub.
  ///
  /// Se elige de forma determinística a partir del uid, así el mismo alumno
  /// siempre tiene el mismo color. Tonos saturados que contrastan sobre fondos
  /// oscuros y con la inicial en blanco. El ORDEN es significativo: cambiarlo
  /// le cambia el color a todos los usuarios existentes.
  static const List<Color> avatar = [
    Color(0xFF8B5CF6), // violeta
    Color(0xFFF59E0B), // ámbar
    Color(0xFFEF4444), // rojo
    Color(0xFF10B981), // verde
    Color(0xFF3B82F6), // azul
    Color(0xFFEC4899), // rosa
    Color(0xFF14B8A6), // teal
    Color(0xFFF97316), // naranja
  ];

  /// Sombra proyectada del marco de teléfono del onboarding
  /// (`OnboardingDevicePreview`).
  ///
  /// Decorativa y **deliberadamente invariante al tema**, igual que el bezel
  /// blanco que la proyecta: ese marco representa el chasis físico de un
  /// teléfono, no UI de la app, así que no sigue a la paleta. Por eso no es
  /// `AppPalette.shadow` ni un primitivo semántico.
  ///
  /// El valor coincide con [AppColorPrimitives.ink900] por casualidad
  /// cromática, no por parentesco: si el ink de marca cambia, esta sombra no
  /// tiene por qué seguirlo.
  static const Color deviceFrameShadow = Color(0xFF0F1513);
}

/// Capa 1 — Tokens de spacing del sistema de diseño TREINO.
///
/// Escala CERRADA: `8 · 12 · 14 · 18 · 20`. No existen `s4`, `s16` ni `s24`.
/// Ver `docs/design-system.md` — escala de espaciado.
///
/// Única excepción: [hairline], para separaciones ópticas genuinamente
/// sub-8 (ej. ícono-a-texto). No crear más micro-tokens ad-hoc — usar
/// [hairline] en todo el kit en vez de números crudos como `2`, `4` o `6`.
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

  /// `4.0` — Micro-gap EXCEPCIONAL, fuera de la escala cerrada. Reservado a
  /// separaciones ópticas sub-8 entre elementos (ej. valor-a-label,
  /// ícono-a-texto, título-a-subtítulo), y al gutter INTERNO de un componente
  /// del kit cuando dos capas del mismo control se tocan (ej. contorno-a-thumb
  /// en `TreinoSegmentedPill`).
  ///
  /// Nunca para padding de LAYOUT — la separación entre elementos de una
  /// pantalla siempre resuelve a un valor de la escala cerrada. La distinción
  /// es dueño: si el espacio es geometría interna de un componente, es
  /// [hairline]; si separa cosas que el layout compone, es la escala.
  ///
  /// El caso del gutter se agregó con #646: la redacción anterior prohibía todo
  /// padding, lo que dejaba a esa separación sin token válido y empujaba a los
  /// componentes a escribir `4` crudo — que es justo lo que este token existe
  /// para evitar.
  static const double hairline = 4.0;
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
