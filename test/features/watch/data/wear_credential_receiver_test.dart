import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/watch/data/watch_bridge.dart';
import 'package:treino/features/watch/data/wear_credential_receiver.dart';
import 'package:treino/features/watch/domain/watch_credential_payload.dart';
import 'package:treino/features/watch/domain/wear_credential.dart';

class _MockBridge extends Mock implements WatchBridge {}

void main() {
  late _MockBridge bridge;
  late StreamController<Map<String, dynamic>> contextos;
  late WearCredentialReceiver receiver;

  /// Un payload tal cual lo publica el teléfono, con todo lo que en Wear sobra.
  Map<String, dynamic> payload({
    String token = 'tok-1',
    String uid = 'atleta-1',
  }) =>
      WatchCredentialPayload(
        customToken: token,
        uid: uid,
        apiKey: 'api-key',
        projectId: 'treino-dev',
        authEmulatorHost: 'http://localhost:9099',
      ).toJson();

  setUp(() {
    bridge = _MockBridge();
    contextos = StreamController<Map<String, dynamic>>.broadcast();
    // Tope corto: los tests que ejercitan el cuelgue no pueden tardar los 5 s
    // de producción, y los demás nunca llegan a agotarlo.
    receiver = WearCredentialReceiver(
      bridge: bridge,
      seedTimeout: const Duration(milliseconds: 50),
    );

    when(() => bridge.contextStream).thenAnswer((_) => contextos.stream);
    when(() => bridge.receivedApplicationContexts)
        .thenAnswer((_) async => const <Map<String, dynamic>>[]);
  });

  tearDown(() => contextos.close());

  /// Junta lo que emita el receiver, con la suscripción YA activa.
  ///
  /// El `pumpEventQueue` no es ceremonia: el `async*` recién corre su cuerpo
  /// —y recién ahí se engancha a `contextStream`— cuando alguien escucha. Sin
  /// esperar ese turno, cualquier evento que agregue el test se pierde y el
  /// test mediría el vacío en vez del transporte.
  Future<List<WearCredential>> recolectar(
    Future<void> Function() guion,
  ) async {
    final recibidas = <WearCredential>[];
    final sub = receiver.credentials.listen(recibidas.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await guion();
    await pumpEventQueue();
    return recibidas;
  }

  group('arranque en frío', () {
    test('la credencial que YA estaba publicada llega igual', () async {
      // El caso que define A2. El teléfono publica el DataItem cuando el atleta
      // inicia sesión, o sea mucho antes de que nadie abra la app del reloj;
      // `contextStream` no reproduce el pasado. Sin sembrar, este reloj espera
      // para siempre una credencial que ya estaba escrita.
      when(() => bridge.receivedApplicationContexts)
          .thenAnswer((_) async => [payload()]);

      final recibidas = await recolectar(() async {});

      expect(
        recibidas,
        const [WearCredential(customToken: 'tok-1', uid: 'atleta-1')],
      );
    });

    test('un contexto que llega MIENTRAS se lee la semilla no se pierde',
        () async {
      // La ventana entre engancharse y terminar de sembrar es un `await`. Si el
      // `listen` viniera después de la semilla, este evento no dejaría rastro.
      final semilla = Completer<List<Map<String, dynamic>>>();
      when(() => bridge.receivedApplicationContexts)
          .thenAnswer((_) => semilla.future);

      final recibidas = await recolectar(() async {
        contextos.add(payload(token: 'tok-en-vuelo', uid: 'atleta-2'));
        await pumpEventQueue();
        semilla.complete(const []);
      });

      expect(
        recibidas,
        const [WearCredential(customToken: 'tok-en-vuelo', uid: 'atleta-2')],
      );
    });

    test('si la semilla NO CONTESTA nunca, el canal en vivo igual arranca',
        () async {
      // El modo de falla más traicionero del plugin: el `Future` no completa
      // —nadie llama a `result`— así que sin tope el reloj se quedaría
      // esperando la semilla mientras la credencial le pasa por al lado.
      when(() => bridge.receivedApplicationContexts)
          .thenAnswer((_) => Completer<List<Map<String, dynamic>>>().future);

      final recibidas = await recolectar(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        contextos.add(payload(token: 'tok-pese-al-cuelgue'));
      });

      expect(recibidas.single.customToken, 'tok-pese-al-cuelgue');
    });

    test('si la semilla explota, el canal en vivo sigue sirviendo', () async {
      // El plugin desreferencia `localNode` —un lateinit async— justo adentro
      // de esta llamada. Que falle no puede dejar al reloj sin la única vía que
      // tiene para conseguir sesión.
      when(() => bridge.receivedApplicationContexts)
          .thenThrow(Exception('UninitializedPropertyAccessException'));

      final recibidas = await recolectar(() async {
        contextos.add(payload(token: 'tok-vivo'));
      });

      expect(recibidas.single.customToken, 'tok-vivo');
    });
  });

  group('traducción del payload', () {
    test('se queda con customToken y uid, y descarta lo de watchOS', () async {
      when(() => bridge.receivedApplicationContexts)
          .thenAnswer((_) async => [payload(token: 'tok-9', uid: 'atleta-9')]);

      final recibidas = await recolectar(() async {});

      // apiKey, projectId y los hosts de emulador no viajan a la máquina de
      // emparejamiento: el SDK de Wear los saca de google-services.json, y
      // `localhost` en un reloj físico es el reloj.
      expect(recibidas.single.customToken, 'tok-9');
      expect(recibidas.single.uid, 'atleta-9');
    });

    test('un payload que no es credencial se ignora', () async {
      final recibidas = await recolectar(() async {
        contextos.add(<String, dynamic>{
          'kind': 'watchRefresh',
          'reason': 'activeRoutine',
        });
      });

      expect(recibidas, isEmpty);
    });

    test('un payload roto NO corta el stream: la próxima credencial entra',
        () async {
      final recibidas = await recolectar(() async {
        contextos.add(<String, dynamic>{
          'kind': WatchCredentialPayload.kind,
          'uid': 'atleta-1',
          // sin customToken
        });
        await pumpEventQueue();
        contextos.add(payload(token: 'tok-bueno'));
      });

      expect(recibidas.single.customToken, 'tok-bueno');
    });
  });

  test('no repite la última credencial, pero sí deja pasar una distinta',
      () async {
    // El mismo DataItem llega por la semilla Y por el stream. Canjear dos veces
    // el mismo token es pedirle a Firebase una sesión que ya se está creando.
    when(() => bridge.receivedApplicationContexts)
        .thenAnswer((_) async => [payload(token: 'tok-1')]);

    final recibidas = await recolectar(() async {
      contextos.add(payload(token: 'tok-1'));
      await pumpEventQueue();
      contextos.add(payload(token: 'tok-2', uid: 'atleta-2'));
    });

    expect(recibidas, const [
      WearCredential(customToken: 'tok-1', uid: 'atleta-1'),
      WearCredential(customToken: 'tok-2', uid: 'atleta-2'),
    ]);
  });
}
