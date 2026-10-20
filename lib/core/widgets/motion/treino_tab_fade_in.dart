import 'package:flutter/material.dart';

import '../../../app/theme/app_motion.dart';

/// Fade-in corto al montar un root de tab de la barra inferior.
///
/// **Por qué no es una `PageTransition`**: go_router arma el Navigator del
/// ShellRoute con el `DefaultTransitionDelegate`, y ese delegate NO anima un
/// reemplazo de página (la saliente se completa y la entrante se agrega sin
/// transición): un `CustomTransitionPage` con `transitionsBuilder` recibe la
/// animación ya en 1.0 y el cambio de tab sigue siendo un corte seco. Así que
/// el fade vive en el contenido: cada tab root se monta fresco (cada tab tiene
/// su `pageKey`) y entra con [AppMotion.fast] + [AppMotion.standard].
///
/// La saliente se desmonta al instante, por eso no hay dos tabs vivos ni taps
/// fantasma sobre la que se va: durante los ~180ms se ve el fondo del shell y
/// el tab nuevo apareciendo encima.
///
/// Reduce-motion → child pelado, sin controller ni FadeTransition.
class TreinoTabFadeIn extends StatefulWidget {
  const TreinoTabFadeIn({super.key, required this.child});

  final Widget child;

  @override
  State<TreinoTabFadeIn> createState() => _TreinoTabFadeInState();
}

class _TreinoTabFadeInState extends State<TreinoTabFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: AppMotion.fast);
  late final Animation<double> _opacity =
      _controller.drive(CurveTween(curve: AppMotion.standard));

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Acá (no en initState): reduce-motion necesita MediaQuery.
    if (!_started) {
      _started = true;
      if (AppMotion.reduceMotion(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    } else if (AppMotion.reduceMotion(context) && !_controller.isCompleted) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // El wrapper queda también con opacity 1.0 (no-op barato): sacarlo cambia
    // la profundidad del árbol y re-montaría el tab (perdería su State).
    return FadeTransition(
      opacity: _opacity,
      // Con opacity 0 FadeTransition excluye semántica por defecto; el tab
      // tiene que existir para el lector de pantalla desde el primer frame.
      alwaysIncludeSemantics: true,
      child: widget.child,
    );
  }
}
