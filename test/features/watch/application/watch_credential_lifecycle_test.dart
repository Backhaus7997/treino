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

  /// El resume de la app, disparable a mano. El hook real crea un
  /// `AppLifecycleListener`, que exige `WidgetsBinding.instance` y por lo tanto
  /// no existe en un test unitario.
  late void Function() dispararResume;
  var hookRegistrado = false;

  ProviderContainer containerWith(Stream<User?> authStream) {
    hookRegistrado = false;
    dispararResume = () {};
    final container = ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => authStream),
        watchCredentialServiceProvider.overrideWithValue(service),
        appResumeHookProvider.overrideWithValue((onResume) {
          hookRegistrado = true;
          dispararResume = onResume;
        }),
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

  // ── Reintento al volver a primer plano (HANDOFF §8.6) ────────────────────
  //
  // La entrega era de UN SOLO DISPARO atada al cambio de sesion. Si fallaba en
  // el arranque, el reloj quedaba SIN CREDENCIAL —o sea inservible, porque sin
  // ella no habla Firestore— hasta desloguearse o reinstalar.
  //
  // El caso tipico: instalas la app del reloj, la entrega sale antes de que el
  // companion termine de instalarse, `updateApplicationContext` tira
  // `WatchAppNotInstalled`, y nadie vuelve a intentar.

  test('un fallo transitorio se reintenta; uno definitivo no', () {
    // Los dos que valen la pena: el reloj todavia instalandose, y la red o la
    // CF caida. Los dos se resuelven solos.
    expect(
      watchCredentialShouldRetry(WatchCredentialOutcome.deliveryFailed),
      isTrue,
      reason: 'WatchAppNotInstalled mientras el companion se instala',
    );
    expect(
      watchCredentialShouldRetry(WatchCredentialOutcome.mintFailed),
      isTrue,
    );

    // Los que NO: reintentar sin reloj emparejado seria un viaje a la Cloud
    // Function en cada foreground de la enorme mayoria de usuarios, que no
    // tienen reloj.
    expect(
      watchCredentialShouldRetry(WatchCredentialOutcome.noWatchPaired),
      isFalse,
      reason: 'sin reloj no hay a quien entregarle nada, reintentar es ruido '
          'para siempre',
    );
    expect(
      watchCredentialShouldRetry(WatchCredentialOutcome.notSupported),
      isFalse,
    );
    expect(
      watchCredentialShouldRetry(WatchCredentialOutcome.delivered),
      isFalse,
    );
  });

  // El caso que este arreglo cierra: la entrega falla en el arranque porque el
  // companion todavia se esta instalando, y ANTES nadie volvia a intentar. El
  // reloj quedaba inservible —sin credencial no habla Firestore— hasta
  // desloguearse o reinstalar.
  test('si la entrega fallo, volver a primer plano la REINTENTA', () async {
    when(() => service.deliverCredential(uid: any(named: 'uid')))
        .thenAnswer((_) async => WatchCredentialOutcome.deliveryFailed);

    final container = containerWith(Stream.value(userWithUid('atleta-1')));
    container.read(watchCredentialLifecycleProvider);
    await container.read(authStateChangesProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(hookRegistrado, isTrue, reason: 'sin hook no hay reintento posible');
    verify(() => service.deliverCredential(uid: 'atleta-1')).called(1);

    dispararResume();
    await Future<void>.delayed(Duration.zero);

    verify(() => service.deliverCredential(uid: 'atleta-1')).called(1);
  });

  // Sin reloj emparejado reintentar seria un viaje a la Cloud Function en cada
  // foreground de la enorme mayoria de usuarios, que no tienen reloj.
  test('sin reloj emparejado, volver a primer plano NO reintenta', () async {
    when(() => service.deliverCredential(uid: any(named: 'uid')))
        .thenAnswer((_) async => WatchCredentialOutcome.noWatchPaired);

    final container = containerWith(Stream.value(userWithUid('atleta-1')));
    container.read(watchCredentialLifecycleProvider);
    await container.read(authStateChangesProvider.future);
    await Future<void>.delayed(Duration.zero);
    verify(() => service.deliverCredential(uid: 'atleta-1')).called(1);

    dispararResume();
    await Future<void>.delayed(Duration.zero);

    verifyNever(() => service.deliverCredential(uid: any(named: 'uid')));
  });

  // Entregada es entregada: no se reintenta al volver a primer plano.
  test('si ya se entrego, volver a primer plano no hace nada', () async {
    final container = containerWith(Stream.value(userWithUid('atleta-1')));
    container.read(watchCredentialLifecycleProvider);
    await container.read(authStateChangesProvider.future);
    await Future<void>.delayed(Duration.zero);
    verify(() => service.deliverCredential(uid: 'atleta-1')).called(1);

    dispararResume();
    await Future<void>.delayed(Duration.zero);

    verifyNever(() => service.deliverCredential(uid: any(named: 'uid')));
  });
}
