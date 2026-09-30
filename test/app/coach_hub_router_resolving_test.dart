// El teléfono no muestra «Coach Hub en escritorio» mientras el router resuelve
// la sesión (bug: el link del mail del tope llegaba al banner y recién después,
// a la pantalla de planes).
//
// Este archivo monta el `buildCoachHubRouter` REAL con la cadena REAL de
// providers —`AuthNotifier`, `userProfileProvider`, `RouterRefreshNotifier`— y
// sólo falsea los dos bordes de IO: el stream de auth de Firebase y el stream
// del perfil en Firestore. Los dos arrancan mudos, o sea con la sesión y el
// perfil en `AsyncLoading`, y el test los hace emitir de a uno, como en
// producción.
//
// A diferencia de `coach_hub_router_shell_test.dart` —que calienta los
// providers ANTES de montar el router y por eso nunca ve el tránsito—, acá lo
// que se mide es justamente el tránsito: un observador anota qué pantalla hay
// en CADA frame que se dibuja, y los tests comparan la secuencia completa.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/coach_hub_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_login_screen.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_not_allowed_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/pricing_screen.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_resolving_view.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_sidebar.dart';
import 'package:treino/features/coach_hub/presentation/shell/mobile_banner.dart';
import 'package:treino/features/coach_hub/presentation/shell/mobile_facturacion_shell.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../helpers/onboarding_test_helpers.dart';

class _MockUser extends Mock implements User {}

class _MockUserRepository extends Mock implements UserRepository {}

/// El link que manda el mail del tope: `/abrir/profe?to=facturacion` en Vercel
/// redirige acá y el query string se reenvía solo.
final _kLinkDelMail = Uri.parse('https://app.gettreino.com/?to=facturacion');

/// iPhone 14/15 — el mismo viewport que usa el resto de los tests de la
/// excepción móvil de facturación.
const _kTelefono = Size(390, 844);

UserProfile _perfil(UserRole role) => UserProfile(
      onboardingSeen: allSurfacesSeen(),
      uid: 'pf-1',
      email: 'pf@example.com',
      displayName: 'Mateo',
      role: role,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Anota, en CADA frame que se dibuja, qué pantalla hay. Sólo guarda los
/// cambios, así que el resultado es la secuencia de pantallas que vio el
/// usuario — `['carga', 'planes']` y no cuarenta veces `'carga'`.
///
/// Se engancha con `addPostFrameCallback` y se re-registra en cada frame: así ve
/// TODOS los frames, incluidos los de un `pumpAndSettle`, y no sólo el estado
/// con el que termina cada `pump`.
class _Frames {
  _Frames(this._binding) {
    _binding.addPostFrameCallback(_onFrame);
  }

  final TestWidgetsFlutterBinding _binding;
  final List<String> secuencia = [];
  bool _activo = true;

  void _onFrame(Duration _) {
    if (!_activo) return;
    final ahora = _pantalla();
    if (secuencia.isEmpty || secuencia.last != ahora) secuencia.add(ahora);
    _binding.addPostFrameCallback(_onFrame);
  }

  void detener() => _activo = false;

  static String _pantalla() {
    bool hay(Type t) => find.byType(t).evaluate().isNotEmpty;
    if (hay(CoachHubResolvingView)) return 'carga';
    if (hay(MobileBanner)) return 'banner';
    if (hay(MobileFacturacionShell)) return 'planes';
    if (hay(CoachHubLoginScreen)) return 'login';
    if (hay(CoachHubNotAllowedScreen)) return 'no-autorizado';
    if (hay(CoachHubSidebar)) return 'escritorio';
    return 'otra';
  }
}

class _Hub {
  _Hub({
    required this.tester,
    required this.auth,
    required this.perfil,
    required this.router,
    required this.frames,
  });

  final WidgetTester tester;

  /// Lo que emitiría `FirebaseAuth.authStateChanges()`. Mudo = sesión cargando.
  final StreamController<User?> auth;

  /// Lo que emitiría el snapshot del perfil en Firestore. Mudo = perfil
  /// cargando.
  final StreamController<UserProfile?> perfil;

  final GoRouter router;
  final _Frames frames;

  late final User usuario = _MockUser();

  String get ruta => router.routerDelegate.currentConfiguration.uri.toString();

  /// Deja pasar un segundo de frames, de a 40 ms — los suficientes para que un
  /// evento llegue al provider, el refresh dispare el redirect, el resultado se
  /// dibuje y termine la transición de página (un segundo alcanza para la que
  /// trae el tema por defecto). Se hace frame por frame y no de un salto para
  /// que el observador vea también los frames del medio de la transición.
  ///
  /// NO usa `pumpAndSettle`: la vista de carga tiene un indicador que anima
  /// para siempre y `pumpAndSettle` no volvería.
  Future<void> avanzar() async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }
}

Future<_Hub> _montar(
  WidgetTester tester, {
  Size size = _kTelefono,
  Uri? initialUri,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();

  // `.broadcast()`: el provider se suscribe cuando se crea y se vuelve a
  // suscribir cada vez que se reconstruye (p. ej. cuando cambia la sesión).
  final auth = StreamController<User?>.broadcast();
  final perfil = StreamController<UserProfile?>.broadcast();
  addTearDown(auth.close);
  addTearDown(perfil.close);

  final repo = _MockUserRepository();
  when(() => repo.watch(any())).thenAnswer((_) => perfil.stream);

  final container = ProviderContainer(overrides: [
    // Los dos bordes de IO. Todo lo demás —`AuthNotifier`,
    // `userProfileProvider`, `RouterRefreshNotifier`— es el de producción.
    authStateChangesProvider.overrideWith((ref) => auth.stream),
    userRepositoryProvider.overrideWithValue(repo),
    sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
    trainerLinksStreamProvider
        .overrideWith((ref) => Stream.value(const <TrainerLink>[])),
  ]);
  addTearDown(container.dispose);

  final router = buildCoachHubRouter(
    // El refresh REAL, el mismo de `CoachHubApp`: es el que hace re-evaluar el
    // redirect cuando la sesión o el perfil cambian.
    refreshListenable: container.read(routerRefreshNotifierProvider),
    read: container.read,
    initialUri: initialUri,
  );

  final frames = _Frames(tester.binding);
  addTearDown(frames.detener);

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

  final hub = _Hub(
    tester: tester,
    auth: auth,
    perfil: perfil,
    router: router,
    frames: frames,
  );
  when(() => hub.usuario.uid).thenReturn('pf-1');
  await hub.avanzar();
  return hub;
}

void main() {
  group('teléfono (390×844): la sesión se resuelve sin pasar por el banner',
      () {
    testWidgets(
        'link del mail + PF logueado: carga → planes, nunca «Coach Hub en '
        'escritorio»', (tester) async {
      final hub = await _montar(tester, initialUri: _kLinkDelMail);

      // 1) Sesión cargando: el router se queda en `/dashboard`, y ahí iba el
      //    banner.
      expect(find.byType(CoachHubResolvingView), findsOneWidget);
      expect(find.text('Coach Hub en escritorio'), findsNothing);

      // 2) Llega la sesión; el perfil todavía no.
      hub.auth.add(hub.usuario);
      await hub.avanzar();
      expect(find.byType(CoachHubResolvingView), findsOneWidget);
      expect(find.text('Coach Hub en escritorio'), findsNothing);

      // 3) Llega el perfil: el redirect aterriza en el destino del mail.
      hub.perfil.add(_perfil(UserRole.trainer));
      await hub.avanzar();
      await tester.pumpAndSettle();

      expect(hub.ruta, '/facturacion/planes');
      expect(find.byType(MobileFacturacionShell), findsOneWidget);
      expect(find.byType(PricingScreen), findsOneWidget);
      expect(find.byType(CoachHubResolvingView), findsNothing);
      expect(find.byType(MobileBanner), findsNothing);

      // La secuencia completa: el banner no aparece NUNCA, ni un frame.
      expect(hub.frames.secuencia, ['carga', 'planes']);
    });

    testWidgets(
        'link del mail + SIN sesión: carga → login → planes al loguearse, '
        'nunca «Coach Hub en escritorio»', (tester) async {
      final hub = await _montar(tester, initialUri: _kLinkDelMail);
      expect(find.byType(CoachHubResolvingView), findsOneWidget);

      // Sin sesión: `/login` no cuelga del shell.
      hub.auth.add(null);
      await hub.avanzar();
      expect(hub.ruta, '/login');
      expect(find.byType(CoachHubLoginScreen), findsOneWidget);

      // Se loguea el PF. Mientras carga su perfil sigue en el login.
      hub.auth.add(hub.usuario);
      await hub.avanzar();
      expect(find.byType(CoachHubLoginScreen), findsOneWidget);

      // Y vuelve al destino que trajo el mail: el `?to=` no se perdió en el
      // camino, porque el redirect sólo lo consume cuando hay un PF resuelto.
      hub.perfil.add(_perfil(UserRole.trainer));
      await hub.avanzar();
      await tester.pumpAndSettle();

      expect(hub.ruta, '/facturacion/planes');
      expect(find.byType(PricingScreen), findsOneWidget);
      expect(hub.frames.secuencia, ['carga', 'login', 'planes']);
    });

    testWidgets(
        'sin ?to=: la carga TERMINA aunque la ruta no cambie (/dashboard → '
        '/dashboard) y recién ahí aparece el banner', (tester) async {
      // El caso que un flag calculado en el `pageBuilder` del router no
      // resuelve: un PF sin destino fino se queda en la misma ruta, go_router
      // no reconstruye la página, y el flag quedaba congelado en "resolviendo".
      final hub = await _montar(tester);
      expect(find.byType(CoachHubResolvingView), findsOneWidget);

      hub.auth.add(hub.usuario);
      await hub.avanzar();
      hub.perfil.add(_perfil(UserRole.trainer));
      await hub.avanzar();

      expect(hub.ruta, '/dashboard');
      expect(find.byType(MobileBanner), findsOneWidget);
      expect(find.byType(CoachHubResolvingView), findsNothing);
      expect(hub.frames.secuencia, ['carga', 'banner']);
    });

    testWidgets('un atleta: carga → /not-allowed, sin pasar por el banner',
        (tester) async {
      final hub = await _montar(tester, initialUri: _kLinkDelMail);

      hub.auth.add(hub.usuario);
      await hub.avanzar();
      hub.perfil.add(_perfil(UserRole.athlete));
      await hub.avanzar();

      expect(hub.ruta, '/not-allowed');
      expect(find.byType(CoachHubNotAllowedScreen), findsOneWidget);
      expect(hub.frames.secuencia, ['carga', 'no-autorizado']);
    });
  });

  group('escritorio (1400×900): no cambia', () {
    testWidgets(
        'con la sesión cargando ya se ve el shell, nunca la vista de carga',
        (tester) async {
      final hub = await _montar(
        tester,
        size: const Size(1400, 900),
        initialUri: _kLinkDelMail,
      );

      expect(find.byType(CoachHubSidebar), findsOneWidget);
      expect(find.byType(CoachHubResolvingView), findsNothing);

      hub.auth.add(hub.usuario);
      await hub.avanzar();
      hub.perfil.add(_perfil(UserRole.trainer));
      await hub.avanzar();
      await tester.pumpAndSettle();

      expect(hub.ruta, '/facturacion/planes');
      expect(find.byType(CoachHubSidebar), findsOneWidget);
      expect(find.byType(PricingScreen), findsOneWidget);
      expect(hub.frames.secuencia, ['escritorio']);
    });
  });
}
