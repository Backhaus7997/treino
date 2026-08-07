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
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .environmentObject(workoutCoordinator)
                // Activa WatchConnectivity y recupera la credencial guardada.
                // Va acá y no en el init del coordinator para que el trabajo
                // arranque con la escena viva, no durante la construcción.
                .task {
                    // El coordinator del entreno pide su cliente al de
                    // credenciales, en vez de que uno conozca al otro.
                    workoutCoordinator.makeClient = {
                        let credential = try await coordinator.firestoreClient()
                        return credential
                    }
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
                // Relee la rutina al volver a primer plano. Sin esto el reloj
                // solo la leia al arrancar la app: si el atleta cambiaba su
                // rutina activa desde el telefono, el reloj seguia mostrando la
                // anterior hasta que alguien lo relanzaba.
                //
                // No se refresca durante un entreno en curso: cambiar los
                // ejercicios abajo del atleta a mitad de serie seria peor que
                // mostrar un dato viejo.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        // Con un entreno abierto se reintenta la cola en vez de
                        // refrescar la rutina: cambiarle los ejercicios al
                        // atleta a mitad de serie seria peor.
                        if workoutCoordinator.session != nil {
                            await workoutCoordinator.sync(
                                workout: coordinator.todaysWorkout
                            )
                        } else {
                            await coordinator.loadTodaysWorkout()
                        }
                    }
                }
        }
    }
}
