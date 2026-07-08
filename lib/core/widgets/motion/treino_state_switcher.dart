import 'package:flutter/material.dart';

import '../../../app/theme/app_motion.dart';

/// Cross-fade entre estados de una pantalla (loading → data → error) —
/// TREINO Motion PR2. Wrapper fino sobre [AnimatedSwitcher] con los tokens
/// del sistema ya cableados:
///
/// - `duration`: [AppMotion.base] pasado por [AppMotion.resolve] — con
///   reduce-motion activo el cambio es instantáneo ([Duration.zero]).
/// - Curvas: [AppMotion.standard] de entrada, [AppMotion.exit] de salida.
/// - Transición fade-only ([FadeTransition]) — anima opacity en la capa de
///   composición, sin repaint del subtree (docs/performance.md).
/// - Layout top-aligned: pantallas de alto distinto no "saltan" al centro
///   durante el cross-fade (el default de [AnimatedSwitcher] centra).
///
/// **El caller DEBE diferenciar los estados con keys distintas** (p. ej.
/// `ValueKey('loading')` vs `ValueKey('data')`) vía [childKey] o poniendo la
/// key en el child directamente. Si dos estados comparten runtimeType y key,
/// [AnimatedSwitcher] los considera el mismo widget y NO anima el cambio.
class TreinoStateSwitcher extends StatelessWidget {
  const TreinoStateSwitcher({
    super.key,
    required this.child,
    this.childKey,
  });

  /// El widget del estado actual (resultado del `.when()` del AsyncValue).
  final Widget child;

  /// Key que identifica el estado actual (`ValueKey('loading')` /
  /// `ValueKey('data')` / `ValueKey('error')`). Si se pasa, [child] se
  /// envuelve en un [KeyedSubtree] — así el caller no tiene que poner la
  /// key en cada branch del `.when()`.
  final Key? childKey;

  /// Igual que el layoutBuilder default de [AnimatedSwitcher] pero alineado
  /// arriba-centro: durante el cross-fade el child saliente y el entrante se
  /// apilan desde el tope, no desde el centro.
  static Widget _topAlignedLayout(
    Widget? currentChild,
    List<Widget> previousChildren,
  ) {
    return Stack(
      alignment: Alignment.topCenter,
      children: <Widget>[
        ...previousChildren,
        if (currentChild != null) currentChild,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.resolve(context, AppMotion.base),
      switchInCurve: AppMotion.standard,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      layoutBuilder: _topAlignedLayout,
      child:
          childKey == null ? child : KeyedSubtree(key: childKey, child: child),
    );
  }
}
