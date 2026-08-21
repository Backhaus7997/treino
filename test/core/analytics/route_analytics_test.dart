// Issue #666 — antes de esto la app no emitía UN solo evento de navegación.
//
// El test que importa es "reporta cada navegación": que navegar produzca
// `screen_view` con el PATRÓN de ruta. Los demás protegen las decisiones que
// se tomaron para llegar ahí — patrón y no ruta concreta, ruta inicial
// contada, y sobre todo que enganchar desde `initState` no crashee.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/core/analytics/route_analytics.dart';

import '../../helpers/fake_analytics_service.dart';

GoRouter _router({Listenable? refresh}) => GoRouter(
      initialLocation: '/home',
      refreshListenable: refresh,
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const Text('home')),
        GoRoute(path: '/feed', builder: (_, __) => const Text('feed')),
        GoRoute(
          // Ruta con parámetro — la que revienta la cardinalidad si se
          // reportara concreta.
          path: '/coach/exercise/:id',
          // pageBuilder a propósito: es la forma que NO recibe nombre de
          // página automático, y la que usan los cinco tabs raíz.
          pageBuilder: (_, __) => const NoTransitionPage(child: Text('ex')),
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

void main() {
  late FakeAnalyticsService analytics;

  setUp(() => analytics = FakeAnalyticsService());

  group('RouteAnalytics', () {
    testWidgets('reporta la ruta inicial al engancharse', (tester) async {
      final router = _router();
      addTearDown(router.dispose);
      await _pump(tester, router);

      final ra = RouteAnalytics(router: router, analytics: analytics)..attach();
      addTearDown(ra.detach);
      await tester.pumpAndSettle();

      // Si la inicial no contara, la primera pantalla de cada sesión —la que
      // más importa— no existiría para el dato.
      expect(analytics.screenRoutes, ['/home']);
    });

    testWidgets('reporta cada navegación', (tester) async {
      final router = _router();
      addTearDown(router.dispose);
      await _pump(tester, router);
      final ra = RouteAnalytics(router: router, analytics: analytics)..attach();
      addTearDown(ra.detach);

      router.go('/feed');
      await tester.pumpAndSettle();

      expect(analytics.screenRoutes, ['/home', '/feed']);
    });

    testWidgets('reporta el PATRÓN de ruta, no la ruta concreta',
        (tester) async {
      final router = _router();
      addTearDown(router.dispose);
      await _pump(tester, router);
      final ra = RouteAnalytics(router: router, analytics: analytics)..attach();
      addTearDown(ra.detach);

      router.go('/coach/exercise/abc123');
      await tester.pumpAndSettle();

      // `/coach/exercise/:id` y NO `/coach/exercise/abc123`: reportar la
      // concreta daría un valor distinto por cada id y ningún reporte
      // agregable.
      expect(analytics.screenRoutes.last, '/coach/exercise/:id');
      expect(
        analytics.screenRoutes.last,
        isNot(contains('abc123')),
        reason: 'un id de ejercicio no puede terminar dentro del evento',
      );
    });

    testWidgets('esta ruta se reporta aunque use pageBuilder', (tester) async {
      // El motivo de no usar FirebaseAnalyticsObserver: las rutas de
      // `pageBuilder` construyen páginas sin `name`, y el observer las
      // descarta en silencio. Los cinco tabs raíz son todos `pageBuilder`.
      final router = _router();
      addTearDown(router.dispose);
      await _pump(tester, router);
      final ra = RouteAnalytics(router: router, analytics: analytics)..attach();
      addTearDown(ra.detach);

      router.go('/coach/exercise/abc123');
      await tester.pumpAndSettle();

      expect(analytics.screenRoutes, contains('/coach/exercise/:id'));
    });

    testWidgets(
        'enganchado ANTES de montar (como hace app.dart en initState) '
        'no crashea y cuenta la ruta inicial una sola vez', (tester) async {
      final refresh = ValueNotifier<int>(0);
      addTearDown(refresh.dispose);
      final router = _router(refresh: refresh);
      addTearDown(router.dispose);

      // Este es el orden REAL: `app.dart` construye el router y engancha en
      // `initState`, o sea antes de que `MaterialApp.router` monte. En ese
      // momento el router no resolvió ninguna ruta y `GoRouter.state` TIRA
      // `StateError: No element`. Sin la guarda de `_currentRoute`, esto
      // crashea el arranque de la app — no falla el evento, se cae la app.
      final ra = RouteAnalytics(router: router, analytics: analytics)..attach();
      addTearDown(ra.detach);
      await _pump(tester, router);

      // Y el redirect reevaluándose tampoco tiene que sumar.
      refresh.value = 1;
      await tester.pumpAndSettle();

      expect(analytics.screenRoutes, ['/home']);
    });

    testWidgets('volver a una ruta ya visitada sí vuelve a contar',
        (tester) async {
      final router = _router();
      addTearDown(router.dispose);
      await _pump(tester, router);
      final ra = RouteAnalytics(router: router, analytics: analytics)..attach();
      addTearDown(ra.detach);

      router.go('/feed');
      await tester.pumpAndSettle();
      router.go('/home');
      await tester.pumpAndSettle();

      // Volver a /home es una visita nueva y tiene que contar: si alguien
      // "optimizara" filtrando rutas ya vistas, el dato de retorno a una
      // pantalla desaparecería.
      expect(analytics.screenRoutes, ['/home', '/feed', '/home']);
    });

    testWidgets('después de detach deja de reportar', (tester) async {
      final router = _router();
      addTearDown(router.dispose);
      await _pump(tester, router);
      final ra = RouteAnalytics(router: router, analytics: analytics)..attach();

      ra.detach();
      router.go('/feed');
      await tester.pumpAndSettle();

      expect(analytics.screenRoutes, ['/home']);
    });
  });
}
