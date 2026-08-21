//
//  SupersetOrder.swift
//  TreinoWatch Watch App
//
//  El orden en que se recorre una superserie.
//
//  ── Por que existe ──────────────────────────────────────────────────────
//
//  El reloj NO sabia que las superseries existian: `TodaysWorkout.swift` ni
//  leia `supersetGroup`, asi que aplanaba el bloque en una lista de ejercicios
//  sueltos y su cursor avanzaba ejercicio por ejercicio.
//
//  Medido en hardware el 2026-08-19, con tres ejercicios A, B, C de tres series:
//  el atleta veia SOLO el ejercicio A en la muneca y, despues de marcar 1a, lo
//  unico marcable era 2a. El dato quedaba valido —misma identidad logica que
//  usa el telefono, mismos documentos— pero producido en el orden equivocado.
//
//  Y ahi esta el dano: una superserie hecha como tres ejercicios seguidos ES
//  OTRO ENTRENAMIENTO. No es un problema de pantalla, es el estimulo.
//
//  El contrato compartido con Dart vive en `conformance/superset_order.json`.
//  Fuente de verdad: `lib/features/workout/domain/superset_order.dart`.
//

import Foundation

/// Un miembro del bloque, con lo unico que la regla necesita saber.
struct SupersetMember: Equatable {
    let exerciseId: String
    let plannedSets: Int
    /// CANTIDAD de series cargadas, no numeros de serie. Igual que en Dart.
    let loggedSets: Int
}

/// La celda que toca AHORA.
///
/// `round` coincide con `setNumber` por construccion: en la vuelta N de una
/// superserie se hace la serie N de cada miembro.
struct SupersetCell: Equatable {
    let exerciseId: String
    let setNumber: Int
    let round: Int
}

enum SupersetOrder {

    /// Vueltas totales del bloque: las del miembro mas largo.
    ///
    /// Un miembro con menos series se saltea en las vueltas que le sobran; no
    /// acorta el bloque.
    static func totalRounds(_ members: [SupersetMember]) -> Int {
        members.reduce(0) { $1.plannedSets > $0 ? $1.plannedSets : $0 }
    }

    /// La primera celda sin hacer, recorriendo VUELTA por vuelta.
    ///
    /// Devuelve nil cuando el bloque esta completo.
    ///
    /// El anidamiento ES la regla, y es exactamente lo que el reloj tenia al
    /// reves: la vuelta va AFUERA y el ejercicio ADENTRO. Eso produce
    /// 1a, 1b, 1c, 2a, 2b, 2c... y no 1a, 2a, 3a, 1b...
    static func nextCell(_ members: [SupersetMember]) -> SupersetCell? {
        let vueltas = totalRounds(members)
        guard vueltas > 0 else { return nil }
        for vuelta in 1...vueltas {
            for m in members {
                if vuelta > m.plannedSets { continue }
                if m.loggedSets < vuelta {
                    return SupersetCell(
                        exerciseId: m.exerciseId,
                        setNumber: vuelta,
                        round: vuelta
                    )
                }
            }
        }
        return nil
    }
}
