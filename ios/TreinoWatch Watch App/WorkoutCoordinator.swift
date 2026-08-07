//
//  WorkoutCoordinator.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F3.
//

import Combine
import Foundation

/// Maneja la sesión de entrenamiento en curso desde el reloj.
///
/// F3 es LOCAL: nada se escribe al historial todavía. La sincronización —y con
/// ella el problema difícil de no duplicar si el teléfono también abrió una
/// sesión— es F4.
@MainActor
final class WorkoutCoordinator: ObservableObject {

    @Published private(set) var session: WorkoutSession?
    @Published private(set) var exercises: [WatchExercise] = []
    @Published var currentExerciseIndex: Int = 0

    /// Segundos que faltan del descanso, o nil si no hay descanso corriendo.
    @Published private(set) var restRemaining: Int?

    /// Ultima falla de sincronizacion, para diagnostico. La UI solo muestra que
    /// hay pendientes, no el detalle.
    @Published private(set) var syncError: String?

    private var restTimer: Timer?

    /// Como conseguir un cliente de Firestore autenticado. Lo inyecta la app
    /// para no acoplar este coordinator al de credenciales.
    var makeClient: (() async throws -> (FirestoreREST, String))?

    var currentExercise: WatchExercise? {
        guard currentExerciseIndex >= 0, currentExerciseIndex < exercises.count
        else { return nil }
        return exercises[currentExerciseIndex]
    }

    /// Recupera una sesión que haya quedado a medias.
    ///
    /// [workout] se necesita porque los ejercicios NO se persisten: se
    /// re-resuelven desde la rutina. Guardar la prescripción entera dejaría al
    /// reloj mostrando series viejas si el PF la cambia a mitad de plan.
    func restore(workout: TodaysWorkout?) {
        guard let stored = WorkoutSessionStore.load(), let workout else { return }
        // Una sesión guardada de OTRA rutina o de otro día quedó huérfana: el
        // atleta ya avanzó de plan. Descartarla es mejor que mostrar un entreno
        // que no corresponde.
        guard stored.routineId == workout.routineId,
              stored.dayNumber == workout.dayNumber,
              stored.weekNumber == workout.weekNumber
        else {
            WorkoutSessionStore.clear()
            return
        }
        session = stored
        exercises = workout.exercises
        currentExerciseIndex = firstUnfinishedIndex(in: workout.exercises, session: stored)
    }

    func start(workout: TodaysWorkout) {
        let new = WorkoutSession(
            localId: UUID().uuidString,
            routineId: workout.routineId,
            routineName: workout.routineName,
            dayName: workout.dayName,
            dayNumber: workout.dayNumber,
            weekNumber: workout.weekNumber,
            startedAt: Date(),
            loggedSets: []
        )
        session = new
        exercises = workout.exercises
        currentExerciseIndex = 0
        WorkoutSessionStore.save(new)

        // Se adopta o crea la sesion remota en segundo plano: el atleta empieza
        // a entrenar YA, sin esperar a la red. Si falla, el proximo sync lo
        // reintenta.
        Task { await sync(workout: workout) }
    }

    /// Carga una serie. Idempotente por `exerciseId + setNumber`, igual que el
    /// teléfono: tocar dos veces la misma no la duplica.
    func logSet(exerciseId: String, setNumber: Int, spec: SetSpec, restSeconds: Int) {
        guard var current = session else { return }
        guard !current.isLogged(exerciseId: exerciseId, setNumber: setNumber) else { return }

        current.loggedSets.append(
            LoggedSet(
                exerciseId: exerciseId,
                setNumber: setNumber,
                // Con un rango se registra el máximo: es el objetivo del plan.
                // El atleta podrá corregirlo cuando exista la edición (F4).
                reps: spec.reps ?? spec.repsMax ?? spec.repsMin,
                weightKg: spec.weightKg,
                completedAt: Date()
            )
        )
        session = current
        WorkoutSessionStore.save(current)

        startRest(seconds: restSeconds)
        advanceIfExerciseDone(exerciseId: exerciseId)

        Task { await sync(workout: nil) }
    }

    /// Cierra el entreno. Intenta subir lo que falte ANTES de descartar el
    /// estado local: si se borrara primero, una serie que nunca llego al
    /// historial se perderia sin dejar rastro.
    func finish() async {
        stopRest()
        await sync(workout: nil)

        // Si quedan pendientes, el entreno NO se descarta: se conserva para
        // reintentar. Perder series que el atleta hizo es peor que dejarle la
        // pantalla abierta.
        if let current = session, !current.pendingSets.isEmpty { return }

        session = nil
        exercises = []
        currentExerciseIndex = 0
        WorkoutSessionStore.clear()
    }

    /// Sube al historial lo que falte: primero resuelve la sesion remota, y
    /// despues las series pendientes una por una.
    ///
    /// Cada serie se marca como subida SOLO si su escritura salio bien, asi que
    /// una falla parcial deja el resto en la cola en vez de darlas por hechas.
    func sync(workout: TodaysWorkout?) async {
        guard var current = session, let makeClient else { return }
        do {
            let (client, uid) = try await makeClient()

            if current.remoteId == nil {
                guard let workout else {
                    // Sin la rutina no se puede adoptar/crear: queda para el
                    // proximo sync, que si la tiene.
                    return
                }
                let adopted = try await HistorySync.adoptOrCreateSession(
                    client: client, uid: uid, workout: workout,
                    startedAt: current.startedAt
                )
                current.remoteId = adopted.sessionId
                // Series que ya estaban en esa sesion (cargadas desde el
                // telefono, o por un intento anterior): se marcan como hechas
                // para no volver a ofrecerlas ni re-escribirlas.
                for existing in adopted.alreadyLogged
                where !current.isLogged(
                    exerciseId: existing.exerciseId, setNumber: existing.setNumber
                ) {
                    current.loggedSets.append(existing)
                }
                session = current
                WorkoutSessionStore.save(current)
            }

            guard let remoteId = current.remoteId else { return }

            for pending in current.pendingSets {
                let name = exercises
                    .first { $0.exerciseId == pending.exerciseId }?
                    .exerciseName ?? pending.exerciseId
                try await HistorySync.writeSetLog(
                    client: client, uid: uid, sessionId: remoteId,
                    exerciseName: name, set: pending
                )
                if let index = current.loggedSets.firstIndex(where: {
                    $0.exerciseId == pending.exerciseId
                        && $0.setNumber == pending.setNumber
                }) {
                    current.loggedSets[index].synced = true
                }
                session = current
                WorkoutSessionStore.save(current)
            }
            syncError = nil
        } catch {
            syncError = String(describing: error)
        }
    }

    func skipRest() { stopRest() }

    // MARK: - Internos

    /// Avanza al siguiente ejercicio cuando el actual quedó completo.
    ///
    /// No avanza más allá del último: quedarse ahí deja al atleta ver que
    /// terminó, en vez de mostrarle una pantalla vacía.
    private func advanceIfExerciseDone(exerciseId: String) {
        guard let session, let exercise = currentExercise,
              exercise.exerciseId == exerciseId,
              session.loggedCount(exerciseId: exerciseId) >= exercise.sets.count,
              currentExerciseIndex + 1 < exercises.count
        else { return }
        currentExerciseIndex += 1
    }

    private func firstUnfinishedIndex(
        in exercises: [WatchExercise],
        session: WorkoutSession
    ) -> Int {
        for (index, exercise) in exercises.enumerated() {
            if session.loggedCount(exerciseId: exercise.exerciseId) < exercise.sets.count {
                return index
            }
        }
        return max(exercises.count - 1, 0)
    }

    /// Descanso contado LOCALMENTE por el reloj.
    ///
    /// El plan original lo descartaba porque mandar un tick por segundo desde
    /// el teléfono saturaba el canal. Acá no aplica: el reloj es autónomo y
    /// tiene el estado, así que contar no cuesta tráfico (Locked Decision #8).
    private func startRest(seconds: Int) {
        stopRest()
        guard seconds > 0 else { return }
        restRemaining = seconds
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let remaining = self.restRemaining else { return }
                if remaining <= 1 {
                    self.stopRest()
                } else {
                    self.restRemaining = remaining - 1
                }
            }
        }
    }

    private func stopRest() {
        restTimer?.invalidate()
        restTimer = nil
        restRemaining = nil
    }
}
