import 'package:flutter/material.dart';

/// Tokens de movimiento del sistema de diseño TREINO ("TREINO Motion").
///
/// Igual que `AppPalette` centraliza el color y la escala `8·12·14·18·20`
/// centraliza el spacing, `AppMotion` centraliza el **movimiento**: duraciones,
/// curvas y distancias de slide. Ningún widget debe hardcodear
/// `Duration(milliseconds: N)` ni una `Curve` cruda — siempre vía estos tokens.
///
/// **Por qué una clase de consts y no un `ThemeExtension`**: el movimiento no
/// varía entre paletas (Mint Magenta / Electric Violet), así que no necesita
/// `lerp`/`copyWith`. Sigue el patrón de `AppColors`, no el de `AppPalette`.
///
/// **Doctrina** (ver `docs/performance.md`): la app es *implicit-first*. Estos
/// tokens alimentan `AnimatedContainer`/`AnimatedOpacity`/`AnimatedSwitcher` y
/// demás widgets implícitos. La escala de duraciones se derivó del default
/// emergente ya presente en el código (`180ms` + `easeOutCubic`).
@immutable
class AppMotion {
  const AppMotion._();

  // ---------------------------------------------------------------------------
  // Duraciones (semánticas). Consolidan los 6 valores dispersos que había
  // hardcodeados (150/180/200/220/320/350) en 4 escalones intencionales.
  // ---------------------------------------------------------------------------

  /// `120ms` — micro-interacciones: feedback de presión (tap-down), toggles,
  /// selección de chip. El escalón más rápido; se siente instantáneo.
  static const Duration micro = Duration(milliseconds: 120);

  /// `180ms` — **default del sistema**. Cards, containers, cambios de estado
  /// chicos. Era el valor más repetido del codebase (6 usos).
  static const Duration fast = Duration(milliseconds: 180);

  /// `240ms` — entradas de contenido, expand/collapse, `AnimatedSwitcher`
  /// entre loading→data.
  static const Duration base = Duration(milliseconds: 240);

  /// `320ms` — movimiento a nivel de página/hero: transición de ruta,
  /// pill del tab bar, scroll animado a un ítem.
  static const Duration slow = Duration(milliseconds: 320);

  /// `40ms` — intervalo entre hermanos en un stagger. Ver [stagger].
  static const Duration staggerStep = Duration(milliseconds: 40);

  // ---------------------------------------------------------------------------
  // Curvas (semánticas).
  // ---------------------------------------------------------------------------

  /// Curva por defecto: desacelera al final. Para entradas y la mayoría de la
  /// UI. Era la curva más usada del codebase (`easeOutCubic`, 6 usos).
  static const Curve standard = Curves.easeOutCubic;

  /// Acelera y desacelera: para movimientos más grandes o que piden atención
  /// (toggle de sidebar, transiciones de página con desplazamiento notable).
  static const Curve emphasized = Curves.easeInOutCubic;

  /// Acelera hacia el final: para salidas (algo que se va de pantalla).
  static const Curve exit = Curves.easeInCubic;

  // ---------------------------------------------------------------------------
  // Distancias de slide (px). RESPETAN la escala de spacing `8·12·14·18·20`
  // (docs/design-system.md) — un slide nunca puede ser 16px, igual que el
  // padding. Son las distancias de desplazamiento de una entrada fade+slide.
  // ---------------------------------------------------------------------------

  /// `8px` — desplazamiento sutil (elementos chicos, chips, filas densas).
  static const double slideSm = 8;

  /// `12px` — desplazamiento default de una entrada de card/ítem.
  static const double slideMd = 12;

  /// `20px` — desplazamiento amplio (hero cards, secciones grandes).
  static const double slideLg = 20;

  // ---------------------------------------------------------------------------
  // Helpers de accesibilidad y stagger.
  // ---------------------------------------------------------------------------

  /// `true` si el sistema pide **reducir movimiento** (iOS: Ajustes →
  /// Accesibilidad → Movimiento; Android: equivalente). Toda animación debe
  /// consultarlo para respetar la preferencia del usuario.
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// Resuelve una [duration] contra la preferencia de reduce-motion: devuelve
  /// `Duration.zero` si el usuario pidió reducir movimiento, o la [duration]
  /// original si no. Es la puerta única por la que pasa toda animación.
  ///
  /// ```dart
  /// AnimatedOpacity(
  ///   duration: AppMotion.resolve(context, AppMotion.fast),
  ///   opacity: _visible ? 1 : 0,
  ///   child: ...,
  /// )
  /// ```
  static Duration resolve(BuildContext context, Duration duration) =>
      reduceMotion(context) ? Duration.zero : duration;

  /// Delay de stagger para el ítem [index] de una lista, capado a [maxItems]
  /// (default 8) para que una lista larga no genere una cascada interminable.
  /// El ítem 0 no tiene delay; cada siguiente suma [staggerStep].
  ///
  /// ```dart
  /// TreinoFadeSlideIn(delay: AppMotion.stagger(index), child: card)
  /// ```
  static Duration stagger(int index, {int maxItems = 8}) =>
      staggerStep * index.clamp(0, maxItems - 1);
}
