import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/back_anidado_sync.dart';
import 'package:treino/features/notifications/application/notification_router.dart';

/// El back del SISTEMA de Android después de abrir un chat desde la lista de
/// Notificaciones (#1468).
///
/// Con el back predictivo Android no le manda el back a Flutter: antes le
/// pregunta si "puede manejarlo" (`SystemNavigator.setFrameworkHandlesBack`).
/// Ese valor sale de las `NavigationNotification` de cada `Navigator`, y la app
/// tiene dos (raíz y shell). Por eso un `handlePopRoute()` solo NO alcanza para
/// reproducirlo —en el test siempre llega a Flutter—: hay que mirar lo que se
/// le DIJO a la plataforma. Ver [BackAnidadoSync] para la cadena completa.
///
/// La forma es la de la app real: Inicio → campana (`push`) → Notificaciones,
/// todo dentro del `ShellRoute`, y el chat como ruta top-level del raíz.
void main() {
  final shellKey = GlobalKey<NavigatorState>(debugLabel: 'ShellNav');

  GoRouter armarRouter() => GoRouter(
        initialLocation: '/home',
        routes: [
          ShellRoute(
            navigatorKey: shellKey,
            builder: (_, __, child) => Scaffold(body: child),
            routes: [
              GoRoute(
                path: '/home',
                builder: (ctx, _) => TextButton(
                  onPressed: () => ctx.push('/home/notifications'),
                  child: const Text('INICIO'),
                ),
                routes: [
                  GoRoute(
                    path: 'notifications',
                    builder: (ctx, _) => TextButton(
                      onPressed: () => goDeepLink(
                        ctx,
                        '/coach/chat/abc?other=xyz',
                        sobreLaPilaActual: true,
                      ),
                      child: const Text('NOTIFICACIONES'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/coach/chat/:chatId',
            builder: (_, __) => const Scaffold(body: Text('CHAT')),
          ),
        ],
      );

  /// Lo que la app le va diciendo a Android sobre si el framework maneja el
  /// back, en orden. El último es el que vale.
  late List<bool> frameworkHandlesBack;

  void escucharPlataforma(WidgetTester tester) {
    frameworkHandlesBack = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
          frameworkHandlesBack.add(call.arguments as bool);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    // `WidgetsApp` ignora los avisos hasta que la app esté "lista".
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  Widget app(GoRouter r) => MaterialApp.router(
        routerConfig: r,
        // Misma forma que `app.dart`: el sync envuelve lo que cuelga del router.
        builder: (_, child) => BackAnidadoSync(router: r, child: child!),
      );

  /// Inicio → campana → Notificaciones → tocar el chat → back → back.
  Future<void> abrirChatYVolver(WidgetTester tester, GoRouter r) async {
    await tester.tap(find.text('INICIO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NOTIFICACIONES'));
    await tester.pumpAndSettle();
    expect(locationActualDe(r), '/coach/chat/abc?other=xyz');
    expect(frameworkHandlesBack.last, isTrue);

    // Primer back del sistema: saca el chat.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(locationActualDe(r), '/home/notifications');
  }

  testWidgets(
    'atrás del sistema desde Notificaciones, después de volver del chat: '
    'Android sigue delegando el back en Flutter y se vuelve a Inicio',
    (tester) async {
      escucharPlataforma(tester);
      final r = armarRouter();
      await tester.pumpWidget(app(r));
      await tester.pumpAndSettle();

      await abrirChatYVolver(tester, r);

      // El dato de la falla: en Notificaciones hay algo para volver (Inicio),
      // así que Android tiene que seguir mandándole el back a Flutter. Sin el
      // arreglo el último aviso era `false` (lo dejó el navigator raíz al sacar
      // el chat) y el siguiente back cerraba la app.
      expect(
        frameworkHandlesBack.last,
        isTrue,
        reason: 'con false, Android cierra la app en vez de mandarle el back',
      );

      // Segundo back: vuelve a Inicio.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(locationActualDe(r), '/home');
      expect(find.text('INICIO'), findsOneWidget);

      // Y en Inicio, ya sin nada para volver, SÍ se le suelta el back a Android
      // (que cierra la app): el arreglo no deja el back trabado en `true`.
      expect(frameworkHandlesBack.last, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'sin pasar por el chat, el back del sistema ya andaba y sigue andando',
    (tester) async {
      escucharPlataforma(tester);
      final r = armarRouter();
      await tester.pumpWidget(app(r));
      await tester.pumpAndSettle();

      await tester.tap(find.text('INICIO'));
      await tester.pumpAndSettle();
      expect(frameworkHandlesBack.last, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(locationActualDe(r), '/home');
      expect(frameworkHandlesBack.last, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  test('app.dart envuelve el router con BackAnidadoSync', () {
    // El widget no sirve de nada si `app.dart` no lo usa, y armar el `App`
    // entero en un test pide Firebase. Mismo recurso que los escáneres de
    // `test/app/guards`: mirar el fuente.
    final fuente = File('lib/app/app.dart').readAsStringSync();
    expect(fuente, contains('BackAnidadoSync('));
    expect(fuente, contains('router: _router'));
  });
}
