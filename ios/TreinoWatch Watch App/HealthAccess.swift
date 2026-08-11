//
//  HealthAccess.swift
//  TreinoWatch Watch App
//
//  Change `watch-workout-session`, fase F0.
//
//  Que le pide TREINO a la app Salud, y como se lee la respuesta.
//
//  ESTE ARCHIVO NO IMPORTA HealthKit, a proposito. HealthKit no existe en
//  macOS, asi que dejar la decision acá —separada del framework— es lo que
//  permite testearla en el host en segundos (`scripts/test_watch_swift.sh`) en
//  vez de depender de un simulador. El puente que si toca HealthKit vive en
//  `HealthStore.swift` y no toma ninguna decision.
//

import Foundation

/// En que quedo el pedido de permiso a Salud.
enum HealthAccessState: Equatable {
    /// El dispositivo no tiene Salud. Pasa en el simulador; en un Apple Watch
    /// real, no.
    case unsupported

    /// Todavia no se le pregunto al atleta.
    case notRequested

    /// Salud ya contesto.
    ///
    /// Fijarse que solo figura la ESCRITURA. No es un olvido: HealthKit **no
    /// revela** si el atleta nego la LECTURA — `authorizationStatus(for:)`
    /// contesta sobre los tipos de escritura, y para los de lectura devuelve
    /// siempre `notDetermined` para no filtrar que alguien no tiene datos de
    /// ese tipo.
    ///
    /// O sea: de la lectura nos enteramos recien cuando llegan —o no llegan—
    /// pulsaciones, en F2. Modelarlo de otra forma seria mentir.
    case resolved(canWriteWorkouts: Bool)

    /// Salud fallo. El entreno sigue igual (D2).
    case failed(String)

    /// D2, decision FIRMADA por el dueño: si el atleta niega el permiso, el
    /// entreno funciona igual, sin pulsaciones y sin degradar nada mas.
    ///
    /// Siempre `false`, a proposito. Es un alambre de trampa: el dia que
    /// alguien necesite que esto devuelva `true` esta cambiando una decision
    /// firmada, y eso vuelve al dueño — no se arregla tocando esta linea.
    var blocksWorkout: Bool { false }
}

/// Espejo de `HKAuthorizationStatus`, con los mismos valores crudos.
///
/// Existe para que la regla de decision no necesite importar HealthKit y se
/// pueda testear en el host. El puente traduce de uno al otro.
enum HealthShareAuthorization: Int {
    case notDetermined = 0
    case sharingDenied = 1
    case sharingAuthorized = 2
}

enum HealthAccess {
    /// Tipos que se LEEN: el esfuerzo en vivo mientras el atleta entrena (F2).
    ///
    /// El alcance de esta lista es una decision de PRIVACIDAD, no un detalle
    /// tecnico. Cada identificador de mas es un dato del atleta que TREINO no
    /// necesita, y algo que Apple pregunta en la review. Agregar uno pasa por
    /// el test que fija la lista, no por acá solo.
    nonisolated static let readIdentifiers: [String] = [
        "HKQuantityTypeIdentifierHeartRate",
        "HKQuantityTypeIdentifierActiveEnergyBurned",
    ]

    /// Tipos que se ESCRIBEN: el entreno va a Salud para que cuente en los
    /// anillos y en el historial del atleta (D3, firmada).
    nonisolated static let shareIdentifiers: [String] = [
        "HKWorkoutTypeIdentifier",
        "HKQuantityTypeIdentifierActiveEnergyBurned",
    ]

    /// Si corresponde pedirle permiso al atleta.
    ///
    /// Salud no vuelve a mostrar la hoja una vez que el atleta contesto, pero
    /// pedirlo igual gasta un viaje en cada entreno. Un FALLO si se reintenta:
    /// que Salud no conteste no es lo mismo que el atleta diciendo que no.
    nonisolated static func shouldRequest(
        current: HealthAccessState,
        isHealthDataAvailable: Bool
    ) -> Bool {
        guard isHealthDataAvailable else { return false }

        switch current {
        case .notRequested, .failed:
            return true
        case .resolved, .unsupported:
            return false
        }
    }

    /// Como queda el estado despues de que Salud contesta.
    ///
    /// `notDetermined` despues de pedir permiso no es un caso raro: es lo que
    /// contesta Salud cuando el atleta cierra la hoja sin decidir. Se toma como
    /// "no se puede escribir", que es la lectura conservadora y la unica que no
    /// termina en un intento de escritura que falla.
    nonisolated static func stateAfterRequest(
        shareStatus: HealthShareAuthorization
    ) -> HealthAccessState {
        .resolved(canWriteWorkouts: shareStatus == .sharingAuthorized)
    }
}
