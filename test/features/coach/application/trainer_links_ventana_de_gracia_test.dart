import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/workout/application/session_providers.dart';

import '../../../helpers/trainer_links.dart';

class _MockTrainerLinkRepository extends Mock
    implements TrainerLinkRepository {}

void main() {
  // El PF: «cuando entro a la sección de alumnos hay como un parpadeo en los
  // componentes».
  //
  // La causa no estaba en la pantalla sino en el ciclo de vida del provider.
  // Con `autoDispose` pelado, SALIR de Alumnos lo destruía, y volver arrancaba
  // en `AsyncLoading` sin valor: esqueleto → cross-fade del
  // `TreinoStateSwitcher` → Firestore resolvía de caché en un frame →
  // segundo cross-fade → los cuatro `TreinoFadeSlideIn` escalonados. En CADA
  // entrada, no sólo en la primera.
  group('trainerLinksStreamProvider — ventana de gracia', () {
    late _MockTrainerLinkRepository repo;

    setUp(() {
      repo = _MockTrainerLinkRepository();
      when(() => repo.watchForTrainer(any()))
          .thenAnswer((_) => Stream.value(const <TrainerLink>[]));
    });

    ProviderContainer _container() => ProviderContainer(
          overrides: [
            currentUidProvider.overrideWithValue('trainer-1'),
            trainerLinkRepositoryProvider.overrideWithValue(repo),
          ],
        );

    test('soltar al último oyente NO tira el valor', () async {
      final container = _container();
      addTearDown(container.dispose);

      // Entra a la sección: se suscribe y llega el primer valor.
      final sub = container.listen(
        trainerLinksStreamProvider,
        (_, __) {},
        fireImmediately: true,
      );
      await container.read(trainerLinksStreamProvider.future);
      expect(container.read(trainerLinksStreamProvider).hasValue, isTrue);

      // Se va de la sección: no queda nadie escuchando.
      sub.close();
      await Future<void>.delayed(Duration.zero);

      // Vuelve. ÉSTE es el assert: encuentra el valor puesto, no un
      // `AsyncLoading`. Sin la ventana de gracia acá había `isLoading` y la
      // pantalla dibujaba el esqueleto de nuevo.
      final alVolver = container.read(trainerLinksStreamProvider);
      expect(
        alVolver.hasValue,
        isTrue,
        reason: 'volver a la sección no puede costar una recarga',
      );
      expect(alVolver.isLoading, isFalse);
    });

    test('y el repositorio se consulta UNA sola vez', () async {
      final container = _container();
      addTearDown(container.dispose);

      final sub = container.listen(
        trainerLinksStreamProvider,
        (_, __) {},
        fireImmediately: true,
      );
      await container.read(trainerLinksStreamProvider.future);
      sub.close();
      await Future<void>.delayed(Duration.zero);

      // Segunda entrada.
      container.listen(trainerLinksStreamProvider, (_, __) {},
          fireImmediately: true);
      await Future<void>.delayed(Duration.zero);

      // Un solo `watchForTrainer`: la segunda entrada reusa el stream vivo en
      // vez de abrir otro listener contra Firestore.
      verify(() => repo.watchForTrainer('trainer-1')).called(1);
    });
  });

  // #1695: el gate de «¿se le puede asignar algo a este alumno?». Lo que no
  // puede pasar nunca es contestar `false` (= «ya no es tuyo») por NO SABER:
  // le apagaría la acción a un PF con el vínculo vivo.
  group('alumnoConVinculoVivoProvider', () {
    Future<AsyncValue<bool>> consultar(
      String? uid,
      Stream<List<TrainerLink>> links, {
      String athleteId = 'a1',
    }) async {
      final repo = _MockTrainerLinkRepository();
      when(() => repo.watchForTrainer(any())).thenAnswer((_) => links);
      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWithValue(uid),
        trainerLinkRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      final provider = alumnoConVinculoVivoProvider(athleteId);
      container.listen(provider, (_, __) {}, fireImmediately: true);
      await Future<void>.delayed(Duration.zero);
      return container.read(provider);
    }

    test('`active` y `paused` con ESE alumno dan true; el resto, false',
        () async {
      Future<bool?> con(TrainerLinkStatus s, [String athlete = 'a1']) async =>
          (await consultar(
            'trainer-1',
            Stream.value([linkDe(athlete, status: s)]),
          ))
              .valueOrNull;

      expect(await con(TrainerLinkStatus.active), isTrue);
      expect(await con(TrainerLinkStatus.terminated), isFalse); // ex-alumno
      expect(await con(TrainerLinkStatus.paused), isTrue); // hold, no corte
      expect(await con(TrainerLinkStatus.pending), isFalse);
      expect(await con(TrainerLinkStatus.active, 'otro'), isFalse);
      expect(await con(TrainerLinkStatus.paused, 'otro'), isFalse);
      // Re-vinculado: el link terminado viejo no le gana al activo nuevo.
      final reVinculado = await consultar(
          'trainer-1',
          Stream.value([
            linkDe('a1', status: TrainerLinkStatus.terminated),
            linkDe('a1'),
          ]));
      expect(reVinculado.valueOrNull, isTrue);
    });

    test('sin uid o sin datos del roster: loading, NO false', () async {
      final sinUid = await consultar(null, Stream.value([linkDe('a1')]));
      expect(sinUid.isLoading, isTrue);
      expect(sinUid.valueOrNull, isNull);

      final sinRoster = await consultar('trainer-1', const Stream.empty());
      expect(sinRoster.isLoading, isTrue);
      expect(sinRoster.valueOrNull, isNull);
    });

    test('si el roster falla antes de traer datos: error, NO false', () async {
      final fallo = await consultar(
        'trainer-1',
        Stream<List<TrainerLink>>.error(StateError('boom')),
      );
      expect(fallo.hasError, isTrue);
      expect(fallo.valueOrNull, isNull);
    });
  });
}
