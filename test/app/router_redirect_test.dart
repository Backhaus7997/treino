import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/router.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

class MockUser extends Mock implements User {}

// ---------------------------------------------------------------------------
// Helper — calls the exported pure redirect function with a container whose
// authNotifierProvider is in a controlled state.
// ---------------------------------------------------------------------------
String? callRedirect(ProviderContainer container, String location) {
  return authRedirect(container.read, location);
}

// Stub notifier that holds a fixed AsyncValue without touching Firebase.
class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AsyncValue<User?> _fixedState;

  @override
  Future<User?> build() async {
    state = _fixedState;
    return _fixedState.valueOrNull;
  }
}

// Stub notifier that stays in AsyncLoading forever.
class _LoadingAuthNotifier extends AuthNotifier {
  @override
  Future<User?> build() => Completer<User?>().future;
}

/// Fixture: UserProfile con displayName seteado → profile completo.
/// El redirect tiene que tratar este perfil como "ya pasó ProfileSetup".
UserProfile _completeProfile() => UserProfile(
      uid: 'test-uid',
      email: 'test@example.com',
      displayName: 'tincho',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Fixture: UserProfile con displayName=null → profile incompleto.
/// AuthService.signUpWithEmail crea el doc inicial así; ProfileSetup lo
/// completa.
UserProfile _incompleteProfile() => UserProfile(
      uid: 'test-uid',
      email: 'test@example.com',
      displayName: null,
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  late MockUser mockUser;

  setUp(() {
    mockUser = MockUser();
  });

  ProviderContainer anonContainer() => ProviderContainer(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(const AsyncData(null)),
          ),
          userProfileProvider
              .overrideWith((ref) => Stream<UserProfile?>.value(null)),
        ],
      );

  ProviderContainer loggedInContainer({
    UserProfile? profile,
  }) =>
      ProviderContainer(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(mockUser)),
          ),
          userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(profile ?? _completeProfile()),
          ),
        ],
      );

  ProviderContainer loadingContainer() => ProviderContainer(
        overrides: [
          authNotifierProvider.overrideWith(() => _LoadingAuthNotifier()),
          userProfileProvider
              .overrideWith((ref) => Stream<UserProfile?>.value(null)),
        ],
      );

  // ---------------------------------------------------------------------------
  // Anonymous user — shell routes redirect to /welcome
  // ---------------------------------------------------------------------------
  group('redirect — anonymous user', () {
    test('anon + /home → /welcome', () async {
      final c = anonContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(callRedirect(c, '/home'), '/welcome');
    });

    test('anon + /workout → /welcome', () async {
      final c = anonContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(callRedirect(c, '/workout'), '/welcome');
    });

    test('anon + /login → null (stay)', () async {
      final c = anonContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(callRedirect(c, '/login'), isNull);
    });

    test('anon + /welcome → null (stay)', () async {
      final c = anonContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(callRedirect(c, '/welcome'), isNull);
    });

    test('anon + /register → null (stay)', () async {
      final c = anonContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(callRedirect(c, '/register'), isNull);
    });

    test('anon + /forgot-password → null (do not bounce mid-reset)', () async {
      final c = anonContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(callRedirect(c, '/forgot-password'), isNull);
    });

    test('anon + /splash → null (no redirect on splash)', () async {
      final c = anonContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(callRedirect(c, '/splash'), isNull);
    });

    test('anon + /login/deep → null (startsWith semantics)', () async {
      final c = anonContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(callRedirect(c, '/login/deep'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Authenticated user with COMPLETE profile — auth routes redirect to /home.
  // El loggedInContainer por default usa _completeProfile().
  // ---------------------------------------------------------------------------
  group('redirect — authenticated user (complete profile)', () {
    test('scenario 16.1 — user + /login → /home', () async {
      final c = loggedInContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/login'), '/home');
    });

    test('scenario 16.2 — user + /register → /home', () async {
      final c = loggedInContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/register'), '/home');
    });

    test('scenario 16.3 — user + /home → null (stay)', () async {
      final c = loggedInContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/home'), isNull);
    });

    test('user + /workout → null (stay)', () async {
      final c = loggedInContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/workout'), isNull);
    });

    test('user + /welcome → /home', () async {
      final c = loggedInContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/welcome'), '/home');
    });

    test('user + /splash → null (splash handles its own navigation)', () async {
      final c = loggedInContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/splash'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Authenticated user with INCOMPLETE profile — todo cae a /profile-setup
  // (excepto /profile-setup mismo y /splash que no se bouncea).
  // ---------------------------------------------------------------------------
  group('redirect — authenticated user (incomplete profile)', () {
    test('incomplete + /home → /profile-setup', () async {
      final c = loggedInContainer(profile: _incompleteProfile());
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/home'), '/profile-setup');
    });

    test('incomplete + /workout → /profile-setup', () async {
      final c = loggedInContainer(profile: _incompleteProfile());
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/workout'), '/profile-setup');
    });

    test('incomplete + /login → /profile-setup', () async {
      final c = loggedInContainer(profile: _incompleteProfile());
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/login'), '/profile-setup');
    });

    test('incomplete + /profile-setup → null (stay)', () async {
      final c = loggedInContainer(profile: _incompleteProfile());
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/profile-setup'), isNull);
    });

    test('no profile doc yet → /profile-setup (treat as incomplete)', () async {
      // Inline en vez de loggedInContainer() porque el helper tiene un
      // default a _completeProfile() para el caso común; acá queremos
      // explícitamente que la collection no tenga el doc todavía.
      final c = ProviderContainer(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(mockUser)),
          ),
          userProfileProvider
              .overrideWith((ref) => Stream<UserProfile?>.value(null)),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/home'), '/profile-setup');
    });
  });

  // ---------------------------------------------------------------------------
  // AsyncLoading state — never redirects
  // ---------------------------------------------------------------------------
  group('redirect — AsyncLoading state', () {
    test('scenario 17.1 — loading + /home → null (no redirect while resolving)',
        () {
      final c = loadingContainer();
      addTearDown(c.dispose);
      expect(callRedirect(c, '/home'), isNull);
    });

    test('scenario 17.1 — loading + /login → null', () {
      final c = loadingContainer();
      addTearDown(c.dispose);
      expect(callRedirect(c, '/login'), isNull);
    });

    test('scenario 17.1 — loading + /workout → null', () {
      final c = loadingContainer();
      addTearDown(c.dispose);
      expect(callRedirect(c, '/workout'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Fixtures for trainer role tests
  // ---------------------------------------------------------------------------

  /// Fixture: trainer with complete profile.
  UserProfile trainerProfile() => UserProfile(
        uid: 'test-trainer-uid',
        email: 'trainer@example.com',
        displayName: 'pf-mauro',
        role: UserRole.trainer,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  /// Fixture: trainer with incomplete profile (displayName=null).
  UserProfile trainerIncompleteProfile() => UserProfile(
        uid: 'test-trainer-uid',
        email: 'trainer@example.com',
        displayName: null,
        role: UserRole.trainer,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  // ---------------------------------------------------------------------------
  // Authenticated user with TRAINER role (complete profile) — Option A:
  // no role-specific redirects at the router layer. All routes stay.
  // ---------------------------------------------------------------------------
  group('redirect — authenticated user (trainer role)', () {
    test('trainer + /home → null (stay)', () async {
      final c = loggedInContainer(profile: trainerProfile());
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/home'), isNull);
    });

    test('trainer + /coach → null (stay; widget-level dispatch decides)',
        () async {
      final c = loggedInContainer(profile: trainerProfile());
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/coach'), isNull);
    });

    test('trainer + /welcome → /home (same gate as athlete)', () async {
      final c = loggedInContainer(profile: trainerProfile());
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/welcome'), '/home');
    });

    test('trainer + /workout → null (Option A: NOT redirected away)', () async {
      final c = loggedInContainer(profile: trainerProfile());
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/workout'), isNull);
    });

    test('trainer + /feed → null (Option A: NOT redirected away)', () async {
      final c = loggedInContainer(profile: trainerProfile());
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/feed'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Trainer with INCOMPLETE profile — role does NOT bypass the completeness gate
  // ---------------------------------------------------------------------------
  group('redirect — trainer with incomplete profile', () {
    test(
        'trainer + displayName=null + /home → /profile-setup (completeness gate)',
        () async {
      final c = loggedInContainer(profile: trainerIncompleteProfile());
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/home'), '/profile-setup');
    });

    test('trainer + displayName=null + /profile-setup → null (stay)', () async {
      final c = loggedInContainer(profile: trainerIncompleteProfile());
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      await c.read(userProfileProvider.future);
      expect(callRedirect(c, '/profile-setup'), isNull);
    });
  });
}
