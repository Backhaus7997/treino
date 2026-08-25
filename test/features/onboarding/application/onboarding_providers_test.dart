import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/onboarding/application/onboarding_providers.dart';
import 'package:treino/features/onboarding/domain/onboarding_surface.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

UserProfile _profile(String uid) => UserProfile(
      uid: uid,
      email: '$uid@test.com',
      displayName: uid,
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Cobertura a nivel PROVIDER del scope de `onboardingDismissedProvider`.
///
/// `onboarding_gate_test` ya cubre el caso de punta a punta ("a SECOND account
/// on the same device still gets its tour"); esto ejercita el mismo contrato un
/// nivel más abajo, y sobre todo el **race guard**, que el gate no toca: el
/// `select` sobre el uid existe para que las re-emisiones del MISMO usuario no
/// vacíen el set. Sin esa mitad, `markSeen` —que escribe en `users/{uid}` y por
/// lo tanto provoca una re-emisión del perfil— resucitaría el tour que el
/// usuario acaba de cerrar, en la misma sesión.
void main() {
  group('onboardingDismissedProvider — scope', () {
    test('a new sign-in does not inherit the previous dismissals', () async {
      // El root scope sobrevive al sign-out. Sin el watch del uid, un atleta
      // que cerró sesión sin matar la app dejaba al siguiente sin poder ver un
      // tour que su propio documento dice que nunca vio.
      final profiles = StreamController<UserProfile?>();
      addTearDown(profiles.close);

      final container = ProviderContainer(
        overrides: [
          userProfileProvider.overrideWith((_) => profiles.stream),
        ],
      );
      addTearDown(container.dispose);
      // Mantiene el provider vivo entre rebuilds, como hace la app corriendo.
      container.listen(onboardingDismissedProvider, (_, __) {});

      profiles.add(_profile('athlete-a'));
      await pumpEventQueue();

      container.read(onboardingDismissedProvider.notifier).state = {
        OnboardingSurface.templatesAthleteMobile,
      };
      expect(container.read(onboardingDismissedProvider), isNotEmpty);

      profiles.add(null);
      await pumpEventQueue();
      profiles.add(_profile('athlete-b'));
      await pumpEventQueue();

      expect(
        container.read(onboardingDismissedProvider),
        isEmpty,
        reason: 'B nunca descartó nada',
      );
    });

    test('the same user re-emitting keeps their dismissals', () async {
      // El stream del perfil re-emite por razones que NO son un cambio de
      // persona — el propio `markSeen` es una de ellas, porque escribe en
      // `users/{uid}`. Resetear en esas resucitaría un tour recién cerrado.
      final profiles = StreamController<UserProfile?>();
      addTearDown(profiles.close);

      final container = ProviderContainer(
        overrides: [
          userProfileProvider.overrideWith((_) => profiles.stream),
        ],
      );
      addTearDown(container.dispose);
      container.listen(onboardingDismissedProvider, (_, __) {});

      profiles.add(_profile('athlete-a'));
      await pumpEventQueue();

      container.read(onboardingDismissedProvider.notifier).state = {
        OnboardingSurface.templatesAthleteMobile,
      };

      // Otra instancia de UserProfile con el MISMO uid.
      profiles.add(_profile('athlete-a').copyWith(displayName: 'renombrado'));
      await pumpEventQueue();

      expect(
        container.read(onboardingDismissedProvider),
        {OnboardingSurface.templatesAthleteMobile},
      );
    });
  });
}
