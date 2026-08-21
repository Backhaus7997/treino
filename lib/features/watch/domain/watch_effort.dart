/// Lo que el reloj le manda al teléfono mientras el atleta entrena.
///
/// Change `watch-workout-session`, fase F4.
///
/// Es un **agregado**: si el atleta agarra el celular a mitad de entreno, sus
/// pulsaciones y calorías también están ahí, al lado del tiempo. Sin reloj
/// conectado la pantalla queda exactamente como estaba.
///
/// ── Por qué esto NO viola D1 ──────────────────────────────────────────────
///
/// D1, firmada, dice que el ritmo cardíaco vive en pantalla y en la app Salud,
/// y que este ciclo **no toca Firestore**. Esto no lo toca: el dato viaja del
/// reloj al teléfono por WatchConnectivity, se muestra en vivo, y muere cuando
/// termina el entreno. No se persiste en ningún lado.
///
/// Y para Apple tampoco es "collect" —que define como transmitir datos FUERA
/// del dispositivo de forma que el desarrollador pueda accederlos—: acá el dato
/// nunca sale de los dispositivos del atleta hacia un servidor nuestro. Por eso
/// este agregado no suma ninguna declaración de privacidad.
///
/// Si algún día esto se guarda en Firestore, las dos cosas dejan de ser ciertas
/// EN EL ACTO. Ese sería otro ciclo, y arranca por una decisión de privacidad.
///
/// No es freezed a propósito, igual que `WatchCredentialPayload`: el reloj
/// arma este mismo shape en Swift, así que el JSON es un contrato entre
/// lenguajes y conviene tenerlo escrito a mano y a la vista.
library;

class WatchEffort {
  const WatchEffort({
    this.bpm,
    this.kcal,
    this.measuredAt,
    this.timerEndsAt,
    this.timerTotalSeconds,
    this.timerExerciseId,
    this.timerSetNumber,
  });

  /// Discrimina este payload de cualquier otro que viaje por el mismo canal.
  ///
  /// No es opcional: el canal lo comparte con la credencial del reloj, y sin
  /// esto un payload de credencial se leería como esfuerzo con todo en null.
  static const String kind = 'watchEffort';

  /// Pulsaciones. Null si el reloj todavía no midió, o si el atleta negó el
  /// permiso de lectura — que son indistinguibles entre sí, medido en F0.
  final int? bpm;

  /// Calorías activas acumuladas en lo que va del entreno.
  final int? kcal;

  /// Cuándo lo midió EL RELOJ, no cuándo llegó al teléfono.
  ///
  /// Esa distinción es la que hace que la regla de antigüedad funcione: la
  /// latencia de WatchConnectivity se midió entre 2 y 24 segundos según la
  /// carga, así que fechar el dato al recibirlo lo haría pasar por más fresco
  /// de lo que es.
  final DateTime? measuredAt;

  /// Cuándo termina el ejercicio POR TIEMPO que corre en el reloj.
  ///
  /// Viaja el INSTANTE DE FIN y no los segundos restantes: así el teléfono
  /// calcula la cuenta solo, sin tráfico por segundo, y un envío que llega
  /// tarde —el reloj throttlea a 5s— sigue mostrando el número correcto.
  ///
  /// Null significa que no hay cronómetro corriendo.
  final DateTime? timerEndsAt;
  final int? timerTotalSeconds;
  final String? timerExerciseId;

  /// CUÁL de las series del ejercicio se está cronometrando.
  ///
  /// Sin esto el teléfono sabe QUÉ ejercicio corre pero no cuál de sus series,
  /// y con tres series por tiempo en el mismo ejercicio tendría que adivinar.
  /// Adivinar por "la próxima sin cargar" falla justo cuando el estado viene
  /// desordenado, que es cuando importa. Es la misma identidad lógica
  /// —ejercicio + número de serie— que usa el resto del sistema.
  final int? timerSetNumber;

  /// Si hay un cronómetro corriendo en el reloj para [exerciseId]/[setNumber].
  ///
  /// Pide los TRES datos —ejercicio, serie e instante de fin— porque con
  /// cualquiera de ellos ausente la cuenta no se puede ubicar, y una cuenta
  /// dibujada en la fila equivocada es peor que ninguna.
  bool timerCorreEn({required String exerciseId, required int setNumber}) =>
      timerEndsAt != null &&
      timerExerciseId == exerciseId &&
      timerSetNumber == setNumber;

  /// Si trae al menos una medición.
  bool get isEmpty => bpm == null && kcal == null;

  // Acá vivía un `toContext()`. Se borró, y el porqué vale la pena:
  //
  // El teléfono NUNCA escribe este payload — sólo lo lee. El que lo escribe es
  // `EffortSnapshot.context(measuredAt:)` en Swift. `toContext()` tenía cero
  // call sites en producción y su único uso era un test de ida y vuelta de
  // Dart contra Dart, que además pasaba por vacuidad: no serializaba ninguno
  // de los campos del cronómetro, así que confirmaba un contrato que no era el
  // real. Peor que no tener nada, porque la suite se veía verde.
  //
  // El contrato de verdad —Swift escribe, Dart lee— vive en
  // `conformance/effort_payload.json` y lo corren los dos lados.

  /// Lee un contexto entrante, o devuelve null si no es de esfuerzo.
  ///
  /// Defensivo a propósito: el payload cruza un puente entre lenguajes, y un
  /// cambio del lado Swift no puede tirar la app del teléfono.
  static WatchEffort? tryParse(Map<String, dynamic> context) {
    if (context['kind'] != kind) return null;

    final ms = context['measuredAtMs'];
    // Sin momento no se puede juzgar la antigüedad.
    if (ms is! int) {
      return null;
    }

    final rawBpm = context['bpm'];
    final rawKcal = context['kcal'];

    // El cronómetro del reloj. Defensivo igual que el resto: si falta o viene
    // mal formado, simplemente no hay cronómetro — nunca tira.
    final rawEnds = context['timerEndsAtMs'];
    final rawTotal = context['timerTotalSeconds'];
    final rawTimerId = context['timerExerciseId'];
    final rawTimerSet = context['timerSetNumber'];

    return WatchEffort(
      timerEndsAt: rawEnds is int
          ? DateTime.fromMillisecondsSinceEpoch(rawEnds, isUtc: true)
          : null,
      timerTotalSeconds: rawTotal is int && rawTotal > 0 ? rawTotal : null,
      timerExerciseId:
          rawTimerId is String && rawTimerId.isNotEmpty ? rawTimerId : null,
      // No existe la serie 0: un 0 acá es un campo sin llenar, no una serie.
      timerSetNumber:
          rawTimerSet is int && rawTimerSet > 0 ? rawTimerSet : null,
      // Un bpm de 0 no es una medición: es un sensor que no enganchó.
      bpm: rawBpm is int && rawBpm > 0 ? rawBpm : null,
      // Un kcal de 0 SÍ es un dato cierto — todavía no se midió consumo.
      // Misma asimetría que en el reloj.
      kcal: rawKcal is int && rawKcal >= 0 ? rawKcal : null,
      measuredAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WatchEffort &&
      other.bpm == bpm &&
      other.kcal == kcal &&
      other.measuredAt == measuredAt &&
      // Los campos del cronómetro TIENEN que estar acá: el notifier compara
      // por igualdad para decidir si re-renderiza, y sin esto un payload que
      // solo cambia el cronómetro se descartaría por "igual al anterior".
      other.timerEndsAt == timerEndsAt &&
      other.timerTotalSeconds == timerTotalSeconds &&
      other.timerExerciseId == timerExerciseId &&
      other.timerSetNumber == timerSetNumber;

  @override
  int get hashCode => Object.hash(
        bpm,
        kcal,
        measuredAt,
        timerEndsAt,
        timerTotalSeconds,
        timerExerciseId,
        timerSetNumber,
      );

  @override
  String toString() => 'WatchEffort(bpm: $bpm, kcal: $kcal, at: $measuredAt, '
      'timerEndsAt: $timerEndsAt)';
}

/// Qué mostrar en el player.
class WatchEffortDisplay {
  const WatchEffortDisplay({this.bpm, this.kcal});

  /// Nada que mostrar: no se dibuja fila, ni vacía.
  const WatchEffortDisplay.nada()
      : bpm = null,
        kcal = null;

  final int? bpm;
  final int? kcal;

  bool get isEmpty => bpm == null && kcal == null;

  @override
  bool operator ==(Object other) =>
      other is WatchEffortDisplay && other.bpm == bpm && other.kcal == kcal;

  @override
  int get hashCode => Object.hash(bpm, kcal);

  @override
  String toString() => 'WatchEffortDisplay(bpm: $bpm, kcal: $kcal)';
}

abstract final class WatchEffortRules {
  /// Cuánto vale un dato del reloj antes de darlo por muerto.
  ///
  /// Más generoso que los 15 segundos que usa el reloj para su propia pantalla,
  /// y no por descuido: acá el dato viene RELAYADO. La latencia de
  /// WatchConnectivity se midió entre 2,0s y 24,4s según la carga de la
  /// máquina, así que un umbral apretado descartaría datos buenos simplemente
  /// porque el teléfono estaba ocupado.
  static const Duration maxAntiguedad = Duration(seconds: 45);

  /// Qué mostrar.
  ///
  /// **Acá la regla se aparta de la del reloj a propósito.** En el reloj las
  /// calorías no caducan: son acumuladas y siguen siendo verdad. En el teléfono
  /// la antigüedad del dato mide otra cosa — si hace 45 segundos que no llega
  /// nada, lo más probable es que el vínculo esté muerto: el entreno terminó,
  /// la app del reloj se cerró, o se perdió el bluetooth.
  ///
  /// Mostrar calorías congeladas en esa situación sugiere una conexión viva que
  /// no existe. Se muestra nada, que es lo cierto.
  static WatchEffortDisplay display({
    required WatchEffort? effort,
    required DateTime now,
  }) {
    if (effort == null) return const WatchEffortDisplay.nada();

    // No hay un chequeo de `isEmpty` acá y no es un olvido: un esfuerzo sin
    // mediciones ya cae en `WatchEffortDisplay(bpm: null, kcal: null)`, que ES
    // `nada()`. Un guard extra seria codigo muerto — se detecto porque la
    // mutacion que lo borraba no ponia ningun test en rojo.

    final medido = effort.measuredAt;
    if (medido == null) return const WatchEffortDisplay.nada();

    // Antigüedad negativa = el reloj va adelantado. Es un problema de reloj, no
    // del atleta, y no tiene por qué borrarle la pantalla.
    final antiguedad = now.difference(medido);
    if (antiguedad > maxAntiguedad) {
      return const WatchEffortDisplay.nada();
    }

    return WatchEffortDisplay(bpm: effort.bpm, kcal: effort.kcal);
  }
}
