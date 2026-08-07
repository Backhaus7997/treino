//
//  ContentView.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F1.
//

import SwiftUI

/// Pantalla de estado del emparejamiento.
///
/// Deliberadamente austera: F1 solo entrega credencial. La pantalla del
/// entreno llega en F2, cuando el reloj pueda leer la rutina.
struct ContentView: View {
    @EnvironmentObject private var coordinator: CredentialCoordinator
    @EnvironmentObject private var workoutCoordinator: WorkoutCoordinator

    var body: some View {
        VStack(spacing: 8) {
            switch coordinator.state {
            case .waitingForPairing:
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .imageScale(.large)
                Text("Abrí TREINO en el teléfono para vincular el reloj")
                    .font(.footnote)
                    .multilineTextAlignment(.center)

            case .exchanging:
                ProgressView()
                Text("Vinculando…")
                    .font(.footnote)

            case .ready:
                if workoutCoordinator.session != nil {
                    // Hay un entreno en curso: gana sobre la pantalla de "hoy".
                    WorkoutView()
                } else if let workout = coordinator.todaysWorkout {
                    TodaysWorkoutView(workout: workout)
                } else if coordinator.workoutError != nil {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.large)
                        .foregroundStyle(.orange)
                    Text("No se pudo cargar tu rutina")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView()
                    Text("Cargando tu rutina…")
                        .font(.footnote)
                }

            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .imageScale(.large)
                    .foregroundStyle(.orange)
                Text("No se pudo vincular. Abrí TREINO en el teléfono.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

/// El entreno de hoy, en una pantalla de 40mm.
///
/// Austera a propósito: el nombre del día es lo que el atleta necesita leer de
/// un vistazo entre series. El resto es contexto secundario.
struct TodaysWorkoutView: View {
    @EnvironmentObject private var workoutCoordinator: WorkoutCoordinator
    let workout: TodaysWorkout

    var body: some View {
        VStack(spacing: 4) {
            Text("HOY")
                .font(.caption2)
                .foregroundStyle(.green)

            Text(workout.dayName)
                .font(.headline)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)

            Text(workout.routineName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                Label("\(workout.exerciseCount)", systemImage: "dumbbell")
                // La semana solo se muestra en planes periodizados: en uno de
                // una sola semana el dato es ruido.
                if workout.numWeeks > 1 {
                    Text("Sem \(workout.weekNumber + 1)/\(workout.numWeeks)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 2)

            // Sin ejercicios no hay nada que empezar: puede pasar si el plan
            // no tiene ninguno activo en esta semana.
            if workout.exercises.isEmpty {
                Text("Sin ejercicios esta semana")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else {
                Button("Empezar") { workoutCoordinator.start(workout: workout) }
                    .font(.caption)
                    .tint(.green)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    ContentView()
        .environmentObject(CredentialCoordinator())
        .environmentObject(WorkoutCoordinator())
}
