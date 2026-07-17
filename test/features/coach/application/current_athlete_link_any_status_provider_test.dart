// Regresión de QA-COA-001 (CRITICAL, bug-app CONFIRMED).
//
// `currentAthleteLinkProvider` filtra solo `active`, pero la vista de coach del
// atleta (card "SOLICITUD ENVIADA" / "VÍNCULO PAUSADO" + el guard anti-duplicados
// del CTA "PEDIR VÍNCULO") necesita ver también `pending` y `paused`. Con el
// provider active-only, un link pending/paused emitía `null` → la vista caía a
// discovery, la card quedaba muerta y el guard permitía solicitudes duplicadas.
//
// El fix agrega `currentAthleteLinkAnyStatusProvider` (pending/active/paused)
// para esos consumidores, dejando `currentAthleteLinkProvider` (active-only)
// intacto para chat/reviews/mi_cuota/agenda/workout.
//
// Estos tests siembran links reales en FakeFirebaseFirestore (sin overridear el
// provider — ejercitan el filtro real repo→provider) y verifican que el provider
// nuevo EXPONE pending/paused mientras el active-only sigue devolviendo null
// para esos estados (no le cambiamos la semántica).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late TrainerLinkRepository seedRepo;

  const athleteId = 'athlete-1';
  const trainerId = 'trainer-1';

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    seedRepo = TrainerLinkRepository(firestore: fakeFirestore);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentUidProvider.overrideWithValue(athleteId),
      ],
    );
    addTearDown(container.dispose);
    // Keep both autoDispose providers alive while we read `.future`.
    container.listen(currentAthleteLinkProvider, (_, __) {},
        fireImmediately: true);
    container.listen(currentAthleteLinkAnyStatusProvider, (_, __) {},
        fireImmediately: true);
    return container;
  }

  group('currentAthleteLinkAnyStatusProvider — QA-COA-001', () {
    test('expone un link PENDING (y el active-only sigue devolviendo null)',
        () async {
      await seedRepo.request(trainerId: trainerId, athleteId: athleteId);
      final container = makeContainer();

      final anyStatus =
          await container.read(currentAthleteLinkAnyStatusProvider.future);
      expect(anyStatus, isNotNull);
      expect(anyStatus!.status, TrainerLinkStatus.pending);
      expect(anyStatus.trainerId, trainerId);

      final activeOnly =
          await container.read(currentAthleteLinkProvider.future);
      expect(activeOnly, isNull,
          reason: 'currentAthleteLinkProvider conserva su semántica active-only');
    });

    test('expone un link PAUSED (y el active-only devuelve null)', () async {
      final link =
          await seedRepo.request(trainerId: trainerId, athleteId: athleteId);
      await seedRepo.accept(link.id);
      await seedRepo.pause(link.id);
      final container = makeContainer();

      final anyStatus =
          await container.read(currentAthleteLinkAnyStatusProvider.future);
      expect(anyStatus, isNotNull);
      expect(anyStatus!.status, TrainerLinkStatus.paused);

      final activeOnly =
          await container.read(currentAthleteLinkProvider.future);
      expect(activeOnly, isNull);
    });

    test('expone un link ACTIVE (ambos providers lo ven)', () async {
      final link =
          await seedRepo.request(trainerId: trainerId, athleteId: athleteId);
      await seedRepo.accept(link.id);
      final container = makeContainer();

      final anyStatus =
          await container.read(currentAthleteLinkAnyStatusProvider.future);
      final activeOnly =
          await container.read(currentAthleteLinkProvider.future);

      expect(anyStatus?.status, TrainerLinkStatus.active);
      expect(activeOnly?.status, TrainerLinkStatus.active);
    });

    test('devuelve null si el único link está TERMINATED', () async {
      final link =
          await seedRepo.request(trainerId: trainerId, athleteId: athleteId);
      await seedRepo.cancel(link.id); // pending -> terminated
      final container = makeContainer();

      final anyStatus =
          await container.read(currentAthleteLinkAnyStatusProvider.future);
      expect(anyStatus, isNull,
          reason: 'terminated no es un vínculo vivo → no se muestra card');
    });
  });
}
