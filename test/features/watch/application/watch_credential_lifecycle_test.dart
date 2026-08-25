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

  /// Cuánto se pidió esperar entre reintentos, en orden. La espera REAL no se
  /// hace: un test que duerme cuatro segundos mide el reloj de pared, no la
  /// conducta.
  late List<Duration> esperas;

  ProviderContainer containerWith(Stream<User?> authStream) {
    hookRegistrado = false;
    dispararResume = () {};
    esperas = [];
    final container = ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => authStream),
        watchCredentialServiceProvider.overrideWithValue(service),
        appResumeHookProvider.overrideWithValue((onResume) {
          hookRegistrado = true;
          dispararResume = onResume;
        }),
        watchRetryDelayProvider.overrideWithValue((espera) async {
          esperas.add(espera);
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

    // `noWatchPaired` TAMBIEN, y antes no. El motivo que lo excluia decia que
    // reintentar seria "un viaje a la Cloud Function en cada foreground", y es
    // falso: `deliverCredential` corta en `isPaired` ANTES de tocar
    // `_functions`. No hay que creerlo — ya estaba medido en
    // `test/features/watch/data/watch_credential_service_test.dart:54`, que
    // afirma textual "no llama a la Cloud Function" con un `verifyNever` sobre
    // `httpsCallable`. La politica se pagaba cara sin recibir nada.
    //
    // Lo que si costaba: `WCSession.activate()` es asincrono, asi que un
    // `isPaired` que responde antes de la activacion miente — y ese false no se
    // reintentaba NUNCA.
    expect(
      watchCredentialShouldRetry(WatchCredentialOutcome.noWatchPaired),
      isTrue,
      reason: 'el reloj puede aparecer despues: activacion asincrona de '
          'WCSession, o emparejado con la app ya abierta',
    );

    // El unico definitivo: esta plataforma no soporta relojes y eso no cambia
    // en caliente. Aca si, reintentar seria ruido para siempre.
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

  // La plataforma no soporta relojes: eso no cambia en caliente. Es el unico
  // resultado en el que reintentar es ruido para siempre.
  test('si la plataforma no soporta relojes, el resume NO reintenta', () async {
    when(() => service.deliverCredential(uid: any(named: 'uid')))
        .thenAnswer((_) async => WatchCredentialOutcome.notSupported);

    final container = containerWith(Stream.value(userWithUid('atleta-1')));
    container.read(watchCredentialLifecycleProvider);
    await container.read(authStateChangesProvider.future);
    await pumpEventQueue();
    verify(() => service.deliverCredential(uid: 'atleta-1')).called(1);

    dispararResume();
    await pumpEventQueue();

    verifyNever(() => service.deliverCredential(uid: any(named: 'uid')));
    expect(esperas, isEmpty, reason: 'no hay nada que reintentar');
  });

  // ── La race de activacion de WCSession (HANDOFF §8.6) ────────────────────
  //
  // `WCSession.activate()` es asincrono y el plugin lo dispara en su `init`
  // (`watch_connectivity-0.2.8`, `WatchConnectivityPlugin.swift:15-19`). Antes
  // de que active, `isPaired` devuelve el `?? false` de `Self.session?.isPaired`
  // — false aunque el reloj este ahi.
  //
  // El resultado era `noWatchPaired`, que no se reintentaba NUNCA, ni en
  // resume. Y el resume no alcanza para cubrir esto ni aunque se reintentara:
  // la race pasa en el arranque en frio, y un atleta que abre la app y la usa
  // puede no generar un solo resume en toda la sesion.

  test('si isPaired mintio por la race, se REINTENTA y entrega', () async {
    var llamadas = 0;
    when(() => service.deliverCredential(uid: any(named: 'uid')))
        .thenAnswer((_) async {
      llamadas++;
      // El primer chequeo cae antes de que WCSession active; el segundo, ya
      // con la sesion activa, ve el reloj.
      return llamadas == 1
          ? WatchCredentialOutcome.noWatchPaired
          : WatchCredentialOutcome.delivered;
    });

    final container = containerWith(Stream.value(userWithUid('atleta-1')));
    container.read(watchCredentialLifecycleProvider);
    await container.read(authStateChangesProvider.future);
    await pumpEventQueue();

    expect(llamadas, 2,
        reason: 'sin el reintento el reloj queda sin credencial');
    expect(esperas, [watchPairingRaceDelay],
        reason: 'una sola espera: al segundo intento ya entrego');
  });

  test('el reintento de race es ACOTADO, no un bucle', () async {
    when(() => service.deliverCredential(uid: any(named: 'uid')))
        .thenAnswer((_) async => WatchCredentialOutcome.noWatchPaired);

    final container = containerWith(Stream.value(userWithUid('atleta-1')));
    container.read(watchCredentialLifecycleProvider);
    await container.read(authStateChangesProvider.future);
    await pumpEventQueue();

    // Este es el atleta que REALMENTE no tiene reloj: paga los reintentos y
    // nada mas. Si esto crece, cada arranque de la mayoria de los usuarios
    // paga de mas.
    verify(() => service.deliverCredential(uid: 'atleta-1'))
        .called(1 + watchPairingRaceRetries);
    expect(esperas.length, watchPairingRaceRetries);
  });

  // El bucle es SOLO para la race. Machacar un `mintFailed` acá seria pegarle a
  // la Cloud Function tres veces seguidas en el arranque, y ese ya tiene su
  // reintento por resume.
  test('un fallo que no es de emparejamiento no entra al bucle', () async {
    when(() => service.deliverCredential(uid: any(named: 'uid')))
        .thenAnswer((_) async => WatchCredentialOutcome.mintFailed);

    final container = containerWith(Stream.value(userWithUid('atleta-1')));
    container.read(watchCredentialLifecycleProvider);
    await container.read(authStateChangesProvider.future);
    await pumpEventQueue();

    verify(() => service.deliverCredential(uid: 'atleta-1')).called(1);
    expect(esperas, isEmpty);
  });

  // El otro agujero que dejaba `noWatchPaired` como definitivo: emparejar el
  // reloj con la app ya abierta. Volvia a primer plano y seguia sin credencial
  // hasta el proximo arranque en frio.
  test('emparejar el reloj y volver a primer plano entrega la credencial',
      () async {
    when(() => service.deliverCredential(uid: any(named: 'uid')))
        .thenAnswer((_) async => WatchCredentialOutcome.noWatchPaired);

    final container = containerWith(Stream.value(userWithUid('atleta-1')));
    container.read(watchCredentialLifecycleProvider);
    await container.read(authStateChangesProvider.future);
    await pumpEventQueue();
    verify(() => service.deliverCredential(uid: 'atleta-1'))
        .called(1 + watchPairingRaceRetries);

    // El atleta empareja el reloj y vuelve al telefono.
    when(() => service.deliverCredential(uid: any(named: 'uid')))
        .thenAnswer((_) async => WatchCredentialOutcome.delivered);
    esperas.clear();
    dispararResume();
    await pumpEventQueue();

    // UNA sola: en el resume no van reintentos de race. La app lleva rato viva
    // y la sesion hace rato que activo, asi que un false aca es cierto.
    verify(() => service.deliverCredential(uid: 'atleta-1')).called(1);
    expect(esperas, isEmpty);
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
