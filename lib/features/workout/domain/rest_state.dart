/// El descanso en curso, tal como queda anotado en la sesión (#1616).
///
/// Mismo shape que `DurationTimerState` —identidad, total, INSTANTE DE FIN y
/// quién lo arrancó— y por los mismos motivos, que están escritos allá y en
/// `rest_rules.dart`. Lo que cambia es para qué sirve el dueño: en un descanso
/// nadie carga una serie al llegar a cero, así que [owner] no decide nada del
/// lado del producto. Viaja para que el que lo lea sepa de dónde vino —por
/// ejemplo, la notificación de #1617 puede no avisar en el teléfono lo que ya
/// vibró en la muñeca— y para poder diagnosticar una sesión mirando el doc.
library;

import 'rest_rules.dart';

/// Qué aparato arrancó el descanso.
enum RestOwner {
  telefono,

  /// Cualquiera de los dos relojes: Wear OS o Apple Watch. Desde la sesión no
  /// se distinguen y no hace falta — son la misma muñeca.
  reloj,
}

class RestState {
  const RestState({
    required this.exerciseId,
    required this.setNumber,
    required this.totalSeconds,
    required this.endsAt,
    required this.owner,
  });

  /// El que arranca al marcar la serie [setNumber] de [exerciseId] en [start].
  ///
  /// El instante de fin sale de [RestRules.endsAt], la misma regla que usa el
  /// reloj de Apple: si cada lado lo calculara a mano, la diferencia recién se
  /// vería con los dos números a la vista.
  ///
  /// [start] se trunca al milisegundo ANTES de pasárselo. [RestRules.endsAt]
  /// redondea el fin al milisegundo más cercano, y con un inicio de
  /// microsegundos ≥ 500 eso deja el fin hasta 0,5 ms DESPUÉS de inicio + total:
  /// en el instante de marcar faltaban 90,0004 s, el techo daba 91 y la barra
  /// —que tickea cada segundo— mostraba «1:31» un segundo entero en un descanso
  /// de 90, con el lector de pantalla anunciando «1 minuto 31 segundos». Con el
  /// inicio ya en el milisegundo el redondeo no mueve nada y el fin cae justo
  /// en inicio + total.
  factory RestState.startedAt({
    required String exerciseId,
    required int setNumber,
    required int totalSeconds,
    required DateTime start,
    required RestOwner owner,
  }) =>
      RestState(
        exerciseId: exerciseId,
        setNumber: setNumber,
        totalSeconds: totalSeconds,
        endsAt: RestRules.endsAt(
          start: DateTime.fromMillisecondsSinceEpoch(
            start.millisecondsSinceEpoch,
            isUtc: true,
          ),
          totalSeconds: totalSeconds,
        ),
        owner: owner,
      );

  /// La serie cuyo marcado lo arrancó.
  final String exerciseId;
  final int setNumber;

  /// Duración total, contando los +15 s. Es lo que llena la barra de progreso.
  final int totalSeconds;

  /// Cuándo termina, en UTC y al milisegundo. **La fuente de la verdad.**
  final DateTime endsAt;

  final RestOwner owner;

  int remainingAt(DateTime now) =>
      RestRules.remaining(endsAt: endsAt, now: now);

  bool isFinishedAt(DateTime now) =>
      RestRules.isFinished(endsAt: endsAt, now: now);

  /// El mismo descanso, [seconds] más largo, o null si ya terminó.
  ///
  /// Conserva identidad y dueño: estirarlo no lo vuelve otro descanso.
  RestState? extendedBy(int seconds, {required DateTime now}) {
    final e = RestRules.extend(
      endsAt: endsAt,
      totalSeconds: totalSeconds,
      seconds: seconds,
      now: now,
    );
    if (e == null) return null;
    return RestState(
      exerciseId: exerciseId,
      setNumber: setNumber,
      totalSeconds: e.totalSeconds,
      endsAt: e.endsAt,
      owner: owner,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RestState &&
      other.exerciseId == exerciseId &&
      other.setNumber == setNumber &&
      other.totalSeconds == totalSeconds &&
      other.endsAt.isAtSameMomentAs(endsAt) &&
      other.owner == owner;

  @override
  int get hashCode => Object.hash(
        exerciseId,
        setNumber,
        totalSeconds,
        endsAt.millisecondsSinceEpoch,
        owner,
      );

  @override
  String toString() => 'RestState($exerciseId #$setNumber, ${totalSeconds}s, '
      'endsAt: $endsAt, owner: ${owner.name})';
}
