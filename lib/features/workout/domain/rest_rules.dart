/// El descanso entre series, COMPARTIDO entre el teléfono y el reloj (#1616).
///
/// ── El problema ─────────────────────────────────────────────────────────
///
/// Desde #1579 el teléfono tenía su descanso y cada reloj el suyo, y si el
/// atleta entrenaba con los dos corrían DOS descansos independientes: SALTAR o
/// +15 s en uno no se veía en el otro, y cada uno avisaba por su cuenta.
///
/// ── La decisión ─────────────────────────────────────────────────────────
///
/// El descanso pasa a ser ESTADO de la sesión, igual que el cronómetro del
/// ejercicio por tiempo (`DurationTimerState`): un instante de fin en tiempo de
/// pared, en el documento que los tres aparatos ya leen. Cada uno lo ESPEJA
/// contra su propio reloj, así que los avisos caen en el mismo instante.
///
/// **El documento es un registro único y gana el que escribe último.** Nadie
/// reescribe al espejar —sólo escriben las acciones del atleta: marcar una
/// serie, SALTAR, +15 s—, así que no hay ping-pong y los aparatos convergen al
/// último valor que aceptó el servidor. Se eligió esto y no "gana el dueño"
/// porque en un descanso no hay nada que dependa del dueño: nadie carga una
/// serie al llegar a cero, a diferencia del cronómetro por tiempo. Si los dos
/// marcan casi a la vez, los dos descansos difieren en lo que tardó en cruzar
/// la red, y cualquiera de los dos es correcto.
///
/// Esta librería es la aritmética pura, bajo contrato con Swift en
/// `conformance/rest_timer.json`. Implementación hermana:
/// `ios/TreinoWatch Watch App/RestRules.swift`.
library;

import 'duration_timer.dart';

/// Qué hace un aparato con el descanso que lee de la sesión.
enum RestMirrorAction {
  /// Nada: lo que muestra ya es lo que dice la sesión.
  keep,

  /// Pasa a mostrar el descanso de la sesión (arranca, se estiró, o es otro).
  adopt,

  /// Corta el suyo: en la sesión ya no hay descanso (lo saltaron del otro lado).
  stop,
}

abstract final class RestRules {
  /// Cuánto suma el botón «+15 s».
  static const int extraSeconds = 15;

  /// Hasta dónde dos instantes de fin se consideran EL MISMO descanso.
  ///
  /// Existe por Wear OS: su descanso vive en el nativo, contado en
  /// `elapsedRealtime`, y para compararlo con la sesión se lo pasa a tiempo de
  /// pared con una resta. Esa resta corre unos milisegundos, y sin tolerancia
  /// el eco de la escritura propia reiniciaría la alarma nativa en cada
  /// lectura. Medio segundo está por debajo de lo que se ve —la cuenta se
  /// muestra en segundos— y muy por debajo de un +15 s, que siempre se detecta.
  static const Duration mirrorTolerance = Duration(milliseconds: 500);

  /// Cuándo termina un descanso de [totalSeconds] arrancado en [start].
  ///
  /// Redondeado al MILISEGUNDO más cercano, que es la resolución con la que
  /// viaja en la sesión. Sin esto el valor local tendría microsegundos y el eco
  /// de la propia escritura volvería distinto de lo que se escribió.
  ///
  /// Al más cercano y no truncado, por Swift: allá un instante es un `Double`
  /// de segundos, y 1800000000,123 s puede guardarse como ...122,9999 ms.
  /// Truncar ahí daría un milisegundo menos que acá; redondear da lo mismo en
  /// los dos lados.
  static DateTime endsAt({required DateTime start, required int totalSeconds}) {
    final finUs =
        start.add(Duration(seconds: totalSeconds)).microsecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(
      (finUs + 500) ~/ 1000,
      isUtc: true,
    );
  }

  /// Segundos que faltan, redondeados hacia ARRIBA y nunca negativos.
  ///
  /// Es la MISMA aritmética que el ejercicio por tiempo, y a propósito: si el
  /// descanso contara distinto, el número de la muñeca y el de la mano se
  /// separarían en el último segundo.
  static int remaining({required DateTime endsAt, required DateTime now}) =>
      DurationTimerRules.remaining(endsAt: endsAt, now: now);

  static bool isFinished({required DateTime endsAt, required DateTime now}) =>
      DurationTimerRules.isFinished(endsAt: endsAt, now: now);

  /// «+15 s»: corre el fin y el total, o null si no hay descanso que estirar.
  ///
  /// Sobre un descanso VENCIDO no hace nada. Sumarle 15 al instante de fin de
  /// uno que terminó hace un minuto daría otro instante en el pasado: un botón
  /// que no hace nada y además escribe en la sesión.
  static ({DateTime endsAt, int totalSeconds})? extend({
    required DateTime endsAt,
    required int totalSeconds,
    required int seconds,
    required DateTime now,
  }) {
    if (isFinished(endsAt: endsAt, now: now)) return null;
    if (seconds <= 0) return (endsAt: endsAt, totalSeconds: totalSeconds);
    return (
      endsAt: endsAt.add(Duration(seconds: seconds)),
      totalSeconds: totalSeconds + seconds,
    );
  }

  /// Qué hacer con el descanso que dice la sesión.
  ///
  /// [local] es el instante de fin del descanso que este aparato muestra, o
  /// null. [remote] es el de la sesión, o null si no hay.
  /// [localPending] es un cambio LOCAL que todavía no se pudo escribir: el
  /// reloj de Apple no tiene listeners y escribe por REST, así que puede tener
  /// un SALTAR o un descanso propio en vuelo. Ese cambio es el más nuevo y va a
  /// ganar cuando llegue, así que lo que diga la sesión mientras tanto es
  /// viejo. Los clientes con el SDK de Firestore no lo necesitan: su propia
  /// escritura ya aparece en lo que leen, aun sin red.
  static RestMirrorAction decide({
    required DateTime? local,
    required DateTime? remote,
    bool localPending = false,
    required DateTime now,
  }) {
    if (localPending) return RestMirrorAction.keep;

    final localVivo = local != null && !isFinished(endsAt: local, now: now);
    final remotoVivo = remote != null && !isFinished(endsAt: remote, now: now);

    if (remotoVivo) {
      if (localVivo && local.difference(remote).abs() <= mirrorTolerance) {
        return RestMirrorAction.keep;
      }
      return RestMirrorAction.adopt;
    }
    // En la sesión no hay descanso vivo: si acá sí, alguien lo saltó.
    return localVivo ? RestMirrorAction.stop : RestMirrorAction.keep;
  }
}
