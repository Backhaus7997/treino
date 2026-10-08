// Quién acota la espera, y por qué NO es el provider.
//
// La primera versión del fix de caché fría metía la espera adentro de
// `currentAthleteLinkProvider`: a los 8s emitía la lista vacía. Eso convertía
// un timeout en una ausencia CONFIRMADA — `AthleteCoachView` mandaba a
// discovery a un alumno vinculado, el entitlement le sacaba el acceso derivado
// del Coach, y los `.future` resolvían con "no hay vínculo". O sea el bug
// original entrando por otra puerta. Lo encontró Codex en el PR #1109.
//
// El contrato quedó así:
//   - el provider NO acota nada. `AsyncLoading` significa "todavía no sé", y
//     `AsyncData(null)` significa "el SERVIDOR dijo que no hay vínculo activo".
//     Nunca "nos cansamos de esperar".
//   - la acotan los DOS consumidores que no pueden colgarse, los que hacen
//     `await ...future` adentro de un handler de usuario
//     (`profile_share_toggle_tile.dart`, `invite_gate.dart`), porque ahí sí se
//     puede representar "no pude confirmar" sin mentirle a nadie más.
//   - y la UI del gate (`_EsperandoVinculo` en `router.dart`) le pone plazo al
//     spinner, para que "honesto" no signifique "pared".
//
// `fake_async` avanza el reloj sin esperar 8s/20s reales.

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

/// Arma un container con un repo cuyo `watchForAthlete` devuelve [stream].
({ProviderContainer container, StreamController<List<TrainerLink>> ctrl})
    _armar() {
  final ctrl = StreamController<List<TrainerLink>>();
  final repo = _MockTrainerLinkRepository();
  when(() => repo.watchForAthlete(any(), statuses: any(named: 'statuses')))
      .thenAnswer((_) => ctrl.stream);
  final container = ProviderContainer(
    overrides: [
      currentUidProvider.overrideWithValue('athlete-1'),
      trainerLinkRepositoryProvider.overrideWithValue(repo),
    ],
  );
  container.listen(currentAthleteLinkProvider, (_, __) {},
      fireImmediately: true);
  return (container: container, ctrl: ctrl);
}

TrainerLink _link() => TrainerLink(
      id: 'link-1',
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 9, 1),
    );

void main() {
  test(
    'si el server no contesta, el provider NO resuelve: AsyncData(null) está '
    'reservado para una respuesta del servidor',
    () {
      fakeAsync((async) {
        final (:container, :ctrl) = _armar();

        var completo = false;
        container
            .read(currentAthleteLinkProvider.future)
            .then((_) => completo = true);

        // Mucho más que la espera de los consumidores.
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        expect(completo, isFalse,
            reason: 'un timeout no puede publicarse como "no tenés vínculo"');
        expect(container.read(currentAthleteLinkProvider).isLoading, isTrue);

        ctrl.close();
        container.dispose();
      });
    },
  );

  test(
    'cuando el server contesta, emite el vínculo y ahí sí resuelve',
    () {
      fakeAsync((async) {
        final (:container, :ctrl) = _armar();

        TrainerLink? resuelto;
        container
            .read(currentAthleteLinkProvider.future)
            .then((v) => resuelto = v);

        ctrl.add([_link()]);
        async.flushMicrotasks();

        expect(resuelto?.trainerId, 'trainer-1');

        // Y no se pisa con el paso del tiempo: el provider no tiene ningún
        // temporizador que pueda redispararse sobre un valor ya asentado.
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(
            container.read(currentAthleteLinkProvider).valueOrNull, isNotNull);

        ctrl.close();
        container.dispose();
      });
    },
  );

  test(
    'el CONSUMIDOR acota la espera: .timeout sobre .future cae en null a los 8s',
    () {
      // Es exactamente lo que hacen `profile_share_toggle_tile.dart` e
      // `invite_gate.dart`. Sin esto, un handler con `_busy` puesto quedaría
      // muerto para siempre — que es el motivo por el que la espera existía, y
      // el que hay que seguir cubriendo ahora que se mudó de capa.
      fakeAsync((async) {
        final (:container, :ctrl) = _armar();

        Object? resultado = #sinResolver;
        container
            .read(currentAthleteLinkProvider.future)
            .timeout(kEsperaDelServidorDeVinculo, onTimeout: () => null)
            .then((v) => resultado = v);

        async.elapse(kEsperaDelServidorDeVinculo + const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(resultado, isNull);

        ctrl.close();
        container.dispose();
      });
    },
  );
}
