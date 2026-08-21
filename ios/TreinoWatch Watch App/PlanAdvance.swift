//
//  PlanAdvance.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F2.
//

import Foundation

/// Posición dentro de un plan: qué día toca entrenar y en qué semana.
///
/// `dayNumber` es 1-based, `weekNumber` es 0-based.
struct PlanPosition: Equatable {
    let dayNumber: Int
    let weekNumber: Int
}

/// Calcula la próxima posición del plan a partir de la última sesión
/// FINALIZADA de esa rutina.
///
/// ⚠️ **PUERTO LITERAL de `nextPlanPosition` en
/// `lib/features/workout/domain/plan_advance.dart`.** No es "una
/// implementación equivalente": es la misma regla escrita dos veces, que es
/// exactamente el riesgo estructural de este change. Si una cambia y la otra
/// no, el historial del usuario se corrompe en silencio.
///
/// Los fixtures de `conformance/plan_advance.json` son el contrato entre las
/// dos, y `conformance/run_swift.sh` los corre contra ESTA función. Si tocás
/// esto sin tocar el Dart —o al revés— el corredor se pone rojo.
///
/// Reglas:
/// * Primera sesión de la rutina (`lastFinished == nil`) → día 1, semana 0.
/// * Avance de día: `(último % numDays) + 1`. Rota Día 5 → Día 1.
/// * La semana avanza SOLO cuando el día da la vuelta, a
///   `(últimaSemana + 1) % numWeeks`.
/// * Días salteados: es último-completado + 1, puro.
/// * `numWeeks <= 0` se trata como 1 — un doc corrupto con `numWeeks: 0`
///   explícito haría `% 0`, que en Swift ES UN CRASH (igual que la
///   `IntegerDivisionByZeroException` de Dart).
///
/// `numDays` debe ser >= 1: el llamador ya descartó las rutinas sin días.
func nextPlanPosition(
    lastFinished: PlanPosition?,
    numDays: Int,
    numWeeks: Int
) -> PlanPosition {
    precondition(numDays >= 1, "numDays debe ser >= 1; llegó \(numDays)")

    guard let last = lastFinished else {
        return PlanPosition(dayNumber: 1, weekNumber: 0)
    }

    let nextDayNumber = (last.dayNumber % numDays) + 1

    let effectiveWeeks = numWeeks > 0 ? numWeeks : 1
    let rolledOver = last.dayNumber >= numDays
    let weekNumber = rolledOver
        ? (last.weekNumber + 1) % effectiveWeeks
        : last.weekNumber

    return PlanPosition(dayNumber: nextDayNumber, weekNumber: weekNumber)
}
