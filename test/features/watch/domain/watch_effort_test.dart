import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/watch/domain/watch_effort.dart';

/// Change `watch-workout-session`, fase F4.
///
/// El reloj le manda al teléfono lo que está midiendo —pulsaciones y calorías—
/// para que si el atleta agarra el celular a mitad de entreno, los datos
/// también estén ahí.
///
/// **Esto NO persiste nada.** Es un dato en vivo que viaja por
/// WatchConnectivity y muere cuando termina el entreno. D1 sigue intacta: el
/// ciclo no toca Firestore, y para Apple esto no es "collect" porque el dato
/// nunca sale de los dispositivos del atleta.
void main() {
  final t0 = DateTime.utc(2026, 8, 12, 10, 0, 0);

  group('WatchEffort.tryParse', () {
    test('parsea un payload bien formado', () {
      final effort = WatchEffort.tryParse({
        'kind': WatchEffort.kind,
        'bpm': 142,
        'kcal': 87,
        'measuredAtMs': t0.millisecondsSinceEpoch,
      });

      expect(effort, isNotNull);
      expect(effort!.bpm, 142);
      expect(effort.kcal, 87);
      expect(effort.measuredAt, t0);
    });

    test('ignora un payload de otro tipo que viaja por el mismo canal', () {
      // El canal lo comparte con la credencial del reloj.
      //
      // El payload de prueba trae `measuredAtMs` A PROPÓSITO: sin eso, el
      // descarte lo haría el guard del timestamp y no el del discriminador, y
      // el test pasaría por la razón equivocada. Se descubrió así — la mutación
      // que borraba el chequeo de `kind` sobrevivía.
      final effort = WatchEffort.tryParse({
        'kind': 'watchCredential',
        'customToken': 'abc',
        'measuredAtMs': t0.millisecondsSinceEpoch,
        'bpm': 999,
      });

      expect(effort, isNull);
    });

    test('ignora un payload sin timestamp', () {
      // Sin el momento de la medición no se puede decidir si está vieja, y sin
      // eso no se puede mostrar sin mentir.
      final effort = WatchEffort.tryParse({
        'kind': WatchEffort.kind,
        'bpm': 142,
      });

      expect(effort, isNull);
    });

    test('sobrevive a campos con el tipo equivocado', () {
      // El payload cruza un puente entre lenguajes. Un cambio del lado Swift no
      // puede tirar la app del teléfono.
      final effort = WatchEffort.tryParse({
        'kind': WatchEffort.kind,
        'bpm': 'ciento cuarenta',
        'kcal': null,
        'measuredAtMs': t0.millisecondsSinceEpoch,
      });

      expect(effort, isNotNull);
      expect(effort!.bpm, isNull, reason: 'un bpm no numérico se descarta');
      expect(effort.kcal, isNull);
    });

    test('descarta un bpm de 0, que es un sensor que no enganchó', () {
      final effort = WatchEffort.tryParse({
        'kind': WatchEffort.kind,
        'bpm': 0,
        'measuredAtMs': t0.millisecondsSinceEpoch,
      });

      expect(effort!.bpm, isNull);
    });

    test('CONSERVA un kcal de 0, que es un dato cierto', () {
      // Misma asimetría que en el reloj: 0 pulsaciones es imposible, 0 calorías
      // es verdad — todavía no se midió consumo.
      final effort = WatchEffort.tryParse({
        'kind': WatchEffort.kind,
        'kcal': 0,
        'measuredAtMs': t0.millisecondsSinceEpoch,
      });

      expect(effort!.kcal, 0);
    });

    // El test de "ida y vuelta" que había acá se borró junto con `toContext()`.
    //
    // Serializaba con Dart y parseaba con Dart, o sea que confirmaba un
    // contrato que no es el real: el que ESCRIBE este payload es Swift. Y
    // pasaba por vacuidad — `toContext()` no incluía ninguno de los campos del
    // cronómetro, así que el round-trip no los ejercía. La suite se veía verde
    // sobre el contrato que después resultó estar roto.
    //
    // El contrato de verdad vive en `conformance/effort_payload.json` y lo
    // corren los DOS lados.

    test('un cronómetro sin pulso ni calorías sobrevive el parseo', () {
      // El caso normal de los primeros segundos de una serie por tiempo: el
      // atleta arranca la plancha antes de que llegue la primera muestra de
      // HealthKit. Si alguna guarda lo descartara por "vacío", el teléfono no
      // se enteraría nunca del cronómetro — y es justo cuando más importa.
      final effort = WatchEffort.tryParse({
        'kind': WatchEffort.kind,
        'measuredAtMs': t0.millisecondsSinceEpoch,
        'timerExerciseId': 'plancha',
        'timerSetNumber': 2,
        'timerTotalSeconds': 60,
        'timerEndsAtMs':
            t0.add(const Duration(seconds: 60)).millisecondsSinceEpoch,
      });

      expect(effort, isNotNull);
      expect(effort!.bpm, isNull);
      expect(effort.kcal, isNull);
      expect(effort.timerCorreEn(exerciseId: 'plancha', setNumber: 2), isTrue);
      expect(
        effort.timerCorreEn(exerciseId: 'plancha', setNumber: 3),
        isFalse,
        reason: 'otra serie del MISMO ejercicio no es la que corre',
      );
      expect(
        effort.timerCorreEn(exerciseId: 'sentadilla', setNumber: 2),
        isFalse,
      );
    });

    test('sin número de serie no se puede ubicar la cuenta', () {
      // Una cuenta dibujada en la fila equivocada es peor que ninguna: el
      // atleta la ve correr sobre una serie que no está haciendo.
      final effort = WatchEffort.tryParse({
        'kind': WatchEffort.kind,
        'measuredAtMs': t0.millisecondsSinceEpoch,
        'timerExerciseId': 'plancha',
        'timerTotalSeconds': 60,
        'timerEndsAtMs':
            t0.add(const Duration(seconds: 60)).millisecondsSinceEpoch,
      });

      expect(effort, isNotNull);
      expect(effort!.timerSetNumber, isNull);
      expect(effort.timerCorreEn(exerciseId: 'plancha', setNumber: 1), isFalse);
    });
  });

  group('WatchEffortRules.display', () {
    test('sin dato no se muestra nada', () {
      expect(
        WatchEffortRules.display(effort: null, now: t0),
        const WatchEffortDisplay.nada(),
      );
    });

    test('un dato recién llegado se muestra', () {
      final display = WatchEffortRules.display(
        effort: WatchEffort(bpm: 138, kcal: 55, measuredAt: t0),
        now: t0.add(const Duration(seconds: 2)),
      );

      expect(display, const WatchEffortDisplay(bpm: 138, kcal: 55));
    });

    test('aguanta la latencia de transporte medida', () {
      // La sesión paralela midió WatchConnectivity entre 2,0s y 24,4s según la
      // carga de la máquina. Un umbral apretado descartaría datos buenos
      // simplemente porque el teléfono estaba ocupado.
      final display = WatchEffortRules.display(
        effort: WatchEffort(bpm: 138, measuredAt: t0),
        now: t0.add(const Duration(seconds: 25)),
      );

      expect(display.bpm, 138);
    });

    test('un dato viejo se deja de mostrar ENTERO', () {
      // Acá la regla se aparta de la del reloj a propósito.
      //
      // En el reloj las calorías NO caducan: son acumuladas y siguen siendo
      // verdad. Pero en el teléfono el dato viene RELAYADO, así que su
      // antigüedad mide otra cosa: si hace 45 segundos que no llega nada, lo
      // más probable es que el vínculo con el reloj esté muerto — el entreno
      // terminó, la app del reloj se cerró, o se perdió el bluetooth.
      //
      // Mostrar calorías congeladas en esa situación sugiere una conexión viva
      // que no existe. Se muestra nada, que es lo cierto.
      final display = WatchEffortRules.display(
        effort: WatchEffort(bpm: 138, kcal: 90, measuredAt: t0),
        now:
            t0.add(WatchEffortRules.maxAntiguedad + const Duration(seconds: 1)),
      );

      expect(display, const WatchEffortDisplay.nada());
    });

    test('justo en el límite todavía vale', () {
      final display = WatchEffortRules.display(
        effort: WatchEffort(bpm: 138, measuredAt: t0),
        now: t0.add(WatchEffortRules.maxAntiguedad),
      );

      expect(display.bpm, 138);
    });

    test('un reloj corrido hacia adelante no borra la pantalla', () {
      // Desfase mayor que el umbral, para que el test distinga esta regla de
      // una que use el valor absoluto de la diferencia.
      final display = WatchEffortRules.display(
        effort: WatchEffort(
            bpm: 138, measuredAt: t0.add(const Duration(minutes: 5))),
        now: t0,
      );

      expect(display.bpm, 138);
    });

    test('muestra lo que hay aunque falte el otro dato', () {
      expect(
        WatchEffortRules.display(
          effort: WatchEffort(kcal: 12, measuredAt: t0),
          now: t0,
        ),
        const WatchEffortDisplay(bpm: null, kcal: 12),
      );
    });

    test('un dato fresco pero vacío no dibuja nada', () {
      // Llegó el payload pero sin ninguna medición: no hay nada que mostrar, y
      // una fila vacía ocupa lugar en la pantalla igual.
      expect(
        WatchEffortRules.display(
          effort: WatchEffort(measuredAt: t0),
          now: t0,
        ),
        const WatchEffortDisplay.nada(),
      );
    });
  });
}
