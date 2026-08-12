// Gate de onboarding en la cadena de redirects del router mobile (issue #627,
// slice 1 — alumno). Ejercita `authRedirect` puro, sin widget tree, igual que
// router_auth_redirect_test.
//
// Lo que se protege acá es la lección de #429: un gate de onboarding NO puede
// comerse toda ruta protegida. De ahí que la mitad de los casos sean salidas
// (loop guard, rutas públicas, escape hatch de sesión) y no entradas.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/router.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/onboarding/application/onboarding_providers.dart';
import 'package:treino/features/onboarding/domain/onboarding_seen.dart';
import 'package:treino/features/onboarding/domain/onboarding_surface.dart';
import 'package:treino/features/profile/application/account_deletion_notifier.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

class MockUser extends Mock implements User {}

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AsyncValue<User?> _fixedState;

  @override
  Future<User?> build() async {
    state = _fixedState;
    return _fixedState.valueOrNull;
  }
}

final DateTime _kDate = DateTime.utc(2026, 1, 1);

final OnboardingSeen _seen =
    OnboardingSeen.empty.markSeen(OnboardingSurface.athleteMobile);

UserProfile _athlete({OnboardingSeen? onboardingSeen}) => UserProfile(
      uid: 'athlete-uid',
      email: 'athlete@example.com',
      displayName: 'sporty',
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
      onboardingSeen: onboardingSeen ?? OnboardingSeen.empty,
    );

UserProfile _athleteNoDisplayName() => UserProfile(
      uid: 'athlete-uid',
      email: 'athlete@example.com',
      displayName: null,
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

/// PF con perfil profesional completo: el gate de trainer-incompleto no
/// dispara, así que si el de onboarding disparara lo veríamos.
UserProfile _trainerComplete() => UserProfile(
      uid: 'trainer-uid',
      email: 'trainer@example.com',
      displayName: 'pf-mauro',
      role: UserRole.trainer,
      createdAt: _kDate,
      updatedAt: _kDate,
      trainerBio: 'bio text',
      trainerSpecialty: 'crossfit',
      trainerMonthlyRate: 50000,
      trainerOffersOnline: true,
    );

Future<ProviderContainer> _container({
  required UserProfile profile,
  bool dismissed = false,
}) async {
  final c = ProviderContainer(
    overrides: [
      authNotifierProvider.overrideWith(
        () => _StubAuthNotifier(AsyncData(MockUser())),
      ),
      userProfileProvider.overrideWith(
        (ref) => Stream<UserProfile?>.value(profile),
      ),
      accountDeletionInFlightProvider.overrideWith((ref) => false),
    ],
  );
  await c.read(authNotifierProvider.future);
  await c.read(userProfileProvider.future);
  if (dismissed) c.read(onboardingDismissedProvider.notifier).state = true;
  return c;
}

String? _redirect(ProviderContainer c, String location) =>
    authRedirect(c.read, location);

void main() {
  group('authRedirect — gate del tour de onboarding (#627)', () {
    test('alumno que nunca vio el tour + /home → /onboarding/athlete',
        () async {
      final c = await _container(profile: _athlete());
      addTearDown(c.dispose);
      expect(_redirect(c, '/home'), equals('/onboarding/athlete'));
    });

    test('el gate cubre cualquier ruta protegida, no sólo /home', () async {
      final c = await _container(profile: _athlete());
      addTearDown(c.dispose);
      expect(_redirect(c, '/workout'), equals('/onboarding/athlete'));
      expect(_redirect(c, '/feed'), equals('/onboarding/athlete'));
    });

    test('alumno que ya lo vio + /home → null (no vuelve a aparecer)',
        () async {
      final c = await _container(profile: _athlete(onboardingSeen: _seen));
      addTearDown(c.dispose);
      expect(_redirect(c, '/home'), isNull);
    });

    test('versión vieja vista → vuelve a estar pendiente', () async {
      // Simula el bump de OnboardingSurface.athleteMobile.version: el doc
      // guarda 0 (o cualquier valor menor al actual) y el tour re-aparece
      // sin migración de datos.
      const stale = OnboardingSeen({'athleteMobile': 0});
      final c = await _container(profile: _athlete(onboardingSeen: stale));
      addTearDown(c.dispose);
      expect(_redirect(c, '/home'), equals('/onboarding/athlete'));
    });

    test('claves de otras superficies no cuentan como visto', () async {
      const otherSurfaces =
          OnboardingSeen({'trainerWeb': 9, 'trainerMobile': 9});
      final c = await _container(
        profile: _athlete(onboardingSeen: otherSurfaces),
      );
      addTearDown(c.dispose);
      expect(_redirect(c, '/home'), equals('/onboarding/athlete'));
    });

    test('loop guard: ya estando en /onboarding/athlete → null', () async {
      final c = await _container(profile: _athlete());
      addTearDown(c.dispose);
      expect(_redirect(c, '/onboarding/athlete'), isNull);
    });

    test('salida: el flag se persistió y el usuario sigue en el tour → /home',
        () async {
      final c = await _container(profile: _athlete(onboardingSeen: _seen));
      addTearDown(c.dispose);
      expect(_redirect(c, '/onboarding/athlete'), equals('/home'));
    });

    test(
        'escape hatch de sesión: aunque el write falle, salta/termina y sale '
        '(#429 — nunca sin salida)', () async {
      // Perfil SIN el flag persistido (el write a Firestore falló) pero con
      // el tour ya despachado en esta sesión.
      final c = await _container(profile: _athlete(), dismissed: true);
      addTearDown(c.dispose);
      expect(_redirect(c, '/onboarding/athlete'), equals('/home'));
      expect(_redirect(c, '/home'), isNull);
      expect(_redirect(c, '/workout'), isNull);
    });

    test('rutas públicas siguen accesibles con el tour pendiente', () async {
      final c = await _container(profile: _athlete());
      addTearDown(c.dispose);
      for (final route in ['/login', '/register', '/forgot-password']) {
        expect(
          _redirect(c, route),
          isNot(equals('/onboarding/athlete')),
          reason: '$route es pública — el gate no puede comérsela',
        );
      }
    });

    test('profile_setup incompleto gana: displayName null → /profile-setup',
        () async {
      final c = await _container(profile: _athleteNoDisplayName());
      addTearDown(c.dispose);
      expect(_redirect(c, '/home'), equals('/profile-setup'));
    });

    test('el gate no dispara para un PF (slice 2 trae el tour de trainer)',
        () async {
      final c = await _container(profile: _trainerComplete());
      addTearDown(c.dispose);
      expect(_redirect(c, '/home'), isNull);
    });

    test('sin sesión + /home → /welcome (el gate no se mete)', () async {
      final c = ProviderContainer(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(const AsyncData(null)),
          ),
          userProfileProvider
              .overrideWith((ref) => Stream<UserProfile?>.value(null)),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(_redirect(c, '/home'), equals('/welcome'));
    });

    test('borrado de cuenta en vuelo → null (ese gate corre antes)', () async {
      final c = ProviderContainer(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(MockUser())),
          ),
          userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(_athlete()),
          ),
          accountDeletionInFlightProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(_redirect(c, '/home'), isNull);
    });
  });

  group('OnboardingSeen — modelo del flag', () {
    test('mapa vacío ⇒ ninguna superficie vista', () {
      for (final s in OnboardingSurface.values) {
        expect(OnboardingSeen.empty.hasSeen(s), isFalse);
        expect(OnboardingSeen.empty.isPending(s), isTrue);
      }
    });

    test('markSeen no pisa las otras superficies', () {
      final seen = OnboardingSeen.empty
          .markSeen(OnboardingSurface.athleteMobile)
          .markSeen(OnboardingSurface.trainerWeb);
      expect(seen.hasSeen(OnboardingSurface.athleteMobile), isTrue);
      expect(seen.hasSeen(OnboardingSurface.trainerWeb), isTrue);
      expect(seen.hasSeen(OnboardingSurface.trainerMobile), isFalse);
    });

    test('reset deja la clave en 0 en vez de borrarla (merge profundo)', () {
      final seen =
          OnboardingSeen.empty.markSeen(OnboardingSurface.athleteMobile);
      final reset = seen.reset(OnboardingSurface.athleteMobile);
      expect(reset.isPending(OnboardingSurface.athleteMobile), isTrue);
      expect(reset.toJson(), containsPair('athleteMobile', 0));
    });

    test('fromJson normaliza números flojos de Firestore y basura', () {
      final parsed = OnboardingSeen.fromJson(<String, Object?>{
        'athleteMobile': 1.0, // double que llega como num
        'trainerMobile': -3, // negativo → no visto
        'trainerWeb': 'nope', // no numérico → no visto
        'futureSurface': 7, // clave desconocida: se preserva
      });
      expect(parsed.hasSeen(OnboardingSurface.athleteMobile), isTrue);
      expect(parsed.hasSeen(OnboardingSurface.trainerMobile), isFalse);
      expect(parsed.hasSeen(OnboardingSurface.trainerWeb), isFalse);
      expect(parsed.toJson(), containsPair('futureSurface', 7));
    });

    test('round-trip por UserProfile.toJson/fromJson', () {
      final profile = _athlete(onboardingSeen: _seen);
      final restored = UserProfile.fromJson(profile.toJson());
      expect(restored.onboardingSeen, equals(_seen));
      expect(
        restored.onboardingSeen.hasSeen(OnboardingSurface.athleteMobile),
        isTrue,
      );
    });

    test('el campo ausente en el doc cae en el default vacío', () {
      final json = _athlete().toJson()..remove('onboardingSeen');
      final restored = UserProfile.fromJson(json);
      expect(restored.onboardingSeen, equals(OnboardingSeen.empty));
    });
  });
}
