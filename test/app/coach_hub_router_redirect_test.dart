import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/coach_hub_router.dart';
import 'package:treino/core/utils/deep_link_destination.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

class _MockUser extends Mock implements User {}

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AsyncValue<User?> _fixedState;

  @override
  Future<User?> build() async {
    state = _fixedState;
    return _fixedState.valueOrNull;
  }
}

class _LoadingAuthNotifier extends AuthNotifier {
  @override
  Future<User?> build() => Completer<User?>().future;
}

UserProfile _trainerProfile() => UserProfile(
      uid: 'test-uid',
      email: 'trainer@example.com',
      displayName: 'Mateo',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

UserProfile _athleteProfile() => UserProfile(
      uid: 'test-uid',
      email: 'athlete@example.com',
      displayName: 'Tincho',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Helper: warms up `userProfileProvider` (StreamProvider) leyendo su
/// future antes de llamar al redirect. Sin esto el provider queda en
/// AsyncLoading y `coachHubRedirect` retorna null defensivamente,
/// haciendo fallar todos los tests con user logueado.
// Envuelve en una caja NUEVA por llamada: cada test de este archivo (salvo
// el grupo "caja compartida" de más abajo, que llama a coachHubRedirect
// directo) quiere una llamada aislada, no una que se apague sola por
// compartir caja con otra.
Future<String?> _call(
  ProviderContainer container,
  String location, {
  DeepLinkDestination? initialDestination,
}) async {
  await container.read(userProfileProvider.future).catchError((_) => null);
  return coachHubRedirect(
    container.read,
    location,
    initialDestination: initialDestination == null
        ? null
        : DeepLinkDestinationBox(initialDestination),
  );
}

ProviderContainer _container({
  required Override authOverride,
  Override? profileOverride,
}) {
  return ProviderContainer(overrides: [
    authOverride,
    profileOverride ??
        userProfileProvider
            .overrideWith((ref) => Stream<UserProfile?>.value(null)),
  ]);
}

void main() {
  group('coachHubRedirect — Etapa 7 bootstrap', () {
    // ── Auth loading ─────────────────────────────────────────────────────────

    test('auth en loading → no redirect (cualquier path)', () async {
      final container = _container(
        authOverride:
            authNotifierProvider.overrideWith(_LoadingAuthNotifier.new),
      );
      addTearDown(container.dispose);

      // Sin warm-up porque cuando auth está en loading, el redirect
      // retorna null antes de tocar el profile provider.
      expect(coachHubRedirect(container.read, '/dashboard'), isNull);
      expect(coachHubRedirect(container.read, '/login'), isNull);
      expect(coachHubRedirect(container.read, '/not-allowed'), isNull);
    });

    // ── Anonymous ────────────────────────────────────────────────────────────

    test('anonymous en /dashboard → redirige a /login', () async {
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(const AsyncData(null)),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/dashboard'), '/login');
    });

    test('anonymous en /not-allowed → redirige a /login', () async {
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(const AsyncData(null)),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/not-allowed'), '/login');
    });

    test('anonymous en /login → no redirect (stay)', () async {
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(const AsyncData(null)),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/login'), isNull);
    });

    // ── Trainer ──────────────────────────────────────────────────────────────

    test('trainer en /login → redirige a /dashboard', () async {
      final user = _MockUser();
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_trainerProfile()),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/login'), '/dashboard');
    });

    test('trainer en /dashboard → no redirect (stay)', () async {
      final user = _MockUser();
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_trainerProfile()),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/dashboard'), isNull);
    });

    test('trainer en /not-allowed → redirige a /dashboard', () async {
      final user = _MockUser();
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_trainerProfile()),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/not-allowed'), '/dashboard');
    });

    // ── Athlete ──────────────────────────────────────────────────────────────

    test('athlete en /dashboard → redirige a /not-allowed', () async {
      final user = _MockUser();
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_athleteProfile()),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/dashboard'), '/not-allowed');
    });

    test('athlete en /login → redirige a /not-allowed', () async {
      final user = _MockUser();
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_athleteProfile()),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/login'), '/not-allowed');
    });

    test('athlete en /not-allowed → no redirect (stay)', () async {
      final user = _MockUser();
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_athleteProfile()),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/not-allowed'), isNull);
    });

    // ── Edge cases ───────────────────────────────────────────────────────────

    test('user autenticado sin profile doc → tratado como not-allowed',
        () async {
      final user = _MockUser();
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        // userProfileProvider default: Stream.value(null)
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/dashboard'), '/not-allowed');
    });

    // ── Section routes (W1.2) ────────────────────────────────────────────────
    // El redirect es agnóstico de la ruta concreta: cualquier path signed-in
    // (no /login, no /not-allowed) se comporta igual que /dashboard. Estos
    // casos lo fijan sobre rutas de sección reales.

    test('trainer en /alumnos → no redirect (stay)', () async {
      final user = _MockUser();
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_trainerProfile()),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/alumnos'), isNull);
    });

    test('anonymous en /alumnos → redirige a /login', () async {
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(const AsyncData(null)),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/alumnos'), '/login');
    });

    test('athlete en /alumnos → redirige a /not-allowed', () async {
      final user = _MockUser();
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_athleteProfile()),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/alumnos'), '/not-allowed');
    });

    test('trainer en /actividad → no redirect (stay)', () async {
      final user = _MockUser();
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_trainerProfile()),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/actividad'), isNull);
    });
  });

  // ── location == '/' — el bug que #923 hizo alcanzable con un click ───────
  //
  // `/abrir/profe` en Vercel redirige a `app.gettreino.com/`, sin ninguna
  // GoRoute propia para `/`. Antes de este fix, un PF YA logueado que
  // aterrizaba ahí no encontraba ni el gate de /login ni el de /not-allowed
  // (ninguno de los dos matchea `/`), `coachHubRedirect` devolvía `null`, y
  // go_router mostraba su pantalla de error generica en vez del dashboard.
  group('coachHubRedirect — la raíz "/" (bug de #923)', () {
    test('trainer en / → redirige a /dashboard, no se queda varado', () async {
      final user = _MockUser();
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_trainerProfile()),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/'), '/dashboard');
    });

    test('anonymous en / → redirige a /login (gate existente, sin cambios)',
        () async {
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(const AsyncData(null)),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/'), '/login');
    });

    test('athlete en / → redirige a /not-allowed, no al dashboard', () async {
      final user = _MockUser();
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_athleteProfile()),
        ),
      );
      addTearDown(container.dispose);

      expect(await _call(container, '/'), '/not-allowed');
    });
  });

  // ── El destino fino que trae un mail ──────────────────────────────────────
  group('coachHubRedirect — destino fino (initialDestination)', () {
    Future<ProviderContainer> trainerContainer() async {
      final user = _MockUser();
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_trainerProfile()),
        ),
      );
      addTearDown(container.dispose);
      return container;
    }

    test('to=facturacion en / → /facturacion/planes', () async {
      final container = await trainerContainer();
      expect(
        await _call(
          container,
          '/',
          initialDestination: const DeepLinkDestination(DeepLinkTo.facturacion),
        ),
        '/facturacion/planes',
      );
    });

    test('to=agenda en / → /agenda', () async {
      final container = await trainerContainer();
      expect(
        await _call(
          container,
          '/',
          initialDestination: const DeepLinkDestination(DeepLinkTo.agenda),
        ),
        '/agenda',
      );
    });

    test('to=solicitudes en / → /invitaciones', () async {
      final container = await trainerContainer();
      expect(
        await _call(
          container,
          '/',
          initialDestination:
              const DeepLinkDestination(DeepLinkTo.solicitudes),
        ),
        '/invitaciones',
      );
    });

    test('to=alumno en / → /alumnos/:id, con el id que trajo', () async {
      final container = await trainerContainer();
      expect(
        await _call(
          container,
          '/',
          initialDestination:
              const DeepLinkDestination(DeepLinkTo.alumno, 'uid-789'),
        ),
        '/alumnos/uid-789',
      );
    });

    // Mismo mecanismo que ya usa el gate de /login y /not-allowed: sirve
    // TAMBIÉN ahí, no solo en '/'.
    test('to=agenda en /login → /agenda, no /dashboard', () async {
      final container = await trainerContainer();
      expect(
        await _call(
          container,
          '/login',
          initialDestination: const DeepLinkDestination(DeepLinkTo.agenda),
        ),
        '/agenda',
      );
    });

    // El caso que importa más: un `to` presente no puede sacar a un PF de
    // una ruta protegida en la que YA está. Si esto fallara, cualquier
    // navegación interna que revalide el redirect (el `refreshListenable`
    // dispara en cada cambio de auth/profile) podría hijackear al usuario
    // de vuelta al destino del mail, sin que haya vuelto a tocar el link.
    test('to=agenda en /alumnos (ruta protegida) → NO redirige', () async {
      final container = await trainerContainer();
      expect(
        await _call(
          container,
          '/alumnos',
          initialDestination: const DeepLinkDestination(DeepLinkTo.agenda),
        ),
        isNull,
      );
    });

    // Un athlete con un `to` en la URL (por ejemplo, reenvió el mail de otro
    // PF, o abrió un link viejo desde una cuenta que cambió de rol) sigue
    // yendo a /not-allowed. El destino fino NUNCA gana sobre el role gate.
    test('to=facturacion + athlete en / → /not-allowed, no /facturacion/planes',
        () async {
      final user = _MockUser();
      final container = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_athleteProfile()),
        ),
      );
      addTearDown(container.dispose);

      expect(
        await _call(
          container,
          '/',
          initialDestination: const DeepLinkDestination(DeepLinkTo.facturacion),
        ),
        '/not-allowed',
      );
    });
  });

  // ── La caja se apaga sola: logout + login en la MISMA pestaña ────────────
  //
  // Encontrado en revisión adversarial. "Salir" (coach_hub_top_bar.dart) es
  // `FirebaseAuth.signOut()` puro, sin reload de página, así que `isPublic`
  // (location=='/login') SÍ vuelve a ser cierto dentro de la misma sesión de
  // router — el comentario original de `coachHubRedirect` decía lo contrario.
  //
  // Estos tests llaman a `coachHubRedirect` DIRECTO, no via `_call` — porque
  // lo que hay que probar es que la MISMA caja, reusada en llamadas
  // sucesivas (tal como la reusa la closure real de `buildCoachHubRouter`,
  // que la construye una sola vez), se apague sola en el primer consult.
  group('coachHubRedirect — la caja se apaga sola (logout + login)', () {
    // El caso completo: logout de verdad (auth pasa a null) y re-login,
    // compartiendo la MISMA caja entre las cuatro llamadas — tal como pasa
    // en la app real, donde `destination` vive en un solo closure para toda
    // la vida de la pestaña.
    test(
        'secuencia completa: destino -> ruta protegida -> logout -> login '
        'de nuevo cae en /dashboard, no en el destino viejo', () async {
      final user = _MockUser();
      final loggedInContainer = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_trainerProfile()),
        ),
      );
      addTearDown(loggedInContainer.dispose);
      await loggedInContainer
          .read(userProfileProvider.future)
          .catchError((_) => null);

      final loggedOutContainer = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(const AsyncData(null)),
        ),
      );
      addTearDown(loggedOutContainer.dispose);

      final box = DeepLinkDestinationBox(
        const DeepLinkDestination(DeepLinkTo.agenda),
      );

      // 1. Llega con el destino del mail.
      expect(
        coachHubRedirect(loggedInContainer.read, '/', initialDestination: box),
        '/agenda',
      );

      // 2. Usa la app normalmente.
      expect(
        coachHubRedirect(
          loggedInContainer.read,
          '/agenda',
          initialDestination: box,
        ),
        isNull,
      );

      // 3. Cierra sesión (simulado con el container deslogueado) — sin
      //    reload, `location` sigue en /agenda un instante hasta que el
      //    gate de anonymous lo manda a /login.
      expect(
        coachHubRedirect(
          loggedOutContainer.read,
          '/agenda',
          initialDestination: box,
        ),
        '/login',
      );

      // 4. Alguien se loguea de nuevo en la MISMA pestaña, reusando la
      //    MISMA caja (tal como pasa en la app real). El punto central del
      //    fix: esto tiene que dar /dashboard, NO /agenda de nuevo.
      expect(
        coachHubRedirect(
          loggedInContainer.read,
          '/login',
          initialDestination: box,
        ),
        '/dashboard',
      );
    });
  });
}
