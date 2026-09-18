import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/router.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/account_deletion_notifier.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

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
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

UserProfile _trainerIncomplete() => UserProfile(
      uid: 'trainer-uid',
      email: 'trainer@example.com',
      displayName: 'pf-mauro',
      bornAt: _adultBornAt,
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
        userProfileProvider
            .overrideWith((ref) => Stream<UserProfile?>.value(null)),
      ],
    );

ProviderContainer _loggedInContainer({
  required UserProfile profile,
  bool deletionInFlight = false,
}) {
  final mockUser = MockUser();
  return ProviderContainer(
    overrides: [
      authNotifierProvider.overrideWith(
        () => _StubAuthNotifier(AsyncData(mockUser)),
      ),
      userProfileProvider.overrideWith(
        (ref) => Stream<UserProfile?>.value(profile),
      ),
      accountDeletionInFlightProvider.overrideWith((ref) => deletionInFlight),
    ],
  );
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
}
