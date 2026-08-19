import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/watch/application/watch_effort_notifier.dart';
import 'package:treino/features/watch/domain/watch_effort.dart';

/// Change `watch-workout-session`, fase F4.
///
/// El notifier escucha el contexto que publica el reloj y deja disponible el
/// último esfuerzo. **No persiste nada**: vive en memoria mientras dura el
/// entreno.
void main() {
  late StreamController<Map<String, dynamic>> contextos;

  setUp(() => contextos = StreamController<Map<String, dynamic>>.broadcast());
  tearDown(() => contextos.close());

  Map<String, dynamic> payload({int? bpm, int? kcal, required DateTime at}) => {
        'kind': WatchEffort.kind,
        if (bpm != null) 'bpm': bpm,
        if (kcal != null) 'kcal': kcal,
        'measuredAtMs': at.millisecondsSinceEpoch,
      };

  test('arranca sin nada', () {
    final notifier = WatchEffortNotifier(contextStream: contextos.stream);
    addTearDown(notifier.dispose);

    expect(notifier.value, isNull);
  });

  test('toma el esfuerzo que publica el reloj', () async {
    final notifier = WatchEffortNotifier(contextStream: contextos.stream);
    addTearDown(notifier.dispose);

    final t = DateTime.utc(2026, 8, 12, 10);
    contextos.add(payload(bpm: 142, kcal: 88, at: t));
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value?.bpm, 142);
    expect(notifier.value?.kcal, 88);
  });

  test('ignora contextos que no son de esfuerzo', () async {
    // El canal lo comparte con la credencial. Un payload ajeno no puede pisar
    // el último esfuerzo bueno con un null.
    final notifier = WatchEffortNotifier(contextStream: contextos.stream);
    addTearDown(notifier.dispose);

    final t = DateTime.utc(2026, 8, 12, 10);
    contextos.add(payload(bpm: 142, at: t));
    await Future<void>.delayed(Duration.zero);

    contextos.add({'kind': 'watchCredential', 'customToken': 'abc'});
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value?.bpm, 142, reason: 'el esfuerzo bueno sobrevive');
  });

  test('se queda con el más nuevo', () async {
    final notifier = WatchEffortNotifier(contextStream: contextos.stream);
    addTearDown(notifier.dispose);

    final t = DateTime.utc(2026, 8, 12, 10);
    contextos.add(payload(bpm: 140, at: t));
    await Future<void>.delayed(Duration.zero);
    contextos.add(payload(bpm: 151, at: t.add(const Duration(seconds: 5))));
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value?.bpm, 151);
  });

  test('un payload roto no tira la app ni borra lo anterior', () async {
    // El payload cruza un puente entre lenguajes: un cambio del lado Swift no
    // puede dejar al teléfono peor que antes.
    final notifier = WatchEffortNotifier(contextStream: contextos.stream);
    addTearDown(notifier.dispose);

    final t = DateTime.utc(2026, 8, 12, 10);
    contextos.add(payload(bpm: 133, at: t));
    await Future<void>.delayed(Duration.zero);

    contextos.add({'kind': WatchEffort.kind, 'bpm': 'raro'});
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value?.bpm, 133);
  });

  test('un error del stream no lo mata', () async {
    // Si el canal de plataforma emite un error y el notifier se cae, el atleta
    // pierde el dato para el resto del entreno sin ningún síntoma.
    final notifier = WatchEffortNotifier(contextStream: contextos.stream);
    addTearDown(notifier.dispose);

    contextos.addError(Exception('canal roto'));
    await Future<void>.delayed(Duration.zero);

    final t = DateTime.utc(2026, 8, 12, 10);
    contextos.add(payload(bpm: 128, at: t));
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value?.bpm, 128,
        reason: 'sigue escuchando después del error');
  });

  test('siembra con lo que YA habia llegado antes de existir', () async {
    // El caso real que se reporto: el reloj publica un cronometro corriendo y
    // el telefono no muestra nada, porque `contextStream` solo emite contextos
    // NUEVOS y el notifier nacio despues. Sin leer lo ya recibido, ese dato se
    // pierde para siempre y la pantalla queda vacia sin ningun error.
    final ya = DateTime.utc(2026, 8, 19, 12);
    final notifier = WatchEffortNotifier(
      contextStream: contextos.stream,
      recibidos: Future.value([
        payload(bpm: 132, at: ya),
      ]),
    );
    addTearDown(notifier.dispose);

    await Future<void>.delayed(Duration.zero);
    expect(notifier.value?.bpm, 132);
  });

  test('lo que llega por el stream le gana a la siembra', () async {
    final viejo = DateTime.utc(2026, 8, 19, 12);
    final nuevo = DateTime.utc(2026, 8, 19, 12, 5);
    final notifier = WatchEffortNotifier(
      contextStream: contextos.stream,
      // Una siembra que resuelve TARDE no puede pisar un dato mas fresco que
      // ya entro por el stream.
      recibidos: Future<List<Map<String, dynamic>>>.delayed(
        const Duration(milliseconds: 20),
        () => [payload(bpm: 100, at: viejo)],
      ),
    );
    addTearDown(notifier.dispose);

    contextos.add(payload(bpm: 155, at: nuevo));
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(notifier.value?.bpm, 155);
  });

  test('el cronometro del reloj viaja en el mismo payload', () async {
    final at = DateTime.utc(2026, 8, 19, 12);
    final fin = DateTime.utc(2026, 8, 19, 12, 1);
    final notifier = WatchEffortNotifier(contextStream: contextos.stream);
    addTearDown(notifier.dispose);

    contextos.add({
      'kind': WatchEffort.kind,
      'bpm': 140,
      'measuredAtMs': at.millisecondsSinceEpoch,
      'timerEndsAtMs': fin.millisecondsSinceEpoch,
      'timerTotalSeconds': 60,
      'timerExerciseId': 'plancha',
    });
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value?.timerEndsAt, fin);
    expect(notifier.value?.timerTotalSeconds, 60);
    expect(notifier.value?.timerExerciseId, 'plancha');
    // Y el pulso sigue llegando por el mismo payload: van juntos porque el
    // reloj tiene UN SOLO applicationContext de salida.
    expect(notifier.value?.bpm, 140);
  });
}
