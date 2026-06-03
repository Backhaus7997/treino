import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/notifications/application/notification_providers.dart';
import 'package:treino/features/notifications/data/fcm_service.dart';
import 'package:treino/features/notifications/data/fcm_token_repository.dart';

class MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

class MockFcmTokenRepository extends Mock implements FcmTokenRepository {}

class MockFcmService extends Mock implements FcmService {}

class MockUser extends Mock implements User {}

void main() {
  late MockFcmService mockFcmService;
  late MockUser mockUser;

  setUp(() {
    mockFcmService = MockFcmService();
    mockUser = MockUser();
    when(() => mockUser.uid).thenReturn('uid-test-user');
    when(() => mockFcmService.init(any())).thenAnswer((_) async {});
    when(() => mockFcmService.dispose(any())).thenAnswer((_) async {});
  });

  /// Builds a [ProviderContainer] that overrides:
  /// - [authStateChangesProvider] with a controllable stream.
  /// - [fcmServiceProvider] with [mockFcmService].
  (ProviderContainer, StreamController<User?>) buildContainer() {
    final authController = StreamController<User?>.broadcast();
    final container = ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith(
          (ref) => authController.stream,
        ),
        fcmServiceProvider.overrideWithValue(mockFcmService),
      ],
    );
    // Eagerly read fcmLifecycleProvider so the ref.listen is registered.
    container.read(fcmLifecycleProvider);
    return (container, authController);
  }

  group('fcmLifecycleProvider', () {
    // SCENARIO-650: auth emits non-null user → FcmService.init(uid) called
    test(
      'SCENARIO-650: authStateChangesProvider emits non-null user → init called',
      () async {
        final (container, authController) = buildContainer();
        addTearDown(container.dispose);
        addTearDown(authController.close);

        authController.add(mockUser);
        // Allow provider graph to process.
        await Future<void>.delayed(Duration.zero);

        verify(() => mockFcmService.init('uid-test-user')).called(1);
      },
    );

    // SCENARIO-651: auth emits null after sign-in → FcmService.dispose(prev uid)
    test(
      'SCENARIO-651: authStateChangesProvider emits null after user → '
      'dispose called with previous uid',
      () async {
        final (container, authController) = buildContainer();
        addTearDown(container.dispose);
        addTearDown(authController.close);

        // Sign in first.
        authController.add(mockUser);
        await Future<void>.delayed(Duration.zero);

        // Then sign out.
        authController.add(null);
        await Future<void>.delayed(Duration.zero);

        verify(() => mockFcmService.dispose('uid-test-user')).called(1);
      },
    );

    // SCENARIO-683: foreground handler not attached before user is authenticated
    test(
      'SCENARIO-683: no init called when auth stream emits null (no user) — '
      'no crash, no navigation',
      () async {
        final (container, authController) = buildContainer();
        addTearDown(container.dispose);
        addTearDown(authController.close);

        // Only null emitted — no user, no init.
        authController.add(null);
        await Future<void>.delayed(Duration.zero);

        verifyNever(() => mockFcmService.init(any()));
        verifyNever(() => mockFcmService.dispose(any()));
      },
    );
  });
}
