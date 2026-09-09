import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/workout/application/session_providers.dart';

class _MockTrainerLinkRepository extends Mock implements TrainerLinkRepository {}

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
}
