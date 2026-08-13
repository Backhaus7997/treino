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
