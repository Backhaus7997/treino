/// Posición dentro de un plan: qué día toca entrenar y en qué semana.
///
/// `dayNumber` es 1-based (coincide con [RoutineDay.dayNumber]).
/// `weekNumber` es 0-based (coincide con [Session.weekNumber]).
typedef PlanPosition = ({int dayNumber, int weekNumber});

/// Calcula la próxima posición del plan a partir de la última sesión
/// FINALIZADA de esa rutina.
///
/// Extraído de `todaysRoutineProvider` para que la regla sea:
///   1. testeable como función pura, sin levantar un ProviderContainer, y
///   2. **replicable byte a byte por el cliente watchOS**, que la reimplementa
///      en Swift. Los fixtures compartidos de `conformance/plan_advance.json`
///      son el contrato entre ambas implementaciones — si divergen, el
///      historial del usuario se corrompe en silencio, que es el riesgo
///      estructural #1 del change `watch-standalone-client`.
///
/// Reglas (idénticas a las que vivían inline en el provider):
///
/// * **Primera sesión de la rutina** ([lastFinished] null) → día 1, semana 0.
/// * **Avance de día**: `(último % numDays) + 1`. Rota Día 5 → Día 1.
/// * **Avance de semana**: solo cuando el día da la vuelta. Mientras
///   `últimoDía < numDays` se queda en la misma semana; al dar la vuelta pasa
///   a `(últimaSemana + 1) % numWeeks`.
/// * **Días salteados**: es último-completado + 1, puro. Si el atleta saltea
///   el Día 2 y solo hace Día 1 y Día 3, el próximo es el Día 4 — no el Día 2
///   que se perdió. Mismo criterio que Hevy/Strong.
/// * **[numWeeks] <= 0**: se trata como 1. Un doc de Firestore corrupto o
///   legacy con `numWeeks: 0` explícito esquiva el `?? 1` del `fromJson`
///   generado (que solo cubre el campo AUSENTE), y `% 0` tira
///   `IntegerDivisionByZeroException`. Mismo guard que `derivePlanProgress`
///   y `SessionNotifier._buildFresh`.
///
/// [numDays] debe ser >= 1: el llamador ya descartó las rutinas sin días
/// (`routine.days.isEmpty`) antes de llegar acá.
PlanPosition nextPlanPosition({
  required PlanPosition? lastFinished,
  required int numDays,
  required int numWeeks,
}) {
  assert(numDays >= 1, 'numDays debe ser >= 1; llegó $numDays');

  if (lastFinished == null) {
    return (dayNumber: 1, weekNumber: 0);
  }

  final nextDayNumber = (lastFinished.dayNumber % numDays) + 1;

  final effectiveWeeks = numWeeks > 0 ? numWeeks : 1;
  // La semana rota SOLO cuando el día da la vuelta. Para planes no
  // periodizados numWeeks es 1, así que el módulo es un no-op.
  final rolledOver = lastFinished.dayNumber >= numDays;
  final weekNumber = rolledOver
      ? (lastFinished.weekNumber + 1) % effectiveWeeks
      : lastFinished.weekNumber;

  return (dayNumber: nextDayNumber, weekNumber: weekNumber);
}
