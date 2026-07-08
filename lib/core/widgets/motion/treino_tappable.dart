import 'package:flutter/material.dart';

import '../../../app/theme/app_motion.dart';

/// Feedback de presión universal — TREINO Motion PR3.
///
/// Envuelve un CTA y lo escala a [pressedScale] (`0.97`) mientras el dedo
/// está apoyado (tap-down), volviendo a `1.0` al soltar o cancelar. Es el
/// reemplazo del ripple de Material para los botones de alto contacto de la
/// app: un feedback físico ("el botón se hunde") consistente en iOS y
/// Android, estilo Hevy.
///
/// **Reemplaza, no envuelve**: en cada call-site migrado, `TreinoTappable`
/// REEMPLAZA al `GestureDetector`/`InkWell` existente y absorbe su `onTap`.
/// Nunca se envuelve un botón que ya maneja taps (ElevatedButton, InkWell
/// con onTap activo): los dos recognizers competirían en el gesture arena y
/// el de afuera perdería siempre — scale que arranca y se cancela, feedback
/// roto.
///
/// - [onTap] `null` → **sin gesture**: devuelve el child pelado (estado
///   disabled). No hay `GestureDetector` ni `AnimatedScale` en el árbol.
/// - Reduce-motion ([AppMotion.reduceMotion]) → el tap sigue funcionando
///   pero sin scale: no se construye el `AnimatedScale` ni se trackea el
///   estado de presión (además de que [AppMotion.resolve] ya daría
///   `Duration.zero`, evitamos el trabajo directamente).
/// - Implicit-first (docs/performance.md): usa [AnimatedScale], sin
///   controller.
///
/// Nota de API: el gate de "disabled" es [onTap]. Un [onLongPress] sin
/// [onTap] también devuelve el child pelado — todos los CTAs del sistema
/// tienen tap como acción primaria.
class TreinoTappable extends StatefulWidget {
  const TreinoTappable({
    super.key,
    this.onTap,
    this.onLongPress,
    required this.child,
  });

  /// Acción primaria. `null` → disabled: child pelado, sin gesture.
  final VoidCallback? onTap;

  /// Acción secundaria opcional (long-press). Solo se registra si [onTap]
  /// también existe.
  final VoidCallback? onLongPress;

  /// El CTA a escalar (pill, card, icono — ya estilado por el caller).
  final Widget child;

  /// Escala durante la presión. `0.97` per spec de PR3 — hundimiento sutil,
  /// no un botón de dibujito.
  static const double pressedScale = 0.97;

  @override
  State<TreinoTappable> createState() => _TreinoTappableState();
}

class _TreinoTappableState extends State<TreinoTappable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    // Disabled: sin gesture, sin scale — child tal cual.
    if (widget.onTap == null) return widget.child;

    final reduce = AppMotion.reduceMotion(context);

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      // Con reduce-motion no trackeamos presión: ni setState ni AnimatedScale.
      onTapDown: reduce ? null : (_) => _setPressed(true),
      onTapUp: reduce ? null : (_) => _setPressed(false),
      onTapCancel: reduce ? null : () => _setPressed(false),
      // opaque: toda el área del CTA responde, no solo los px pintados —
      // mismo comportamiento que los GestureDetector que reemplaza.
      behavior: HitTestBehavior.opaque,
      child: reduce
          ? widget.child
          : AnimatedScale(
              scale: _pressed ? TreinoTappable.pressedScale : 1.0,
              duration: AppMotion.resolve(context, AppMotion.micro),
              curve: AppMotion.standard,
              child: widget.child,
            ),
    );
  }
}
