import 'package:flutter/widgets.dart';

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
