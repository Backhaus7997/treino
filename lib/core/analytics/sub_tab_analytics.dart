import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics_service.dart';

/// Emite `sub_tab_viewed` cada vez que una página de un [TabBarView] queda
/// visible.
///
/// **Por qué existe.** El `FirebaseAnalyticsObserver` del router no puede ver
/// esto: FEED y RANKINGS son las dos la ruta `/feed`, y TU ENTRENO y
/// PLANTILLAS las dos `/workout`. Son páginas de un [TabBarView], no rutas —
/// para el observer son la misma pantalla. Sin este widget, "cuánta gente usa
/// RANKINGS" queda sin respuesta aunque el observer esté puesto.
///
/// **Por qué se cuelga del [TabController] y no del `onTap` del [TabBar].**
/// El `onTap` sólo ve los taps. Estas dos pantallas son swipeables a
/// propósito, así que instrumentar el `onTap` perdería silenciosamente todos
/// los cambios por gesto — y sesgaría el dato justo hacia abajo en la página
/// que se descubre deslizando.
///
/// **Dónde va.** Como hijo directo del [DefaultTabController], envolviendo el
/// subárbol que contiene al [TabBar] y al [TabBarView]:
///
/// ```dart
/// DefaultTabController(
///   length: 2,
///   child: SubTabAnalytics(
///     surface: 'feed',
///     tabs: ['feed', 'rankings'],
///     child: Column(...),
///   ),
/// )
/// ```
///
/// Si no encuentra un [DefaultTabController] ancestro no rompe: no loguea.
/// Telemetría faltante es un bug de datos, no una pantalla caída.
class SubTabAnalytics extends ConsumerStatefulWidget {
  const SubTabAnalytics({
    super.key,
    required this.surface,
    required this.tabs,
    required this.child,
  });

  /// Contenedor de las tabs — `feed`, `workout`.
  final String surface;

  /// Nombre analítico de cada página, en el MISMO orden que los hijos del
  /// [TabBarView]. Son slugs estables (`rankings`, `plantillas`), no los
  /// labels visibles: los labels cambian con el copy y con el idioma, y un
  /// evento que se renombra solo rompe la serie histórica.
  final List<String> tabs;

  final Widget child;

  @override
  ConsumerState<SubTabAnalytics> createState() => _SubTabAnalyticsState();
}

class _SubTabAnalyticsState extends ConsumerState<SubTabAnalytics> {
  TabController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = DefaultTabController.maybeOf(context);
    if (identical(controller, _controller)) return;
    _controller?.removeListener(_onTabChanged);
    _controller = controller;
    if (controller == null) return;
    controller.addListener(_onTabChanged);
    // La página inicial también cuenta. Se puede entrar directo por deep-link
    // (`/feed?tab=rankings`), y sin esto esa visita no existiría para el dato.
    _log(controller.index);
  }

  void _onTabChanged() {
    final controller = _controller;
    if (controller == null) return;
    // ESTE guard es el que hace todo el trabajo de deduplicación, y conviene
    // saber por qué. Medido sobre Flutter 3.41: un TAP notifica DOS veces
    // —primero con `indexIsChanging: true` mientras la página se mueve, y
    // otra vez al asentar—, un swipe completo notifica UNA sola con
    // `indexIsChanging: false`, y un swipe que se arrepiente a mitad de
    // camino no notifica nunca. El TabController no notifica por frame de
    // arrastre: eso vive en `controller.animation`, que a propósito no se
    // escucha acá.
    //
    // Con esto, cada notificación que pasa de acá es una página que quedó
    // efectivamente visible. No hace falta recordar la última logueada.
    if (controller.indexIsChanging) return;
    _log(controller.index);
  }

  void _log(int index) {
    if (index < 0 || index >= widget.tabs.length) return;
    ref.read(analyticsServiceProvider).logSubTabViewed(
          surface: widget.surface,
          tab: widget.tabs[index],
        );
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
