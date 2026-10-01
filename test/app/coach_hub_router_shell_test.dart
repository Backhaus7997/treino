// Shell invariant test for the Coach Hub router (W1.2.5, REQ-CHW-ROUTER-002,
// REQ-CHW-QA-002).
//
// Asserts the structural contract of ADR-CHW-001: public routes (`/login`,
// `/not-allowed`) are top-level siblings that DO NOT render `CoachHubScaffold`,
// while signed-in routes (`/dashboard`) live inside the `ShellRoute` and DO.
//
// Unlike `coach_hub_router_redirect_test.dart` (which tests the pure redirect
// function), this pumps the real `buildCoachHubRouter` to verify the wiring.
// The router hardcodes `initialLocation: '/dashboard'`, so we warm the auth +
// profile providers before pumping and let the redirect route each role to its
// destination (a dummy `refreshListenable` would not re-fire the redirect once
// providers resolve later).

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/coach_hub_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/application/email_gate_providers.dart';
import 'package:treino/features/auth/data/mail_verification_service.dart';
import 'package:treino/features/auth/presentation/verify_mail_screen.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_login_screen.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_not_allowed_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/pricing_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_scaffold.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_sidebar.dart';
import 'package:treino/features/coach_hub/presentation/shell/mobile_banner.dart';
import 'package:treino/features/coach_hub/presentation/shell/mobile_facturacion_shell.dart';
import 'package:treino/features/coach_hub/presentation/shell/proximamente_screen.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

import '../helpers/mail_test_helpers.dart';
import '../helpers/onboarding_test_helpers.dart';

class _MockUser extends Mock implements User {}

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockAuth extends Mock implements FirebaseAuth {}

/// Servicio del código que no toca la red: contesta «ya hay uno vigente», que
/// no arranca la cuenta regresiva del «Reenviar» (un `Timer` periódico que
/// mantendría vivo a `pumpAndSettle`).
class _ServicioQuieto extends MailVerificationService {
  _ServicioQuieto() : super(functions: _MockFunctions());

  @override
  Future<ResultadoDeSolicitud> solicitar({bool reenviar = false}) async =>
      const ResultadoDeSolicitud(SolicitudDeCodigo.vigente);
}

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AsyncValue<User?> _fixedState;

  @override
  Future<User?> build() async {
    state = _fixedState;
    return _fixedState.valueOrNull;
  }
}

UserProfile _trainerProfile() => UserProfile(
      onboardingSeen: allSurfacesSeen(),
      uid: 'test-uid',
      email: 'trainer@example.com',
      displayName: 'Mateo',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

UserProfile _athleteProfile() => UserProfile(
      onboardingSeen: allSurfacesSeen(),
      uid: 'test-uid',
      email: 'athlete@example.com',
      displayName: 'Tincho',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Builds the shared container, warms auth + profile so the redirect resolves
/// on first evaluation, pumps the real router, and settles. Returns the
/// [GoRouter] so a test can navigate to a deeper route (e.g. a placeholder).
Future<GoRouter> _pumpRouter(
  WidgetTester tester, {
  required Override authOverride,
  Override? profileOverride,
  Uri? initialUri,
  // Coach Hub es un layout de escritorio (min 1024px). En el surface default
  // de 800x600 el sidebar (264px) deja muy poco ancho y el dashboard real
  // desborda. Pumpeamos a un tamaño desktop realista por default; los tests
  // de la excepción móvil de facturación (ver `mobile_facturacion_shell.dart`)
  // lo pisan con un tamaño de teléfono.
  Size size = const Size(1400, 900),
  // El interruptor `app_config/email_gate`. Apagado por defecto: sin el
  // override, el provider real intenta abrir Firestore y solo "anda" porque en
  // un test falla (y el error lo deja apagado).
  Stream<bool>? emailGate,
  // Para los tests que cambian el perfil en vivo y disparan el redirect. El
  // helper se queda con su ciclo de vida: el test no lo descarta.
  ValueNotifier<int>? refresh,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();

  final container = ProviderContainer(overrides: [
    authOverride,
    profileOverride ??
        userProfileProvider
            .overrideWith((ref) => Stream<UserProfile?>.value(null)),
    sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
    trainerLinksStreamProvider
        .overrideWith((ref) => Stream.value(const <TrainerLink>[])),
    emailGateEnabledProvider
        .overrideWith((ref) => emailGate ?? Stream<bool>.value(false)),
    ...overrides,
  ]);
  addTearDown(container.dispose);

  // Warm the providers the redirect reads — without this they are AsyncLoading
  // at first evaluation and the redirect defensively returns null (stay).
  await tester.runAsync(() async {
    await container.read(authNotifierProvider.future).catchError(
          (_) => null,
        );
    await container.read(userProfileProvider.future).catchError(
          (_) => null,
        );
    await container.read(emailGateEnabledProvider.future).catchError(
          (_) => false,
        );
  });

  final refreshListenable = refresh ?? ValueNotifier<int>(0);
  addTearDown(refreshListenable.dispose);
  final router = buildCoachHubRouter(
    refreshListenable: refreshListenable,
    read: container.read,
    initialUri: initialUri,
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
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
  group('Coach Hub router shell invariant (ADR-CHW-001)', () {
    testWidgets(
      'anonymous → /login does NOT render CoachHubScaffold [SCENARIO-758]',
      (tester) async {
        await _pumpRouter(
          tester,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(const AsyncData(null)),
          ),
        );

        expect(find.byType(CoachHubScaffold), findsNothing);
        expect(find.byType(CoachHubLoginScreen), findsOneWidget);
      },
    );

    testWidgets(
      '/login a 390×844 (mismo viewport que la excepción móvil de '
      'facturación) sin overflow — CoachHubLoginScreen no tiene breakpoints '
      'responsivos propios (MVP, ver su dartdoc)',
      (tester) async {
        await _pumpRouter(
          tester,
          size: const Size(390, 844),
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(const AsyncData(null)),
          ),
        );

        expect(find.byType(CoachHubLoginScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'athlete → /not-allowed does NOT render CoachHubScaffold [SCENARIO-759]',
      (tester) async {
        final user = _MockUser();
        await _pumpRouter(
          tester,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(user)),
          ),
          profileOverride: userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(_athleteProfile()),
          ),
        );

        expect(find.byType(CoachHubScaffold), findsNothing);
        expect(find.byType(CoachHubNotAllowedScreen), findsOneWidget);
      },
    );

    testWidgets(
      'trainer → /dashboard renders exactly one CoachHubScaffold [SCENARIO-770]',
      (tester) async {
        final user = _MockUser();
        await _pumpRouter(
          tester,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(user)),
          ),
          profileOverride: userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(_trainerProfile()),
          ),
        );

        expect(find.byType(CoachHubScaffold), findsOneWidget);
        expect(find.byType(CoachHubDashboardScreen), findsOneWidget);
      },
    );

    testWidgets(
      'trainer → placeholder route renders ProximamenteScreen inside the shell '
      '[SCENARIO-753]',
      (tester) async {
        final user = _MockUser();
        final router = await _pumpRouter(
          tester,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(user)),
          ),
          profileOverride: userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(_trainerProfile()),
          ),
        );

        // `/nutricion` dejó de ser placeholder en Fase 6 (WU-04,
        // `NutricionScreen`) y `/planes` dejó de serlo en Fase 10 (WU-03,
        // `PlanesScreen`) — `/planner` sigue sin screen real, sirve de
        // fixture estable para este invariante estructural del shell.
        router.go('/planner');
        await tester.pumpAndSettle();

        // Placeholder renders WITHIN the shell (sidebar stays visible).
        expect(find.byType(CoachHubScaffold), findsOneWidget);
        expect(find.byType(ProximamenteScreen), findsOneWidget);
        expect(find.text('Próximamente.'), findsOneWidget);
      },
    );
  });

  // Encontrado en revisión adversarial: el mapeo `to` → path está probado a
  // fondo via la función pura `coachHubRedirect`, pero el PEGAMENTO real —
  // `buildCoachHubRouter` leyendo `Uri.base`/`initialUri` y pasándolo por
  // closure a cada `redirect:` — nunca se ejercitaba con un router de
  // verdad. Si alguien rompe esa plomería (por ejemplo, deja de pasar
  // `initialDestination: destination` en la llamada real), esto lo detecta;
  // los tests de la función pura no pueden, porque construyen el destino a
  // mano.
  group('Coach Hub router — destino fino via Uri.base/initialUri', () {
    testWidgets(
      'un trainer que llega con to=agenda en la URL cae en /agenda',
      (tester) async {
        final router = await _pumpRouter(
          tester,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(_MockUser())),
          ),
          profileOverride: userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(_trainerProfile()),
          ),
          initialUri: Uri.parse('https://app.gettreino.com/?to=agenda'),
        );

        // SIN forzar ninguna navegación: el router arranca en
        // `initialLocation` y el destino fino tiene que aplicarse ahí mismo.
        //
        // Antes este test hacía `router.go('/login')` primero, con el
        // comentario de que en `/dashboard` "el gate no se dispara, a
        // propósito" y que forzar `/login` "simula el gate que SÍ dispara en
        // la app real". Esa creencia era el bug: en la app real, un PF CON
        // SESIÓN entra por `/abrir/profe?to=X`, Vercel lo manda a
        // `app.gettreino.com/?to=X`, y como el Coach Hub usa hash routing el
        // fragmento llega VACÍO — así que go_router arranca en
        // `initialLocation`, no en `/`. El gate nunca se disparaba y todos los
        // destinos finos morían en el dashboard.
        //
        // El rodeo del `go('/login')` hacía pasar el test por el único camino
        // donde el bug NO aparece: el del que llega deslogueado.
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/agenda',
        );
      },
    );

    testWidgets(
      'el mismo destino aplica al que llega DESLOGUEADO y se autentica',
      (tester) async {
        // El otro camino, que antes era el unico que el test ejercitaba: sin
        // sesion la landing es `/login`, que es `isPublic`, y el destino se
        // aplica despues del gate de rol. Sigue andando.
        final router = await _pumpRouter(
          tester,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(_MockUser())),
          ),
          profileOverride: userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(_trainerProfile()),
          ),
          initialUri: Uri.parse('https://app.gettreino.com/?to=agenda'),
        );

        router.go('/login');
        await tester.pumpAndSettle();

        // Ya se consumio en el aterrizaje, asi que volver a /login cae en el
        // dashboard — el destino es de UN solo uso, y eso es lo correcto:
        // un `to` viejo en la URL no puede reenviarte cada vez que pasas por
        // la pantalla de login.
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/dashboard',
        );
      },
    );

    testWidgets(
      'sin to en la URL, el gate sigue cayendo en /dashboard como siempre',
      (tester) async {
        final router = await _pumpRouter(
          tester,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(_MockUser())),
          ),
          profileOverride: userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(_trainerProfile()),
          ),
          initialUri: Uri.parse('https://app.gettreino.com/'),
        );

        router.go('/login');
        await tester.pumpAndSettle();

        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/dashboard',
        );
      },
    );
  });

  // La excepción móvil de `/facturacion/planes` (ver
  // `mobile_facturacion_shell.dart`): el mail del tope de plan manda al PF a
  // esta ruta y hasta ahora `MobileBanner` la frenaba en el teléfono, sin
  // forma de pagar. `_kMobileSize` es el mismo viewport que
  // `pricing_screen_test.dart` usa para el layout angosto del paywall
  // (iPhone 14/15, 390×844).
  group('Excepción móvil de facturación (ADR-CHW-004 + mobile paywall)', () {
    const kMobileSize = Size(390, 844);

    testWidgets(
      'teléfono + /facturacion/planes → se ve la pantalla de planes, sin '
      'sidebar ni MobileBanner',
      (tester) async {
        final router = await _pumpRouter(
          tester,
          size: kMobileSize,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(_MockUser())),
          ),
          profileOverride: userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(_trainerProfile()),
          ),
        );

        router.go('/facturacion/planes');
        await tester.pumpAndSettle();

        expect(find.byType(MobileFacturacionShell), findsOneWidget);
        expect(find.byType(MobileBanner), findsNothing);
        expect(find.byType(CoachHubSidebar), findsNothing);
        expect(find.byType(PricingScreen), findsOneWidget);
        expect(find.text('PLAN 1'), findsOneWidget);
      },
    );

    testWidgets(
      'teléfono + /dashboard sigue mostrando MobileBanner (la excepción NO '
      'se filtra al resto del Coach Hub)',
      (tester) async {
        await _pumpRouter(
          tester,
          size: kMobileSize,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(_MockUser())),
          ),
          profileOverride: userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(_trainerProfile()),
          ),
        );

        expect(find.byType(MobileBanner), findsOneWidget);
        expect(find.byType(MobileFacturacionShell), findsNothing);
      },
    );

    testWidgets(
      'escritorio + /facturacion/planes → shell normal con sidebar '
      '(la excepción es sólo para mobile)',
      (tester) async {
        final router = await _pumpRouter(
          tester,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(_MockUser())),
          ),
          profileOverride: userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(_trainerProfile()),
          ),
        );

        router.go('/facturacion/planes');
        await tester.pumpAndSettle();

        expect(find.byType(CoachHubSidebar), findsOneWidget);
        expect(find.byType(MobileFacturacionShell), findsNothing);
        expect(find.byType(PricingScreen), findsOneWidget);
      },
    );

    testWidgets(
      'teléfono logueado con ?to=facturacion en la URL termina viendo los '
      'planes, no el MobileBanner intermedio',
      (tester) async {
        final router = await _pumpRouter(
          tester,
          size: kMobileSize,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(_MockUser())),
          ),
          profileOverride: userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(_trainerProfile()),
          ),
          initialUri: Uri.parse('https://app.gettreino.com/?to=facturacion'),
        );

        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/facturacion/planes',
        );
        expect(find.byType(MobileFacturacionShell), findsOneWidget);
        expect(find.byType(MobileBanner), findsNothing);
      },
    );
  });

  // El gate del mail con el router REAL: la ruta existe, vive fuera del shell,
  // y el destino del mail sobrevive a la confirmación (en
  // `coach_hub_router_redirect_test.dart` está la misma regla sobre la función
  // pura; acá se comprueba que go_router re-evalúa el redirect sobre la
  // ubicación a la que sale el gate).
  group('Gate del mail con código (router real)', () {
    const email = 'trainer@example.com';

    testWidgets(
      'PF sin confirmar, con ?to=facturacion: ve el código sin sidebar y, al '
      'confirmar, cae en /facturacion/planes',
      (tester) async {
        final user = _MockUser();
        when(() => user.email).thenReturn(email);
        // La pantalla del código dice a qué mail mandó el código.
        final auth = _MockAuth();
        when(() => auth.currentUser).thenReturn(user);
        final perfil = StreamController<UserProfile?>();
        addTearDown(perfil.close);
        perfil.add(_trainerProfile());
        final refresh = ValueNotifier<int>(0);

        final router = await _pumpRouter(
          tester,
          authOverride: authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(user)),
          ),
          profileOverride: userProfileProvider.overrideWith(
            (ref) => perfil.stream,
          ),
          emailGate: Stream<bool>.value(true),
          refresh: refresh,
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            mailVerificationServiceProvider
                .overrideWithValue(_ServicioQuieto()),
          ],
          initialUri: Uri.parse('https://app.gettreino.com/?to=facturacion'),
        );

        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/verificar-mail',
        );
        expect(find.byType(VerifyMailScreen), findsOneWidget);
        expect(find.byType(CoachHubScaffold), findsNothing);
        expect(find.byType(CoachHubSidebar), findsNothing);
        expect(tester.takeException(), isNull);
        // En escritorio el campo no se estira a todo el ancho de la ventana
        // (sin acotar medía 1360 px en esta de 1400).
        expect(
          tester.getSize(find.byKey(const Key('verify_mail_code_field'))).width,
          lessThanOrEqualTo(480),
        );

        // Llega el perfil con la marca que escribe el servidor.
        perfil.add(
          _trainerProfile().copyWith(
            emailVerification: mailConfirmadoPara(UserRole.trainer, email),
          ),
        );
        await tester.pump();
        refresh.value++;
        await tester.pumpAndSettle();

        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/facturacion/planes',
        );
        expect(find.byType(VerifyMailScreen), findsNothing);
        expect(find.byType(PricingScreen), findsOneWidget);
      },
    );
  });
}
