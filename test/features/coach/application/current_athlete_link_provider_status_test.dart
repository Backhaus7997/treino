// Regresión de QA-COA-001 (CRITICAL, bug-app CONFIRMED).
//
// `currentAthleteLinkProvider` (lib/features/coach/application/trainer_link_providers.dart:47-56)
// filtra `listForAthlete(uid, statuses: {TrainerLinkStatus.active})` — SOLO
// active. Toda la UI del atleta (card "SOLICITUD ENVIADA" + cancelar, card
// "VÍNCULO PAUSADO" + terminar, y el guard anti-duplicados del CTA
// "PEDIR VÍNCULO") depende de que ese MISMO provider emita también `pending`
// y `paused`. Con el filtro active-only, un link pending/paused hace que el
// provider emita `null` → la vista renderiza discovery de nuevo → el atleta
// puede disparar solicitudes duplicadas ilimitadas y un vínculo pausado queda
// invisible.
//
// Estos tests siembran links reales en FakeFirebaseFirestore (SIN overridear el
// provider — así ejercitan el filtro real del repo→provider, que es donde vive
// el bug) y assertan el comportamiento CORRECTO: el provider EXPONE el link
// pending / paused. Contra el código actual devuelven `null`, así que fallarían;
// van marcados con `skip`. Cuando se amplíe el set de statuses a
// {pending, active, paused} (fix sugerido en el finding), basta con quitar el
// skip para tener la prueba ejecutable en verde.
//
// El test de control (link active) NO lleva skip: documenta el happy-path que
// hoy YA funciona y ancla que el seeding vía repo es correcto.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
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
    // Repo apuntando a la MISMA fake que consume el provider bajo prueba.
    seedRepo = TrainerLinkRepository(firestore: fakeFirestore);
  });

  // Siembra la transición pending → active directamente sobre la fake.
  //
  // `TrainerLinkRepository.accept()` ya no existe: la transición se movió a la
  // Cloud Function `acceptTrainerLink` (paywall Fase 7, PR4) porque desde el
  // cliente el límite de alumnos era inaplicable. Esa CF no corre contra
  // FakeFirebaseFirestore, y acá no hace falta: estos tests ejercitan el FILTRO
  // DE STATUS del provider, no la transición. Lo que se necesita es el ESTADO.
  //
  // La forma escrita es la misma que dejaba el método viejo y sigue dejando la
  // CF: `status: 'active'` + `acceptedAt`.
  Future<void> seedAccepted(String linkId) async {
    await fakeFirestore.collection('trainer_links').doc(linkId).update({
      'status': TrainerLinkStatusX(TrainerLinkStatus.active).toJson(),
      'acceptedAt': Timestamp.fromDate(DateTime.now().toUtc()),
    });
  }

  // Container con la fake Firestore inyectada y el uid del atleta forzado, de
  // modo que `currentAthleteLinkProvider` (que lee `currentUidProvider` +
  // `firestoreProvider` internamente) resuelva contra los datos sembrados.
  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentUidProvider.overrideWithValue(athleteId),
      ],
    );
    addTearDown(container.dispose);
    // Mantiene viva la suscripción del provider autoDispose mientras leemos
    // `.future`.
    container.listen(currentAthleteLinkProvider, (_, __) {},
        fireImmediately: true);
    return container;
  }

  group('currentAthleteLinkProvider — expone todos los estados vivos', () {
    // CONTROL (sin skip): el happy-path active ya funciona hoy. Ancla que el
    // seeding vía repo produce un doc que el provider sabe leer.
    test('link active → el provider lo expone (happy path, verde hoy)',
        () async {
      final link = await seedRepo.request(
        trainerId: trainerId,
        athleteId: athleteId,
      );
      await seedAccepted(link.id); // pending → active

      final container = makeContainer();
      final result = await container.read(currentAthleteLinkProvider.future);

      expect(result, isNotNull);
      expect(result!.status, TrainerLinkStatus.active);
      expect(result.athleteId, athleteId);
    });

    // Comportamiento CORRECTO: con una solicitud pending, el provider debe
    // exponerla para que la vista muestre "SOLICITUD ENVIADA" y el CTA quede
    // deshabilitado (guard anti-duplicados). Hoy el filtro active-only la
    // descarta y el provider emite null → FALLA.
    test(
      'link pending → el provider lo expone (no null)',
      () async {
        // request() crea el doc con status=pending.
        await seedRepo.request(trainerId: trainerId, athleteId: athleteId);

        final container = makeContainer();
        final TrainerLink? result =
            await container.read(currentAthleteLinkProvider.future);

        expect(result, isNotNull,
            reason: 'un vínculo pending debe seguir siendo el "vínculo actual" '
                'del atleta; si el provider lo oculta, la card "SOLICITUD '
                'ENVIADA" es inalcanzable y el guard anti-duplicados muere');
        expect(result!.status, TrainerLinkStatus.pending);
      },
      skip: 'QA-COA-001: bug confirmado — currentAthleteLinkProvider filtra '
          'statuses:{active}; el fix amplía a {pending,active,paused}. '
          'Quitar el skip cuando se corrija.',
    );

    // Comportamiento CORRECTO: un vínculo pausado por el PF debe seguir siendo
    // el vínculo actual del atleta, para mostrar "VÍNCULO PAUSADO" +
    // "TERMINAR VÍNCULO" y evitar que pida un segundo PF (invariante MVP: un
    // solo PF a la vez). Hoy el provider active-only emite null → FALLA.
    test(
      'link paused → el provider lo expone (no null)',
      () async {
        final link = await seedRepo.request(
          trainerId: trainerId,
          athleteId: athleteId,
        );
        await seedAccepted(link.id); // pending → active
        await seedRepo.pause(link.id); // active → paused

        final container = makeContainer();
        final TrainerLink? result =
            await container.read(currentAthleteLinkProvider.future);

        expect(result, isNotNull,
            reason: 'un vínculo paused debe exponerse para que el atleta vea '
                'la card de vínculo pausado y no vuelva al discovery');
        expect(result!.status, TrainerLinkStatus.paused);
      },
      skip: 'QA-COA-001: bug confirmado — currentAthleteLinkProvider descarta '
          'paused (filtra statuses:{active}). Quitar el skip cuando se corrija.',
    );
  });
}
