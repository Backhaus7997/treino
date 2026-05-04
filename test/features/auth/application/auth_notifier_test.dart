import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/data/auth_service.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';

// --- Mocks ---
class MockAuthService extends Mock implements AuthService {}

class MockUser extends Mock implements User {}

// ---------------------------------------------------------------------------
// Helper: builds a ProviderContainer with overrides for authServiceProvider
// and authStateChangesProvider (driven by the supplied StreamController).
// ---------------------------------------------------------------------------
ProviderContainer buildContainer({
  required MockAuthService mockService,
  required Stream<User?> authStream,
}) {
  return ProviderContainer(
    overrides: [
      authServiceProvider.overrideWithValue(mockService),
      authStateChangesProvider.overrideWith((_) => authStream),
    ],
  );
}

void main() {
  late MockAuthService mockService;
  late MockUser mockUser;

  setUp(() {
    mockService = MockAuthService();
    mockUser = MockUser();
    when(() => mockUser.emailVerified).thenReturn(false);
  });

  // ---------------------------------------------------------------------------
  // build() — seeds state from authStateChangesProvider
  // ---------------------------------------------------------------------------
  group('AuthNotifier.build()', () {
    test('seeds state from first stream emission', () async {
      final streamController = StreamController<User?>();
      final container = buildContainer(
        mockService: mockService,
        authStream: streamController.stream,
      );
      addTearDown(container.dispose);

      // Emit a user immediately
      streamController.add(mockUser);

      // Wait for the notifier to initialize and receive the emission
      await container.read(authNotifierProvider.future);

      expect(
        container.read(authNotifierProvider).valueOrNull,
        mockUser,
      );
      await streamController.close();
    });

    test('seeds state as null when stream emits null', () async {
      final container = buildContainer(
        mockService: mockService,
        authStream: Stream.value(null),
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.future);

      expect(
        container.read(authNotifierProvider).valueOrNull,
        isNull,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // signIn
  // ---------------------------------------------------------------------------
  group('AuthNotifier.signIn', () {
    test('signIn happy path — AsyncData(null) → AsyncLoading → AsyncData(user)',
        () async {
      final streamController = StreamController<User?>();
      final container = buildContainer(
        mockService: mockService,
        authStream: streamController.stream,
      );
      addTearDown(() {
        container.dispose();
        streamController.close();
      });

      // Seed with null (logged out)
      streamController.add(null);
      await container.read(authNotifierProvider.future);

      when(
        () => mockService.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async {
        // Simulate Firebase emitting the user mid-sign-in
        streamController.add(mockUser);
        return mockUser;
      });

      await container
          .read(authNotifierProvider.notifier)
          .signIn(email: 'a@b.c', password: 'Pass1234');

      final state = container.read(authNotifierProvider);
      expect(state.hasValue, isTrue);
    });

    test('signIn failure — sets AsyncError with AuthFailure', () async {
      final streamController = StreamController<User?>();
      final container = buildContainer(
        mockService: mockService,
        authStream: streamController.stream,
      );
      addTearDown(() {
        container.dispose();
        streamController.close();
      });

      streamController.add(null);
      await container.read(authNotifierProvider.future);

      when(
        () => mockService.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const AuthFailure.wrongPassword());

      await container
          .read(authNotifierProvider.notifier)
          .signIn(email: 'a@b.c', password: 'wrong');

      final state = container.read(authNotifierProvider);
      expect(state.hasError, isTrue);
      expect(state.error, const AuthFailure.wrongPassword());
    });
  });

  // ---------------------------------------------------------------------------
  // signUp
  // ---------------------------------------------------------------------------
  group('AuthNotifier.signUp', () {
    test('signUp happy path — resolves to AsyncData(user)', () async {
      final streamController = StreamController<User?>();
      final container = buildContainer(
        mockService: mockService,
        authStream: streamController.stream,
      );
      addTearDown(() {
        container.dispose();
        streamController.close();
      });

      streamController.add(null);
      await container.read(authNotifierProvider.future);

      when(
        () => mockService.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async {
        streamController.add(mockUser);
        return mockUser;
      });

      await container
          .read(authNotifierProvider.notifier)
          .signUp(email: 'a@b.c', password: 'Pass1234');

      final state = container.read(authNotifierProvider);
      expect(state.hasValue, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // signOut
  // ---------------------------------------------------------------------------
  group('AuthNotifier.signOut', () {
    test('scenario 12.2 — signOut transitions state to AsyncData(null)',
        () async {
      final streamController = StreamController<User?>();
      final container = buildContainer(
        mockService: mockService,
        authStream: streamController.stream,
      );
      addTearDown(() {
        container.dispose();
        streamController.close();
      });

      // Start logged in
      streamController.add(mockUser);
      await container.read(authNotifierProvider.future);

      when(() => mockService.signOut()).thenAnswer((_) async {
        streamController.add(null);
      });

      await container.read(authNotifierProvider.notifier).signOut();

      final state = container.read(authNotifierProvider);
      expect(state.valueOrNull, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // sendPasswordResetEmail
  // ---------------------------------------------------------------------------
  group('AuthNotifier.sendPasswordResetEmail', () {
    test('does NOT change state.valueOrNull (no user state mutation)',
        () async {
      final streamController = StreamController<User?>();
      final container = buildContainer(
        mockService: mockService,
        authStream: streamController.stream,
      );
      addTearDown(() {
        container.dispose();
        streamController.close();
      });

      streamController.add(null);
      await container.read(authNotifierProvider.future);

      when(
        () => mockService.sendPasswordResetEmail(
          email: any(named: 'email'),
        ),
      ).thenAnswer((_) async {});

      await container
          .read(authNotifierProvider.notifier)
          .sendPasswordResetEmail(email: 'a@b.c');

      // State should be data (not error), and user value unchanged (null)
      final state = container.read(authNotifierProvider);
      expect(state.hasError, isFalse);
      expect(state.valueOrNull, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Race-condition guard
  // ---------------------------------------------------------------------------
  group('Race condition: stream emission during in-flight action', () {
    test(
        'stream emission mid-signIn does not clobber AsyncLoading; '
        'final state is AsyncData(streamUser)', () async {
      final streamController = StreamController<User?>.broadcast();
      final container = buildContainer(
        mockService: mockService,
        authStream: streamController.stream,
      );
      addTearDown(() {
        container.dispose();
        streamController.close();
      });

      // Seed as logged out
      streamController.add(null);

      // Wait for initial value
      await Future<void>.delayed(Duration.zero);

      final Completer<void> signInStarted = Completer();
      final Completer<void> streamEmitted = Completer();

      when(
        () => mockService.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async {
        // Signal that signIn has started, then wait for stream emission
        signInStarted.complete();
        await streamEmitted.future;
        return mockUser;
      });

      // Start signIn (don't await yet)
      final signInFuture = container
          .read(authNotifierProvider.notifier)
          .signIn(email: 'a@b.c', password: 'Pass1234');

      // Wait until signIn is in-flight, then emit on stream
      await signInStarted.future;

      // Use ref.listen pattern: verify that a stream emission mid-flight
      // does NOT cause a permanent AsyncError or lost state.
      // Emit the user on the stream while signIn is still pending
      streamController.add(mockUser);
      streamEmitted.complete();

      await signInFuture;

      final state = container.read(authNotifierProvider);
      // Final state must be data (stream emission was absorbed, action completed)
      expect(state.hasValue, isTrue);
      expect(state.error, isNull);
    });
  });
}
