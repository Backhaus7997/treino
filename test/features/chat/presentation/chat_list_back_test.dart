import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/chat/presentation/chat_list_screen.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Monta el inbox en un GoRouter real. `/feed` es un stub.
GoRouter _router(String initial) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/feed',
          builder: (_, __) => const Scaffold(body: Text('feed-stub')),
        ),
        GoRoute(
          path: '/feed/messages',
          builder: (_, __) => const ChatListScreen(),
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWith((_) => 'aaa'),
        chatsForCurrentUserProvider.overrideWith(
          (ref) => Stream.value(const <Chat>[]),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// La ruta del tope del stack: refleja también lo empujado con `push`
// (`currentConfiguration.uri` se queda en la base).
String _loc(GoRouter r) =>
    r.routerDelegate.currentConfiguration.last.matchedLocation;

void main() {
  group('ChatListScreen — flecha de volver', () {
    testWidgets('sin nada debajo (deep link con go) vuelve al feed', (
      tester,
    ) async {
      final router = _router('/feed/messages');
      await _pump(tester, router);
      expect(_loc(router), '/feed/messages');

      await tester.tap(find.byIcon(TreinoIcon.back));
      await tester.pumpAndSettle();

      expect(_loc(router), '/feed');
    });

    testWidgets('el back del sistema sin nada debajo también vuelve al feed', (
      tester,
    ) async {
      final router = _router('/feed/messages');
      await _pump(tester, router);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(_loc(router), '/feed');
    });

    testWidgets('empujado sobre otra pantalla, popea normalmente', (
      tester,
    ) async {
      final router = _router('/feed');
      await _pump(tester, router);
      router.push('/feed/messages');
      await tester.pumpAndSettle();
      expect(_loc(router), '/feed/messages');

      await tester.tap(find.byIcon(TreinoIcon.back));
      await tester.pumpAndSettle();

      expect(_loc(router), '/feed');
      expect(router.canPop(), isFalse);
    });

    testWidgets(
        'empujado, el PopScope no le apaga el swipe de iOS a la bandeja', (
      tester,
    ) async {
      final router = _router('/feed');
      await _pump(tester, router);
      router.push('/feed/messages');
      await tester.pumpAndSettle();

      final ruta = ModalRoute.of(tester.element(find.byType(ChatListScreen)))!;
      expect(ruta.popGestureEnabled, isTrue,
          reason: 'con algo debajo, flecha, swipe y back tienen que ser un pop '
              'nativo; un PopScope(canPop: false) acá apagaría el gesto');
    });
  });
}
