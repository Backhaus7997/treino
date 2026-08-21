//
//  ExerciseCursor.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, tanda de bugfixes de sincronizacion.
//

import Foundation

/// En que ejercicio tiene que estar parado el reloj.
///
/// Es una regla PURA y vive afuera del coordinator para poder medirla en el
/// host: el cursor es de lo mas incomodo de verificar corriendo, porque depende
/// de lo que el OTRO dispositivo hizo mientras el reloj no miraba.
///
/// ⚠️ SIEMPRE ABSOLUTO, NUNCA UN DELTA. El cursor se movia con
/// `currentExerciseIndex += 1`, y avanzaba un solo paso aunque en un mismo sync
/// entraran tres ejercicios enteros cargados desde el telefono. El atleta
/// entrenaba un rato en el celular, miraba la muñeca, y la encontraba clavada en
/// un ejercicio ya terminado: sin fila tocable —todas sus series estaban hechas—
/// y sin boton de Terminar.
///
/// Es la misma trampa del §4.5 del HANDOFF que ya mordio a `logSet` y a
/// `removeSet`. La leccion, con cuatro casos ya: no preguntarse cuanto se movio
/// el mundo, recalcular.
///
/// Tiene que poder RETROCEDER, ademas: si el telefono borro una serie del
/// ejercicio en curso, ese ejercicio dejo de estar completo y hay que volver a
/// ofrecerlo.
///
/// - Parameters:
///   - seriesPlanificadas: cuantas series pide el plan por ejercicio, en orden.
///   - seriesCargadas: cuantas hay cargadas por ejercicio, en el mismo orden.
/// - Returns: el indice del primer ejercicio incompleto. Si estan todos
///   completos devuelve el ULTIMO, para que el atleta vea que termino en vez de
///   una pantalla vacia. Con la lista vacia devuelve 0: un indice negativo se
///   usaria para indexar y reventaria.
func firstUnfinishedExerciseIndex(
    seriesPlanificadas: [Int],
    seriesCargadas: [Int]
) -> Int {
    guard !seriesPlanificadas.isEmpty else { return 0 }
    for (index, planificadas) in seriesPlanificadas.enumerated() {
        let cargadas = index < seriesCargadas.count ? seriesCargadas[index] : 0
        if cargadas < planificadas { return index }
    }
    return seriesPlanificadas.count - 1
}

// MARK: - Superseries

/// Un ejercicio, con lo que el cursor necesita para ubicarlo en su bloque.
struct CursorExercise: Equatable {
    let exerciseId: String
    let plannedSets: Int
    let loggedSets: Int
    let supersetGroup: Int?
}

/// Que celda ofrecerle al atleta: que ejercicio y que serie.
struct CursorPosition: Equatable {
    /// Indice en la lista original, para no cambiar como el reloj indexa.
    let exerciseIndex: Int
    let setNumber: Int
    /// Cuando la celda pertenece a una superserie, en que vuelta va y de
    /// cuantas. Nil para un ejercicio suelto.
    let round: Int?
    let totalRounds: Int?
}

/// Bloques del entreno: corridas CONSECUTIVAS de ejercicios que comparten el
/// mismo `supersetGroup` no nulo. Un ejercicio tagueado SOLO degrada a suelto,
/// igual que en Dart (`buildBlocks` en `session_player_screen.dart`).
func supersetBlocks(_ exercises: [CursorExercise]) -> [[Int]] {
    var bloques: [[Int]] = []
    var i = 0
    while i < exercises.count {
        if let grupo = exercises[i].supersetGroup {
            var scan = i
            var miembros: [Int] = []
            while scan < exercises.count, exercises[scan].supersetGroup == grupo {
                miembros.append(scan)
                scan += 1
            }
            if miembros.count >= 2 {
                bloques.append(miembros)
                i = scan
                continue
            }
        }
        bloques.append([i])
        i += 1
    }
    return bloques
}

/// La celda que toca AHORA, respetando las superseries.
///
/// Reemplaza a `firstUnfinishedExerciseIndex` cuando hay bloques: ese recorria
/// ejercicio por ejercicio, que es correcto para ejercicios sueltos y ERRADO
/// para una superserie. Dentro de un bloque la vuelta va afuera y el ejercicio
/// adentro, que es la regla compartida de `conformance/superset_order.json`.
///
/// Si esta todo completo devuelve la ULTIMA celda, para que el atleta vea que
/// termino en vez de una pantalla vacia — mismo criterio que el cursor viejo.
func cursorPosition(_ exercises: [CursorExercise]) -> CursorPosition {
    guard !exercises.isEmpty else {
        return CursorPosition(exerciseIndex: 0, setNumber: 1, round: nil, totalRounds: nil)
    }

    for bloque in supersetBlocks(exercises) {
        if bloque.count == 1 {
            let i = bloque[0]
            let e = exercises[i]
            if e.loggedSets < e.plannedSets {
                return CursorPosition(
                    exerciseIndex: i,
                    setNumber: e.loggedSets + 1,
                    round: nil,
                    totalRounds: nil
                )
            }
            continue
        }

        let miembros = bloque.map {
            SupersetMember(
                exerciseId: exercises[$0].exerciseId,
                plannedSets: exercises[$0].plannedSets,
                loggedSets: exercises[$0].loggedSets
            )
        }
        if let celda = SupersetOrder.nextCell(miembros) {
            // El indice sale del bloque, no de un `firstIndex` global: dos
            // ejercicios distintos pueden compartir exerciseId en teoria, y
            // buscar por id agarraria el equivocado.
            let idx = bloque.first { exercises[$0].exerciseId == celda.exerciseId } ?? bloque[0]
            return CursorPosition(
                exerciseIndex: idx,
                setNumber: celda.setNumber,
                round: celda.round,
                totalRounds: SupersetOrder.totalRounds(miembros)
            )
        }
    }

    // Todo completo: la ultima celda del ultimo ejercicio.
    let ultimo = exercises.count - 1
    return CursorPosition(
        exerciseIndex: ultimo,
        setNumber: max(1, exercises[ultimo].plannedSets),
        round: nil,
        totalRounds: nil
    )
}
