/// La cuenta regresiva de un ejercicio POR TIEMPO.
///
/// ── Por qué esto existe como regla pura ─────────────────────────────────
///
/// La regla estaba escrita DOS VECES y de dos maneras distintas. En el reloj,
/// `CountdownRules.swift`: guardar el instante de fin y restar contra la hora
/// actual. En el teléfono, adentro del `State` de `_DurationSetRow`: un
/// `Timer.periodic` de un segundo que decrementaba un contador.
///
/// Las dos daban el mismo número mientras nada las molestara, y por eso la
/// divergencia era invisible. Pero un contador de ticks se ATRASA apenas el
/// sistema estrangula la app —pantalla bloqueada, batería baja, otra app
/// adelante—: los ticks que no corren no se recuperan. Para un descanso eso se
/// tolera. Para un ejercicio por tiempo no: una plancha de 60 segundos que
/// dura 70 no es la misma serie, y el atleta no tiene cómo notarlo.
///
/// Contar contra el reloj de pared da el número correcto aunque no se ejecute
/// un solo tick. Los ticks pasan a ser lo único que son: cuándo REDIBUJAR.
///
/// El contrato compartido vive en `conformance/duration_timer.json`.
/// Implementación hermana: `ios/TreinoWatch Watch App/CountdownRules.swift`.
library;

abstract final class DurationTimerRules {
  /// Cada cuánto conviene redibujar la cuenta.
  ///
  /// Medio segundo y no uno: con un tick de un segundo el número mostrado
  /// puede quedar hasta ~1s desfasado del real, porque el tick y el segundo de
  /// pared no están alineados. No cuesta nada y es el mismo intervalo que usa
  /// el reloj.
  ///
  /// Que esto se pueda cambiar sin tocar la cuenta ES la propiedad que se
  /// buscaba: el intervalo de redibujo ya no es la fuente de la verdad.
  static const Duration tickInterval = Duration(milliseconds: 500);

  /// Cuándo termina una serie de [totalSeconds] arrancada en [start].
  static DateTime endsAt({
    required DateTime start,
    required int totalSeconds,
  }) =>
      start.add(Duration(seconds: totalSeconds));

  /// Segundos que faltan, nunca negativos.
  ///
  /// Se redondea hacia ARRIBA: mientras quede una fracción de segundo, la
  /// serie no terminó. Mostrar 0 con tiempo restante no solo miente — invita a
  /// cortar antes, y en un ejercicio por tiempo cortar antes es hacer otra
  /// serie.
  static int remaining({required DateTime endsAt, required DateTime now}) {
    final microsegundos = endsAt.difference(now).inMicroseconds;
    if (microsegundos <= 0) return 0;
    // Techo con aritmética entera. Dividir en punto flotante y llamar a
    // `ceil()` daría 2 en vez de 1 para diferencias que son exactamente un
    // segundo pero se representan como 1.0000000000000002.
    const porSegundo = Duration.microsecondsPerSecond;
    return (microsegundos + porSegundo - 1) ~/ porSegundo;
  }

  /// Si la cuenta llegó a cero.
  static bool isFinished({required DateTime endsAt, required DateTime now}) =>
      remaining(endsAt: endsAt, now: now) == 0;
}
