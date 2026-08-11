//
//  HealthStore.swift
//  TreinoWatch Watch App
//
//  Change `watch-workout-session`, fase F0.
//
//  El puente con HealthKit. Es lo unico del reloj que importa el framework, y
//  no toma NINGUNA decision: que se pide y como se lee la respuesta vive en
//  `HealthAccess.swift`, que por no importar HealthKit se puede testear en el
//  host en segundos.
//
//  F0 llega hasta el permiso. La `HKWorkoutSession` —el arreglo que justifica
//  el ciclo— es F1.
//

import Combine
import Foundation
import HealthKit
import os

/// Pide el permiso de Salud y recuerda en que quedo.
///
/// **Ninguno de sus metodos lanza.** Es la forma en codigo de la decision D2,
/// firmada por el dueño: si el atleta niega el permiso —o si Salud falla, o si
/// el dispositivo ni siquiera tiene Salud— el entreno funciona igual, sin
/// pulsaciones y sin degradar nada mas.
@MainActor
final class HealthStore: ObservableObject {

    @Published private(set) var state: HealthAccessState = .notRequested

    private let store = HKHealthStore()

    private let log = Logger(
        subsystem: "com.backhaus.treino.watchkitapp",
        category: "health"
    )

    /// Le pide permiso al atleta, si corresponde pedirlo.
    ///
    /// No lanza y no bloquea el entreno: quien la llama la dispara y sigue.
    func requestAccessIfNeeded() async {
        let available = HKHealthStore.isHealthDataAvailable()

        guard HealthAccess.shouldRequest(current: state, isHealthDataAvailable: available) else {
            if !available {
                // Sin Salud en el dispositivo no hay a quien preguntarle. Pasa
                // en el simulador; en un Apple Watch real, no.
                state = .unsupported
                log.notice("Salud no esta disponible en este dispositivo")
            }
            return
        }

        guard let share = sampleTypes(for: HealthAccess.shareIdentifiers),
              let read = objectTypes(for: HealthAccess.readIdentifiers)
        else {
            // Un identificador que HealthKit no reconoce se traduciria a nil y
            // desapareceria del pedido en silencio: el atleta aceptaria un
            // permiso que no incluye lo que ibamos a usar. Preferimos que se
            // note.
            state = .failed("Hay un identificador de Salud que HealthKit no reconoce")
            log.error("Identificador de Salud no reconocido; no se pide permiso")
            return
        }

        do {
            try await store.requestAuthorization(toShare: share, read: read)
        } catch {
            // Que Salud no conteste no es el atleta diciendo que no: queda como
            // fallo, y el proximo entreno lo reintenta.
            state = .failed(error.localizedDescription)
            log.error("Salud no contesto al pedido de permiso: \(error.localizedDescription)")
            return
        }

        // Se relee el estado en vez de asumir que "no lanzo" es "acepto":
        // `requestAuthorization` tambien vuelve sin error cuando el atleta
        // cierra la hoja sin decidir.
        //
        // Ojo con lo que NO se sabe acá: HealthKit no revela si el atleta nego
        // la LECTURA, asi que esto habla solo de la escritura. De las
        // pulsaciones nos enteramos cuando lleguen —o no— en F2.
        let shareStatus = store.authorizationStatus(for: HKObjectType.workoutType())
        state = HealthAccess.stateAfterRequest(
            shareStatus: HealthShareAuthorization(rawValue: shareStatus.rawValue) ?? .notDetermined
        )
        log.notice("Permiso de Salud resuelto: \(String(describing: self.state))")
    }

    // MARK: - Traduccion de identificadores
    //
    // `HealthAccess` habla en identificadores crudos para no depender de
    // HealthKit. Acá se convierten en los tipos del framework.

    private func objectType(for identifier: String) -> HKObjectType? {
        if identifier == HKWorkoutTypeIdentifier {
            return HKObjectType.workoutType()
        }
        return HKObjectType.quantityType(
            forIdentifier: HKQuantityTypeIdentifier(rawValue: identifier)
        )
    }

    private func objectTypes(for identifiers: [String]) -> Set<HKObjectType>? {
        var types: Set<HKObjectType> = []
        for identifier in identifiers {
            guard let type = objectType(for: identifier) else { return nil }
            types.insert(type)
        }
        return types
    }

    private func sampleTypes(for identifiers: [String]) -> Set<HKSampleType>? {
        var types: Set<HKSampleType> = []
        for identifier in identifiers {
            guard let type = objectType(for: identifier) as? HKSampleType else { return nil }
            types.insert(type)
        }
        return types
    }
}
