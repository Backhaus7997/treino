import 'package:flutter/material.dart';

import '../app_motion.dart';

/// Capa 3b — Tokens de movimiento semánticos del sistema de diseño TREINO.
///
/// Re-exporta los valores de [AppMotion] con nombres de intención de componente.
/// Ningún valor de runtime cambia: todo delega a [AppMotion] sin agregar lógica.
///
/// **AppMotion sigue siendo la fuente de verdad** — las 93 ocurrencias existentes
/// de `AppMotion.*` no se rompen. Esta capa es ADITIVA.
///
/// Uso preferido en código nuevo:
/// ```dart
/// AnimatedContainer(
///   duration: AppMotion.resolve(context, AppMotionTokens.cardStateChange),
///   curve: AppMotionTokens.enter,
///   child: ...,
/// )
/// ```
abstract final class AppMotionTokens {
  // ---------------------------------------------------------------------------
  // Duraciones semánticas (delegan a AppMotion)
  // ---------------------------------------------------------------------------

  /// `120ms` — Feedback de tap, toggles, selección de chip.
  /// Delega a [AppMotion.micro].
  static const Duration tapFeedback = AppMotion.micro;

  /// `180ms` — Cambio de estado de cards y containers chicos.
  /// Delega a [AppMotion.fast].
  static const Duration cardStateChange = AppMotion.fast;

  /// `240ms` — Transición de estado de entidad (loading→data, switch de tab).
  /// Delega a [AppMotion.base].
  static const Duration stateSwitch = AppMotion.base;

  /// `240ms` — Entrada de contenido principal, expand/collapse.
  /// Delega a [AppMotion.base].
  static const Duration contentEnter = AppMotion.base;

  /// `320ms` — Transición de página/hero, pill del tab bar.
  /// Delega a [AppMotion.slow].
  static const Duration pageTransition = AppMotion.slow;

  // ---------------------------------------------------------------------------
  // Curvas semánticas (delegan a AppMotion)
  // ---------------------------------------------------------------------------

  /// Curva de entrada — desacelera al final.
  /// Delega a [AppMotion.standard] (`easeOutCubic`).
  static const Curve enter = AppMotion.standard;

  /// Curva de reposicionamiento — acelera y desacelera.
  /// Delega a [AppMotion.emphasized] (`easeInOutCubic`).
  static const Curve reposition = AppMotion.emphasized;

  /// Curva de salida — acelera hacia el final.
  /// Delega a [AppMotion.exit] (`easeInCubic`).
  static const Curve leave = AppMotion.exit;

  // ---------------------------------------------------------------------------
  // Distancias de slide semánticas (delegan a AppMotion)
  // ---------------------------------------------------------------------------

  /// `8px` — Desplazamiento de row/chip densa.
  /// Delega a [AppMotion.slideSm].
  static const double rowSlide = AppMotion.slideSm;

  /// `12px` — Desplazamiento default de entrada de card/ítem.
  /// Delega a [AppMotion.slideMd].
  static const double cardSlide = AppMotion.slideMd;

  /// `20px` — Desplazamiento amplio de hero cards y secciones.
  /// Delega a [AppMotion.slideLg].
  static const double heroSlide = AppMotion.slideLg;

  // ---------------------------------------------------------------------------
  // Helpers de accesibilidad (delegan a AppMotion)
  // ---------------------------------------------------------------------------

  /// Delega a [AppMotion.reduceMotion] — respeta preferencia del sistema.
  static bool reduceMotion(BuildContext context) =>
      AppMotion.reduceMotion(context);

  /// Delega a [AppMotion.resolve] — puerta única para respetar reduceMotion.
  static Duration resolve(BuildContext context, Duration duration) =>
      AppMotion.resolve(context, duration);
}
