//
//  WorkoutSessionLifecycle.swift
//  TreinoWatch Watch App
//
//  Change `watch-workout-session`, fase F1.
//
//  Cuando se abre y cuando se cierra la sesion de entrenamiento de watchOS.
//
//  No importa HealthKit: la regla no lo necesita, y no arrastrarlo la deja
//  verificable en el host en segundos (`scripts/test_watch_swift.sh`). El
//  puente que si lo toca vive en `WorkoutSessionController.swift`.
//
//  Aparte, `HKWorkoutSession.init(healthStore:configuration:)` es watchOS-only
//  —da "unavailable in macOS", medido— asi que sin este corte no habria forma
//  de testear la regla sin un simulador.
//

import Foundation

/// Si hay una sesion de entrenamiento abierta en watchOS.
///
/// Dos estados y no cuatro porque abrir y cerrar son SINCRONICOS: el `init` de
/// `HKWorkoutSession`, `startActivity(with:)` y `end()` no son `async`. Lo
/// asincronico es `beginCollection` del builder, que es F2 y no toca esto.
///
/// Eso no es un detalle de estilo: como no hay `await` entre el chequeo y la
/// asignacion, y todo esto corre en el MainActor, dos llamadores concurrentes
/// NO pueden colarse en el medio. La garantia de una sola sesion queda
/// demostrada por construccion, no confiada a que nadie llame dos veces.
enum WorkoutSessionPhase: Equatable {
    case idle
    case open
}

enum WorkoutSessionCommand: Equatable {
    case begin
    case end
}

/// Lo que el coordinator del entreno necesita de la sesion de watchOS.
///
/// Existe para que `WorkoutCoordinator` no importe HealthKit. No es purismo:
/// `HKWorkoutSession` es watchOS-only, asi que sin este corte el coordinator
/// dejaria de compilar en el host y se perderia la unica forma barata que hay
/// de testearlo. La implementacion real la inyecta la app, igual que ya hace
/// con el cliente de Firestore.
@MainActor
protocol WorkoutSessionControlling: AnyObject {
    var phase: WorkoutSessionPhase { get }

    /// Segundos que lleva MEDIDOS la sesion de entrenamiento, o `nil` si no hay
    /// sesion abierta.
    ///
    /// Es lo que convierte la duracion de estimacion en medicion (D4). Devuelve
    /// `nil` —y no 0— cuando no hay nada que medir, para que el llamador pueda
    /// distinguir "duro cero" de "no se midio" y caer al calculo de respaldo.
    var measuredElapsedSeconds: TimeInterval? { get }

    func begin()
    func end()
}

enum WorkoutSessionLifecycle {

    /// Decide si una orden se ejecuta o se ignora, y en que estado queda.
    ///
    /// Devolver `execute: false` en vez de lanzar es deliberado: que dos
    /// caminos pidan abrir el mismo entreno no es un error del que haya que
    /// avisar, es el funcionamiento normal de un companion. El segundo
    /// simplemente no tiene nada que hacer.
    ///
    /// El reloj entra en modo entreno por TRES caminos —empezarlo ahi, adoptar
    /// el que abrio el telefono, y recuperar uno a medias— y al arrancar la app
    /// dos corren en paralelo (medido en F0). Poner la defensa acá, en el
    /// recurso, y no en cada llamador, es lo que hace que agregar un cuarto
    /// camino mañana no vuelva a abrir el agujero.
    static func resolve(
        _ command: WorkoutSessionCommand,
        in phase: WorkoutSessionPhase
    ) -> (execute: Bool, next: WorkoutSessionPhase) {
        switch (command, phase) {
        case (.begin, .idle):
            return (true, .open)

        // La garantia de F1: una sola sesion por entreno.
        case (.begin, .open):
            return (false, .open)

        case (.end, .open):
            return (true, .idle)

        // Pasa de verdad: el atleta descarta un entreno que el reloj nunca
        // llego a abrir, o el telefono cierra la sesion antes.
        case (.end, .idle):
            return (false, .idle)
        }
    }
}
