import 'package:flutter/material.dart';

import '../primitives.dart';
import '../../app_palette.dart';

/// Capa 3 — Tokens del control segmentado de sub-navegación
/// ([TreinoSegmentedPill]).
///
/// El defecto que originó estos tokens (#646) NO era el contraste del texto:
/// era que el control no tenía CONTORNO VISIBLE. El borde
/// (`textMuted` al 12%) medía 1.50:1 en dark y 1.26:1 en light contra el fondo
/// de página, y `AppPalette.border` apenas 1.40:1 / 1.20:1 — WCAG 1.4.11 pide
/// 3:1 para identificar un componente de UI. Sin contorno, el conjunto se leía
/// como "un badge de acento al lado de una palabra gris", que es literalmente
/// lo que reportaron los participantes de las pruebas de usabilidad.
///
/// El label inactivo, en cambio, SIEMPRE cumplió (6.19:1 dark / 5.74:1 light).
/// No lo toques buscando arreglar la legibilidad: el problema era el límite.
///
/// Reparto de responsabilidades — leer antes de mover cualquier valor:
///
///  - [trackBorder] es el ÚNICO responsable del 3:1 del contorno. Es
///    deliberadamente más fuerte que el borde de las cards (`AppPalette.border`,
///    ~1.3:1): las cards son cromo decorativo, esto es un control operable. Esa
///    diferencia de peso ES la señal de affordance.
///  - [activeInk] hace DOS trabajos: el label del segmento activo y el keyline
///    del thumb. Es la misma invariante que `TreinoButtonTokens.foreground`, y
///    `treino_segmented_pill_tokens_test.dart` las pinea juntas para que no
///    puedan divergir.
///  - El estado seleccionado llega a 3:1 contra la pista en ambos temas, pero
///    NO por el mismo elemento: en dark lo carga el relleno ([activeFill],
///    11.29:1) y en light el keyline ([activeInk], 19.80:1), porque el mint
///    sobre una pista clara da apenas 1.64:1. Sacar el keyline deja el tema
///    claro sin forma de distinguir qué pestaña está activa.
///
/// Por qué esto se escapó hasta #646: `AGENTS.md` afirmaba que la app no tenía
/// tema claro. Lo tiene, y arranca en `ThemeMode.system`. Todo par de tokens
/// donde `accent` sea fondo se mide en LAS DOS paletas.
///
/// ALCANCE: se migraron las cuatro copias mobile. La quinta —`_Tabs` en
/// `alumno_detail_screen.dart`, Coach Hub web— sigue con `labelColor:
/// palette.bg` y alto 38, o sea que TODAVÍA arrastra las dos fallas de arriba.
/// Y no es sólo dark: `coach_hub_app.dart` también resuelve `AppTheme.light()`
/// contra `ThemeMode.system`. Quedó afuera a propósito, no por olvido: ese
/// archivo está bajo el rediseño `kit v2` que se está mergeando. Migrarla es un
/// PR aparte y es lo que cierra #646 del todo.
///
/// Uso:
/// ```dart
/// final t = TreinoSegmentedPillTokens.of(context);
/// Container(
///   padding: const EdgeInsets.all(TreinoSegmentedPillTokens.trackPadding),
///   decoration: BoxDecoration(
///     color: t.trackFill,
///     border: Border.all(color: t.trackBorder),
///     borderRadius: BorderRadius.circular(TreinoSegmentedPillTokens.trackRadius),
///   ),
/// )
/// ```
@immutable
class TreinoSegmentedPillTokens {
  const TreinoSegmentedPillTokens._({
    required this.trackFill,
    required this.trackBorder,
    required this.activeFill,
    required this.inactiveLabel,
    required this.hoverOverlay,
    required this.pressedOverlay,
    required this.focusOverlay,
  });

  /// Relleno de la pista — delega a `AppPalette.bgCard`.
  final Color trackFill;

  /// Contorno de la pista — `AppPalette.textMuted` al 45%.
  ///
  /// El 45% no es estético, es el valor redondo más bajo que cruza 3:1 en los
  /// dos temas: 4.83:1 en dark y 3.22:1 en light, midiendo el borde compuesto
  /// sobre [trackFill] contra `AppPalette.bg`. Con 30% el tema claro cae a
  /// 2.03:1 y falla. Está compuesto sobre el relleno propio porque
  /// `BorderSide` se pinta hacia adentro.
  final Color trackBorder;

  /// Relleno del segmento activo — delega a `AppPalette.accent`.
  final Color activeFill;

  /// Label del segmento inactivo — delega a `AppPalette.textMuted`.
  final Color inactiveLabel;

  /// Overlay de hover (web) — `textPrimary` al 8%.
  ///
  /// Sale de `textPrimary` y NO del acento, aunque el resto del kit tiña con
  /// acento: sobre la pista, un overlay de acento al 8% es casi indistinguible
  /// del propio acento del thumb que tiene al lado. `textPrimary` es el
  /// contrario cromático del tema, así que se lee claro sobre `bgCard` en los
  /// dos temas.
  ///
  /// ⚠️ LIMITACIÓN: estos overlays sólo se ven en las celdas INACTIVAS. La
  /// tinta de Material se pinta DEBAJO de todo el subárbol
  /// (`_RenderInkFeatures.paint` dibuja las ink features y recién después
  /// llama a `super.paint`), y `TabBar` mete el indicador en un `CustomPaint`
  /// que pinta su painter antes que los hijos. El orden real es
  /// `pista → tinta → thumb → labels`, así que el thumb opaco tapa el overlay
  /// de la celda activa. No lo arregla ningún color: es el z-order del
  /// framework. Para cambiarlo habría que abandonar el `indicator` de `TabBar`
  /// y pintar el thumb dentro de cada `Tab`, que es el rediseño que
  /// [TreinoSegmentedPill] evita a propósito.
  final Color hoverOverlay;

  /// Overlay de presión — `textPrimary` al 12%.
  ///
  /// Las cuatro copias migradas seteaban `splashBorderRadius` pero dejaban el
  /// overlay en el default de `ThemeData`, imperceptible sobre casi-negro. "No
  /// pasa nada cuando lo toco" es la otra mitad de "no parece un botón".
  final Color pressedOverlay;

  /// Overlay de foco de teclado — `textPrimary` al 20%.
  ///
  /// No es el anillo de 2px de `TreinoFocusTokens`: `TabBar` no expone un hook
  /// para trazar un borde en la pestaña enfocada, sólo para teñirla.
  ///
  /// ⚠️ Por la limitación de z-order que describe [hoverOverlay], este overlay
  /// NO alcanza para el foco: no se ve cuando cae sobre la celda ACTIVA, que es
  /// justo donde queda parado el usuario después de activar una pestaña por
  /// teclado. Sería un hueco de WCAG 2.4.7.
  ///
  /// Por eso `TreinoSegmentedPill` NO se apoya sólo en esto: dibuja además un
  /// anillo de [TreinoFocusTokens] en la PISTA cuando alguna celda tiene el
  /// foco. Ahí el z-order deja de importar, porque el anillo va por fuera del
  /// thumb. Este overlay queda como refuerzo sobre las celdas inactivas.
  ///
  /// Si algún consumidor futuro usa estos tokens sin ese anillo, hereda el
  /// hueco. No es opcional.
  final Color focusOverlay;

  /// Ink del segmento activo: label Y keyline del thumb.
  ///
  /// Invariante de tema (el acento es el mismo mint en dark y light), por eso
  /// vive como `static const` en vez de en el `factory .of` — mismo criterio
  /// que `TreinoChipTokens.transparentBorder`.
  ///
  /// Reemplaza a `AppPalette.bg`, que era lo que usaban las copias migradas: sobre
  /// el mint daba 12.10:1 en dark pero **1.57:1 en light**, un fallo WCAG AA
  /// real. Con ink es 12.10:1 en los dos.
  static const Color activeInk = AppColorPrimitives.ink950;

  /// Divisor inferior del `TabBar` — siempre invisible. Evita que el widget
  /// del kit escriba `Colors.transparent` crudo.
  static const Color dividerColor = AppColorPrimitives.transparent;

  /// Peso del label — `AppFonts.w700`.
  ///
  /// Expuesto acá, y no leído de `AppFonts` en el widget, para que el kit no
  /// importe capa 1 directamente — mismo criterio que [dividerColor].
  static const FontWeight labelWeight = AppFonts.w700;

  /// Tracking del label — `AppFonts.headingTracking`.
  static const double labelTracking = AppFonts.headingTracking;

  /// Radio de la pista — `AppRadius.full` = 9999.0.
  static const double trackRadius = AppRadius.full;

  /// Radio del segmento activo — `AppRadius.full`. Concéntrico con la pista
  /// por construcción, sin cuentas.
  static const double segmentRadius = AppRadius.full;

  /// Grosor del contorno de la pista y del keyline del thumb.
  ///
  /// Se queda en 1.0: `BorderSide` se pinta hacia adentro, así que
  /// ensancharlo desplazaría el contenido en todas las pantallas migradas.
  static const double borderWidth = 1.0;

  /// Gutter óptico entre el contorno de la pista y el thumb.
  ///
  /// Usa [AppSpacing.hairline] (4), no un literal: es exactamente la separación
  /// óptica sub-8 que `hairline` existe para cubrir, sólo que interna a un
  /// componente en vez de entre dos elementos hermanos. El dartdoc de
  /// `hairline` se amplió en este mismo cambio para nombrar ese caso — antes
  /// prohibía todo padding y dejaba a este gutter sin token válido, con las
  /// copias originales resolviéndolo con `EdgeInsets.all(4)` crudo.
  ///
  /// Subirlo a `AppSpacing.s8` llevaría el control a ~60pt de alto y apretaría
  /// la fila del header del Feed contra sus acciones de 44pt.
  static const double trackPadding = AppSpacing.hairline;

  /// Padding horizontal de cada label — `AppSpacing.s8`.
  ///
  /// El valor más chico de la escala cerrada, y no por estética: el Feed
  /// encierra su pill en `maxWidth: 176` y comparte fila con cuatro acciones de
  /// 44pt. En un Pixel 5 (340dp) quedan ~116dp para el control; con 12 de
  /// padding sobran ~30dp por etiqueta y el `FittedBox` encoge RANKINGS ~21%
  /// respecto de lo que se veía antes. Con 8 vuelve a ~38dp.
  static const double labelPadding = AppSpacing.s8;

  /// Aire vertical TOTAL que se suma al alto de línea del label para calcular
  /// el alto del segmento — `AppSpacing.s20`.
  ///
  /// **No es un padding por lado.** Se suma UNA vez:
  ///
  /// ```dart
  /// segmentHeight = max(minSegmentHeight, scaledLabelHeight + labelVerticalRoom)
  /// ```
  ///
  /// A escala 1.0 el label mide `14 × 1.2 = 16.8`, así que `16.8 + 20 = 36.8` y
  /// gana el piso de [minSegmentHeight]: la celda queda en 44 y el control en
  /// 54 (44 + 2×[trackPadding] + 2×[borderWidth]). Este token recién manda por
  /// encima de ~1.4× de escala de texto, que es su razón de existir — que el
  /// label no quede apretado con dynamic type grande.
  ///
  /// Se llamaba `segmentVerticalPadding` y el nombre mentía: leído como padding
  /// simétrico daba 40px y un control de ~64, que no es lo que pasa.
  static const double labelVerticalRoom = AppSpacing.s20;

  /// Altura mínima del segmento — piso de área tapeable.
  ///
  /// Las cuatro copias migradas estaban en 38-40, por debajo del mínimo de
  /// plataforma. Mismo número y mismo criterio que `_kFeedActionTapTarget` en
  /// `feed_screen.dart`.
  static const double minSegmentHeight = 44.0;

  /// Escala de texto a partir de la cual la pista scrollea en vez de repartir
  /// el ancho. Heurística heredada de `_AthleteWorkout`, ya probada en device.
  static const double scrollTextScaleThreshold = 1.3;

  /// Resuelve los tokens de color según el tema activo.
  factory TreinoSegmentedPillTokens.of(BuildContext ctx) {
    final p = AppPalette.of(ctx);
    return TreinoSegmentedPillTokens._(
      trackFill: p.bgCard,
      // 45% — ver el dartdoc de [trackBorder] para la aritmética.
      trackBorder: p.textMuted.withValues(alpha: 0.45),
      activeFill: p.accent,
      inactiveLabel: p.textMuted,
      // 8% de opacidad sobre el acento (igual que TreinoChipTokens.hover).
      hoverOverlay: p.textPrimary.withValues(alpha: 0.08),
      // 12% de opacidad sobre el acento.
      pressedOverlay: p.textPrimary.withValues(alpha: 0.12),
      // 20% de opacidad sobre el acento.
      focusOverlay: p.textPrimary.withValues(alpha: 0.20),
    );
  }
}
