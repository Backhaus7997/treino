import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/coach_hub_router.dart';
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
Future<String?> _call(ProviderContainer container, String location) async {
  await container.read(userProfileProvider.future).catchError((_) => null);
  return coachHubRedirect(container.read, location);
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
  });
}
