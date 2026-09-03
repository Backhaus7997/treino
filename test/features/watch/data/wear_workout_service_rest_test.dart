import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/watch/data/wear_workout_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> llamadas;
  late WearWorkoutService service;

  setUp(() {
    llamadas = [];
    const canal = MethodChannel('treino/wear_workout');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, (call) async {
      llamadas.add(call);
      return null;
    });
    service = WearWorkoutService(channel: canal);
  });

  group('descanso de un ejercicio SIN descanso', () {
    test('cero segundos no arranca ningún descanso', () async {
      // El bug medido en la muñeca: el nativo persistia un deadline que nacia
      // vencido, y la barra aparecia en estado "terminado" apenas se marcaba
      // una serie.
      await service.startRest(0);

      expect(llamadas.map((c) => c.method), isNot(contains('startRest')));
    });

    test('cero segundos CANCELA el que estuviera corriendo', () async {
      // Si venia el descanso del ejercicio anterior, marcar una serie de uno
      // sin descanso significa que el atleta ya volvio a entrenar.
      await service.startRest(0);

      expect(llamadas.single.method, 'cancelRest');
    });

    test('un valor negativo se trata igual que cero', () async {
      await service.startRest(-5);

      expect(llamadas.single.method, 'cancelRest');
    });
  });

  test('con descanso de verdad sí arranca, y con wakelock', () async {
    await service.startRest(90);

    final call = llamadas.single;
    expect(call.method, 'startRest');
    expect(call.arguments, {'seconds': 90, 'wakeLock': true});
  });
}
