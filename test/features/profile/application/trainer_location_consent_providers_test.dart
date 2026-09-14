import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/trainer_location.dart';
import 'package:treino/features/profile/application/trainer_location_consent_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

/// consentimiento-legal-versionado — R5.
///
/// Mirror de `onboarding_providers_test.dart`: `ProviderContainer` +
/// `userProfileProvider.overrideWith` con un `StreamController` fake, sin
/// Firebase real.
void main() {
  const loc = TrainerLocation(
    id: 'loc-1',
    type: TrainerLocationType.gym,
    gymId: 'gym-1',
    lat: -34.6,
    lng: -58.4,
    geohash: '69y7w',
  );

  UserProfile trainer({
    List<TrainerLocation> locations = const [loc],
    DateTime? consentAt,
    DateTime? promptedAt,
  }) =>
      UserProfile(
        uid: 'trainer-1',
        email: 'pf@test.com',
        displayName: 'Coach',
        role: UserRole.trainer,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        trainerLocations: locations,
        trainerLocationConsentAt: consentAt,
        trainerLocationConsentPromptedAt: promptedAt,
      );

  UserProfile athlete() => UserProfile(
        uid: 'athlete-1',
        email: 'athlete@test.com',
        displayName: 'Athlete',
        role: UserRole.athlete,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  late StreamController<UserProfile?> profiles;
  late ProviderContainer container;

  setUp(() {
    profiles = StreamController<UserProfile?>();
    container = ProviderContainer(
      overrides: [
        userProfileProvider.overrideWith((_) => profiles.stream),
      ],
    );
    // Mantiene el provider vivo entre rebuilds, como hace la app corriendo.
    container.listen(shouldAskTrainerLocationConsentProvider, (_, __) {});
  });

  tearDown(() {
    container.dispose();
    profiles.close();
  });

  group('shouldAskTrainerLocationConsentProvider — tabla de estados (D-B)', () {
    test('consentAt=null, promptedAt=null (nunca preguntado) ⇒ true', () async {
      profiles.add(trainer());
      await pumpEventQueue();

      expect(
        container.read(shouldAskTrainerLocationConsentProvider),
        isTrue,
      );
    });

    test('consentAt=set, promptedAt=set (otorgado) ⇒ false', () async {
      profiles.add(trainer(
        consentAt: DateTime.utc(2026, 2, 1),
        promptedAt: DateTime.utc(2026, 2, 1),
      ));
      await pumpEventQueue();

      expect(
        container.read(shouldAskTrainerLocationConsentProvider),
        isFalse,
      );
    });

    test(
        'consentAt=null, promptedAt=set (preguntado y no otorgado) ⇒ false '
        '— no reabre aunque trainerLocations siga no-vacío', () async {
      profiles.add(trainer(
        consentAt: null,
        promptedAt: DateTime.utc(2026, 2, 1),
      ));
      await pumpEventQueue();

      expect(
        container.read(shouldAskTrainerLocationConsentProvider),
        isFalse,
      );
    });

    test(
        'consentAt=set, promptedAt=null (imposible por construcción) ⇒ '
        'tratado como otorgado, false', () async {
      profiles.add(trainer(
        consentAt: DateTime.utc(2026, 2, 1),
        promptedAt: null,
      ));
      await pumpEventQueue();

      expect(
        container.read(shouldAskTrainerLocationConsentProvider),
        isFalse,
      );
    });
  });

  group('shouldAskTrainerLocationConsentProvider — otros gates', () {
    test('atleta ⇒ false sea cual sea el resto de los campos', () async {
      profiles.add(athlete());
      await pumpEventQueue();

      expect(
        container.read(shouldAskTrainerLocationConsentProvider),
        isFalse,
      );
    });

    test(
        'trainer sin ubicaciones (trainerLocations vacío) ⇒ false — nada '
        'que consentir', () async {
      profiles.add(trainer(locations: const []));
      await pumpEventQueue();

      expect(
        container.read(shouldAskTrainerLocationConsentProvider),
        isFalse,
      );
    });

    test('perfil aún no resuelto (null) ⇒ false', () async {
      profiles.add(null);
      await pumpEventQueue();

      expect(
        container.read(shouldAskTrainerLocationConsentProvider),
        isFalse,
      );
    });
  });

  group('trainerLocationConsentDismissedProvider', () {
    test('markDismissed suprime el gate en la misma sesión', () async {
      profiles.add(trainer());
      await pumpEventQueue();
      expect(
        container.read(shouldAskTrainerLocationConsentProvider),
        isTrue,
      );

      container
          .read(trainerLocationConsentDismissedProvider.notifier)
          .markDismissed();

      expect(
        container.read(shouldAskTrainerLocationConsentProvider),
        isFalse,
      );
    });

    test('un cambio de cuenta (uid distinto) resetea el dismissal', () async {
      profiles.add(trainer());
      await pumpEventQueue();
      container
          .read(trainerLocationConsentDismissedProvider.notifier)
          .markDismissed();
      expect(container.read(trainerLocationConsentDismissedProvider), isTrue);

      profiles.add(trainer().copyWith(uid: 'trainer-2'));
      await pumpEventQueue();

      expect(
        container.read(trainerLocationConsentDismissedProvider),
        isFalse,
      );
    });
  });
}
