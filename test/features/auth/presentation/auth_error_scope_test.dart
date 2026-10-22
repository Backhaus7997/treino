// El error de auth pertenece a la pantalla y al intento que lo generó.
//
// Bug QA 07: Login y Registro leían el `AsyncError` del `authNotifierProvider`
// global. Un login fallido dejaba «Email o contraseña incorrectos» pegado en
// Registro (campos vacíos, texto de otra pantalla) hasta el próximo login
// exitoso. Estos tests montan las dos pantallas reales con el mismo
// `pushReplacement` que usa la app y comparten UN notifier, como en producción.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/auth/presentation/login_screen.dart';
import 'package:treino/features/auth/presentation/register_screen.dart';
import 'package:treino/features/auth/presentation/widgets/auth_failure_banner.dart';
import 'package:treino/features/auth/presentation/widgets/auth_pill_button.dart';
import 'package:treino/features/auth/presentation/widgets/auth_switch_link.dart';
import 'package:treino/l10n/app_l10n.dart';

const _loginCopy = 'Email o contraseña incorrectos';
const _registerCopy = 'Ya existe una cuenta con ese email';

/// Falla todo intento con el error que corresponde a cada acción, igual que
/// el notifier real: deja el `AsyncError` en el estado global.
class _FailingAuthNotifier extends AuthNotifier {
  @override
  Future<User?> build() async => null;

  @override
  Future<void> signIn({required String email, required String password}) async {
    state =
        const AsyncError(AuthFailure.invalidCredentials(), StackTrace.empty);
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    state = const AsyncError(AuthFailure.emailAlreadyInUse(), StackTrace.empty);
  }
}

Widget _buildApp({String initialLocation = '/login'}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const Scaffold(body: Text('FORGOT')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [authNotifierProvider.overrideWith(_FailingAuthNotifier.new)],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

/// Superficie de teléfono: con los 800×600 por defecto el link de cambio de
/// pantalla queda debajo del borde y el tap no le pega.
Future<void> _pumpApp(
  WidgetTester tester, {
  String initialLocation = '/login',
}) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_buildApp(initialLocation: initialLocation));
}

Future<void> _failLogin(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'atleta@example.com');
  await tester.enterText(fields.at(1), 'mal1234');
  await tester.pump();
  await tester.ensureVisible(find.byType(AuthPillButton));
  await tester.tap(find.byType(AuthPillButton));
  await tester.pumpAndSettle();
}

Future<void> _failRegister(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'existe@example.com');
  await tester.enterText(fields.at(1), 'Pass1234');
  await tester.pump();
  await tester.ensureVisible(find.byType(Checkbox));
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
  await tester.ensureVisible(find.byType(AuthPillButton));
  await tester.tap(find.byType(AuthPillButton));
  await tester.pumpAndSettle();
}

Future<void> _tapSwitchLink(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(AuthSwitchLink));
  await tester.tap(find.byType(AuthSwitchLink));
  await tester.pumpAndSettle();
}

void main() {
  // Control negativo: sin esto, los «sin banner» de abajo pasarían también
  // con un notifier que nunca falla.
  testWidgets('control — un login fallido SÍ muestra su banner en Login',
      (tester) async {
    await _pumpApp(tester);
    await tester.pumpAndSettle();

    await _failLogin(tester);

    expect(find.byType(AuthFailureBanner), findsOneWidget);
    expect(find.text(_loginCopy), findsOneWidget);
  });

  testWidgets('el error de Login no viaja a Registro', (tester) async {
    await _pumpApp(tester);
    await tester.pumpAndSettle();
    await _failLogin(tester);
    expect(find.text(_loginCopy), findsOneWidget);

    await _tapSwitchLink(tester);

    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.byType(AuthFailureBanner), findsNothing);
    expect(find.text(_loginCopy), findsNothing);
  });

  testWidgets('volver de Registro a Login tampoco trae el error viejo',
      (tester) async {
    await _pumpApp(tester);
    await tester.pumpAndSettle();
    await _failLogin(tester);

    await _tapSwitchLink(tester); // → Registro
    await _tapSwitchLink(tester); // → Login de nuevo

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(AuthFailureBanner), findsNothing);
  });

  testWidgets('editar el email limpia el error de Login', (tester) async {
    await _pumpApp(tester);
    await tester.pumpAndSettle();
    await _failLogin(tester);
    expect(find.text(_loginCopy), findsOneWidget);

    await tester.enterText(
        find.byType(TextFormField).at(0), 'otro@example.com');
    await tester.pump();

    expect(find.byType(AuthFailureBanner), findsNothing);
  });

  testWidgets('editar la contraseña limpia el error de Login', (tester) async {
    await _pumpApp(tester);
    await tester.pumpAndSettle();
    await _failLogin(tester);

    await tester.enterText(find.byType(TextFormField).at(1), 'otra1234');
    await tester.pump();

    expect(find.byType(AuthFailureBanner), findsNothing);
  });

  testWidgets(
      'Registro muestra su propio error, nunca el texto de Login, aunque '
      'venga de un login fallido', (tester) async {
    await _pumpApp(tester);
    await tester.pumpAndSettle();
    await _failLogin(tester);
    await _tapSwitchLink(tester);

    await _failRegister(tester);

    expect(find.text(_registerCopy), findsOneWidget);
    expect(find.text(_loginCopy), findsNothing);
  });

  testWidgets('editar el campo limpia el error de Registro', (tester) async {
    await _pumpApp(tester, initialLocation: '/register');
    await tester.pumpAndSettle();
    await _failRegister(tester);
    expect(find.text(_registerCopy), findsOneWidget);

    await tester.enterText(
        find.byType(TextFormField).at(0), 'nuevo@example.com');
    await tester.pump();

    expect(find.byType(AuthFailureBanner), findsNothing);
  });

  testWidgets('el error de Registro no viaja a Login', (tester) async {
    await _pumpApp(tester, initialLocation: '/register');
    await tester.pumpAndSettle();
    await _failRegister(tester);

    await _tapSwitchLink(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(AuthFailureBanner), findsNothing);
  });
}
