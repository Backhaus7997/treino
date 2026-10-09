import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/notifications/application/notification_router.dart';

// ---------------------------------------------------------------------------
// Minimal GoRouter mock via InheritedWidget injection
// ---------------------------------------------------------------------------

class MockGoRouter extends Mock implements GoRouter {}

/// Wraps [child] with a [MockGoRouter] accessible via [GoRouter.of(context)].
Widget _withRouter(MockGoRouter router, Widget child) {
  return MaterialApp(
    home: InheritedGoRouter(
      goRouter: router,
      child: Builder(builder: (_) => child),
    ),
  );
}

void main() {
  late MockGoRouter router;

  setUp(() {
    router = MockGoRouter();
    when(() => router.go(any(), extra: any(named: 'extra'))).thenReturn(null);
    when(() => router.go(any())).thenReturn(null);
  });

  group('goDeepLink', () {
    // SCENARIO-654: null → fallback /coach
    testWidgets(
      'SCENARIO-654: null deepLink → context.go("/coach")',
      (tester) async {
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, null),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        verify(() => router.go('/coach')).called(1);
      },
    );

    // SCENARIO-654: empty string → fallback /coach
    testWidgets(
      'SCENARIO-654: empty deepLink → context.go("/coach")',
      (tester) async {
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, ''),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        verify(() => router.go('/coach')).called(1);
      },
    );

    // SCENARIO-682: no leading slash → log + fallback /coach
    testWidgets(
      'SCENARIO-682: deepLink without leading slash → log + context.go("/coach")',
      (tester) async {
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, 'no-leading-slash'),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        verify(() => router.go('/coach')).called(1);
      },
    );

    // SCENARIO-653 (link de chat) ya no es un `go` exacto: arma el stack
    // Feed → Mensajes → chat. Se prueba con un GoRouter de verdad en el grupo
    // `goDeepLink — link de chat` de abajo.

    // SCENARIO-655: valid path with query parameter
    testWidgets(
      'SCENARIO-655: valid deepLink /coach?tab=agenda → context.go exactly',
      (tester) async {
        const deepLink = '/coach?tab=agenda';
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, deepLink),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        verify(() => router.go(deepLink)).called(1);
        verifyNever(() => router.go('/coach'));
      },
    );

    // Triangulation: path without leading slash that looks like a host
    testWidgets(
      'TRIANGULATE: "coach" (no slash) → fallback /coach + log',
      (tester) async {
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, 'coach'),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        verify(() => router.go('/coach')).called(1);
      },
    );

    // Triangulation: valid trainer profile deep link
    testWidgets(
      'TRIANGULATE: /coach/trainer/uid-1 → context.go exactly',
      (tester) async {
        const deepLink = '/coach/trainer/uid-1';
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, deepLink),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        verify(() => router.go(deepLink)).called(1);
        verifyNever(() => router.go('/coach'));
      },
    );

    // Triangulation: valid agenda deep link
    testWidgets(
      'TRIANGULATE: /coach/agenda → context.go exactly',
      (tester) async {
        const deepLink = '/coach/agenda';
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, deepLink),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        verify(() => router.go(deepLink)).called(1);
        verifyNever(() => router.go('/coach'));
      },
    );

    // Triangulation: whitespace-only string → fallback (treated as empty)
    testWidgets(
      'TRIANGULATE: whitespace-only deepLink → goes to "/coach"',
      (tester) async {
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, '   '),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        // '   ' doesn't start with '/' → logged + falls back
        verify(() => router.go('/coach')).called(1);
      },
    );
  });

  group('goDeepLink — link de chat arma Feed → Mensajes → chat', () {
    // Misma forma que el router real: `/feed` adentro del ShellRoute, y la
    // bandeja y el chat como rutas top-level del navigator raíz.
    GoRouter armarRouter() => GoRouter(
          initialLocation: '/home/notifications',
          routes: [
            ShellRoute(
              builder: (_, __, child) => Scaffold(body: child),
              routes: [
                GoRoute(
                  path: '/feed',
                  builder: (_, __) => const Text('FEED'),
                ),
                GoRoute(
                  path: '/home/notifications',
                  builder: (ctx, _) => TextButton(
                    onPressed: () =>
                        goDeepLink(ctx, '/coach/chat/abc?other=xyz'),
                    child: const Text('abrir-chat'),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: '/feed/messages',
              builder: (_, __) => const Scaffold(body: Text('MENSAJES')),
            ),
            GoRoute(
              path: '/coach/chat/:chatId',
              builder: (_, __) => const Scaffold(body: Text('CHAT')),
            ),
            GoRoute(
              path: '/coach',
              builder: (_, __) => const Scaffold(body: Text('COACH')),
            ),
          ],
        );

    Future<GoRouter> abrirChatDesdeNotificacion(WidgetTester tester) async {
      final r = armarRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();
      await tester.tap(find.text('abrir-chat'));
      await tester.pumpAndSettle();
      return r;
    }

    List<String> stack(GoRouter r) => [
          for (final m in r.routerDelegate.currentConfiguration.matches)
            m is ShellRouteMatch
                ? m.matches.last.matchedLocation
                : m.matchedLocation,
        ];

    testWidgets('el stack queda [feed, mensajes, chat] y el chat puede volver',
        (tester) async {
      final r = await abrirChatDesdeNotificacion(tester);

      expect(stack(r), ['/feed', '/feed/messages', '/coach/chat/abc']);
      expect(locationActualDe(r), '/coach/chat/abc?other=xyz',
          reason: 'el `?other=` del link tiene que llegar al chat');
      expect(r.canPop(), isTrue);
    });

    testWidgets('el swipe de iOS está habilitado en el chat y en la bandeja',
        (tester) async {
      final r = await abrirChatDesdeNotificacion(tester);

      final chat = ModalRoute.of(tester.element(find.text('CHAT')))!;
      expect(chat.popGestureEnabled, isTrue,
          reason: 'sin una ruta debajo el gesto de volver no existe');

      r.pop();
      await tester.pumpAndSettle();
      final bandeja = ModalRoute.of(tester.element(find.text('MENSAJES')))!;
      expect(bandeja.popGestureEnabled, isTrue);
    });

    testWidgets('dos back del sistema: chat → mensajes → feed', (tester) async {
      final r = await abrirChatDesdeNotificacion(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(locationActualDe(r), '/feed/messages');
      expect(r.canPop(), isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(locationActualDe(r), '/feed');
      expect(r.canPop(), isFalse);
    });

    testWidgets('la supresión sigue viendo el chat abierto por este camino',
        (tester) async {
      final r = await abrirChatDesdeNotificacion(tester);
      const link = '/coach/chat/abc?other=xyz';

      expect(
        shouldSuppressForegroundNotification(
          currentLocation: locationActualDe(r),
          deepLink: link,
        ),
        isTrue,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        shouldSuppressForegroundNotification(
          currentLocation: locationActualDe(r),
          deepLink: link,
        ),
        isFalse,
        reason: 'ya en la bandeja, un mensaje de ese chat tiene que avisarse',
      );
    });

    testWidgets(
        'el camino del header del Feed (push, push) no cambia y da el MISMO '
        'stack que la notificación', (tester) async {
      final r = armarRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();
      r.go('/feed');
      await tester.pumpAndSettle();
      unawaited(r.push<void>('/feed/messages'));
      await tester.pumpAndSettle();
      unawaited(r.push<void>('/coach/chat/abc?other=xyz'));
      await tester.pumpAndSettle();

      expect(stack(r), ['/feed', '/feed/messages', '/coach/chat/abc']);
      expect(r.canPop(), isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(locationActualDe(r), '/feed/messages');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(locationActualDe(r), '/feed');
    });

    testWidgets(
        'con otro chat ya abierto, la notificación rearma el stack desde cero '
        '(no apila un chat sobre otro)', (tester) async {
      final r = armarRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();
      r.go('/feed');
      await tester.pumpAndSettle();
      unawaited(r.push<void>('/feed/messages'));
      await tester.pumpAndSettle();
      unawaited(r.push<void>('/coach/chat/otro?other=zzz'));
      await tester.pumpAndSettle();

      goDeepLink(
        tester.element(find.text('CHAT')),
        '/coach/chat/abc?other=xyz',
      );
      await tester.pumpAndSettle();

      expect(stack(r), ['/feed', '/feed/messages', '/coach/chat/abc']);
      expect(locationActualDe(r), '/coach/chat/abc?other=xyz');
    });

    testWidgets('un link que no es de chat sigue siendo un `go` sin stack',
        (tester) async {
      final r = armarRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();
      goDeepLink(tester.element(find.text('abrir-chat')), '/coach');
      await tester.pumpAndSettle();

      expect(stack(r), ['/coach']);
      expect(r.canPop(), isFalse);
    });

    testWidgets('si un redirect desvía el feed, cae al `go(deepLink)` de antes',
        (tester) async {
      final r = GoRouter(
        initialLocation: '/start',
        // Simula el gate de auth/perfil mandando el feed a otro lado.
        redirect: (_, s) => s.matchedLocation == '/feed' ? '/start' : null,
        routes: [
          GoRoute(
            path: '/start',
            builder: (ctx, _) => TextButton(
              onPressed: () => goDeepLink(ctx, '/coach/chat/abc?other=xyz'),
              child: const Text('abrir-chat'),
            ),
          ),
          GoRoute(path: '/feed', builder: (_, __) => const Text('FEED')),
          GoRoute(
            path: '/feed/messages',
            builder: (_, __) => const Text('MENSAJES'),
          ),
          GoRoute(
            path: '/coach/chat/:chatId',
            builder: (_, __) => const Text('CHAT'),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();
      await tester.tap(find.text('abrir-chat'));
      await tester.pumpAndSettle();

      expect(locationActualDe(r), '/coach/chat/abc?other=xyz');
      expect(stack(r), ['/coach/chat/abc'],
          reason: 'sin feed no se apila nada encima de un destino ajeno');
    });
  });
}
