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

    /// La ultima lectura de ritmo cardiaco que llego del reloj (F2).
    ///
    /// Es la LECTURA CRUDA, con su timestamp. Que mostrar a partir de ella —y
    /// cuando no mostrar nada— lo decide `HeartRateRules`, para que la pantalla
    /// no tenga que saber de HealthKit y la regla se pueda testear en el host.
    @Published private(set) var heartRate: HeartRateReading?

    /// Las calorias activas quemadas en lo que va del entreno.
    ///
    /// Acumulado, no instantaneo — por eso `ActiveEnergyRules` no las hace
    /// caducar como al ritmo cardiaco.
    @Published private(set) var activeEnergy: ActiveEnergyReading?

    /// Segundos medidos por la sesion (D4). `nil` sin sesion abierta.
    var measuredElapsedSeconds: TimeInterval? {
        guard phase == .open, let builder else { return nil }
        return builder.elapsedTime
    }

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

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

        let config = Self.configuration()
        do {
            let new = try HKWorkoutSession(healthStore: store, configuration: config)
            new.delegate = self
            new.startActivity(with: Date())

            // El builder es lo que recolecta ritmo cardiaco y calorias (F2) y lo
            // que despues escribe el entreno en Salud (F3, D3).
            let newBuilder = new.associatedWorkoutBuilder()
            newBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: store, workoutConfiguration: config
            )
            newBuilder.delegate = self

            session = new
            builder = newBuilder
            // El estado se avanza DESPUES de que HealthKit acepto, no antes: la
            // maquina dice a donde iriamos, el recurso dice si llegamos.
            phase = decision.next
            log.notice("Sesion de entrenamiento abierta")

            // La recoleccion arranca aparte y NO condiciona nada de lo de
            // arriba. Si el atleta nego el permiso de lectura, esto falla con
            // "Not authorized" —medido en F0— y el entreno sigue igual, sin
            // pulsaciones: la sesion ya esta abierta y el segundo plano ya esta
            // conseguido. Es exactamente la degradacion que firma D2.
            newBuilder.beginCollection(withStart: Date()) { [weak self] ok, error in
                Task { @MainActor in
                    guard let self else { return }
                    if ok {
                        self.log.notice("El builder empezo a recolectar")
                    } else {
                        let detalle = error?.localizedDescription ?? "sin detalle"
                        self.log.error("El builder no pudo recolectar (sin pulsaciones): \(detalle)")
                    }
                }
            }
        } catch {
            // Queda en idle: no hay sesion. El entreno sigue igual (D2).
            log.error("No se pudo abrir la sesion de entrenamiento: \(error.localizedDescription)")
        }
    }

    /// Cierra la sesion, si hay una abierta, y escribe el entreno en Salud.
    ///
    /// El cambio de estado es SINCRONICO —igual que en `begin()`, y por la
    /// misma razon—. Lo que va suelto es la escritura en Salud, que puede
    /// tardar y no condiciona nada.
    func end() {
        let decision = WorkoutSessionLifecycle.resolve(.end, in: phase)
        guard decision.execute else { return }

        let cerrando = session
        let cerrandoBuilder = builder

        session = nil
        builder = nil
        heartRate = nil
        activeEnergy = nil
        phase = decision.next

        cerrando?.end()
        log.notice("Sesion de entrenamiento cerrada")

        guard let cerrandoBuilder else { return }
        Task { await escribirEnSalud(cerrandoBuilder) }
    }

    /// Escribe el entreno terminado en la app Salud (D3, firmada).
    ///
    /// Sin esto el entreno de TREINO no cuenta para los anillos ni el historial
    /// del atleta, que es lo que espera cualquier usuario de Apple Watch.
    ///
    /// No lanza: si el atleta nego la escritura, el entreno ya quedo guardado en
    /// el historial de TREINO igual. Salud es un destino ADEMAS, nunca EN VEZ.
    private func escribirEnSalud(_ builder: HKLiveWorkoutBuilder) async {
        let fin = Date()
        do {
            try await builder.endCollection(at: fin)
            // `finishWorkout` devuelve nil cuando no hay nada que guardar —por
            // ejemplo si la recoleccion nunca arranco por falta de permiso—.
            // No es un error: es el caso degradado y esperado.
            if let workout = try await builder.finishWorkout() {
                log.notice("Entreno escrito en Salud, duracion \(workout.duration)s")
            } else {
                log.notice("Salud no guardo el entreno (sin permiso de escritura o sin datos)")
            }
        } catch {
            log.error("No se pudo escribir el entreno en Salud: \(error.localizedDescription)")
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutSessionController: HKLiveWorkoutBuilderDelegate {

    /// Llega cada vez que el builder recolecta muestras nuevas.
    ///
    /// Se lee la estadistica MAS RECIENTE, no el promedio: al atleta le importa
    /// a cuanto esta AHORA, no a cuanto estuvo en promedio desde que empezo.
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        collectActiveEnergy(from: workoutBuilder, collectedTypes: collectedTypes)

        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(hrType),
              let stats = workoutBuilder.statistics(for: hrType),
              let quantity = stats.mostRecentQuantity()
        else { return }

        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        // El timestamp sale de la MUESTRA, no de `Date()`: si el reloj entrega
        // una tanda con retraso, fecharla ahora la haria pasar por mas fresca de
        // lo que es, y la regla de antiguedad dejaria de servir.
        let tomada = stats.mostRecentQuantityDateInterval()?.end ?? Date()

        Task { @MainActor in
            self.heartRate = HeartRateReading(
                bpm: HeartRateReading.bpm(fromQuantity: bpm),
                takenAt: tomada
            )
        }
    }

    /// Las calorias se leen con `sumQuantity`, NO con `mostRecentQuantity`.
    ///
    /// Es la diferencia con el ritmo cardiaco y no es un detalle: la muestra mas
    /// reciente de energia son las calorias del ULTIMO INTERVALO —un puñado—,
    /// mientras que lo que el atleta quiere ver es el TOTAL del entreno. Leerlas
    /// como se lee el pulso mostraria un numero chico que sube y baja en vez de
    /// un acumulado que crece.
    nonisolated func collectActiveEnergy(
        from workoutBuilder: HKLiveWorkoutBuilder,
        collectedTypes: Set<HKSampleType>
    ) {
        guard let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              collectedTypes.contains(energyType),
              let stats = workoutBuilder.statistics(for: energyType),
              let total = stats.sumQuantity()
        else { return }

        let kcal = total.doubleValue(for: .kilocalorie())
        let tomada = stats.mostRecentQuantityDateInterval()?.end ?? Date()

        Task { @MainActor in
            self.activeEnergy = ActiveEnergyReading(
                kcal: ActiveEnergyReading.kcal(fromQuantity: kcal),
                takenAt: tomada
            )
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Pausas y reanudaciones del sistema. F1/F2 no las usan; el metodo es
        // obligatorio en el protocolo.
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
