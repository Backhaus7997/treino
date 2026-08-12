//
//  WorkoutSessionController.swift
//  TreinoWatch Watch App
//
//  Change `watch-workout-session`, fase F1.
//
//  Abre y cierra la `HKWorkoutSession` que dura lo que dura el entreno.
//
//  Es el arreglo que justifica el ciclo. Sin esto, para watchOS TREINO es una
//  app comun que MUESTRA un entrenamiento, y el sistema la suspende al bajar la
//  muñeca — que en el gimnasio es el caso normal, no el borde. Medido: el
//  descanso perdia 57 segundos en 84 de reloj de pared.
//
//  Lo que decide CUANDO abrir y cerrar vive en `WorkoutSessionLifecycle.swift`,
//  sin HealthKit, para que sea testeable en el host. Acá solo esta el framework.
//
//  F1 llega hasta abrir y cerrar. El ritmo cardiaco en vivo —el
//  `HKLiveWorkoutBuilder` y su `beginCollection`— es F2.
//

import Combine
import Foundation
import HealthKit
import os

/// Mantiene abierta una sesion de entrenamiento de watchOS mientras el atleta
/// entrena.
///
/// **Ningun metodo lanza, y ninguno bloquea el entreno.** Es la misma regla que
/// F0 puso para el permiso (D2, firmada): si HealthKit falla, si el atleta nego
/// el permiso, o si el dispositivo no tiene Salud, el entreno funciona igual.
///
/// Y eso no es un principio suelto: en F0 se midio que la sesion ABRE incluso
/// con el permiso negado por completo, y llega a `running`. Lo unico que se
/// pierde sin permiso es la recoleccion de datos, que es F2.
@MainActor
final class WorkoutSessionController: NSObject, ObservableObject, WorkoutSessionControlling {

    /// Si hay una sesion abierta. Lo lee la UI en F2; en F1 sirve de
    /// diagnostico.
    @Published private(set) var phase: WorkoutSessionPhase = .idle

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?

    private let log = Logger(
        subsystem: "com.backhaus.treino.watchkitapp",
        category: "workout-session"
    )

    /// La configuracion del entreno que se le declara a watchOS.
    ///
    /// `traditionalStrengthTraining` + `indoor` porque TREINO es una app de
    /// gimnasio: pesas bajo techo. No es cosmetico — de eso dependen las
    /// calorias que estima el reloj y como aparece el entreno en la app Salud.
    private static func configuration() -> HKWorkoutConfiguration {
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        return config
    }

    /// Abre la sesion, si no hay una abierta ya.
    ///
    /// Sincronico a proposito. `HKWorkoutSession.init` y `startActivity(with:)`
    /// no son `async`, asi que entre el chequeo y la asignacion NO hay ningun
    /// punto de suspension. Corriendo todo en el MainActor, dos llamadores
    /// concurrentes no pueden colarse en el medio: la garantia de UNA sola
    /// sesion queda demostrada por construccion.
    ///
    /// Si esto alguna vez necesita un `await` adentro, esa garantia se rompe y
    /// hay que rehacerla — no alcanza con volver a leer `phase`.
    func begin() {
        guard HKHealthStore.isHealthDataAvailable() else {
            log.notice("Sin Salud en el dispositivo: no se abre sesion de entrenamiento")
            return
        }

        let decision = WorkoutSessionLifecycle.resolve(.begin, in: phase)
        guard decision.execute else {
            log.debug("Ya hay una sesion abierta: no se abre otra")
            return
        }

        do {
            let new = try HKWorkoutSession(
                healthStore: store,
                configuration: Self.configuration()
            )
            new.delegate = self
            new.startActivity(with: Date())

            session = new
            // El estado se avanza DESPUES de que HealthKit acepto, no antes: la
            // maquina dice a donde iriamos, el recurso dice si llegamos.
            phase = decision.next
            log.notice("Sesion de entrenamiento abierta")
        } catch {
            // Queda en idle: no hay sesion. El entreno sigue igual (D2).
            log.error("No se pudo abrir la sesion de entrenamiento: \(error.localizedDescription)")
        }
    }

    /// Cierra la sesion, si hay una abierta.
    func end() {
        let decision = WorkoutSessionLifecycle.resolve(.end, in: phase)
        guard decision.execute else { return }

        session?.end()
        session = nil
        phase = decision.next
        log.notice("Sesion de entrenamiento cerrada")
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutSessionController: HKWorkoutSessionDelegate {

    /// watchOS puede terminar la sesion por su cuenta.
    ///
    /// Sin esto, `phase` seguiria diciendo `.open` con la sesion muerta, y el
    /// proximo `begin()` no abriria ninguna —creyendo que ya hay una— dejando
    /// al atleta sin segundo plano y sin ningun sintoma visible. Escuchar el
    /// delegate es lo que evita que el estado mienta.
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            self.log.notice(
                "La sesion paso de \(fromState.rawValue) a \(toState.rawValue)"
            )
            guard toState == .ended || toState == .stopped else { return }
            if self.phase == .open {
                self.log.notice("watchOS termino la sesion por su cuenta; se sincroniza el estado")
                self.session = nil
                self.phase = .idle
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.log.error("La sesion de entrenamiento fallo: \(error.localizedDescription)")
            self.session = nil
            self.phase = .idle
        }
    }
}
