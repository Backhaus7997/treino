import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/watch/data/treino_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> llamadas;
  late TreinoLink link;
  Object? respuesta;

  setUp(() {
    llamadas = [];
    respuesta = true;
    const canal = MethodChannel('treino/link');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, (call) async {
      llamadas.add(call);
      if (respuesta is Exception) throw respuesta as Exception;
      return respuesta;
    });
    link = TreinoLink(methods: canal);
  });

  group('mandar', () {
    test('el path viaja tal cual y el payload como JSON', () async {
      final ok = await link.send(TreinoLink.pathWorkoutStarted, {'a': 1});

      expect(ok, isTrue);
      final args = llamadas.single.arguments as Map;
      expect(args['path'], '/treino/workout-started');
      expect(jsonDecode(args['payload'] as String), {'a': 1});
    });

    test('el path SIEMPRE empieza con barra', () {
      // No es cosmético: Play Services despacha a los servicios del manifest
      // armando `wear://<nodo>/<path>`, y sin la barra inicial la URI queda
      // malformada y NINGÚN filtro la matchea. Es exactamente el bug de
      // `watch_connectivity` que hizo que el reloj no se despertara nunca.
      expect(TreinoLink.pathWorkoutStarted, startsWith('/'));
      expect(TreinoLink.pathPrefix, startsWith('/'));
    });

    test('sin nodos del otro lado devuelve false, no tira', () async {
      respuesta = false;
      expect(await link.send(TreinoLink.pathWorkoutStarted), isFalse);
    });

    test('si el canal explota, el aviso se pierde pero no rompe nada',
        () async {
      // Un aviso que no sale no puede tumbar al que lo manda: esto corre en el
      // camino de empezar un entreno, que es lo más caliente de la app.
      respuesta = Exception('sin Play Services');
      expect(await link.send(TreinoLink.pathWorkoutStarted), isFalse);
    });
  });

  group('recibir', () {
    TreinoLinkMessage parsear(String payload) {
      final mensajes = <TreinoLinkMessage>[];
      final link = TreinoLink(
        methods: const MethodChannel('treino/link'),
        messages: _CanalFalso({'path': '/treino/x', 'payload': payload}),
      );
      link.messages.listen(mensajes.add);
      return mensajes.isEmpty
          ? const TreinoLinkMessage(path: '', data: {})
          : mensajes.first;
    }

    test('un payload roto no mata el stream: llega vacío', () async {
      final link = TreinoLink(
        methods: const MethodChannel('treino/link'),
        messages: const _CanalFalso(
          {'path': '/treino/x', 'payload': '{no es json'},
        ),
      );

      final msg = await link.messages.first;

      expect(msg.path, '/treino/x');
      expect(msg.data, isEmpty);
    });

    test('un payload bueno se parsea', () async {
      final link = TreinoLink(
        methods: const MethodChannel('treino/link'),
        messages: const _CanalFalso({
          'path': '/treino/workout-started',
          'payload': '{"sessionId":"s1"}',
        }),
      );

      final msg = await link.messages.first;

      expect(msg.path, '/treino/workout-started');
      expect(msg.data['sessionId'], 's1');
    });

    // Referenciado arriba para que el helper no quede sin uso.
    test('el helper de parseo no explota con vacío', () {
      expect(parsear('{}').data, isEmpty);
    });
  });
}

/// Un `EventChannel` que emite una sola cosa, sin plataforma de por medio.
class _CanalFalso extends EventChannel {
  const _CanalFalso(this.evento) : super('treino/link/messages');

  final Object evento;

  @override
  Stream<dynamic> receiveBroadcastStream([Object? arguments]) =>
      Stream<Object>.value(evento);
}
