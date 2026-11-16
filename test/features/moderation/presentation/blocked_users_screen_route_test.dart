// «Usuarios bloqueados» como ruta de go_router (#1830): el botón Atrás.
//
// Con una recarga en web la pantalla es la ÚNICA del stack, y el
// `Navigator.maybePop` que tenía antes no hacía nada: Atrás quedaba muerto. Que
// el router REAL registre `/profile/settings/bloqueados` lo fija
// `test/app/router_test.dart`; acá se monta una ruta mínima.
//
// Los tests no pisan ningún provider de bloqueados: con un Firestore falso sin
// documentos la lista es vacía venga del provider que venga.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/moderation/presentation/blocked_users_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

Future<GoRouter> _montar(
  WidgetTester tester, {
  required String inicial,
}) async {
  final router = GoRouter(
    initialLocation: inicial,
    routes: [
      GoRoute(
        path: '/profile/settings/privacidad',
        builder: (_, __) => const Scaffold(body: Text('PRIVACIDAD')),
      ),
      GoRoute(
        path: '/profile/settings/bloqueados',
        builder: (_, __) => const Scaffold(body: BlockedUsersScreen()),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        currentUidProvider.overrideWith((_) => 'aaa'),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('Atrás como única ruta (recarga en web) lleva a Privacidad',
      (tester) async {
    final router =
        await _montar(tester, inicial: '/profile/settings/bloqueados');
    expect(find.text('USUARIOS BLOQUEADOS'), findsOneWidget);

    await tester.tap(find.byIcon(TreinoIcon.back));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/profile/settings/privacidad');
    expect(find.text('PRIVACIDAD'), findsOneWidget);
  });

  testWidgets('con Privacidad debajo en el stack, Atrás la saca y vuelve',
      (tester) async {
    final router =
        await _montar(tester, inicial: '/profile/settings/privacidad');
    unawaited(router.push('/profile/settings/bloqueados'));
    await tester.pumpAndSettle();
    expect(find.text('USUARIOS BLOQUEADOS'), findsOneWidget);

    await tester.tap(find.byIcon(TreinoIcon.back));
    await tester.pumpAndSettle();

    expect(find.text('PRIVACIDAD'), findsOneWidget);
    expect(find.text('USUARIOS BLOQUEADOS'), findsNothing);
  });
}
