// Regresión de `_conEsperaAcotada` (trainer_link_providers.dart:83-100),
// parte del fix del bug de caché fría (commit f7dbb4ef).
//
// `watchForAthlete` puede quedarse esperando al servidor para siempre (p.ej.
// sin red). Sin un límite, `currentAthleteLinkProvider` se colgaría en
// `AsyncLoading`, y hay consumidores que hacen `await ...future` adentro de
// un handler de usuario (`profile_share_toggle_tile.dart:47`,
// `invite_gate.dart:133`) — ahí eso es un control que se deshabilita y no se
// recupera nunca. `_conEsperaAcotada` acota esa espera a 8s con
// `Stream.timeout`, pero `Stream.timeout` reinicia su temporizador con CADA
// hueco y se redispara en cada uno — sin el flag `llegoAlgo`, un vínculo ya
// resuelto se borraría a los 8 segundos de quietud, que es el estado normal
// de un stream de Firestore ya asentado.
//
// Se usa `fake_async` (transitivo vía flutter_test — no está declarado en
// pubspec.yaml, por eso el analyzer marca un `info` de
// `depend_on_referenced_packages`; no es un error) para avanzar el reloj sin
// esperar 8s/20s reales.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/workout/application/session_providers.dart';

class _MockTrainerLinkRepository extends Mock
    implements TrainerLinkRepository {}

void main() {
  const athleteId = 'athlete-1';

  test(
    'si el server no contesta, a los 8s el provider resuelve en null '
    'en vez de colgarse',
    () {
      fakeAsync((async) {
        // Un stream que nunca emite y nunca se cierra: modela "sin red / el
        // server no contesta nunca".
        final controller = StreamController<List<TrainerLink>>();
        final repo = _MockTrainerLinkRepository();
        when(
          () => repo.watchForAthlete(any(), statuses: any(named: 'statuses')),
        ).thenAnswer((_) => controller.stream);

        final container = ProviderContainer(
          overrides: [
            currentUidProvider.overrideWithValue(athleteId),
            trainerLinkRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(() {
          controller.close();
          container.dispose();
        });

        // Mantiene vivo el provider autoDispose mientras esperamos.
        container.listen(currentAthleteLinkProvider, (_, __) {},
            fireImmediately: true);

        TrainerLink? resolved;
        var completed = false;
        container.read(currentAthleteLinkProvider.future).then((value) {
          completed = true;
          resolved = value;
        });

        // Antes de los 8s: el future TODAVÍA no debe resolver — si esto
        // fallara solo, no probaría nada del bug (probaría que el mock no
        // emite nada, que es lo esperado); el assert que importa es el de
        // abajo.
        async.elapse(const Duration(seconds: 7));
        expect(completed, isFalse,
            reason: 'no debería resolver antes de la ventana de espera');

        async.elapse(const Duration(seconds: 2)); // total: 9s > 8s

        expect(
          completed,
          isTrue,
          reason: 'el future no debe quedarse colgado esperando al servidor '
              'para siempre — a los 8s tiene que resolver igual',
        );
        expect(resolved, isNull);
      });
    },
  );

  test(
    'un vínculo ya emitido NO se borra a los 8 segundos de quietud',
    () {
      fakeAsync((async) {
        final controller = StreamController<List<TrainerLink>>();
        final repo = _MockTrainerLinkRepository();
        when(
          () => repo.watchForAthlete(any(), statuses: any(named: 'statuses')),
        ).thenAnswer((_) => controller.stream);

        final container = ProviderContainer(
          overrides: [
            currentUidProvider.overrideWithValue(athleteId),
            trainerLinkRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(() {
          controller.close();
          container.dispose();
        });

        container.listen(currentAthleteLinkProvider, (_, __) {},
            fireImmediately: true);

        final link = TrainerLink(
          id: 'link-1',
          trainerId: 'trainer-1',
          athleteId: athleteId,
          status: TrainerLinkStatus.active,
          requestedAt: DateTime.utc(2026, 1, 1),
        );

        TrainerLink? resolved;
        container.read(currentAthleteLinkProvider.future).then((value) {
          resolved = value;
        });

        controller.add([link]);
        async.flushMicrotasks();

        expect(resolved, isNotNull,
            reason: 'setup: el vínculo tiene que haber llegado antes de '
                'poder probar que no se borra');
        expect(resolved!.id, link.id);

        // CONTROL NEGATIVO del flag `llegoAlgo`: 20s de silencio del server
        // (más de dos ventanas de 8s) sin ningún evento nuevo.
        async.elapse(const Duration(seconds: 20));

        final current = container.read(currentAthleteLinkProvider);
        expect(
          current.value,
          isNotNull,
          reason: 'Stream.timeout se redispara en cada hueco de 8s; sin el '
              'flag llegoAlgo esto se pisa con null aunque el vínculo real '
              'siga vigente',
        );
        expect(current.value!.id, link.id);
      });
    },
  );
}
