import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/router.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/domain/trainer_location.dart';
import 'package:treino/features/profile/application/account_deletion_notifier.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// ignore_for_file: avoid_dynamic_calls

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

class _LoadingAuthNotifier extends AuthNotifier {
  @override
  Future<User?> build() => Completer<User?>().future;
}

// ---------------------------------------------------------------------------
// Profile fixtures
// ---------------------------------------------------------------------------

final DateTime _kDate = DateTime.utc(2026, 1, 1);

UserProfile _athleteProfile() => UserProfile(
      uid: 'athlete-uid',
      email: 'athlete@example.com',
      displayName: 'sporty',
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

UserProfile _trainerIncomplete() => UserProfile(
      uid: 'trainer-uid',
      email: 'trainer@example.com',
      displayName: 'pf-mauro',
      role: UserRole.trainer,
      createdAt: _kDate,
      updatedAt: _kDate,
      trainerBio: null, // incomplete — bio missing
    );

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
      trainerLocations: const [],
      trainerOffersOnline: true,
    );

UserProfile _trainerNoDisplayName() => UserProfile(
      uid: 'trainer-uid',
      email: 'trainer@example.com',
      displayName: null, // profile-setup not done
      role: UserRole.trainer,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

final TrainerLocation _kLocation = TrainerLocation(
  id: 'loc-1',
  type: TrainerLocationType.custom,
  customLabel: 'My Studio',
  lat: -31.4,
  lng: -64.1,
  geohash: 'abc12',
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
      accountDeletionInFlightProvider
          .overrideWith((ref) => deletionInFlight),
    ],
  );
}

ProviderContainer _loadingContainer() => ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(() => _LoadingAuthNotifier()),
        userProfileProvider
            .overrideWith((ref) => Stream<UserProfile?>.value(null)),
      ],
    );

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
}
