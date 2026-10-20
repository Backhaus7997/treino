// Las pantallas de auth se apilan con `push` (bienvenida → login → registro /
// olvidé la contraseña). En iOS tienen que volver con el gesto nativo de
// deslizar desde el borde izquierdo: con `pageBuilder + _noAnim` el gesto no
// existía y sólo se podía salir con la flecha.
//
// Los widget tests corren como Android por defecto; acá se fuerza iOS por el
// tema (igual que router_ios_transition_test.dart).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/presentation/forgot_password_screen.dart';
import 'package:treino/features/auth/presentation/login_screen.dart';
import 'package:treino/features/auth/presentation/register_screen.dart';
import 'package:treino/features/auth/presentation/welcome_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

class _LoggedOutAuthNotifier extends AuthNotifier {
  @override
  Future<User?> build() async {
    state = const AsyncData(null);
    return null;
  }
}

Future<GoRouter> _pumpApp(WidgetTester tester, String start) async {
  final container = ProviderContainer(
    overrides: [
      authNotifierProvider.overrideWith(_LoggedOutAuthNotifier.new),
      userProfileProvider
          .overrideWith((ref) => Stream<UserProfile?>.value(null)),
      authStateChangesProvider.overrideWith((_) => Stream.value(null)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(authNotifierProvider.future);

  final router = buildRouter(
    refreshListenable: ValueNotifier<int>(0),
    read: container.read,
  );
  router.go(start);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark().copyWith(platform: TargetPlatform.iOS),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Desliza desde el borde izquierdo hasta más de la mitad de la pantalla, como
/// el gesto de iOS para volver.
Future<void> _swipeBack(WidgetTester tester) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final gesture = await tester.startGesture(Offset(4, size.height / 2));
  for (var i = 0; i < 10; i++) {
    await gesture.moveBy(Offset(size.width * 0.07, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('deslizar desde el borde vuelve de LOGIN a la bienvenida',
      (tester) async {
    final router = await _pumpApp(tester, '/welcome');
    router.push('/login');
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await _swipeBack(tester);

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('deslizar desde el borde vuelve de REGISTRO a la bienvenida',
      (tester) async {
    final router = await _pumpApp(tester, '/welcome');
    router.push('/register');
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);

    await _swipeBack(tester);

    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('deslizar desde el borde vuelve de OLVIDÉ LA CONTRASEÑA al login',
      (tester) async {
    final router = await _pumpApp(tester, '/welcome');
    router.push('/login');
    await tester.pumpAndSettle();
    router.push('/forgot-password');
    await tester.pumpAndSettle();
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);

    await _swipeBack(tester);

    expect(find.byType(ForgotPasswordScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
