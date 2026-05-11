import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// --- Mocks ---
class MockUser extends Mock implements User {}

class MockUserRepository extends Mock implements UserRepository {}

ProviderContainer makeContainer({
  required Stream<User?> authStream,
  required UserRepository repo,
}) {
  return ProviderContainer(
    overrides: [
      authStateChangesProvider.overrideWith((ref) => authStream),
      userRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

/// Drain microtasks + any pending timers so StreamProviders resolve.
Future<void> pumpProviders() async {
  await Future<void>.delayed(const Duration(milliseconds: 200));
}

void main() {
  final fixedDt = DateTime.utc(2026, 5, 11, 13, 30);

  UserProfile makeProfile(String uid) => UserProfile(
        uid: uid,
        email: '$uid@test.com',
        displayName: 'User $uid',
        role: UserRole.athlete,
        createdAt: fixedDt,
        updatedAt: fixedDt,
      );

  group('userProfileProvider', () {
    // SCENARIO-025: anonymous stream → AsyncData(null)
    test('SCENARIO-025: null auth stream emits AsyncData(null)', () async {
      final repo = MockUserRepository();
      final container = makeContainer(
        authStream: Stream.value(null),
        repo: repo,
      );
      addTearDown(container.dispose);

      // Subscribe to force the provider to start
      final sub = container.listen(userProfileProvider, (_, __) {});
      addTearDown(sub.close);

      await pumpProviders();

      final state = container.read(userProfileProvider);
      expect(state, equals(const AsyncData<UserProfile?>(null)));
    });

    // SCENARIO-026: authed user → provider emits AsyncData(profile)
    test('SCENARIO-026: authed user emits AsyncData(UserProfile)', () async {
      final mockUser = MockUser();
      when(() => mockUser.uid).thenReturn('u1');

      final profile = makeProfile('u1');
      final repo = MockUserRepository();
      when(() => repo.watch('u1')).thenAnswer((_) => Stream.value(profile));

      final container = makeContainer(
        authStream: Stream.value(mockUser),
        repo: repo,
      );
      addTearDown(container.dispose);

      final sub = container.listen(userProfileProvider, (_, __) {});
      addTearDown(sub.close);

      await pumpProviders();

      final state = container.read(userProfileProvider);
      expect(state, isA<AsyncData<UserProfile?>>());
      expect(state.value?.uid, equals('u1'));
    });

    // SCENARIO-027: sign-out transition: user then null → profile then null
    test('SCENARIO-027: sign-out clears profile to AsyncData(null)', () async {
      final mockUser = MockUser();
      when(() => mockUser.uid).thenReturn('u2');

      final profile = makeProfile('u2');
      final repo = MockUserRepository();
      when(() => repo.watch('u2')).thenAnswer((_) => Stream.value(profile));

      final authController = StreamController<User?>.broadcast();
      final container = makeContainer(
        authStream: authController.stream,
        repo: repo,
      );
      addTearDown(container.dispose);
      addTearDown(authController.close);

      final sub = container.listen(userProfileProvider, (_, __) {});
      addTearDown(sub.close);

      authController.add(mockUser);
      await pumpProviders();

      final stateBefore = container.read(userProfileProvider);
      expect(stateBefore.value?.uid, equals('u2'));

      authController.add(null);
      await pumpProviders();

      final stateAfter = container.read(userProfileProvider);
      expect(stateAfter, equals(const AsyncData<UserProfile?>(null)));
    });
  });
}
