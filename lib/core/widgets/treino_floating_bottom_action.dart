import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../app/theme/app_palette.dart';

/// Acción fija al pie que FLOTA sobre el contenido en vez de partir la
/// pantalla en dos.
///
/// El [body] ocupa todo el alto y pasa por debajo de la acción; detrás de la
/// acción hay un degradé de transparente a `bg`, así que el contenido se
/// desvanece en vez de terminar en un corte recto contra el botón. Es el
/// mismo criterio que la barra inferior del shell: el contenido corre por
/// debajo del vidrio.
///
/// Por qué no es un `Column` + `Expanded` (lo que había, #641): ahí el scroll
/// terminaba justo donde empezaba la barra y la pantalla quedaba cortada en
/// dos bloques. El riesgo de flotar era el que anotaba #641 — con texto
/// grande el botón crece y un alto fijo dejaría el último ítem debajo. Por eso
/// el alto que el [body] reserva al final NO es fijo: es el que MIDE el área
/// de la acción en cada layout, y se le pasa al [body] para que lo sume como
/// padding inferior de su scroll.
class TreinoFloatingBottomAction extends StatefulWidget {
  const TreinoFloatingBottomAction({
    super.key,
    required this.body,
    required this.action,
  });

  /// Recibe cuánto tiene que reservar al final de su scroll para que el
  /// último ítem quede por encima de la acción.
  final Widget Function(BuildContext context, double reservedBottom) body;

  /// La acción (normalmente un botón a ancho completo). El margen lateral y
  /// el inset inferior del sistema / de la barra del shell los pone este
  /// widget.
  final Widget action;

  /// Alto del degradé por encima del botón.
  static const double fadeHeight = 32;

  /// Separación entre el botón y lo que tiene debajo (barra o borde).
  static const double bottomGap = 12;

  @override
  State<TreinoFloatingBottomAction> createState() =>
      _TreinoFloatingBottomActionState();
}

class _TreinoFloatingBottomActionState
    extends State<TreinoFloatingBottomAction> {
  double _reserved = 0;

  void _onActionHeight(double height) {
    if (height == _reserved) return;
    // Llega desde el layout: el setState va al frame siguiente.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && height != _reserved) setState(() => _reserved = height);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // In-shell el Scaffold publica el alto de la barra flotante en
    // `padding.bottom`; fuera del shell un SafeArea ya lo consumió y vale 0.
    // La misma expresión sirve en los dos montajes.
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Stack(
      children: [
        Positioned.fill(child: widget.body(context, _reserved)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _HeightReporter(
            onHeight: _onActionHeight,
            child: DecoratedBox(
              key: const Key('treino-floating-action-scrim'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // Transparente arriba, casi opaco ya a la altura del botón:
                  // el contenido se funde antes de llegar a pasar por detrás.
                  stops: const [0, 0.45, 1],
                  colors: [
                    palette.bg.withValues(alpha: 0),
                    palette.bg.withValues(alpha: 0.88),
                    palette.bg.withValues(alpha: 0.96),
                  ],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  TreinoFloatingBottomAction.fadeHeight,
                  20,
                  TreinoFloatingBottomAction.bottomGap + bottomInset,
                ),
                child: widget.action,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Avisa el alto con el que quedó layouteado su hijo.
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReporter renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}
