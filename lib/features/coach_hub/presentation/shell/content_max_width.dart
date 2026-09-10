import 'package:flutter/widgets.dart';
import 'package:treino/app/theme/tokens/components/coach_hub_layout_tokens.dart';

/// Techo de ancho de las secciones anchas. Más generoso que el de las otras
/// porque muestran un catálogo o dos paneles a la vez, pero sigue acotado: en
/// un ultrawide una fila de 3440 px no se lee.
const double kWideContentMaxWidth = 1920;

/// Secciones que se salen del techo de 1240.
///
/// - `/biblioteca` — catálogo de 811 ítems en grilla.
/// - `/routine-editor` y `/template-editor` — son una superficie de TRABAJO de
///   dos paneles: la rutina a la izquierda y el catálogo de ejercicios a la
///   derecha. Con el techo de 1240 y el sidebar afuera, a 1280 de viewport
///   quedan 1040: el panel se lleva 400 y a la rutina le quedan 640. Y en un
///   monitor de 1920 quedaban los MISMOS 640, porque el techo no lo levanta
///   una pantalla más grande. El PF lo reportó como «la lista de ejercicios no
///   se adapta a la pantalla»: no era la lista, era el cap.
const Set<String> _kWideSections = {
  '/biblioteca',
  '/routine-editor',
  '/template-editor',
};

double contentMaxWidthForRoute(String path) => _kWideSections.any(
      path.startsWith,
    )
        ? kWideContentMaxWidth
        : CoachHubLayoutTokens.contentMaxWidth;

/// Centra y acota el ancho del contenido del shell (REQ-CHW-SHELL-001).
///
/// El `CoachHubScaffold` lo usa con `maxWidth: 1240` para que las secciones no
/// se estiren a lo ancho en monitores grandes.
class ContentMaxWidth extends StatelessWidget {
  const ContentMaxWidth({
    super.key,
    required this.maxWidth,
    required this.child,
  });

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
