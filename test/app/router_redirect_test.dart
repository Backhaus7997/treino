import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/router.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';

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
        ],
      );

  ProviderContainer loggedInContainer() => ProviderContainer(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _StubAuthNotifier(AsyncData(mockUser)),
          ),
        ],
      );

  ProviderContainer loadingContainer() => ProviderContainer(
        overrides: [
          authNotifierProvider.overrideWith(() => _LoadingAuthNotifier()),
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
  // Authenticated user — auth routes redirect to /home
  // ---------------------------------------------------------------------------
  group('redirect — authenticated user', () {
    test('scenario 16.1 — user + /login → /home', () async {
      final c = loggedInContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(callRedirect(c, '/login'), '/home');
    });

    test('scenario 16.2 — user + /register → /home', () async {
      final c = loggedInContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(callRedirect(c, '/register'), '/home');
    });

    test('scenario 16.3 — user + /home → null (stay)', () async {
      final c = loggedInContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(callRedirect(c, '/home'), isNull);
    });

    test('user + /workout → null (stay)', () async {
      final c = loggedInContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(callRedirect(c, '/workout'), isNull);
    });

    test('user + /welcome → /home', () async {
      final c = loggedInContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(callRedirect(c, '/welcome'), '/home');
    });

    test('user + /splash → null (splash handles its own navigation)', () async {
      final c = loggedInContainer();
      addTearDown(c.dispose);
      await c.read(authNotifierProvider.future);
      expect(callRedirect(c, '/splash'), isNull);
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
}
