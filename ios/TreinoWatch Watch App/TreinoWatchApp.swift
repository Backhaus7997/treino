//
//  TreinoWatchApp.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F1.
//

import Combine
import SwiftUI

@main
struct TreinoWatch_Watch_AppApp: App {
    @StateObject private var coordinator = CredentialCoordinator()
    @StateObject private var workoutCoordinator = WorkoutCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .environmentObject(workoutCoordinator)
                // Activa WatchConnectivity y recupera la credencial guardada.
                // Va acá y no en el init del coordinator para que el trabajo
                // arranque con la escena viva, no durante la construcción.
                .task {
                    coordinator.start()
                    // Recupera un entreno a medias. Espera a que la rutina
                    // este resuelta: los ejercicios no se persisten, se
                    // re-resuelven desde el plan vigente.
                    for await workout in coordinator.$todaysWorkout.values {
                        if workout != nil {
                            workoutCoordinator.restore(workout: workout)
                            break
                        }
                    }
                }
        }
    }
}
