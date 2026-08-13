import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/router.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/presentation/login_screen.dart';
import 'package:treino/features/auth/presentation/register_screen.dart';
import 'package:treino/features/auth/presentation/splash_screen.dart';
import 'package:treino/features/auth/presentation/welcome_screen.dart';
import 'package:treino/features/auth/presentation/widgets/auth_pill_button.dart';
import 'package:treino/features/auth/presentation/widgets/auth_secondary_button.dart';
import 'package:treino/features/auth/presentation/widgets/terms_checkbox.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

// ---------------------------------------------------------------------------
// Issue #499 — flicker /home → /profile-setup en el 100% de los registros
// nuevos.
//
// Las 4 pantallas de entrada (register, login, welcome, splash) navegaban a
// mano a /home apenas authNotifier tenía valor, SIN esperar a
// userProfileProvider. `authRedirect` ya esperaba bien (bloquea el redirect
// mientras el perfil carga), así que la navegación manual lo adelantaba:
// HomeScreen alcanzaba a pintar y recién después el gate rebotaba a
// /profile-setup.
//
// Estos tests montan la pantalla real contra el `authRedirect` de PRODUCCIÓN y
// cuentan cuántas veces se construye la ruta /home. La aserción dura es
// `homeBuilds == 0`: no alcanza con terminar en /profile-setup, HomeScreen no
// puede construirse NI UN FRAME.
// ---------------------------------------------------------------------------

class MockUser extends Mock implements User {}

/// AuthNotifier stub: no toca Firebase y expone un único hook para simular el
/// desenlace de cualquiera de las 4 acciones de auth.
class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier({User? initialUser}) : _initialUser = initialUser;

  final User? _initialUser;

  /// Corre cuando el test tapea la acción de auth. Setealo para simular éxito
  /// (`state = AsyncData(user)`) o falla (`state = AsyncError(...)`).
  void Function()? onAuth;

  @override
  Future<User?> build() async => _initialUser;

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async =>
      onAuth?.call();

  @override
  Future<void> signUp({
    required String email,
    required String password,
  }) async =>
      onAuth?.call();

  @override
  Future<void> signInWithGoogle() async => onAuth?.call();

  @override
  Future<void> signInWithApple() async => onAuth?.call();
}

/// Espejo de [RouterRefreshNotifier] para el container del test: re-dispara el
/// redirect cuando auth o el perfil emiten, deduplicado por microtask igual que
/// en producción.
class _Refresh extends ChangeNotifier {
  _Refresh(ProviderContainer container) {
    container.listen(authNotifierProvider, (_, __) => _schedule());
    container.listen(userProfileProvider, (_, __) => _schedule());
  }

  bool _scheduled = false;
  bool _disposed = false;

  void _schedule() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_disposed) return;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Perfil recién creado por `AuthService.signUpWithEmail`: displayName todavía
/// null. Es el estado del 100% de los registros nuevos.
UserProfile _incompleteProfile() => UserProfile(
      uid: 'test-uid',
      email: 'nuevo@example.com',
      displayName: null,
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Perfil que ya pasó por ProfileSetup — el redirect lo deja llegar a /home.
UserProfile _completeProfile() => UserProfile(
      uid: 'test-uid',
      email: 'existente@example.com',
      displayName: 'tincho',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Monta una pantalla de auth real sobre un router cuyo redirect ES el
/// `authRedirect` de producción, con el perfil manejado a mano por el test para
/// poder abrir la ventana exacta de la carrera (auth resuelto + perfil todavía
/// cargando).
class _Harness {
  _Harness({
    required Widget screen,
    required String initialLocation,
    User? initialUser,
  }) {
    notifier = _TestAuthNotifier(initialUser: initialUser);
    container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(() => notifier),
        userProfileProvider.overrideWith((ref) => profile.stream),
      ],
    );
    refresh = _Refresh(container);
    router = GoRouter(
      initialLocation: initialLocation,
      refreshListenable: refresh,
      redirect: (_, state) =>
          authRedirect(container.read, state.matchedLocation),
      routes: [
        GoRoute(path: initialLocation, builder: (_, __) => screen),
        for (final entry in _placeholders.entries)
          if (entry.key != initialLocation)
            GoRoute(
              path: entry.key,
              builder: (_, __) {
                if (entry.key == '/home') homeBuilds++;
                return Scaffold(body: Text(entry.value));
              },
            ),
      ],
    );
  }

  static const _placeholders = {
    '/home': 'HOME',
    '/profile-setup': 'PROFILE SETUP',
    '/welcome': 'WELCOME',
    '/login': 'LOGIN',
    '/register': 'REGISTER',
    '/splash': 'SPLASH',
  };

  /// Broadcast: lo escuchan el refresh listenable y el propio provider.
  final profile = StreamController<UserProfile?>.broadcast();

  late final _TestAuthNotifier notifier;
  late final ProviderContainer container;
  late final _Refresh refresh;
  late final GoRouter router;

  /// Cuántas veces se construyó la ruta /home. La aserción central de #499.
  int homeBuilds = 0;

  Widget get app => UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
        ),
      );

  void dispose() {
    router.dispose();
    refresh.dispose();
    container.dispose();
    profile.close();
  }
}

/// Avanza los frames necesarios para que corra el microtask del refresh
/// listenable y go_router aplique el redirect resultante.
///
/// NO se puede usar `pumpAndSettle` en las ventanas donde la pantalla queda
/// montada: el CTA muestra un CircularProgressIndicator (animación infinita) y
/// el settle nunca terminaría.
Future<void> _pumpRedirect(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  late MockUser mockUser;

  setUp(() {
    mockUser = MockUser();
    when(() => mockUser.emailVerified).thenReturn(true);
  });

  // -------------------------------------------------------------------------
  // register_screen.dart:74-78
  // -------------------------------------------------------------------------
  group('RegisterScreen', () {
    Future<_Harness> pumpAndSignUp(WidgetTester tester) async {
      final h = _Harness(
        screen: const RegisterScreen(),
        initialLocation: '/register',
      );
      addTearDown(h.dispose);

      await tester.pumpWidget(h.app);
      await tester.pump();
      h.notifier.onAuth = () => h.notifier.state = AsyncData(mockUser);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'nuevo@example.com');
      await tester.enterText(fields.at(1), 'Pass1234');
      await tester.enterText(fields.at(2), 'Pass1234');
      await tester.pump();
      await tester.ensureVisible(find.byType(TermsCheckbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.byType(AuthPillButton));
      await tester.tap(find.byType(AuthPillButton));
      await _pumpRedirect(tester);
      return h;
    }

    testWidgets(
        'alta nueva no construye /home ni un frame — va a /profile-setup',
        (tester) async {
      final h = await pumpAndSignUp(tester);

      // Ventana de la carrera: auth ya resolvió, el perfil todavía no emitió.
      expect(h.homeBuilds, 0,
          reason: '/home no puede construirse mientras el perfil carga');
      expect(find.text('HOME'), findsNothing);

      // Llega el snapshot recién creado: displayName == null.
      h.profile.add(_incompleteProfile());
      await _pumpRedirect(tester);

      expect(find.text('PROFILE SETUP'), findsOneWidget);
      expect(h.homeBuilds, 0,
          reason: 'flicker /home → /profile-setup (issue #499)');
    });

    testWidgets('perfil completo sí llega a /home', (tester) async {
      final h = await pumpAndSignUp(tester);

      h.profile.add(_completeProfile());
      await _pumpRedirect(tester);

      expect(find.text('HOME'), findsOneWidget);
      expect(h.homeBuilds, 1);
    });
  });

  // -------------------------------------------------------------------------
  // login_screen.dart:64-68
  // -------------------------------------------------------------------------
  group('LoginScreen', () {
    Future<_Harness> pumpAndSignIn(WidgetTester tester) async {
      final h = _Harness(
        screen: const LoginScreen(),
        initialLocation: '/login',
      );
      addTearDown(h.dispose);

      await tester.pumpWidget(h.app);
      await tester.pump();
      h.notifier.onAuth = () => h.notifier.state = AsyncData(mockUser);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'nuevo@example.com');
      await tester.enterText(fields.at(1), 'Pass1234');
      await tester.pump();
      await tester.tap(find.byType(AuthPillButton));
      await _pumpRedirect(tester);
      return h;
    }

    testWidgets('login con perfil incompleto no construye /home ni un frame',
        (tester) async {
      final h = await pumpAndSignIn(tester);

      expect(h.homeBuilds, 0,
          reason: '/home no puede construirse mientras el perfil carga');
      expect(find.text('HOME'), findsNothing);

      h.profile.add(_incompleteProfile());
      await _pumpRedirect(tester);

      expect(find.text('PROFILE SETUP'), findsOneWidget);
      expect(h.homeBuilds, 0,
          reason: 'flicker /home → /profile-setup (issue #499)');
    });

    testWidgets('login con perfil completo sí llega a /home', (tester) async {
      final h = await pumpAndSignIn(tester);

      h.profile.add(_completeProfile());
      await _pumpRedirect(tester);

      expect(find.text('HOME'), findsOneWidget);
      expect(h.homeBuilds, 1);
    });

    testWidgets('el CTA sigue en loading mientras el perfil no resuelve',
        (tester) async {
      // Visibility of system status: entre "auth ok" y "el router me mueve" la
      // pantalla queda montada; el CTA no puede volver a estado listo o el tap
      // se lee como que no hizo nada.
      await pumpAndSignIn(tester);

      expect(
        find.descendant(
          of: find.byType(AuthPillButton),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
    });
  });

  // -------------------------------------------------------------------------
  // welcome_screen.dart:284-288,294-298
  // -------------------------------------------------------------------------
  group('WelcomeScreen', () {
    Future<_Harness> pumpAndOAuth(WidgetTester tester) async {
      final h = _Harness(
        screen: const WelcomeScreen(),
        initialLocation: '/welcome',
      );
      addTearDown(h.dispose);

      await tester.pumpWidget(h.app);
      await tester.pump();
      h.notifier.onAuth = () => h.notifier.state = AsyncData(mockUser);

      // Primer AuthSecondaryButton del Row = GOOGLE.
      final google = find.byType(AuthSecondaryButton).first;
      await tester.ensureVisible(google);
      await tester.tap(google);
      await _pumpRedirect(tester);
      return h;
    }

    testWidgets('OAuth de alta nueva no construye /home ni un frame',
        (tester) async {
      final h = await pumpAndOAuth(tester);

      expect(h.homeBuilds, 0,
          reason: '/home no puede construirse mientras el perfil carga');
      expect(find.text('HOME'), findsNothing);

      h.profile.add(_incompleteProfile());
      await _pumpRedirect(tester);

      expect(find.text('PROFILE SETUP'), findsOneWidget);
      expect(h.homeBuilds, 0,
          reason: 'flicker /home → /profile-setup (issue #499)');
    });

    testWidgets('OAuth de usuario existente sí llega a /home', (tester) async {
      final h = await pumpAndOAuth(tester);

      h.profile.add(_completeProfile());
      await _pumpRedirect(tester);

      expect(find.text('HOME'), findsOneWidget);
      expect(h.homeBuilds, 1);
    });
  });

  // -------------------------------------------------------------------------
  // splash_screen.dart:49-56
  //
  // Splash es el único de los 4 que CONSERVA navegación manual: /splash está
  // excluido de la regla `/public → /home` de authRedirect, así que sin el
  // `context.go` la pantalla nunca haría el hand-off. Lo que cambia es que
  // ahora espera también al perfil antes de mandar a /home.
  // -------------------------------------------------------------------------
  group('SplashScreen', () {
    testWidgets('sesión con perfil incompleto no construye /home ni un frame',
        (tester) async {
      final h = _Harness(
        screen: const SplashScreen(),
        initialLocation: '/splash',
        initialUser: mockUser,
      );
      addTearDown(h.dispose);

      await tester.pumpWidget(h.app);
      await _pumpRedirect(tester);

      // Auth ya resolvió; el perfil no. El splash tiene que seguir esperando.
      expect(h.homeBuilds, 0,
          reason: '/home no puede construirse mientras el perfil carga');

      h.profile.add(_incompleteProfile());
      await _pumpRedirect(tester);

      expect(find.text('PROFILE SETUP'), findsOneWidget);
      expect(h.homeBuilds, 0,
          reason: 'flicker /home → /profile-setup (issue #499)');
    });

    testWidgets('sesión con perfil completo sí llega a /home', (tester) async {
      final h = _Harness(
        screen: const SplashScreen(),
        initialLocation: '/splash',
        initialUser: mockUser,
      );
      addTearDown(h.dispose);

      await tester.pumpWidget(h.app);
      await _pumpRedirect(tester);

      h.profile.add(_completeProfile());
      await _pumpRedirect(tester);

      expect(find.text('HOME'), findsOneWidget);
      expect(h.homeBuilds, 1);
    });

    testWidgets('anónimo va a /welcome sin esperar ningún perfil',
        (tester) async {
      final h = _Harness(
        screen: const SplashScreen(),
        initialLocation: '/splash',
      );
      addTearDown(h.dispose);

      await tester.pumpWidget(h.app);
      await _pumpRedirect(tester);

      expect(find.text('WELCOME'), findsOneWidget);
      expect(h.homeBuilds, 0);
    });
  });
}
