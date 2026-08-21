//
//  HealthAccess.swift
//  TreinoWatch Watch App
//
//  Change `watch-workout-session`, fase F0.
//
//  Que le pide TREINO a la app Salud, y como se lee la respuesta.
//
//  ESTE ARCHIVO NO IMPORTA HealthKit, a proposito: dejar la decision acá
//  —separada del framework— es lo que permite testearla en el host en segundos
//  (`scripts/test_watch_swift.sh`) en vez de depender de un simulador. El
//  puente que si toca HealthKit vive en `HealthStore.swift` y no decide nada.
//
//  Ojo con el porque, que es facil de escribir mal: HealthKit SI existe en
//  macOS —`import HealthKit`, `HKHealthStore` y `HKObjectType.workoutType()`
//  compilan— asi que no es que el framework falte. Lo que es watchOS-only es la
//  parte de SESION DE ENTRENAMIENTO: `HKWorkoutSession.init(healthStore:
//  configuration:)` da "unavailable in macOS". Medido, no supuesto.
//
//  O sea que la separacion no se justifica por "el framework no esta": se
//  justifica porque la decision no necesita el framework para nada, y no
//  arrastrarlo la deja verificable en segundos.
//

import Foundation

/// En que quedo el pedido de permiso a Salud.
enum HealthAccessState: Equatable {
    /// El dispositivo no tiene Salud.
    ///
    /// NO es el caso del simulador: se midio en F0 que el simulador de watchOS
    /// da `isHealthDataAvailable = true`, abre una `HKWorkoutSession` y la
    /// lleva a `running`. (Este comentario decia lo contrario y era falso;
    /// alcanzo para que alguien concluyera que F1 no se podia medir sin
    /// hardware.)
    ///
    /// En la practica este caso casi no aparece en un reloj: queda como la
    /// rama honesta para cuando el sistema diga que no hay Salud.
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
