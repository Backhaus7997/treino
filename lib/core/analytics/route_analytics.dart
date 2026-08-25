import 'package:go_router/go_router.dart';

import 'analytics_service.dart';

/// Emite `screen_view` en cada navegación, leyendo la ruta del propio
/// [GoRouter].
///
/// ## Por qué no el `FirebaseAnalyticsObserver`
///
/// La vía "de manual" sería enganchar un [FirebaseAnalyticsObserver] en
/// `observers:` del router. **En este repo no funcionaría**, y falla en
/// silencio, que es peor:
///
/// `FirebaseAnalyticsObserver` saca el nombre de pantalla de
/// `route.settings.name` y descarta el evento si es `null`
/// (`firebase_analytics/observer.dart`, `_sendScreenView`). Ninguna de las 56
/// rutas de `router.dart` define `name:`, y las de `pageBuilder` construyen un
/// [CustomTransitionPage] sin nombre. Peor: go_router SÍ nombra por default
/// las páginas de las rutas que usan `builder:` (`state.name ?? state.path`),
/// así que el observer daría cobertura PARCIAL — perdiendo justo los cinco
/// tabs raíz (`/feed`, `/workout`, `/home`, `/coach`, `/profile`), que son
/// todos `pageBuilder`. Un dashboard a medio llenar y nadie enterándose.
///
/// La alternativa era ponerle `name:` a las 56 rutas. Se descartó: es una
/// convención sin guard, y toda ruta nueva la va a olvidar. Leer la ruta del
/// router cubre lo que existe hoy y lo que se agregue mañana, sin que nadie
/// tenga que acordarse de nada.
///
/// ## Qué se reporta
///
/// `GoRouterState.fullPath`, que es el PATRÓN (`/coach/exercise/:id`) y no la
/// ruta concreta (`/coach/exercise/abc123`). Mandar la concreta haría explotar
/// la cardinalidad: un valor distinto por cada id y ningún reporte agregable.
///
/// No cubre las páginas de `TabBarView` que comparten ruta — FEED y RANKINGS
/// son las dos `/feed`. Para eso está `SubTabAnalytics`.
class RouteAnalytics {
  RouteAnalytics({
    required GoRouter router,
    required AnalyticsService analytics,
  })  : _router = router,
        _analytics = analytics;

  final GoRouter _router;
  final AnalyticsService _analytics;

  /// Arranca a escuchar, e intenta reportar la ruta actual de una: si no, la
  /// primera pantalla de la sesión —que es justamente la que más importa— no
  /// se contaría hasta que el usuario navegue a otro lado.
  ///
  /// "Intenta" porque `app.dart` engancha en `initState`, o sea antes de que
  /// `MaterialApp.router` monte y el router resuelva nada. En ese momento
  /// todavía no hay ruta: ver [_currentRoute]. La primera notificación del
  /// delegate la cubre.
  void attach() {
    _router.routerDelegate.addListener(_onRouteChanged);
    _onRouteChanged();
  }

  void detach() {
    _router.routerDelegate.removeListener(_onRouteChanged);
  }

  /// No lleva registro de la última ruta reportada, y no hace falta. Medido
  /// sobre go_router 14.8: el delegate notifica SÓLO cuando la ruta cambia de
  /// verdad — `refreshListenable` disparando y reevaluando el redirect no
  /// notifica, y un `go()` a la ruta en la que ya estás tampoco. Cada
  /// notificación que llega acá es una pantalla nueva.
  void _onRouteChanged() {
    final route = _currentRoute();
    if (route == null || route.isEmpty) return;
    _analytics.logScreenViewed(route: route);
  }

  /// Ruta actual, o `null` si el router todavía no resolvió ninguna.
  ///
  /// El chequeo NO es decorativo: `GoRouter.state` hace `matches.last` y tira
  /// `StateError: No element` cuando la lista está vacía
  /// (`go_router/src/delegate.dart`). Como se engancha desde `initState`, sin
  /// esta guarda la app crashea al arrancar — telemetría tumbando el arranque,
  /// que es el peor intercambio posible.
  String? _currentRoute() {
    if (_router.routerDelegate.currentConfiguration.isEmpty) return null;
    return _router.state.fullPath;
  }
}
