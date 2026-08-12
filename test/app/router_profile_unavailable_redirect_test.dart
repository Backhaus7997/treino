import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/router.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/account_deletion_notifier.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/onboarding/domain/onboarding_seen.dart';
import 'package:treino/features/onboarding/domain/onboarding_surface.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

/// Issue #544 — "autenticado pero sin perfil accesible" deja la app en
/// skeleton infinito. authRedirect ahora detecta `hasError` en
/// userProfileProvider y degrada explícito a /profile-unavailable.
class MockUser extends Mock implements User {}

String? callRedirect(ProviderContainer container, String location) {
  return authRedirect(container.read, location);
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

final DateTime _kDate = DateTime.utc(2026, 1, 1);

UserProfile _athleteProfile() => UserProfile(
      uid: 'athlete-uid',
      email: 'athlete@example.com',
      displayName: 'sporty',
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
      // #627: alumno que YA vio el tour de onboarding. Sin esto el gate de
      // authRedirect lo manda a /onboarding/athlete.
      onboardingSeen: OnboardingSeen.empty.markSeen(
        OnboardingSurface.athleteMobile,
      ),
    );

/// Container logueado cuyo stream de perfil emite lo que mande [controller].
ProviderContainer _loggedInStreamContainer(
  StreamController<UserProfile?> controller, {
  bool deletionInFlight = false,
}) {
  final mockUser = MockUser();
  return ProviderContainer(
    overrides: [
      authNotifierProvider.overrideWith(
        () => _StubAuthNotifier(AsyncData(mockUser)),
      ),
      userProfileProvider.overrideWith((ref) => controller.stream),
      accountDeletionInFlightProvider.overrideWith((ref) => deletionInFlight),
    ],
  );
}

/// Resuelve el future del perfil tolerando el error — deja el provider en
/// AsyncError sin romper el test.
Future<void> _settleProfile(ProviderContainer c) async {
  try {
    await c.read(userProfileProvider.future);
  } catch (_) {
    // Intencional: el estado del provider queda AsyncError.
  }
}

void main() {
  group('authRedirect — perfil inaccesible (#544)', () {
    test(
      'stream del perfil en error + /home → /profile-unavailable '
      '(NUNCA /profile-setup — el submit ahí fallaría igual)',
      () async {
        final controller = StreamController<UserProfile?>();
        final c = _loggedInStreamContainer(controller);
        addTearDown(c.dispose);
        addTearDown(controller.close);
        await c.read(authNotifierProvider.future);
        controller.addError(Exception('permission-denied'));
        await _settleProfile(c);

        expect(callRedirect(c, '/home'), equals('/profile-unavailable'));
      },
    );

    test(
      'error CON valor retenido (snapshot cacheado + listener muerto — el '
      'caso observado en QA) → /profile-unavailable',
      () async {
        final controller = StreamController<UserProfile?>();
        final c = _loggedInStreamContainer(controller);
        addTearDown(c.dispose);
        addTearDown(controller.close);
        await c.read(authNotifierProvider.future);

        // 1. El cache local emite un perfil COMPLETO (displayName != null)…
        controller.add(_athleteProfile());
        await c.read(userProfileProvider.future);
        // 2. …y después el server mata el listener con permission-denied.
        controller.addError(Exception('permission-denied'));
        await Future<void>.delayed(Duration.zero);

        final state = c.read(userProfileProvider);
        expect(state.hasError, isTrue,
            reason: 'precondición: el error llegó al provider');
        expect(state.valueOrNull, isNotNull,
            reason: 'precondición: copyWithPrevious retiene el valor — '
                'el gate de displayName NO dispararía');

        expect(callRedirect(c, '/home'), equals('/profile-unavailable'));
      },
    );

    test('ya en /profile-unavailable + error → null (sin loop)', () async {
      final controller = StreamController<UserProfile?>();
      final c = _loggedInStreamContainer(controller);
      addTearDown(c.dispose);
      addTearDown(controller.close);
      await c.read(authNotifierProvider.future);
      controller.addError(Exception('permission-denied'));
      await _settleProfile(c);

      expect(callRedirect(c, '/profile-unavailable'), isNull);
    });

    test(
      'recovery exit: en /profile-unavailable + perfil resuelto → /home',
      () async {
        final controller = StreamController<UserProfile?>();
        final c = _loggedInStreamContainer(controller);
        addTearDown(c.dispose);
        addTearDown(controller.close);
        await c.read(authNotifierProvider.future);
        controller.add(_athleteProfile());
        await c.read(userProfileProvider.future);

        expect(callRedirect(c, '/profile-unavailable'), equals('/home'));
      },
    );

    test(
      'cerrar sesión desde el estado degradado: anon en '
      '/profile-unavailable → /welcome',
      () async {
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

        expect(callRedirect(c, '/profile-unavailable'), equals('/welcome'));
      },
    );

    test(
      'deletion in-flight + error → null (el gate de borrado de cuenta '
      'sigue teniendo prioridad)',
      () async {
        final controller = StreamController<UserProfile?>();
        final c = _loggedInStreamContainer(controller, deletionInFlight: true);
        addTearDown(c.dispose);
        addTearDown(controller.close);
        await c.read(authNotifierProvider.future);
        controller.addError(Exception('permission-denied'));
        await _settleProfile(c);

        expect(callRedirect(c, '/home'), isNull);
      },
    );

    test(
      'perfil sano en ruta normal → null (la rama nueva no altera el '
      'happy path)',
      () async {
        final controller = StreamController<UserProfile?>();
        final c = _loggedInStreamContainer(controller);
        addTearDown(c.dispose);
        addTearDown(controller.close);
        await c.read(authNotifierProvider.future);
        controller.add(_athleteProfile());
        await c.read(userProfileProvider.future);

        expect(callRedirect(c, '/home'), isNull);
      },
    );

    test(
      'perfil ausente SIN error (AsyncData(null), doc confirmado ausente) '
      '→ /profile-setup como siempre — la rama de error no lo captura',
      () async {
        final controller = StreamController<UserProfile?>();
        final c = _loggedInStreamContainer(controller);
        addTearDown(c.dispose);
        addTearDown(controller.close);
        await c.read(authNotifierProvider.future);
        controller.add(null);
        await c.read(userProfileProvider.future);

        expect(callRedirect(c, '/home'), equals('/profile-setup'));
      },
    );
  });
}
