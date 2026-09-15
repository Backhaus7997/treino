import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/features/notifications/application/notification_router.dart';

/// El bug que estos tests existen para que no vuelva (2026-09-15):
///
/// La regla de supresión tenía 11 tests y era correcta. Lo que estaba mal era
/// la línea que le pasaba la location: usaba
/// `routerDelegate.currentConfiguration.uri`, que **ignora las rutas abiertas
/// con `push`**. Y el chat se abre siempre con `push`. Así que adentro del
/// chat la location decía `/coach` y la supresión no matcheaba nunca.
///
/// Se detectó con dos teléfonos reales, no con la suite. Estos tests cierran
/// ese hueco: usan un GoRouter DE VERDAD y navegan como navega la app.
GoRouter _router() => GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/coach',
          builder: (_, __) => const Scaffold(body: Text('COACH')),
        ),
        GoRoute(
          path: '/coach/chat/:chatId',
          builder: (_, __) => const Scaffold(body: Text('CHAT')),
        ),
        GoRoute(
          path: '/feed/notifications',
          builder: (_, __) => const Scaffold(body: Text('NOTIFS')),
        ),
      ],
    );

Future<GoRouter> _montar(WidgetTester tester) async {
  final router = _router();
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('locationActualDe', () {
    testWidgets('refleja la location inicial', (tester) async {
      final router = await _montar(tester);
      expect(locationActualDe(router), equals('/home'));
    });

    testWidgets('refleja un `go`', (tester) async {
      final router = await _montar(tester);
      router.go('/coach');
      await tester.pumpAndSettle();
      expect(locationActualDe(router), equals('/coach'));
    });

    testWidgets(
        'EL BUG: refleja un `push`, que es como se abre SIEMPRE el chat',
        (tester) async {
      final router = await _montar(tester);
      router.push('/coach/chat/chat-1?other=uid-pf');
      await tester.pumpAndSettle();

      expect(
        locationActualDe(router),
        equals('/coach/chat/chat-1?other=uid-pf'),
        reason: 'con `currentConfiguration.uri` esto devolvía "/home": las '
            'rutas imperativas no aparecen ahí, y la supresión del chat no '
            'matcheaba nunca',
      );
    });

    testWidgets('un push sobre otra pantalla también se refleja',
        (tester) async {
      final router = await _montar(tester);
      router.go('/coach');
      await tester.pumpAndSettle();
      router.push('/coach/chat/chat-2');
      await tester.pumpAndSettle();

      expect(locationActualDe(router), equals('/coach/chat/chat-2'));
    });

    testWidgets('al hacer pop vuelve la location de abajo', (tester) async {
      final router = await _montar(tester);
      router.push('/coach/chat/chat-1');
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();

      expect(locationActualDe(router), equals('/home'),
          reason: 'saliendo del chat la supresión tiene que dejar de aplicar');
    });
  });

  group('la location de un push alimenta bien la supresión', () {
    testWidgets('adentro del chat al que apunta el link → se suprime',
        (tester) async {
      final router = await _montar(tester);
      const deepLink = '/coach/chat/chat-1?other=uid-pf';
      router.push(deepLink);
      await tester.pumpAndSettle();

      expect(
        shouldSuppressForegroundNotification(
          currentLocation: locationActualDe(router),
          deepLink: deepLink,
        ),
        isTrue,
        reason: 'es EXACTAMENTE el caso que el usuario reportó roto',
      );
    });

    testWidgets('adentro de OTRO chat → se notifica', (tester) async {
      final router = await _montar(tester);
      router.push('/coach/chat/chat-2?other=uid-x');
      await tester.pumpAndSettle();

      expect(
        shouldSuppressForegroundNotification(
          currentLocation: locationActualDe(router),
          deepLink: '/coach/chat/chat-1?other=uid-pf',
        ),
        isFalse,
      );
    });

    testWidgets('en el centro de notificaciones → se suprime', (tester) async {
      final router = await _montar(tester);
      router.go('/feed/notifications');
      await tester.pumpAndSettle();

      expect(
        shouldSuppressForegroundNotification(
          currentLocation: locationActualDe(router),
          deepLink: '/coach/chat/chat-1?other=uid-pf',
        ),
        isTrue,
      );
    });
  });
}
