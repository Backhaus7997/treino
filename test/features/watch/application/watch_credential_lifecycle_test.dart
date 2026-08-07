import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/watch/application/watch_credential_providers.dart';
import 'package:treino/features/watch/data/watch_credential_service.dart';

class _MockService extends Mock implements WatchCredentialService {}

class _MockUser extends Mock implements User {}

void main() {
  late _MockService service;

  setUp(() {
    service = _MockService();
    when(() => service.deliverCredential(uid: any(named: 'uid')))
        .thenAnswer((_) async => WatchCredentialOutcome.delivered);
  });

  ProviderContainer containerWith(Stream<User?> authStream) {
    final container = ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => authStream),
        watchCredentialServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  User userWithUid(String uid) {
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    return user;
  }

  test('al iniciar sesion, le entrega credencial al reloj', () async {
    final container = containerWith(Stream.value(userWithUid('atleta-1')));

    container.read(watchCredentialLifecycleProvider);
    await container.read(authStateChangesProvider.future);
    await Future<void>.delayed(Duration.zero);

    verify(() => service.deliverCredential(uid: 'atleta-1')).called(1);
  });

  test('sin usuario autenticado no entrega nada', () async {
    final container = containerWith(Stream<User?>.value(null));

    container.read(watchCredentialLifecycleProvider);
    await container.read(authStateChangesProvider.future);
    await Future<void>.delayed(Duration.zero);

    verifyNever(() => service.deliverCredential(uid: any(named: 'uid')));
  });

  // Quedarse sin credencial de reloj es una degradacion aceptable; tumbar el
  // arranque de la app por eso, no. El lifecycle corre en el camino critico de
  // inicio, asi que una excepcion suelta acá se lleva puesta toda la app.
  test('si la entrega falla, no propaga la excepcion', () async {
    when(() => service.deliverCredential(uid: any(named: 'uid')))
        .thenThrow(Exception('reloj en llamas'));

    final container = containerWith(Stream.value(userWithUid('atleta-1')));

    container.read(watchCredentialLifecycleProvider);
    await container.read(authStateChangesProvider.future);

    // El await de abajo falla con un unhandled error si el fire-and-forget no
    // atrapa lo suyo.
    await expectLater(Future<void>.delayed(Duration.zero), completes);
  });
}
