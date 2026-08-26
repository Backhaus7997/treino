import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/watch/data/wear_workout_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> llamadas;
  late WearWorkoutService service;
  Map<String, dynamic>? respuesta;

  setUp(() {
    llamadas = [];
    respuesta = null;
    const canal = MethodChannel('treino/wear_workout');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, (call) async {
      llamadas.add(call);
      return respuesta;
    });
    service = WearWorkoutService(channel: canal);
  });

  group('arrancar', () {
    test('un ejercicio por tiempo arranca su propio temporizador', () async {
      await service.startExerciseTimer(45);

      final call = llamadas.single;
      expect(call.method, 'startExerciseTimer');
      expect(call.arguments, {'seconds': 45});
    });

    test('NO usa el canal del descanso', () async {
      // Son dos temporizadores distintos. Si compartieran store, arrancar un
      // ejercicio por tiempo cancelaría el descanso en curso sin decir nada.
      await service.startExerciseTimer(45);

      expect(llamadas.single.method, isNot('startRest'));
    });

    test('cero segundos no arranca nada y cancela el que hubiera', () async {
      await service.startExerciseTimer(0);

      expect(llamadas.single.method, 'cancelExerciseTimer');
    });

    test('un negativo se trata igual que cero', () async {
      await service.startExerciseTimer(-3);

      expect(llamadas.single.method, 'cancelExerciseTimer');
    });
  });

  group('leer el estado', () {
    test('sin temporizador devuelve null', () async {
      respuesta = {'nowElapsedMs': 1000};

      expect(await service.exerciseTimerState(), isNull);
    });

    test('con temporizador trae el total, para poder dibujar el progreso',
        () async {
      respuesta = {
        'endsAtElapsedMs': 50000,
        'totalMs': 45000,
        'remainingMs': 20000,
        'finished': false,
        'nowElapsedMs': 30000,
      };

      final t = await service.exerciseTimerState();

      expect(t, isNotNull);
      expect(t!.remainingMs, 20000);
      // Sin el total no hay fracción que mostrar en el anillo.
      expect(t.totalMs, 45000);
      expect(t.finished, isFalse);
    });

    test('VENCIDO sigue devolviendo estado, no null', () async {
      // Diferencia deliberada con el descanso, que se borra solo al vencer:
      // acá el atleta tiene que VER que el tiempo terminó para recién entonces
      // marcar la serie. Devolver null haría desaparecer la pantalla justo
      // cuando hay que actuar sobre ella.
      respuesta = {
        'endsAtElapsedMs': 50000,
        'totalMs': 45000,
        'remainingMs': 0,
        'finished': true,
        'nowElapsedMs': 60000,
      };

      final t = await service.exerciseTimerState();

      expect(t, isNotNull);
      expect(t!.finished, isTrue);
    });
  });
}
