/// El cronómetro de una serie POR TIEMPO, tal como queda anotado en la sesión.
///
/// ── Por qué no alcanzaba con el shape que ya había ────────────────────────
///
/// `WatchTimerCommand` describe este mismo cronómetro, pero como MENSAJE: viaja
/// una vez, en una dirección, y el CANAL por el que llega ya dice de quién es la
/// serie —el teléfono sólo manda los suyos, el reloj sólo publica los suyos—.
///
/// Acá el canal es un DOCUMENTO COMPARTIDO: los dos aparatos escriben y leen el
/// mismo lugar, así que el canal dejó de decirlo. Por eso [owner] viaja
/// explícito, y es lo único que este shape tiene de más. Sin él la regla que
/// evita el bug —**el lado que arranca es el dueño de la serie; el otro la
/// espeja y no la carga**— no se puede evaluar: los dos leerían el mismo
/// documento, los dos llegarían a cero, y los dos cargarían la serie.
///
/// ── Viaja el INSTANTE DE FIN ──────────────────────────────────────────────
///
/// No los segundos que faltan ni el instante de arranque: [endsAt]. Los dos
/// lados derivan la cuenta de ahí contra su propio reloj de pared con
/// [DurationTimerRules], la aritmética que ya está bajo contrato con Swift en
/// `conformance/duration_timer.json`. Una lectura que llega tarde sigue dando el
/// número correcto, y no hay tráfico por segundo.
///
/// Antes esta rama mandaba `seconds` + `startedAtMs` y restaba lo transcurrido
/// con una función propia. Daba el mismo número, y esa era justamente la
/// trampa: dos aritméticas para una sola regla divergen en silencio, que es el
/// problema que `conformance/duration_timer.json` existe para cerrar.
library;

import 'duration_timer.dart';
import 'duration_timer_owner.dart';

/// Hay a lo sumo UNO por sesión: un atleta aguanta una plancha por vez.
class DurationTimerState {
  const DurationTimerState({
    required this.exerciseId,
    required this.setNumber,
    required this.totalSeconds,
    required this.endsAt,
    required this.owner,
  });

  /// La que acaba de arrancar en [start], de [totalSeconds], y es de [owner].
  ///
  /// El instante de fin se deriva con la MISMA regla que después lo va a leer,
  /// y no a mano: si un lado lo calculara distinto, la divergencia recién se
  /// vería con los dos números a la vista, uno en la muñeca y otro en la mano.
  factory DurationTimerState.startedAt({
    required String exerciseId,
    required int setNumber,
    required int totalSeconds,
    required DateTime start,
    required DurationTimerOwner owner,
  }) =>
      DurationTimerState(
        exerciseId: exerciseId,
        setNumber: setNumber,
        totalSeconds: totalSeconds,
        endsAt: DurationTimerRules.endsAt(
          start: start,
          totalSeconds: totalSeconds,
        ),
        owner: owner,
      );

  /// El cronómetro que el RELOJ publica, si el payload trae todo lo que hace
  /// falta para ubicarlo.
  ///
  /// Los cuatro datos se piden juntos y se devuelve `null` ante cualquier
  /// faltante: una cuenta sin identidad no se puede dibujar en una fila, y
  /// dibujarla en la equivocada es peor que no dibujarla. Es la misma exigencia
  /// que ya hace [DurationTimerOwnership.resolve], puesta en el borde donde
  /// entran los datos.
  static DurationTimerState? fromWatch({
    required String? exerciseId,
    required int? setNumber,
    required int? totalSeconds,
    required DateTime? endsAt,
  }) {
    if (exerciseId == null || exerciseId.isEmpty) return null;
    if (setNumber == null || setNumber <= 0) return null;
    if (totalSeconds == null || totalSeconds <= 0) return null;
    if (endsAt == null) return null;
    return DurationTimerState(
      exerciseId: exerciseId,
      setNumber: setNumber,
      totalSeconds: totalSeconds,
      endsAt: endsAt,
      owner: DurationTimerOwner.reloj,
    );
  }

  /// Qué serie de qué ejercicio se está cronometrando.
  final String exerciseId;
  final int setNumber;

  /// Lo que el plan pide. Se guarda además de [endsAt] porque la pantalla del
  /// reloj dibuja un anillo de progreso, y sin el total no hay fracción.
  final int totalSeconds;

  /// Cuándo termina, en UTC. **La fuente de la verdad.**
  final DateTime endsAt;

  /// Quién la arrancó. Nunca [DurationTimerOwner.nadie]: un cronómetro anotado
  /// siempre tuvo alguien que lo arrancó, y `nadie` es la ausencia de
  /// cronómetro, que se representa con la ausencia del [DurationTimerState].
  final DurationTimerOwner owner;

  int remainingAt(DateTime now) =>
      DurationTimerRules.remaining(endsAt: endsAt, now: now);

  bool isFinishedAt(DateTime now) =>
      DurationTimerRules.isFinished(endsAt: endsAt, now: now);

  /// Si esta cuenta es la de esa fila.
  bool aplicaA({required String exerciseId, required int setNumber}) =>
      this.exerciseId == exerciseId && this.setNumber == setNumber;

  @override
  bool operator ==(Object other) =>
      other is DurationTimerState &&
      other.exerciseId == exerciseId &&
      other.setNumber == setNumber &&
      other.totalSeconds == totalSeconds &&
      other.endsAt == endsAt &&
      other.owner == owner;

  @override
  int get hashCode =>
      Object.hash(exerciseId, setNumber, totalSeconds, endsAt, owner);

  @override
  String toString() => 'DurationTimerState($exerciseId #$setNumber, '
      '${totalSeconds}s, endsAt: $endsAt, owner: ${owner.name})';
}
