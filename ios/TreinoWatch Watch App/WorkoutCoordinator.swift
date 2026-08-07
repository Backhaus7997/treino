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

    private var restTimer: Timer?

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
    }

    func finish() {
        stopRest()
        session = nil
        exercises = []
        currentExerciseIndex = 0
        WorkoutSessionStore.clear()
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
