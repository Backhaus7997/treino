import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

class _MockRepo extends Mock implements UserPublicProfileRepository {}

class _MockUser extends Mock implements User {}

void main() {
  // Hermano de `trainer_links_ventana_de_gracia_test.dart` (#1058).
  //
  // #1058 le puso la ventana de gracia al provider de LINKS y cerró el issue
  // del parpadeo. Pero la pantalla de Alumnos mira DOS asyncs, y el segundo
  // —el batch de perfiles— quedó `autoDispose` pelado. Salir y volver seguía
  // costando un ciclo `loading -> data` completo, con su cross-fade encima.
  // Medido en producción después de #1058: 3 entradas de 3, con caché
  // caliente.
  group('userPublicProfilesBatchProvider — ventana de gracia', () {
    late _MockRepo repo;
    const key = 'a1,a2';

    setUp(() {
      repo = _MockRepo();
      when(() => repo.getByIds(any())).thenAnswer(
        (_) async => {
          'a1': const UserPublicProfile(uid: 'a1', displayName: 'Ana'),
          'a2': const UserPublicProfile(uid: 'a2', displayName: 'Beto'),
        },
      );
    });

    ProviderContainer container() => ProviderContainer(
          overrides: [
            authStateChangesProvider
                .overrideWith((ref) => Stream<User?>.value(_MockUser())),
            userPublicProfileRepositoryProvider.overrideWithValue(repo),
          ],
        );

    test('soltar al último oyente NO tira el valor', () async {
      final c = container();
      addTearDown(c.dispose);

      final sub = c.listen(
        userPublicProfilesBatchProvider(key),
        (_, __) {},
        fireImmediately: true,
      );
      await c.read(userPublicProfilesBatchProvider(key).future);
      expect(c.read(userPublicProfilesBatchProvider(key)).hasValue, isTrue);

      // Se va de /alumnos.
      sub.close();
      await Future<void>.delayed(Duration.zero);

      // Vuelve. Éste es el assert: encuentra el valor puesto, no un
      // `AsyncLoading` que dispare otro cross-fade de la tabla.
      final alVolver = c.read(userPublicProfilesBatchProvider(key));
      expect(
        alVolver.hasValue,
        isTrue,
        reason: 'volver a Alumnos no puede costar una recarga de perfiles',
      );
      expect(alVolver.isLoading, isFalse);
    });

    test('y el repositorio se consulta UNA sola vez', () async {
      final c = container();
      addTearDown(c.dispose);

      final sub = c.listen(
        userPublicProfilesBatchProvider(key),
        (_, __) {},
        fireImmediately: true,
      );
      await c.read(userPublicProfilesBatchProvider(key).future);
      sub.close();
      await Future<void>.delayed(Duration.zero);

      // Segunda entrada.
      c.listen(userPublicProfilesBatchProvider(key), (_, __) {},
          fireImmediately: true);
      await Future<void>.delayed(Duration.zero);

      verify(() => repo.getByIds(any())).called(1);
    });
  });
}
