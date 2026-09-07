import 'package:flutter/widgets.dart';
import 'package:treino/app/theme/tokens/components/coach_hub_layout_tokens.dart';

/// Techo de ancho de Biblioteca. Más generoso que el de las otras secciones
/// porque es la única que muestra un catálogo de 811 ítems en grilla, pero
/// sigue acotado: en un ultrawide una fila de 3440 px no se lee.
const double kWideContentMaxWidth = 1920;

/// Secciones que se salen del techo de 1240.
const Set<String> _kWideSections = {'/biblioteca'};

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
