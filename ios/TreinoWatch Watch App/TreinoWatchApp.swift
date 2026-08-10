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
                        try await coordinator.firestoreClient()
                    }
                    workoutCoordinator.makeWorkout = { routineId, day, week in
                        let (client, uid) = try await coordinator.firestoreClient()
                        // Posición EXPLÍCITA: la sesión ya existe y su día lo
                        // manda el historial. Recalcularlo hacía que el reloj
                        // mostrara los ejercicios de otro día.
                        return try await TodaysWorkoutResolver.resolve(
                            client: client,
                            uid: uid,
                            routineId: routineId,
                            dayNumber: day,
                            weekNumber: week
                        )
                    }
                    coordinator.start()
                    // Recupera un entreno a medias. Ya no espera a que se
                    // resuelva la rutina ACTIVA: la sesión guardada sabe de qué
                    // rutina es y se re-resuelve sola, así que un entreno
                    // arrancado desde una plantilla también sobrevive.
                    await workoutCoordinator.restore()
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
                            // Con entreno abierto se sincroniza en AMBAS
                            // direcciones —sube lo pendiente y baja lo que se
                            // cargo desde el celular— pero NO se re-resuelve la
                            // rutina: cambiarle los ejercicios al atleta a
                            // mitad de serie seria peor que un dato viejo.
                            await workoutCoordinator.sync()
                        } else {
                            // Sin entreno local, puede haber uno abierto que
                            // arranco el telefono. Se busca ANTES de recargar
                            // la rutina: si lo hay, el reloj tiene que entrar
                            // en modo entreno, no mostrar "Empezar".
                            await workoutCoordinator.adoptRemoteSessionIfAny()
                            if workoutCoordinator.session == nil {
                                await coordinator.loadTodaysWorkout()
                            }
                        }
                    }
                }
                // El telefono aviso que algo cambio. Es el camino RAPIDO: sin
                // esto el reloj se entera recien cuando el atleta lo mira, y la
                // idea es que si empezaste a entrenar en el celular la muñeca
                // se ponga en modo entreno sola.
                .onChange(of: coordinator.externalRefresh) { _, _ in
                    Task {
                        if workoutCoordinator.session != nil {
                            await workoutCoordinator.sync()
                        } else {
                            await workoutCoordinator.adoptRemoteSessionIfAny()
                        }
                    }
                }
        }
    }
}
