import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/coach_hub_router.dart';
import 'package:treino/core/utils/deep_link_destination.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/application/email_gate_providers.dart';
import 'package:treino/features/coach_hub/domain/hub_onboarding_stage.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

import '../helpers/coach_hub_profiles.dart';
import '../helpers/mail_test_helpers.dart';

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

UserProfile _trainerProfile() => trainerCompleto();

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
  // El interruptor `app_config/email_gate`. Apagado por defecto: solo los tests
  // del gate del mail lo prenden, y los demás no tocan Firebase para leerlo.
  Stream<bool>? emailGate,
}) {
  return ProviderContainer(overrides: [
    authOverride,
    profileOverride ??
        userProfileProvider
            .overrideWith((ref) => Stream<UserProfile?>.value(null)),
    emailGateEnabledProvider
        .overrideWith((ref) => emailGate ?? Stream<bool>.value(false)),
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

    // El push de vinculación manda UN SOLO `deepLink` a las dos superficies.
    // En mobile `/home/notifications` es una ruta real; acá no existe NINGUNA
    // ruta bajo `/home`, así que sin esta traducción el PF que toca la
    // notificación con el Hub abierto cae en la pantalla de error de go_router.
    test('trainer en /home/notifications → traduce a /invitaciones', () async {
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

      expect(await _call(container, '/home/notifications'), '/invitaciones');
    });

    // Control negativo: la traducción es de UNA ruta, no de todo `/home`.
    // Sin esto, un `startsWith('/home')` demasiado goloso pasaría igual y se
    // llevaría puesto cualquier path futuro bajo ese prefijo.
    test('trainer en otra ruta /home/* → NO la traduce', () async {
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

      expect(await _call(container, '/home/profile/u1'), isNull);
    });

    // Un atleta que llega al Hub sigue cayendo en /not-allowed: la traducción
    // vive DESPUÉS del gate de rol, no antes.
    test('atleta en /home/notifications → /not-allowed, no /invitaciones',
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

      expect(await _call(container, '/home/notifications'), '/not-allowed');
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
          initialDestination: const DeepLinkDestination(DeepLinkTo.solicitudes),
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

    // EL CASO REAL, y el que estuvo roto desde siempre.
    //
    // Bajo hash routing —que es lo que usa el Coach Hub— una URL externa como
    // `app.gettreino.com/?to=X` llega con el FRAGMENTO vacío, así que
    // go_router no arranca en `/` sino en su `initialLocation`. Un PF CON
    // SESIÓN aterriza ahí, no en `/` ni en `/login`, y el destino fino nunca
    // se aplicaba: terminaba en el dashboard.
    //
    // Los tests de este grupo usaban todos `location: '/'`, que es la landing
    // del que llega DESLOGUEADO. Por eso el bug pasó: se probaba el único
    // camino donde no aparece.
    test('to=facturacion en la LANDING real (/dashboard) → /facturacion/planes',
        () async {
      final container = await trainerContainer();
      expect(
        await _call(
          container,
          kCoachHubInitialLocation,
          initialDestination: const DeepLinkDestination(DeepLinkTo.facturacion),
        ),
        '/facturacion/planes',
      );
    });

    // El complemento: sin destino, la landing NO se auto-redirige a sí misma.
    test('sin destino, en la landing → null, no un redirect a sí misma',
        () async {
      final container = await trainerContainer();
      expect(await _call(container, kCoachHubInitialLocation), isNull);
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

  // ── Gate del mail confirmado con código (VerifyMailScreen) ───────────────
  //
  // Misma regla que la app móvil (`authRedirect`), pero el Hub tiene una
  // restricción extra: el `?to=` del mail vive en una caja que el bloque de
  // aterrizajes CONSUME. El gate tiene que correr antes, o el PF que confirma
  // el mail pierde el destino.
  group('coachHubRedirect — gate del mail confirmado con código', () {
    const email = 'trainer@example.com';

    UserProfile verificado() => _trainerProfile().copyWith(
          emailVerification: mailConfirmadoPara(UserRole.trainer, email),
        );

    // Alumno verificado al que el equipo promovió a entrenador: solo tiene la
    // entrada de ALUMNO, y el mail que le llega ahora es el del entrenador.
    UserProfile promovido() => _trainerProfile().copyWith(
          emailVerification: mailConfirmadoPara(UserRole.athlete, email),
        );

    // El mail de Auth tiene que ser el del perfil: sin mail en Auth el gate no
    // corre, y no es lo que se mide.
    ProviderContainer armar(
      UserProfile profile, {
      Stream<bool>? interruptor,
    }) {
      final user = _MockUser();
      when(() => user.email).thenReturn(email);
      final c = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(profile),
        ),
        emailGate: interruptor ?? Stream<bool>.value(true),
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<ProviderContainer> listo(
      UserProfile profile, {
      bool interruptor = true,
    }) async {
      final c = armar(profile, interruptor: Stream<bool>.value(interruptor));
      await c.read(userProfileProvider.future);
      await c.read(emailGateEnabledProvider.future);
      return c;
    }

    DeepLinkDestinationBox cajaFacturacion() => DeepLinkDestinationBox(
          const DeepLinkDestination(DeepLinkTo.facturacion),
        );

    // Sigue los redirects como go_router: aplica el resultado y vuelve a
    // preguntar sobre la ubicación nueva, hasta que contesta `null`.
    List<String> cadena(
      ProviderContainer c,
      String desde,
      DeepLinkDestinationBox box,
    ) {
      final visitadas = [desde];
      for (var i = 0; i < 5; i++) {
        final siguiente = coachHubRedirect(
          c.read,
          visitadas.last,
          initialDestination: box,
        );
        if (siguiente == null) return visitadas;
        visitadas.add(siguiente);
      }
      fail('redirect sin punto fijo: $visitadas');
    }

    test('PF sin el mail confirmado → /verificar-mail, desde cualquier ruta',
        () async {
      final c = await listo(_trainerProfile());
      // `/login` incluida: un PF que se acaba de loguear va al gate ANTES del
      // bloque de aterrizajes, no después.
      for (final ruta in ['/dashboard', '/alumnos', '/login', '/', '/agenda']) {
        expect(await _call(c, ruta), '/verificar-mail', reason: ruta);
      }
    });

    test('con el interruptor APAGADO el gate no existe', () async {
      final c = await listo(_trainerProfile(), interruptor: false);
      expect(await _call(c, '/dashboard'), isNull);
      expect(await _call(c, '/login'), '/dashboard');
    });

    test('apagar el interruptor SACA de la pantalla a quien está en ella',
        () async {
      final c = await listo(_trainerProfile(), interruptor: false);
      expect(await _call(c, '/verificar-mail'), '/dashboard');
    });

    test('alumno promovido a PF (solo la entrada de alumno) → /verificar-mail',
        () async {
      final c = await listo(promovido());
      expect(await _call(c, '/dashboard'), '/verificar-mail');
    });

    test('en la pantalla y sin confirmar, se queda', () async {
      final c = await listo(_trainerProfile());
      expect(await _call(c, '/verificar-mail'), isNull);
    });

    test('PF con el mail confirmado: el gate no dispara', () async {
      final c = await listo(verificado());
      expect(await _call(c, '/dashboard'), isNull);
    });

    test('PF confirmado parado en la pantalla → /dashboard', () async {
      // ENTRADA y SALIDA contra la misma condición: sin la salida, el PF se
      // queda mirando la pantalla con el mail ya confirmado.
      final c = await listo(verificado());
      expect(await _call(c, '/verificar-mail'), '/dashboard');
    });

    test('el alumno sigue yendo a /not-allowed: el gate no es suyo', () async {
      final user = _MockUser();
      when(() => user.email).thenReturn('athlete@example.com');
      final c = _container(
        authOverride: authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(user)),
        ),
        profileOverride: userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_athleteProfile()),
        ),
        emailGate: Stream<bool>.value(true),
      );
      addTearDown(c.dispose);
      await c.read(emailGateEnabledProvider.future);

      // Sin mail confirmado y con el gate prendido: el rol va primero.
      expect(await _call(c, '/dashboard'), '/not-allowed');
      expect(await _call(c, '/verificar-mail'), '/not-allowed');
      expect(await _call(c, '/not-allowed'), isNull);
    });

    test('va ANTES de traducir /home/notifications', () async {
      final c = await listo(_trainerProfile());
      expect(await _call(c, '/home/notifications'), '/verificar-mail');
    });

    // EL FLUJO QUE IMPORTA: el mail trae `?to=facturacion`, el PF todavía no
    // confirmó, confirma, y tiene que terminar en `/facturacion/planes`.
    group('el destino del mail sobrevive a la confirmación', () {
      test('sin confirmar: va al gate y la caja NO se toca', () async {
        final box = cajaFacturacion();
        final c = await listo(_trainerProfile());

        expect(cadena(c, kCoachHubInitialLocation, box), [
          kCoachHubInitialLocation,
          '/verificar-mail',
        ]);
        expect(box.value?.to, DeepLinkTo.facturacion);

        // El `refreshListenable` revalida el redirect con cada cambio de
        // perfil o de interruptor: el PF puede tardar minutos en la pantalla.
        for (var i = 0; i < 3; i++) {
          expect(
            coachHubRedirect(
              c.read,
              '/verificar-mail',
              initialDestination: box,
            ),
            isNull,
          );
        }
        expect(box.value?.to, DeepLinkTo.facturacion);
      });

      test('al confirmar: sale a la landing y de ahí a /facturacion/planes',
          () async {
        final box = cajaFacturacion();
        final sinConfirmar = await listo(_trainerProfile());
        cadena(sinConfirmar, kCoachHubInitialLocation, box);

        // Llega el perfil con la marca (la escribe el servidor).
        final confirmado = await listo(verificado());
        expect(cadena(confirmado, '/verificar-mail', box), [
          '/verificar-mail',
          kCoachHubInitialLocation, // la salida es una ruta de ATERRIZAJE…
          '/facturacion/planes', // …y por eso la pasada siguiente usa la caja.
        ]);
        expect(box.value, isNull);
      });

      test(
          'el interruptor todavía cargando NO gasta la caja del PF sin '
          'confirmar', () async {
        // El perfil y el interruptor llegan por separado: si el perfil llega
        // primero, el aterrizaje no puede consumir el destino antes de saber
        // si el gate está prendido.
        final interruptor = StreamController<bool>();
        addTearDown(interruptor.close);
        final box = cajaFacturacion();
        final c = armar(_trainerProfile(), interruptor: interruptor.stream);

        // Sin respuesta del interruptor: no hay gate (falla abierto), el PF
        // sigue a la landing, pero el destino queda guardado.
        expect(c.read(emailGateEnabledProvider).isLoading, isTrue);
        await c.read(userProfileProvider.future);
        expect(cadena(c, '/login', box), ['/login', kCoachHubInitialLocation]);
        expect(box.value?.to, DeepLinkTo.facturacion);

        // Llega el interruptor prendido: ahora sí, al gate, con la caja intacta.
        interruptor.add(true);
        await c.read(emailGateEnabledProvider.future);
        expect(cadena(c, kCoachHubInitialLocation, box), [
          kCoachHubInitialLocation,
          '/verificar-mail',
        ]);
        expect(box.value?.to, DeepLinkTo.facturacion);
      });

      test(
          'el interruptor que resuelve en APAGADO suelta la caja: el PF sin '
          'confirmar cae en el destino del mail', () async {
        // La otra mitad de la espera: guardar el destino no puede ser para
        // siempre. Si el interruptor llega en `false` no hay gate, y el mismo
        // bloque de aterrizajes tiene que consumir lo que quedó guardado.
        final interruptor = StreamController<bool>();
        addTearDown(interruptor.close);
        final box = cajaFacturacion();
        final c = armar(_trainerProfile(), interruptor: interruptor.stream);
        await c.read(userProfileProvider.future);

        // Cargando: a la landing, con la caja todavía en poder del router.
        expect(c.read(emailGateEnabledProvider).isLoading, isTrue);
        expect(cadena(c, '/login', box), ['/login', kCoachHubInitialLocation]);
        expect(box.value?.to, DeepLinkTo.facturacion);

        // Llega el interruptor en `false`: la revalidación sobre la landing
        // consume la caja y va al destino del mail, sin pasar por el gate.
        interruptor.add(false);
        expect(await c.read(emailGateEnabledProvider.future), isFalse);
        expect(cadena(c, kCoachHubInitialLocation, box), [
          kCoachHubInitialLocation,
          '/facturacion/planes',
        ]);
        expect(box.value, isNull);
      });

      test('interruptor cargando y mail ya confirmado: la caja se usa de una',
          () async {
        // Para el PF confirmado da igual lo que diga el interruptor: no hay
        // motivo para demorarle el destino.
        final interruptor = StreamController<bool>();
        addTearDown(interruptor.close);
        final box = cajaFacturacion();
        final c = armar(verificado(), interruptor: interruptor.stream);
        await c.read(userProfileProvider.future);

        expect(c.read(emailGateEnabledProvider).isLoading, isTrue);
        expect(cadena(c, kCoachHubInitialLocation, box), [
          kCoachHubInitialLocation,
          '/facturacion/planes',
        ]);
        expect(box.value, isNull);
      });
    });
  });

  // ── Gate del onboarding del PF promovido (#1331) ───────────────────────────
  group('coachHubRedirect — gate del onboarding (/completar-perfil)', () {
    const email = 'trainer@example.com';

    // Un PF por etapa. Se verifica contra el predicado para que el fixture no
    // mienta sobre la etapa que dice tener.
    UserProfile conEtapa(HubOnboardingStage etapa) {
      final p = switch (etapa) {
        HubOnboardingStage.age => trainerRecienPromovido(),
        HubOnboardingStage.identity =>
          trainerCompleto().copyWith(displayName: '   '),
        HubOnboardingStage.pf => UserProfile(
            uid: 'test-uid',
            email: email,
            displayName: 'Mateo',
            role: UserRole.trainer,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
            bornAt: DateTime.utc(1990, 1, 1),
          ),
        HubOnboardingStage.done => trainerCompleto(),
      };
      expect(hubOnboardingStage(p), etapa, reason: 'fixture de la etapa');
      return p;
    }

    ProviderContainer armar(
      UserProfile? profile, {
      Stream<bool>? pendiente,
      Stream<bool>? interruptor,
      bool conUsuario = true,
    }) {
      final user = _MockUser();
      when(() => user.email).thenReturn(email);
      final c = ProviderContainer(overrides: [
        authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(conUsuario ? user : null)),
        ),
        userProfileProvider
            .overrideWith((ref) => Stream<UserProfile?>.value(profile)),
        emailGateEnabledProvider
            .overrideWith((ref) => interruptor ?? Stream<bool>.value(false)),
        userProfileHasPendingWritesProvider
            .overrideWith((ref) => pendiente ?? Stream<bool>.value(false)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    // Deja el perfil, el interruptor y (si emite) el pendiente ya resueltos.
    Future<ProviderContainer> listo(
      UserProfile? profile, {
      Stream<bool>? pendiente,
      Stream<bool>? interruptor,
      bool esperarPendiente = true,
    }) async {
      final c = armar(profile, pendiente: pendiente, interruptor: interruptor);
      await c.read(userProfileProvider.future);
      await c.read(emailGateEnabledProvider.future);
      if (esperarPendiente) {
        await c
            .read(userProfileHasPendingWritesProvider.future)
            .catchError((_) => false);
      }
      return c;
    }

    List<String> cadena(
      ProviderContainer c,
      String desde, {
      DeepLinkDestinationBox? box,
    }) {
      final visitadas = [desde];
      for (var i = 0; i < 5; i++) {
        final siguiente = coachHubRedirect(
          c.read,
          visitadas.last,
          initialDestination: box,
        );
        if (siguiente == null) return visitadas;
        visitadas.add(siguiente);
      }
      fail('redirect sin punto fijo: $visitadas');
    }

    const incompletas = [
      HubOnboardingStage.age,
      HubOnboardingStage.identity,
      HubOnboardingStage.pf,
    ];

    test(
        'SCENARIO-007: entrada por etapa desde /login, /dashboard y una ruta '
        'profunda', () async {
      for (final etapa in incompletas) {
        final c = await listo(conEtapa(etapa));
        for (final ruta in ['/login', '/dashboard', '/alumnos/abc', '/']) {
          expect(
            coachHubRedirect(c.read, ruta),
            kCoachHubOnboardingRoute,
            reason: '$etapa desde $ruta',
          );
        }
        expect(
          coachHubRedirect(c.read, kCoachHubOnboardingRoute),
          isNull,
          reason: '$etapa: el gate no se redirige a sí mismo',
        );
      }
    });

    test(
        'SCENARIO-008: etapa done y sin escritura pendiente en el gate → '
        '/dashboard', () async {
      final c = await listo(conEtapa(HubOnboardingStage.done));
      expect(
        coachHubRedirect(c.read, kCoachHubOnboardingRoute),
        kCoachHubInitialLocation,
      );
    });

    test('SCENARIO-009: cambiar de etapa dentro del gate no navega', () async {
      final perfil = StreamController<UserProfile?>();
      addTearDown(perfil.close);
      final user = _MockUser();
      when(() => user.email).thenReturn(email);
      final c = ProviderContainer(overrides: [
        authNotifierProvider
            .overrideWith(() => _StubAuthNotifier(AsyncData(user))),
        userProfileProvider.overrideWith((ref) => perfil.stream),
        emailGateEnabledProvider.overrideWith((ref) => Stream.value(false)),
        userProfileHasPendingWritesProvider
            .overrideWith((ref) => Stream.value(false)),
      ]);
      addTearDown(c.dispose);
      c.listen(userProfileProvider, (_, __) {});

      for (final etapa in incompletas) {
        perfil.add(conEtapa(etapa));
        await Future<void>.delayed(Duration.zero);
        expect(
          coachHubRedirect(c.read, kCoachHubOnboardingRoute),
          isNull,
          reason: 'etapa $etapa dentro del gate',
        );
      }
    });

    test(
        'SCENARIO-010: barrido etapas × pendiente × rutas llega a punto fijo '
        'en ≤ 2 saltos', () async {
      const rutas = [
        '/login',
        '/',
        '/dashboard',
        '/agenda',
        '/alumnos',
        '/alumnos/abc',
        '/pagos',
        '/ajustes',
        '/facturacion/planes',
        '/home/notifications',
        '/not-allowed',
        '/verificar-mail',
        kCoachHubOnboardingRoute,
      ];
      final pendientes = <String, Stream<bool> Function()>{
        'cargando': () => StreamController<bool>().stream,
        'true': () => Stream<bool>.value(true),
        'false': () => Stream<bool>.value(false),
        'error': () => Stream<bool>.error(StateError('stream roto')),
      };
      for (final etapa in HubOnboardingStage.values) {
        for (final p in pendientes.entries) {
          final c = await listo(
            conEtapa(etapa),
            pendiente: p.value(),
            esperarPendiente: p.key != 'cargando',
          );
          for (final ruta in rutas) {
            final saltos = cadena(c, ruta).length - 1;
            expect(
              saltos,
              lessThanOrEqualTo(2),
              reason: '$etapa / pendiente ${p.key} / $ruta',
            );
          }
        }
      }
    });

    test('SCENARIO-011: el rol gana al onboarding (atleta y sin doc)',
        () async {
      final atleta = await listo(_athleteProfile());
      final sinDoc = await listo(null);
      for (final c in [atleta, sinDoc]) {
        for (final ruta in ['/dashboard', '/login', kCoachHubOnboardingRoute]) {
          expect(
            coachHubRedirect(c.read, ruta),
            '/not-allowed',
            reason: ruta,
          );
        }
        expect(coachHubRedirect(c.read, '/not-allowed'), isNull);
      }
    });

    test(
        'SCENARIO-012: el mail gana al onboarding, y al confirmarlo sigue el '
        'onboarding', () async {
      final sinConfirmar = await listo(
        conEtapa(HubOnboardingStage.age),
        interruptor: Stream<bool>.value(true),
      );
      expect(
          coachHubRedirect(sinConfirmar.read, '/dashboard'), '/verificar-mail');
      expect(coachHubRedirect(sinConfirmar.read, kCoachHubOnboardingRoute),
          '/verificar-mail');

      final confirmado = await listo(
        conEtapa(HubOnboardingStage.age).copyWith(
          emailVerification: mailConfirmadoPara(UserRole.trainer, email),
        ),
        interruptor: Stream<bool>.value(true),
      );
      expect(coachHubRedirect(confirmado.read, '/dashboard'),
          kCoachHubOnboardingRoute);
    });

    test('SCENARIO-013: ?to= sobrevive al onboarding y se usa recién al salir',
        () async {
      final box = DeepLinkDestinationBox(
        const DeepLinkDestination(DeepLinkTo.facturacion),
      );
      final enCurso = await listo(conEtapa(HubOnboardingStage.age));
      expect(cadena(enCurso, kCoachHubInitialLocation, box: box),
          [kCoachHubInitialLocation, kCoachHubOnboardingRoute]);
      expect(cadena(enCurso, '/login', box: box),
          ['/login', kCoachHubOnboardingRoute]);
      for (var i = 0; i < 3; i++) {
        expect(
          coachHubRedirect(enCurso.read, kCoachHubOnboardingRoute,
              initialDestination: box),
          isNull,
        );
      }
      expect(box.value?.to, DeepLinkTo.facturacion, reason: 'caja intacta');

      final terminado = await listo(conEtapa(HubOnboardingStage.done));
      expect(cadena(terminado, kCoachHubOnboardingRoute, box: box), [
        kCoachHubOnboardingRoute,
        kCoachHubInitialLocation,
        '/facturacion/planes',
      ]);
      expect(box.value, isNull);
    });

    test('SCENARIO-014: trainer completo no ve el gate', () async {
      final c = await listo(conEtapa(HubOnboardingStage.done));
      for (final ruta in ['/dashboard', '/agenda', '/pagos', '/ajustes']) {
        expect(coachHubRedirect(c.read, ruta), isNull, reason: ruta);
      }
      expect(coachHubRedirect(c.read, '/login'), kCoachHubInitialLocation);
    });

    test('SCENARIO-015: sin sesión → /login, nunca el gate', () async {
      final c = armar(null, conUsuario: false);
      await c.read(userProfileProvider.future);
      for (final ruta in ['/dashboard', kCoachHubOnboardingRoute]) {
        expect(coachHubRedirect(c.read, ruta), '/login', reason: ruta);
      }
    });

    test('SCENARIO-016: perfil cargando no redirige', () async {
      final user = _MockUser();
      when(() => user.email).thenReturn(email);
      final c = ProviderContainer(overrides: [
        authNotifierProvider
            .overrideWith(() => _StubAuthNotifier(AsyncData(user))),
        userProfileProvider
            .overrideWith((ref) => StreamController<UserProfile?>().stream),
        emailGateEnabledProvider.overrideWith((ref) => Stream.value(false)),
      ]);
      addTearDown(c.dispose);
      c.listen(userProfileProvider, (_, __) {});
      for (final ruta in ['/dashboard', '/login', kCoachHubOnboardingRoute]) {
        expect(coachHubRedirect(c.read, ruta), isNull, reason: ruta);
      }
    });

    test('SCENARIO-017: auth cargando no redirige', () {
      final c = ProviderContainer(overrides: [
        authNotifierProvider.overrideWith(_LoadingAuthNotifier.new),
      ]);
      addTearDown(c.dispose);
      for (final ruta in ['/dashboard', '/login', kCoachHubOnboardingRoute]) {
        expect(coachHubRedirect(c.read, ruta), isNull, reason: ruta);
      }
    });

    group('SCENARIO-019: la salida espera la escritura confirmada', () {
      test('pendiente cargando → se queda', () async {
        final c = await listo(
          conEtapa(HubOnboardingStage.done),
          pendiente: StreamController<bool>().stream,
          esperarPendiente: false,
        );
        expect(c.read(userProfileHasPendingWritesProvider).isLoading, isTrue);
        expect(coachHubRedirect(c.read, kCoachHubOnboardingRoute), isNull);
      });

      test('pendiente true → se queda', () async {
        final c = await listo(
          conEtapa(HubOnboardingStage.done),
          pendiente: Stream<bool>.value(true),
        );
        expect(coachHubRedirect(c.read, kCoachHubOnboardingRoute), isNull);
      });

      test('pendiente false → sale', () async {
        final c = await listo(
          conEtapa(HubOnboardingStage.done),
          pendiente: Stream<bool>.value(false),
        );
        expect(coachHubRedirect(c.read, kCoachHubOnboardingRoute),
            kCoachHubInitialLocation);
      });

      test('el stream de pendientes con error falla abierto', () async {
        final c = await listo(
          conEtapa(HubOnboardingStage.done),
          pendiente: Stream<bool>.error(StateError('stream roto')),
        );
        expect(c.read(userProfileHasPendingWritesProvider).hasError, isTrue);
        expect(coachHubRedirect(c.read, kCoachHubOnboardingRoute),
            kCoachHubInitialLocation);
      });

      test('un trainer completo FUERA del gate no mira el pendiente', () async {
        final c = await listo(
          conEtapa(HubOnboardingStage.done),
          pendiente: Stream<bool>.value(true),
        );
        expect(coachHubRedirect(c.read, '/dashboard'), isNull);
        expect(coachHubRedirect(c.read, '/agenda'), isNull);
      });
    });
  });
}
