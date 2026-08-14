import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/onboarding/application/onboarding_providers.dart';
import 'package:treino/features/onboarding/domain/onboarding_surface.dart';

class _MockUser extends Mock implements User {}

User _user(String uid) {
  final user = _MockUser();
  when(() => user.uid).thenReturn(uid);
  return user;
}

void main() {
  group('onboardingDismissedProvider — scope', () {
    test('a new sign-in does not inherit the previous dismissals', () async {
      // The root scope outlives a sign-out. Without the uid watch, an athlete
      // who signed out without killing the app left the next one unable to see
      // a tour their own document says they never saw.
      final auth = StreamController<User?>();
      addTearDown(auth.close);

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((_) => auth.stream),
        ],
      );
      addTearDown(container.dispose);
      // Keeps the provider alive across rebuilds, as the running app does.
      container.listen(onboardingDismissedProvider, (_, __) {});

      auth.add(_user('athlete-a'));
      await container.read(authStateChangesProvider.future);

      container.read(onboardingDismissedProvider.notifier).state = {
        OnboardingSurface.templatesAthleteMobile,
      };
      expect(container.read(onboardingDismissedProvider), isNotEmpty);

      auth.add(null);
      await pumpEventQueue();
      auth.add(_user('athlete-b'));
      await pumpEventQueue();

      expect(
        container.read(onboardingDismissedProvider),
        isEmpty,
        reason: 'B never dismissed anything',
      );
    });

    test('the same user re-emitting keeps their dismissals', () async {
      // `authStateChanges` re-emits for reasons that are not a change of
      // person — a token refresh among them. Resetting on those would
      // resurrect a tour the user just closed, mid-session.
      final auth = StreamController<User?>();
      addTearDown(auth.close);

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((_) => auth.stream),
        ],
      );
      addTearDown(container.dispose);
      container.listen(onboardingDismissedProvider, (_, __) {});

      auth.add(_user('athlete-a'));
      await container.read(authStateChangesProvider.future);

      container.read(onboardingDismissedProvider.notifier).state = {
        OnboardingSurface.templatesAthleteMobile,
      };

      // A DIFFERENT User instance carrying the SAME uid.
      auth.add(_user('athlete-a'));
      await pumpEventQueue();

      expect(
        container.read(onboardingDismissedProvider),
        {OnboardingSurface.templatesAthleteMobile},
      );
    });
  });
}
