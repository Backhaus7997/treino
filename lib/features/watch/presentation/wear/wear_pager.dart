import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_palette.dart';

/// Le dice a cada página si es la que el atleta está viendo.
///
/// Existe por la corona: el `PageView` mantiene las tres páginas VIVAS, así que
/// sin esto habría tres scrollables escuchando el hardware a la vez y el giro
/// movería listas que nadie está mirando.
class WearPageScope extends InheritedWidget {
  const WearPageScope({
    super.key,
    required this.isActive,
    required super.child,
  });

  final bool isActive;

  /// `true` por defecto: una pantalla fuera de un pager siempre es la activa.
  static bool isActiveOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WearPageScope>()?.isActive ??
      true;

  @override
  bool updateShouldNotify(WearPageScope old) => old.isActive != isActive;
}

/// Paginado horizontal del companion, con la salida implementada a mano.
///
/// ## La dirección importa, y no es un detalle
///
/// En Wear OS el gesto **izquierda→derecha** (el dedo va hacia la derecha)
/// cierra la app, y se dispara desde cualquier punto de la pantalla. La versión
/// anterior tenía HOY al medio con planes a la IZQUIERDA, así que llegar a los
/// planes exigía justo ese gesto: el dueño lo reportó como *"cuando quiero
/// moverme a la izquierda no funciona y se cierra la app"*.
///
/// Acá HOY es la PRIMERA página y todo lo demás queda hacia la derecha. Avanzar
/// usa el dedo de derecha a izquierda, que es la dirección libre. El conflicto no
/// se esquiva: deja de existir.
///
/// ## Quién cierra la app
///
/// `windowSwipeToDismiss` está apagado en el tema del flavor `wear`, así que el
/// sistema ya no cierra nada. Lo hacemos acá, y con la misma semántica que tenía:
///
/// * En las páginas 2 y 3, el arrastre izquierda→derecha **vuelve una página**,
///   y eso lo maneja el `PageView` solo.
/// * En la PRIMERA, ese mismo arrastre ya no tiene a dónde ir: se convierte en
///   overscroll, y ahí **sale de la app**.
///
/// O sea que el atleta no aprende un gesto nuevo: significa "atrás", y en la
/// primera pantalla atrás es salir. Si esto no estuviera, quedaría encerrado.
class WearPager extends StatefulWidget {
  const WearPager({super.key, required this.pages});

  /// La primera es la que ve el atleta al abrir.
  final List<Widget> pages;

  @override
  State<WearPager> createState() => _WearPagerState();
}

class _WearPagerState extends State<WearPager> {
  final _controller = PageController();
  int _page = 0;

  /// Cuánto hay que arrastrar MÁS ALLÁ del principio para que cuente como
  /// "salir". En píxeles lógicos.
  static const double _exitThreshold = 48;

  /// Overscroll acumulado hacia atrás en la primera página.
  double _overscroll = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Detecta el intento de "ir atrás" desde la primera página.
  ///
  /// **Por overscroll y NO por un `GestureDetector` encima.** La primera versión
  /// ponía una capa de gestos a pantalla completa con
  /// `onHorizontalDragUpdate`, y eso GANA la arena de gestos contra el
  /// `PageView`: el arrastre nunca llegaba al pager y la app dejaba de
  /// deslizarse de costado. Me robé mi propio gesto.
  ///
  /// Escuchar notificaciones no compite con nadie: el `PageView` maneja el
  /// arrastre normal, y sólo cuando ya no hay a dónde ir aparece el overscroll.
  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false; // ignora el scroll VERTICAL de las páginas
    if (n is OverscrollNotification && _page == 0 && n.overscroll < 0) {
      _overscroll -= n.overscroll;
    } else if (n is ScrollEndNotification) {
      final acumulado = _overscroll;
      _overscroll = 0;
      if (_page == 0 && acumulado > _exitThreshold) SystemNavigator.pop();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              for (var i = 0; i < widget.pages.length; i++)
                WearPageScope(isActive: i == _page, child: widget.pages[i]),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 8,
          child: IgnorePointer(
            child: _PageDots(count: widget.pages.length, current: _page),
          ),
        ),
      ],
    );
  }
}

/// Puntitos de página.
///
/// **No son decoración**: sin ellos nada sugiere que hay más contenido a la
/// derecha, y el atleta no lo descubre nunca.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == current ? palette.accent : palette.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}
