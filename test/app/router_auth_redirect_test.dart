import 'dart:async' show StreamController;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart' show GoRoute, RouteBase;
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/router.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/application/email_gate_providers.dart';
import 'package:treino/features/profile/application/account_deletion_notifier.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import '../helpers/mail_test_helpers.dart';

/// Fecha de nacimiento de un adulto.
///
/// Desde el gate de edad mínima, un perfil "completo" incluye `bornAt`: sin él
/// `authRedirect` manda a `/birth-date`, que es exactamente lo que le pasa a
/// una cuenta creada antes del requisito.
final _adultBornAt = DateTime.utc(1990, 5, 20);

class MockUser extends Mock implements User {}

/// Helper — calls authRedirect with the given container and location.
String? callRedirect(ProviderContainer container, String location) {
  return authRedirect(container.read, location);
}

// ---------------------------------------------------------------------------
// Stub auth notifiers
// ---------------------------------------------------------------------------

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AsyncValue<User?> _fixedState;

  @override
  Future<User?> build() async {
    state = _fixedState;
    return _fixedState.valueOrNull;
  }
}

// ---------------------------------------------------------------------------
// Profile fixtures
// ---------------------------------------------------------------------------

final DateTime _kDate = DateTime.utc(2026, 1, 1);

UserProfile _athleteProfile() => UserProfile(
      uid: 'athlete-uid',
      email: 'athlete@example.com',
      displayName: 'sporty',
      bornAt: _adultBornAt,
      emailVerification:
          mailConfirmadoPara(UserRole.athlete, 'athlete@example.com'),
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

UserProfile _trainerIncomplete() => UserProfile(
      uid: 'trainer-uid',
      email: 'trainer@example.com',
      displayName: 'pf-mauro',
      bornAt: _adultBornAt,
      emailVerification:
          mailConfirmadoPara(UserRole.trainer, 'trainer@example.com'),
      role: UserRole.trainer,
      createdAt: _kDate,
      updatedAt: _kDate,
      trainerBio: null, // incomplete — bio missing
    );

UserProfile _trainerComplete() => UserProfile(
      uid: 'trainer-uid',
      email: 'trainer@example.com',
      displayName: 'pf-mauro',
      bornAt: _adultBornAt,
      emailVerification:
          mailConfirmadoPara(UserRole.trainer, 'trainer@example.com'),
      role: UserRole.trainer,
      createdAt: _kDate,
      updatedAt: _kDate,
      trainerBio: 'bio text',
      trainerSpecialty: 'crossfit',
      trainerMonthlyRate: 50000,
      trainerLocations: const [],
      trainerOffersOnline: true,
    );

/// Cuenta creada ANTES del requisito de edad: tiene displayName (pasó
/// ProfileSetup en su momento) y NO tiene bornAt. Es el caso exacto que existe
/// para cubrir el gate — toda la base de usuarios el día del deploy.
UserProfile _athletePreAgeGate() => UserProfile(
      uid: 'athlete-uid',
      email: 'athlete@example.com',
      displayName: 'sporty',
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

/// Cuenta con una fecha POR DEBAJO del piso ya persistida. No es hipotética:
/// `bornAt` existía como campo opcional editable desde el perfil antes de que
/// hubiera edad mínima.
UserProfile _athleteUnderMinAge() => UserProfile(
      uid: 'athlete-uid',
      email: 'athlete@example.com',
      displayName: 'sporty',
      bornAt: DateTime.utc(DateTime.now().year - 10, 1, 1),
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

/// PF con el perfil comercial incompleto Y sin fecha. Fija el ORDEN de los dos
/// gates: el legal primero.
UserProfile _trainerIncompletePreAgeGate() => UserProfile(
      uid: 'trainer-uid',
      email: 'trainer@example.com',
      displayName: 'pf-mauro',
      role: UserRole.trainer,
      createdAt: _kDate,
      updatedAt: _kDate,
      trainerBio: null,
    );

UserProfile _trainerNoDisplayName() => UserProfile(
      uid: 'trainer-uid',
      email: 'trainer@example.com',
      displayName: null, // profile-setup not done
      role: UserRole.trainer,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

// ---------------------------------------------------------------------------
// Container factories
// ---------------------------------------------------------------------------

ProviderContainer _anonContainer() => ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(const AsyncData(null)),
        ),
        emailGateEnabledProvider
            .overrideWith((ref) => Stream<bool>.value(false)),
        userProfileProvider
            .overrideWith((ref) => Stream<UserProfile?>.value(null)),
      ],
    );

ProviderContainer _loggedInContainer({
  required UserProfile profile,
  bool deletionInFlight = false,
  bool pendingWrites = false,
  String? authEmail,
  // El interruptor `app_config/email_gate`. Apagado por defecto: solo los tests
  // del gate del mail lo prenden, y los demás no tocan Firebase para leerlo.
  Stream<bool>? emailGate,
}) {
  final mockUser = MockUser();
  when(() => mockUser.email).thenReturn(authEmail);
  return ProviderContainer(
    overrides: [
      authNotifierProvider.overrideWith(
        () => _StubAuthNotifier(AsyncData(mockUser)),
      ),
      emailGateEnabledProvider
          .overrideWith((ref) => emailGate ?? Stream<bool>.value(false)),
      userProfileProvider.overrideWith(
        (ref) => Stream<UserProfile?>.value(profile),
      ),
      userProfileHasPendingWritesProvider.overrideWith(
        (ref) => Stream<bool>.value(pendingWrites),
      ),
      accountDeletionInFlightProvider.overrideWith((ref) => deletionInFlight),
    ],
  );
}

// ---------------------------------------------------------------------------
// Rutas exclusivas del PF (#1743)
// ---------------------------------------------------------------------------

/// Plantilla de la ruta → una URL concreta que la matchea. Son las pantallas
/// que SÓLO existen para el PF.
const _rutasSoloDelPF = <String, String>{
  '/coach/actividad': '/coach/actividad',
  '/coach/athlete/:athleteId': '/coach/athlete/ath-1',
  '/coach/athlete/:athleteId/plan/:routineId': '/coach/athlete/ath-1/plan/r-1',
  '/coach/athlete/:athleteId/historial': '/coach/athlete/ath-1/historial',
  '/coach/athlete/:athleteId/nutricion': '/coach/athlete/ath-1/nutricion',
  '/coach/athlete/:athleteId/session/:sessionId':
      '/coach/athlete/ath-1/session/s-1',
  '/coach/athlete/:athleteId/plan/:routineId/exercise/:exerciseId':
      '/coach/athlete/ath-1/plan/r-1/exercise/e-1',
  '/coach/availability-editor': '/coach/availability-editor',
  '/profile/availability-editor': '/profile/availability-editor',
  '/profile/edit-trainer': '/profile/edit-trainer',
  '/profile/trainer-preview/:uid': '/profile/trainer-preview/pf-1',
  '/workout/routine-editor/:athleteId': '/workout/routine-editor/ath-1',
  '/workout/import-pdf/:athleteId': '/workout/import-pdf/ath-1',
  '/workout/import-pdf/:athleteId/preview': '/workout/import-pdf/ath-1/preview',
  '/workout/template-editor': '/workout/template-editor',
  '/facturacion/planes': '/facturacion/planes',
};

/// Rutas que el alumno SÍ usa y que cuelgan de los mismos prefijos
/// (`/coach/...`, `/workout/...`, `/profile/...`): el gate no puede tocarlas.
const _rutasDelAlumno = <String>[
  '/home',
  '/coach',
  '/coach?tab=agenda',
  '/coach/agenda',
  '/coach/agenda?trainerId=pf-1',
  '/coach/nutricion',
  '/coach/archivos',
  '/coach/chat/c-1?other=pf-1',
  '/coach/trainer/pf-1',
  '/workout',
  '/workout/my-routine-editor',
  '/workout/customize-routine/r-1',
  '/profile',
  '/profile/edit-personal',
  '/feed/messages',
];

/// Path completo de cada ruta registrada, con el del padre pegado adelante.
Iterable<String> _fullPaths(List<RouteBase> routes,
    [String parent = '']) sync* {
  for (final r in routes) {
    if (r is GoRoute) {
      final full = r.path.startsWith('/') ? r.path : '$parent/${r.path}';
      yield full;
      yield* _fullPaths(r.routes, full);
    } else {
      yield* _fullPaths(r.routes, parent);
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('authRedirect — trainer-incomplete gate (ADR-TPO-003)', () {
    test(
      'SCENARIO-701: incomplete trainer + /home → /profile/edit-trainer?mode=onboarding',
      () async {
        final c = _loggedInContainer(profile: _trainerIncomplete());
        addTearDown(c.dispose);
        await c.read(authNotifierProvider.future);
        await c.read(userProfileProvider.future);
        expect(
          callRedirect(c, '/home'),
          equals('/profile/edit-trainer?mode=onboarding'),
        );
      },
    );

    test(
      'SCENARIO-702: complete trainer + /home → null (no redirect)',
      () async {
        final c = _loggedInContainer(profile: _trainerComplete());
        addTearDown(c.dispose);
        await c.read(authNotifierProvider.future);
        await c.read(userProfileProvider.future);
        expect(callRedirect(c, '/home'), isNull);
      },
    );

    test(
      'SCENARIO-703: incomplete trainer + /profile/edit-trainer → null '
      '(loop guard — startsWith)',
      () async {
        final c = _loggedInContainer(profile: _trainerIncomplete());
        addTearDown(c.dispose);
        await c.read(authNotifierProvider.future);
        await c.read(userProfileProvider.future);
        expect(callRedirect(c, '/profile/edit-trainer'), isNull);
      },
    );

    test(
      'SCENARIO-703 (query param): incomplete trainer + '
      '/profile/edit-trainer?mode=onboarding → null (loop guard)',
      () async {
        final c = _loggedInContainer(profile: _trainerIncomplete());
        addTearDown(c.dispose);
        await c.read(authNotifierProvider.future);
        await c.read(userProfileProvider.future);
        expect(
          callRedirect(c, '/profile/edit-trainer?mode=onboarding'),
          isNull,
        );
      },
    );

    test(
      'SCENARIO-704: athlete + /home → null (trainer gate does not fire for athletes)',
      () async {
        final c = _loggedInContainer(profile: _athleteProfile());
        addTearDown(c.dispose);
        await c.read(authNotifierProvider.future);
        await c.read(userProfileProvider.future);
        expect(callRedirect(c, '/home'), isNull);
      },
    );

    test(
      'SCENARIO-705: unauthenticated + /home → /welcome',
      () async {
        final c = _anonContainer();
        addTearDown(c.dispose);
        await c.read(authNotifierProvider.future);
        expect(callRedirect(c, '/home'), equals('/welcome'));
      },
    );

    test(
      'SCENARIO-706: trainer with displayName=null + /home → /profile-setup '
      '(NOT trainer gate — displayName check fires first)',
      () async {
        final c = _loggedInContainer(profile: _trainerNoDisplayName());
        addTearDown(c.dispose);
        await c.read(authNotifierProvider.future);
        await c.read(userProfileProvider.future);
        expect(callRedirect(c, '/home'), equals('/profile-setup'));
      },
    );

    test(
      'SCENARIO-707: deletion in-flight + incomplete trainer → null '
      '(account-deletion gate fires before trainer gate)',
      () async {
        final c = _loggedInContainer(
          profile: _trainerIncomplete(),
          deletionInFlight: true,
        );
        addTearDown(c.dispose);
        await c.read(authNotifierProvider.future);
        await c.read(userProfileProvider.future);
        expect(callRedirect(c, '/home'), isNull);
      },
    );

    test(
      'SCENARIO-708: public route + incomplete trainer → null '
      '(trainer gate does NOT fire on public routes)',
      () async {
        // Per ADR-TPO-003, the new branch is inside the loggedIn && !isProfileSetup
        // block. The isPublic branch fires AFTER. But the trainer gate is BEFORE
        // the public→/home redirect. Verify that an incomplete trainer on /login
        // is NOT sent to onboarding (public route stays accessible).
        final c = _loggedInContainer(profile: _trainerIncomplete());
        addTearDown(c.dispose);
        await c.read(authNotifierProvider.future);
        await c.read(userProfileProvider.future);
        // /login is public → trainer gate must NOT fire; the function returns
        // /home (public → home redirect), not onboarding.
        // The key assertion: the result is NOT the onboarding route.
        final result = callRedirect(c, '/login');
        expect(
          result,
          isNot(equals('/profile/edit-trainer?mode=onboarding')),
          reason: 'public routes must not trigger the trainer onboarding gate',
        );
      },
    );
  });
  // ────────────────────────────────────────────────────────────────────────
  // Gate de edad mínima (bornAt) — cuentas preexistentes
  // ────────────────────────────────────────────────────────────────────────
  group('gate de edad mínima (bornAt)', () {
    Future<ProviderContainer> ready(UserProfile profile) async {
      final c = _loggedInContainer(profile: profile);
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      return c;
    }

    test('cuenta preexistente sin bornAt + /home → /birth-date', () async {
      final c = await ready(_athletePreAgeGate());
      expect(callRedirect(c, '/home'), equals('/birth-date'));
    });

    test('ya en /birth-date no vuelve a redirigir (self-skip)', () async {
      final c = await ready(_athletePreAgeGate());
      expect(callRedirect(c, '/birth-date'), isNull);
    });

    test('con bornAt cargado el gate no dispara', () async {
      final c = await ready(_athleteProfile());
      expect(callRedirect(c, '/home'), isNull);
    });

    test('con la fecha ya cargada, /birth-date SACA al usuario', () async {
      // El caso que faltaba, y es el que se ve en la app: el gate tenía regla
      // de ENTRADA con self-skip y ninguna de SALIDA.
      //
      // Guardar la fecha hace que la rama del gate deje de disparar, pero
      // `/birth-date` no es ruta pública, así que el redirect `/public → /home`
      // tampoco la alcanza: `authRedirect` devuelve null y el usuario se queda
      // mirando la misma pantalla, con la fecha ya persistida. Cerrar sesión y
      // volver a entrar "lo arregla" porque esa cadena arranca en /splash y
      // nunca pasa por acá.
      //
      // Es el mismo par entrada/salida que `/profile-unavailable` resuelve diez
      // líneas más arriba en la misma función. Ahí la salida se escribió; acá
      // no.
      final c = await ready(_athleteProfile());
      expect(
        callRedirect(c, '/birth-date'),
        equals('/home'),
        reason: 'un gate con entrada y sin salida deja al usuario adentro '
            'para siempre',
      );
    });

    test('al salir del gate, el PF incompleto sigue hasta SU onboarding',
        () async {
      // La salida devuelve /home y no el destino final a proposito: go_router
      // re-evalua el redirect sobre /home y los gates de abajo re-aplican
      // solos. Es el mismo mecanismo del que depende la salida de
      // /profile-unavailable.
      //
      // Sin este caso, la salida podria devolver /home y dejar al PF ahi —
      // salteandole el onboarding comercial que el gate de abajo existe para
      // imponer.
      final c = await ready(_trainerIncomplete());
      expect(callRedirect(c, '/birth-date'), equals('/home'));
      expect(
        callRedirect(c, '/home'),
        equals('/profile/edit-trainer?mode=onboarding'),
      );
    });

    test('la salida NO se dispara con la escritura sin confirmar', () async {
      // Firestore aplica el update en el cache ANTES del ack del servidor, asi
      // que el stream emite el `bornAt` optimista de inmediato.
      //
      // Sin este chequeo el usuario sale del gate con un dato que todavia
      // puede volver atras — y si el servidor lo rechaza, vuelve al gate SIN
      // EXPLICACION, con la pantalla que podia mostrarle el error ya
      // desmontada. Es peor que el bug original: en vez de "no pasa nada",
      // "funciona y despues rebota solo".
      final c = _loggedInContainer(
        profile: _athleteProfile(),
        pendingWrites: true,
      );
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      await c.read(userProfileHasPendingWritesProvider.future);

      expect(callRedirect(c, '/birth-date'), isNull);
    });

    test('la salida NO se dispara si la fecha sigue sin servir', () async {
      // Control del control: si la salida no mirara el validador, sacaría al
      // usuario del gate con la fecha todavía inválida — que es exactamente lo
      // que el gate existe para impedir. Sin este caso, el test de arriba pasa
      // con un `return '/home'` incondicional.
      final c = await ready(_athleteUnderMinAge());
      expect(callRedirect(c, '/birth-date'), isNull);
    });

    test('sin displayName gana ProfileSetup, no el gate de edad', () async {
      // Orden: una cuenta que nunca completó el alta va al flow, que YA pide la
      // fecha en su paso 2. Mandarla al gate primero la dejaría sin username.
      final c = await ready(_trainerNoDisplayName());
      expect(callRedirect(c, '/home'), equals('/profile-setup'));
    });

    test('el gate de edad corre ANTES del de trainer incompleto', () async {
      final c = await ready(_trainerIncompletePreAgeGate());
      expect(
        callRedirect(c, '/home'),
        equals('/birth-date'),
        reason: 'la edad es un requisito legal; el onboarding comercial '
            'del PF puede esperar',
      );
    });

    test('una fecha de menor de 16 YA persistida también cae en el gate',
        () async {
      // Sin mirar el validador (sólo `bornAt == null`), esta cuenta pasa el
      // gate y se come un permission-denied opaco en su PRIMERA escritura: las
      // rules validan el piso en todo update, no sólo en el create.
      final c = await ready(_athleteUnderMinAge());
      expect(callRedirect(c, '/home'), equals('/birth-date'));
    });

    test('las rutas públicas no las secuestra el gate', () async {
      final c = await ready(_athletePreAgeGate());
      expect(
        callRedirect(c, '/login'),
        isNot(equals('/birth-date')),
        reason: 'mismo contrato que el gate de trainer incompleto',
      );
    });

    // ── EL TEST QUE JUSTIFICA TODO EL DISEÑO ──────────────────────────────
    //
    // La solución obvia —sumar `bornAt == null` a la condición de displayName
    // de arriba— produce un LOOP DE REDIRECT INFINITO: la cuenta vieja tiene
    // displayName, así que el bloque "onboarding-completo" la saca de
    // /profile-setup de vuelta a /home, y /home la manda de nuevo a
    // /profile-setup. Iteramos el redirect como lo haría go_router y exigimos
    // que llegue a un punto fijo sin repetir destino.
    test('el redirect llega a un punto fijo — no hay loop', () async {
      final c = await ready(_athletePreAgeGate());

      var location = '/home';
      final visited = <String>[location];
      for (var i = 0; i < 10; i++) {
        final next = callRedirect(c, location);
        if (next == null) break;
        expect(
          visited,
          isNot(contains(next)),
          reason: 'ciclo de redirect: ${visited.join(" → ")} → $next',
        );
        visited.add(next);
        location = next;
      }

      expect(location, equals('/birth-date'));
      expect(callRedirect(c, location), isNull,
          reason: 'el destino final no puede volver a redirigir');
    });

    test('/profile-setup NO es destino de una cuenta preexistente', () async {
      // El otro lado de la moneda del loop: si esto volviera a ser
      // /profile-setup, el paso 1 le pediría el username a alguien que ya lo
      // tiene, y el chequeo de disponibilidad lo rechazaría contra sí mismo.
      final c = await ready(_athletePreAgeGate());
      expect(callRedirect(c, '/home'), isNot(equals('/profile-setup')));
    });
  });

  // ---------------------------------------------------------------------------
  // Gate del mail confirmado con código (VerifyMailScreen)
  //
  // Para TODAS las cuentas —también Google y Apple—, después del gate de edad y
  // antes del onboarding del PF. `emailVerification` lo escribe solo la Cloud
  // Function `verificarCodigoDeMail`, y cuenta la entrada del rol de HOY con el
  // mail de Auth de HOY (`correoVerificadoParaElRol`).
  // ---------------------------------------------------------------------------
  group('gate del mail confirmado con código', () {
    // El mail de Auth del test es, por defecto, el del perfil: es lo que el
    // gate compara. Sin mail en Auth el gate no corre, y no es lo que se mide.
    Future<ProviderContainer> listo(
      UserProfile profile, {
      String? authEmail,
      bool interruptor = true,
    }) async {
      final c = _loggedInContainer(
        profile: profile,
        authEmail: authEmail ?? profile.email,
        emailGate: Stream<bool>.value(interruptor),
      );
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      await c.read(emailGateEnabledProvider.future);
      return c;
    }

    UserProfile sinMail(UserProfile p) =>
        p.copyWith(emailVerification: const {});

    test('sin el mail confirmado, toda ruta privada manda a /verificar-mail',
        () async {
      final c = await listo(sinMail(_athleteProfile()));
      for (final ruta in ['/home', '/workout', '/coach', '/profile']) {
        expect(callRedirect(c, ruta), equals('/verificar-mail'), reason: ruta);
      }
    });

    test('en la pantalla y sin confirmar, se queda', () async {
      final c = await listo(sinMail(_athleteProfile()));
      expect(callRedirect(c, '/verificar-mail'), isNull);
    });

    test('apenas llega la marca, sale a /home', () async {
      // ENTRADA y SALIDA contra la misma condición: sin la salida, el usuario
      // se queda mirando la pantalla con el mail ya confirmado.
      final c = await listo(_athleteProfile());
      expect(callRedirect(c, '/verificar-mail'), equals('/home'));
    });

    test('con la marca puesta, el gate no dispara', () async {
      final c = await listo(_athleteProfile());
      expect(callRedirect(c, '/home'), isNull);
    });

    test('el alumno verificado que pasa a PF vuelve a la pantalla (promoción)',
        () async {
      // El mail del entrenador es otro, y la entrada de alumno no lo cubre. Con
      // un solo flag para los dos roles, este PF entraba sin ver el código.
      final promovido = _trainerComplete().copyWith(
        emailVerification: mailConfirmadoPara(
          UserRole.athlete,
          'trainer@example.com',
        ),
      );
      final c = await listo(promovido);
      expect(callRedirect(c, '/home'), equals('/verificar-mail'));
    });

    test('una entrada con otro mail que el de Auth no alcanza', () async {
      // El equipo le cambió el correo en Auth: el nuevo no lo abrió nadie.
      final c = await listo(
        _athleteProfile(),
        authEmail: 'otro@example.com',
      );
      expect(callRedirect(c, '/home'), equals('/verificar-mail'));
    });

    test('al PF también, y ANTES de su onboarding', () async {
      final sin = await listo(sinMail(_trainerIncomplete()));
      expect(callRedirect(sin, '/home'), equals('/verificar-mail'));

      final con = await listo(_trainerIncomplete());
      expect(
        callRedirect(con, '/home'),
        equals('/profile/edit-trainer?mode=onboarding'),
      );
    });

    group('interruptor app_config/email_gate', () {
      test('apagado, un alumno sin confirmar NO va al gate', () async {
        final c = await listo(sinMail(_athleteProfile()), interruptor: false);
        for (final ruta in ['/home', '/workout', '/coach', '/profile']) {
          expect(callRedirect(c, ruta), isNull, reason: ruta);
        }
      });

      test('apagado, quien está parado en la pantalla sale a /home', () async {
        // Misma condición para entrar y para salir: con el interruptor apagado
        // no puede quedarse mirando una pantalla que ya no corresponde.
        final c = await listo(sinMail(_athleteProfile()), interruptor: false);
        expect(callRedirect(c, '/verificar-mail'), equals('/home'));
      });

      test('apagado, el PF sin confirmar sigue directo a su onboarding',
          () async {
        final c =
            await listo(sinMail(_trainerIncomplete()), interruptor: false);
        expect(
          callRedirect(c, '/home'),
          equals('/profile/edit-trainer?mode=onboarding'),
        );
      });

      test('prendido, el alumno sin confirmar va al gate', () async {
        final c = await listo(sinMail(_athleteProfile()));
        expect(callRedirect(c, '/home'), equals('/verificar-mail'));
      });

      test('cargando, el gate no corre (falla abierto)', () async {
        // El stream todavía no emitió: `valueOrNull` es null y eso es "apagado".
        final c = _loggedInContainer(
          profile: sinMail(_athleteProfile()),
          authEmail: 'athlete@example.com',
          emailGate: const Stream<bool>.empty(),
        );
        addTearDown(c.dispose);
        await c.read(authNotifierProvider.future);
        await c.read(userProfileProvider.future);
        expect(c.read(emailGateEnabledProvider).isLoading, isTrue);

        expect(callRedirect(c, '/home'), isNull);
      });

      test('con error, el gate no corre (falla abierto)', () async {
        final c = _loggedInContainer(
          profile: sinMail(_athleteProfile()),
          authEmail: 'athlete@example.com',
          emailGate: Stream<bool>.error(StateError('permission-denied')),
        );
        addTearDown(c.dispose);
        await c.read(authNotifierProvider.future);
        await c.read(userProfileProvider.future);
        await c
            .read(emailGateEnabledProvider.future)
            .then<void>((_) {}, onError: (_) {});
        expect(c.read(emailGateEnabledProvider).hasError, isTrue);

        expect(callRedirect(c, '/home'), isNull);
      });
    });

    test('el gate de edad va primero (es un requisito legal)', () async {
      // Sin fecha y sin mail confirmado: primero la fecha.
      final c = await listo(_athletePreAgeGate());
      expect(callRedirect(c, '/home'), equals('/birth-date'));
    });

    test('en /birth-date con la fecha inválida, el gate del mail NO lo saca',
        () async {
      // Si lo sacara, el de edad lo devolvería: rebote infinito, para toda la
      // base de cuentas viejas el día del deploy.
      final c = await listo(_athletePreAgeGate());
      expect(callRedirect(c, '/birth-date'), isNull);
    });

    test('las rutas públicas no se gatean', () async {
      final c = await listo(sinMail(_athleteProfile()));
      // Logueado en una ruta pública va a /home, y desde ahí aplica el gate.
      expect(callRedirect(c, '/login'), equals('/home'));
      expect(callRedirect(c, '/home'), equals('/verificar-mail'));
    });

    test('punto fijo: desde /home termina en /verificar-mail, sin ciclos',
        () async {
      final c = await listo(sinMail(_trainerIncomplete()));

      var location = '/home';
      final visited = <String>[location];
      for (var i = 0; i < 10; i++) {
        final next = callRedirect(c, location);
        if (next == null) break;
        expect(
          visited,
          isNot(contains(next)),
          reason: 'ciclo de redirect: ${visited.join(" → ")} → $next',
        );
        visited.add(next);
        location = next;
      }

      expect(location, equals('/verificar-mail'));
      expect(callRedirect(c, location), isNull);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // Gate de rol — las pantallas exclusivas del PF no abren para un alumno
  // (#1743). Las escrituras ya las frenaba el servidor; la pantalla abría igual.
  // ────────────────────────────────────────────────────────────────────────
  group('gate de rol — rutas exclusivas del PF (#1743)', () {
    Future<ProviderContainer> listo(UserProfile profile) async {
      final c = _loggedInContainer(profile: profile);
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      return c;
    }

    test('la lista de rutas del test sigue siendo la del router REAL', () {
      // Si una ruta se renombra, el gate (que compara por prefijo) se queda
      // protegiendo un path que ya no existe y la nueva queda abierta. Que este
      // test se caiga es la señal para actualizar `_rutasSoloPF`.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final router = buildRouter(
        refreshListenable: ValueNotifier<int>(0),
        read: c.read,
      );
      final registradas = _fullPaths(router.configuration.routes).toSet();

      for (final plantilla in _rutasSoloDelPF.keys) {
        expect(registradas, contains(plantilla),
            reason: '$plantilla ya no está registrada en el router');
      }
    });

    for (final entry in _rutasSoloDelPF.entries) {
      final plantilla = entry.key;
      final url = entry.value;

      test('alumno + $plantilla → /home', () async {
        final c = await listo(_athleteProfile());
        expect(callRedirect(c, url), equals('/home'));
      });

      test('trainer + $plantilla → pasa', () async {
        final c = await listo(_trainerComplete());
        expect(callRedirect(c, url), isNull);
      });
    }

    test('con query: el gate mira el path, no el string entero', () async {
      final c = await listo(_athleteProfile());
      expect(
        callRedirect(c, '/coach/availability-editor?trainerId=seed-coach-001'),
        equals('/home'),
        reason: 'ofrecía Editar/Eliminar la disponibilidad de OTRO PF',
      );
      expect(
        callRedirect(c, '/profile/edit-trainer?mode=onboarding'),
        equals('/home'),
      );
    });

    test('el PF con el perfil incompleto sigue yendo a SU onboarding',
        () async {
      // El gate del PF incompleto corre antes y es del trainer: no puede
      // quedar mal parado por el gate de rol.
      final c = await listo(_trainerIncomplete());
      expect(
        callRedirect(c, '/coach/athlete/ath-1'),
        equals('/profile/edit-trainer?mode=onboarding'),
      );
      expect(callRedirect(c, '/profile/edit-trainer?mode=onboarding'), isNull);
    });

    for (final url in _rutasDelAlumno) {
      test('alumno + $url → pasa (no es exclusiva del PF)', () async {
        final c = await listo(_athleteProfile());
        expect(callRedirect(c, url), isNull);
      });
    }

    test('/profile/edit-personal abre para el PF Y para el alumno (#1817)',
        () async {
      // Cuelga de `/profile`, que tiene pantallas de PF en `_rutasSoloPF`, y
      // sumarla ahí «por ser de perfil» sería un error fácil. El PF llega por la
      // fila «Datos personales» de su Perfil (#1738), el único lugar desde el
      // que cambia su nombre y su avatar; el alumno, por la de CUENTA.
      final alumno = await listo(_athleteProfile());
      final pf = await listo(_trainerComplete());

      expect(callRedirect(alumno, '/profile/edit-personal'), isNull);
      expect(callRedirect(pf, '/profile/edit-personal'), isNull);
    });

    test('un prefijo parecido no cuenta: el match es por segmento', () async {
      final c = await listo(_athleteProfile());
      expect(callRedirect(c, '/coach/athletes'), isNull);
      expect(callRedirect(c, '/profile/edit-trainer-x'), isNull);
      expect(callRedirect(c, '/workout/routine-editors'), isNull);
    });

    test(
        '/profile/settings/bloqueados abre para el PF Y para el alumno (#1830)',
        () async {
      // «Usuarios bloqueados» cuelga de Privacidad, a la que llegan los dos
      // roles (el PF desde `TrainerProfileView`). Si alguien la suma a
      // `_rutasSoloPF` «por ser de configuración», el alumno rebota a /home.
      final alumno = await listo(_athleteProfile());
      final pf = await listo(_trainerComplete());

      expect(callRedirect(alumno, '/profile/settings/bloqueados'), isNull);
      expect(callRedirect(pf, '/profile/settings/bloqueados'), isNull);
    });

    test('mientras el perfil carga NO redirige (el router re-evalúa después)',
        () async {
      // Un PF con el perfil todavía sin leer no puede rebotar de su propia
      // pantalla: sin perfil no hay forma de saber qué rol tiene.
      final mockUser = MockUser();
      when(() => mockUser.email).thenReturn(null);
      final c = ProviderContainer(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(mockUser)),
          ),
          emailGateEnabledProvider
              .overrideWith((ref) => Stream<bool>.value(false)),
          userProfileProvider.overrideWith(
            (ref) => StreamController<UserProfile?>().stream,
          ),
          userProfileHasPendingWritesProvider
              .overrideWith((ref) => Stream<bool>.value(false)),
          accountDeletionInFlightProvider.overrideWith((ref) => false),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(c.read(userProfileProvider).isLoading, isTrue);
      expect(callRedirect(c, '/coach/athlete/ath-1'), isNull);
    });

    test('sin sesión manda a /welcome, no a /home', () async {
      final c = _anonContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(callRedirect(c, '/coach/athlete/ath-1'), equals('/welcome'));
    });

    test('un alumno sin fecha de nacimiento cae en el gate de edad primero',
        () async {
      // Los requisitos de la cuenta (edad, mail, onboarding) le ganan al gate
      // de rol: primero se completa la cuenta, después se decide a dónde va.
      final c = await listo(_athletePreAgeGate());
      expect(callRedirect(c, '/coach/athlete/ath-1'), equals('/birth-date'));
    });

    test('desde la ruta del PF el redirect llega a un punto fijo en /home',
        () async {
      final c = await listo(_athleteProfile());
      var location = '/coach/athlete/ath-1/plan/r-1';
      final visited = <String>[location];
      for (var i = 0; i < 10; i++) {
        final next = callRedirect(c, location);
        if (next == null) break;
        expect(visited, isNot(contains(next)),
            reason: 'ciclo de redirect: ${visited.join(" → ")} → $next');
        visited.add(next);
        location = next;
      }
      expect(location, equals('/home'));
    });
  });
}
